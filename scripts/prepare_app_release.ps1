param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$VersionName,

    [long]$VersionCode = 0,

    [Parameter(Mandatory = $true)]
    [long]$MinimumSupportedVersionCode,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [string]$Changelog
)

$ErrorActionPreference = 'Stop'

# 发布清单的版本必须和应用源码一致；允许省略参数以直接读取 pubspec.yaml，
# 仍兼容旧调用方式，但拒绝传入不一致的版本，避免生成不可升级的清单。
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$pubspecVersionLine = Get-Content -LiteralPath $pubspecPath |
    Where-Object { $_ -match '^\s*version:\s*(?<name>[0-9A-Za-z._-]+)\+(?<code>[1-9][0-9]*)\s*$' } |
    Select-Object -First 1
if ($null -eq $pubspecVersionLine -or $pubspecVersionLine -notmatch '^\s*version:\s*(?<name>[0-9A-Za-z._-]+)\+(?<code>[1-9][0-9]*)\s*$') {
    throw 'pubspec.yaml 必须包含合法的 version: name+code'
}
$pubspecVersionName = $Matches['name']
$pubspecVersionCode = [long]$Matches['code']
if ([string]::IsNullOrWhiteSpace($VersionName)) {
    $VersionName = $pubspecVersionName
} elseif ($VersionName.Trim() -ne $pubspecVersionName) {
    throw "VersionName 必须与 pubspec.yaml ($pubspecVersionName) 一致"
}
if ($VersionCode -eq 0) {
    $VersionCode = $pubspecVersionCode
} elseif ($VersionCode -ne $pubspecVersionCode) {
    throw "VersionCode 必须与 pubspec.yaml ($pubspecVersionCode) 一致"
}

$resolvedApk = (Resolve-Path -LiteralPath $ApkPath).Path
if ([System.IO.Path]::GetExtension($resolvedApk) -ne '.apk') {
    throw 'ApkPath 必须指向 .apk 文件'
}
if ($VersionCode -le 0) {
    throw 'VersionCode 必须为正整数'
}
if ($MinimumSupportedVersionCode -le 0 -or $MinimumSupportedVersionCode -gt $VersionCode) {
    throw 'MinimumSupportedVersionCode 必须为正整数且不能大于 VersionCode'
}
if ([string]::IsNullOrWhiteSpace($VersionName) -or
    [string]::IsNullOrWhiteSpace($Title) -or
    [string]::IsNullOrWhiteSpace($Changelog)) {
    throw 'VersionName、Title 和 Changelog 不能为空'
}

$releaseDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
# 每个版本独立目录（releases/<version_code>/），发布路径不可变，
# 服务端强制校验 apk_file 必须落在该目录下。
$versionDirectory = Join-Path $releaseDirectory (Join-Path 'releases' "$VersionCode")
[System.IO.Directory]::CreateDirectory($versionDirectory) | Out-Null

# 文件名只使用已校验的版本号字符，避免发布清单出现路径穿越或特殊字符。
$safeVersionName = $VersionName.Trim()
if ($safeVersionName -notmatch '^[0-9A-Za-z._-]+$') {
    throw 'VersionName 只能包含字母、数字、点、下划线和连字符'
}
$apkFileName = "luntan-$safeVersionName-$VersionCode.apk"
$publishedApk = Join-Path $versionDirectory $apkFileName

$digest = (Get-FileHash -LiteralPath $resolvedApk -Algorithm SHA256).Hash.ToLowerInvariant()
if (Test-Path -LiteralPath $publishedApk) {
    $existingDigest = (Get-FileHash -LiteralPath $publishedApk -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($existingDigest -ne $digest) {
        throw "发布路径已存在内容不同的 APK：$publishedApk。发布包不可变，禁止原地覆盖；请递增 VersionCode 后重新发布。"
    }
}
else {
    Copy-Item -LiteralPath $resolvedApk -Destination $publishedApk
}

$manifest = [ordered]@{
    version_name                   = $safeVersionName
    version_code                   = $VersionCode
    minimum_supported_version_code = $MinimumSupportedVersionCode
    title                          = $Title.Trim()
    changelog                      = $Changelog.Trim()
    apk_file                       = "releases/$VersionCode/$apkFileName"
    sha256                         = $digest
    published_at                   = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$manifestPath = Join-Path $releaseDirectory 'release.json'
$json = $manifest | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText(
    $manifestPath,
    $json,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Output "APK: $publishedApk"
Write-Output "Manifest: $manifestPath"
Write-Output "SHA-256: $digest"
