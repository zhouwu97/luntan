param(
    [string]$VersionName,

    [long]$VersionCode = 0,

    # 传入 -Publish 时以下四项必填，转发给 prepare_app_release.ps1。
    [string]$OutputDirectory,
    [string]$Title,
    [string]$Changelog,
    [long]$MinimumSupportedVersionCode = 0,

    # Release APK 默认连接正式 HTTPS API；QA 或私有环境必须显式覆盖三项编译期配置。
    [string]$AppEnvironment = 'production',
    [string]$ApiBaseUrl = 'https://shengbeijiang.com',
    [string]$WebBaseUrl = 'https://shengbeijiang.com',

    [switch]$Publish
)

$ErrorActionPreference = 'Stop'

$normalizedAppEnvironment = $AppEnvironment.Trim().ToLowerInvariant()
if ($normalizedAppEnvironment -notin @('production', 'qa', 'staging')) {
    throw 'AppEnvironment 只能是 production、qa 或 staging'
}

function Assert-HttpUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [switch]$RequireHttps
    )

    $trimmed = $Value.Trim()
    $uri = $null
    if ([string]::IsNullOrWhiteSpace($trimmed) -or
        -not [Uri]::TryCreate($trimmed, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Host -eq '' -or
        ($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https')) {
        throw "$Name 必须是完整的 HTTP(S) 地址"
    }
    if ($RequireHttps -and $uri.Scheme -ne 'https') {
        throw "正式环境的 $Name 必须使用 HTTPS"
    }
}

Assert-HttpUrl -Value $ApiBaseUrl -Name 'ApiBaseUrl' -RequireHttps:($normalizedAppEnvironment -eq 'production')
Assert-HttpUrl -Value $WebBaseUrl -Name 'WebBaseUrl'

Set-Location -LiteralPath (Join-Path $PSScriptRoot '..')

# 版本以 pubspec.yaml 为唯一来源；命令行参数仅作为兼容入口，并且必须匹配，
# 避免 APK、PackageInfo 与 release.json 生成出三套版本事实。
$pubspecPath = Join-Path (Get-Location) 'pubspec.yaml'
$pubspecVersionLine = Get-Content -LiteralPath $pubspecPath -Encoding utf8 |
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

if ($Publish) {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory) -or
        [string]::IsNullOrWhiteSpace($Title) -or
        [string]::IsNullOrWhiteSpace($Changelog)) {
        throw '-Publish 需要 -OutputDirectory、-Title、-Changelog、-MinimumSupportedVersionCode'
    }
    if ($MinimumSupportedVersionCode -le 0 -or $MinimumSupportedVersionCode -gt $VersionCode) {
        throw 'MinimumSupportedVersionCode 必须为正整数且不能大于 VersionCode'
    }
}

if (-not (Get-Command 'flutter' -ErrorAction SilentlyContinue)) {
    throw '未找到命令：flutter'
}

Write-Output '==> flutter clean'
flutter clean
if ($LASTEXITCODE -ne 0) { throw "flutter clean 失败（exit $LASTEXITCODE）" }

Write-Output '==> flutter pub get'
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get 失败（exit $LASTEXITCODE）" }

Write-Output '==> flutter build apk (arm64-v8a only)'
Write-Output "运行时配置: APP_ENV=$normalizedAppEnvironment API_BASE_URL=$($ApiBaseUrl.Trim()) WEB_BASE_URL=$($WebBaseUrl.Trim())"
flutter build apk `
    --release `
    --target-platform android-arm64 `
    --build-name $VersionName `
    --build-number $VersionCode `
    "--dart-define=APP_ENV=$normalizedAppEnvironment" `
    "--dart-define=API_BASE_URL=$($ApiBaseUrl.Trim())" `
    "--dart-define=WEB_BASE_URL=$($WebBaseUrl.Trim())"
if ($LASTEXITCODE -ne 0) { throw "flutter build apk 失败（exit $LASTEXITCODE）" }

$apkPath = Join-Path (Get-Location) 'build/app/outputs/flutter-apk/app-release.apk'
if (-not (Test-Path -LiteralPath $apkPath)) {
    throw "未找到构建产物：$apkPath"
}

# 正式发布包必须是 ARM64-only：禁止混入其他 ABI 的原生库，防止以后又打出 85MB 的 fat APK。
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($apkPath)
try {
    $entries = $zip.Entries | ForEach-Object { $_.FullName }
    $forbiddenAbis = @('armeabi-v7a', 'x86_64', 'x86')
    foreach ($abi in $forbiddenAbis) {
        if ($entries | Where-Object { $_ -like "lib/$abi/*" }) {
            throw "正式发布 APK 不是 ARM64-only：检测到 lib/$abi/，拒绝发布。"
        }
    }
    $arm64Libs = @($entries | Where-Object { $_ -like 'lib/arm64-v8a/*' -and $_ -like '*.so' })
    if ($arm64Libs.Count -eq 0) {
        throw '正式发布 APK 缺少 lib/arm64-v8a/ 原生库，拒绝发布。'
    }
    Write-Output ("ARM64 原生库: " + ($arm64Libs -join ', '))
}
finally {
    $zip.Dispose()
}

$apkSizeMb = [math]::Round((Get-Item -LiteralPath $apkPath).Length / 1MB, 1)
Write-Output "APK: $apkPath ($apkSizeMb MB)"

if ($Publish) {
    Write-Output '==> prepare_app_release.ps1'
    & (Join-Path $PSScriptRoot 'prepare_app_release.ps1') `
        -ApkPath $apkPath `
        -OutputDirectory $OutputDirectory `
        -VersionName $VersionName `
        -VersionCode $VersionCode `
        -MinimumSupportedVersionCode $MinimumSupportedVersionCode `
        -Title $Title `
        -Changelog $Changelog
    if ($LASTEXITCODE -ne 0) { throw "prepare_app_release.ps1 失败（exit $LASTEXITCODE）" }
}
