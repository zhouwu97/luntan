[CmdletBinding()]
param(
    [string]$DatabaseUrl = $env:DATABASE_URL,
    [string]$BackupDirectory = (Join-Path (Get-Location) 'backups')
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
    throw 'DATABASE_URL 未配置。'
}
$pgDump = Get-Command pg_dump -ErrorAction SilentlyContinue
if ($null -eq $pgDump) {
    throw '未找到 pg_dump，请先安装 PostgreSQL 客户端。'
}

$resolvedDirectory = New-Item -ItemType Directory -Force -Path $BackupDirectory
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$backupFile = Join-Path $resolvedDirectory.FullName "luntan_$stamp.dump"
& $pgDump.Source --format=custom --no-owner --file=$backupFile $DatabaseUrl
if ($LASTEXITCODE -ne 0) {
    throw "pg_dump 失败，退出码 $LASTEXITCODE。"
}

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $backupFile
"backup_file=$backupFile"
"sha256=$($hash.Hash)"
