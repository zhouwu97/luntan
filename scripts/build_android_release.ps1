param(
    [Parameter(Mandatory = $true)]
    [string]$VersionName,

    [Parameter(Mandatory = $true)]
    [long]$VersionCode,

    # 传入 -Publish 时以下四项必填，转发给 prepare_app_release.ps1。
    [string]$OutputDirectory,
    [string]$Title,
    [string]$Changelog,
    [long]$MinimumSupportedVersionCode = 0,

    [switch]$Publish
)

$ErrorActionPreference = 'Stop'

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

Set-Location -LiteralPath (Join-Path $PSScriptRoot '..')

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
flutter build apk `
    --release `
    --target-platform android-arm64 `
    --build-name $VersionName `
    --build-number $VersionCode
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
