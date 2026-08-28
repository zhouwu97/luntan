<#
  从杯友酱的公开接口生成客户端快照（榜单 + 每个商品的评价与配图）。

  该脚本会保留源站对每个“榜单标签 + 商品分类”组合返回的原始排序和
  可见字段，避免在客户端重新按评分或热度排序而导致名次漂移。
  评价数据（getToyAllReview）保持源站返回的富文本与配图键，图片下载到
  本地 assets 目录后以 asset_paths 记录，导入器负责把内容清洗成纯文本、
  把配图写入本项目对象存储。
#>

[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\assets\ranking\beiyoujiang_snapshot.json')
)

$ErrorActionPreference = 'Stop'
$endpoint = 'https://beiyoujiang.com/api/toy/getAllToy'
$reviewEndpoint = 'https://beiyoujiang.com/api/toyComment/getToyAllReview'
$categories = @('', 'CUP', 'SMALL_MOLD', 'LARGE_MOLD', 'HALF_BODY', 'LUBE')
$segments = @('', 'ENTRY', 'ADVANCED', 'HIGH', 'EXTREME')
$views = [ordered]@{}
$reviews = [ordered]@{}
$imageDirectory = Join-Path $PSScriptRoot '..\assets\ranking\beiyoujiang'
$downloadedImages = @{}

function Save-SourceImage {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    if ([string]::IsNullOrWhiteSpace($Key)) {
        return $null
    }
    if (-not $downloadedImages.ContainsKey($FileName)) {
        New-Item -ItemType Directory -Path $imageDirectory -Force | Out-Null
        $destination = Join-Path $imageDirectory $FileName
        if (-not (Test-Path -LiteralPath $destination) -or (Get-Item -LiteralPath $destination).Length -eq 0) {
            $extension = [IO.Path]::GetExtension($Key)
            $imageUrl = "https://beiyoujiang.com/ToyImg/$([uri]::EscapeDataString($Key))"
            & curl.exe --http1.1 --retry 3 --retry-delay 1 --tlsv1.2 -sS -L $imageUrl -o $destination
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $destination) -or (Get-Item -LiteralPath $destination).Length -eq 0) {
                # 源站历史配图可能已被删除；跳过而不是让整个同步失败。
                Write-Warning "配图下载失败（跳过）：$imageUrl"
                $downloadedImages[$FileName] = $false
                return $null
            }
        }
        $downloadedImages[$FileName] = $true
    }
    if ($downloadedImages[$FileName] -eq $false) {
        return $null
    }
    return "assets/ranking/beiyoujiang/$FileName"
}

function Add-LocalImagePaths {
    param([AllowNull()]$Toy)

    if ($null -eq $Toy) {
        return
    }
    $coverKey = @($Toy.coverUrl) | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") } | Select-Object -First 1
    $heroKey = @($Toy.weeklyTopImg) | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") } | Select-Object -First 1

    $coverPath = $null
    if ($coverKey) {
        $extension = [IO.Path]::GetExtension("$coverKey")
        if ([string]::IsNullOrWhiteSpace($extension) -or $extension.Length -gt 8) {
            $extension = '.webp'
        }
        $coverPath = Save-SourceImage -Key "$coverKey" -FileName "byj_$($Toy.id)$extension"
    }
    $heroPath = $null
    if ($heroKey) {
        $extension = [IO.Path]::GetExtension("$heroKey")
        if ([string]::IsNullOrWhiteSpace($extension) -or $extension.Length -gt 8) {
            $extension = '.webp'
        }
        $heroPath = Save-SourceImage -Key "$heroKey" -FileName "byj_$($Toy.id)_hero$extension"
    }

    $Toy | Add-Member -NotePropertyName 'asset_path' -NotePropertyValue $coverPath -Force
    $Toy | Add-Member -NotePropertyName 'hero_asset_path' -NotePropertyValue $heroPath -Force
}

function Get-RankingView {
    param(
        [AllowEmptyString()][string]$Type,
        [AllowEmptyString()][string]$Classify
    )

    $request = [ordered]@{
        type = $Type
        classify = $Classify
        sort = if ([string]::IsNullOrEmpty($Type)) { 'weekly' } else { 'hot' }
        page = 1
        pageSize = 100
    } | ConvertTo-Json -Compress

    $raw = & curl.exe --http1.1 --retry 3 --retry-delay 1 --tlsv1.2 -sS `
        -X POST $endpoint -H 'Content-Type: application/json' --data $request
    if ($LASTEXITCODE -ne 0) {
        throw "杯友酱榜单请求失败：type=$Type classify=$Classify"
    }

    $response = $raw | ConvertFrom-Json
    if ($response.code -ne 200 -or $null -eq $response.data) {
        throw "杯友酱榜单返回异常：type=$Type classify=$Classify"
    }

    Add-LocalImagePaths -Toy $response.data.weeklyTop
    foreach ($toy in @($response.data.list)) {
        Add-LocalImagePaths -Toy $toy
    }

    $total = $response.pagination.total
    if ($null -eq $total) {
        $total = @($response.data.list).Count
    }

    return [ordered]@{
        weekly_top = $response.data.weeklyTop
        items = @($response.data.list)
        total = [int]$total
    }
}

function Get-ToyReviews {
    param([Parameter(Mandatory = $true)][int]$ToyId)

    $request = [ordered]@{ toyId = $ToyId } | ConvertTo-Json -Compress
    $raw = & curl.exe --http1.1 --retry 3 --retry-delay 1 --tlsv1.2 -sS `
        -X POST $reviewEndpoint -H 'Content-Type: application/json' --data $request
    if ($LASTEXITCODE -ne 0) {
        throw "杯友酱评价请求失败：toyId=$ToyId"
    }
    $response = $raw | ConvertFrom-Json
    if ($response.code -ne 200) {
        throw "杯友酱评价返回异常：toyId=$ToyId"
    }

    $result = @()
    foreach ($review in @($response.data)) {
        $paths = @()
        $index = 0
        foreach ($imageKey in @($review.images)) {
            if ([string]::IsNullOrWhiteSpace("$imageKey")) { continue }
            $extension = [IO.Path]::GetExtension("$imageKey")
            if ([string]::IsNullOrWhiteSpace($extension) -or $extension.Length -gt 8) {
                $extension = '.webp'
            }
            $fileName = "byj_rev$($review.id)_$index$extension"
            $path = Save-SourceImage -Key "$imageKey" -FileName $fileName
            if ($path) { $paths += $path }
            $index += 1
        }
        $review | Add-Member -NotePropertyName 'asset_paths' -NotePropertyValue @($paths) -Force
        $result += $review
    }
    return ,$result
}

foreach ($segment in $segments) {
    foreach ($category in $categories) {
        # 源站在筛选标签时会自动落到“飞机杯”；无标签时才允许全分类综合热榜。
        if (-not [string]::IsNullOrEmpty($segment) -and [string]::IsNullOrEmpty($category)) {
            continue
        }
        $key = "$segment|$category"
        Write-Host "同步 $key"
        $views[$key] = Get-RankingView -Type $segment -Classify $category
    }
}

# 抓取全部出现过的商品的评价（含回复与配图）。
$toyIds = New-Object System.Collections.Generic.HashSet[int]
foreach ($view in $views.Values) {
    if ($null -ne $view.weekly_top) {
        [void]$toyIds.Add([int]$view.weekly_top.id)
    }
    foreach ($toy in @($view.items)) {
        [void]$toyIds.Add([int]$toy.id)
    }
}
foreach ($toyId in $toyIds) {
    Write-Host "同步评价 toyId=$toyId"
    $reviews["$toyId"] = Get-ToyReviews -ToyId $toyId
}

$snapshot = [ordered]@{
    source = 'https://beiyoujiang.com/rankingList'
    fetched_at = (Get-Date).ToUniversalTime().ToString('o')
    tabs = [ordered]@{
        '' = '综合热榜'
        'ENTRY' = '慢玩入门'
        'ADVANCED' = '进阶训练'
        'HIGH' = '超高刺激'
        'EXTREME' = '榨汁玩具'
    }
    categories = [ordered]@{
        'CUP' = '飞机杯'
        'SMALL_MOLD' = '小型臀模'
        'LARGE_MOLD' = '大型臀模'
        'HALF_BODY' = '半身腿模'
        'LUBE' = '润滑油'
    }
    views = $views
    reviews = $reviews
}

$destination = [IO.Path]::GetFullPath($OutputPath)
$destinationDir = Split-Path -Parent $destination
New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
$snapshot | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -Encoding utf8
Write-Host "已写入 $destination"
