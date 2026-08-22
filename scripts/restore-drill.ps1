[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BackupFile,
    [string]$TargetDatabaseUrl = $env:RESTORE_DATABASE_URL
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) {
    throw "备份文件不存在：$BackupFile"
}
if ([string]::IsNullOrWhiteSpace($TargetDatabaseUrl)) {
    throw 'RESTORE_DATABASE_URL 未配置；恢复演练必须使用独立测试数据库。'
}

$pgRestore = Get-Command pg_restore -ErrorAction SilentlyContinue
if ($null -eq $pgRestore) {
    throw '未找到 pg_restore，请先安装 PostgreSQL 客户端。'
}
$env:DATABASE_URL = $TargetDatabaseUrl

& $pgRestore.Source --clean --if-exists --no-owner --dbname=$TargetDatabaseUrl $BackupFile
if ($LASTEXITCODE -ne 0) {
    throw "pg_restore 失败，退出码 $LASTEXITCODE。"
}

Push-Location (Join-Path (Join-Path $PSScriptRoot '..') 'server')
try {
    go run ./cmd/migrate
    if ($LASTEXITCODE -ne 0) {
        throw "恢复后的 migration 失败，退出码 $LASTEXITCODE。"
    }
} finally {
    Pop-Location
}

$psql = Get-Command psql -ErrorAction SilentlyContinue
if ($null -eq $psql) {
    throw '未找到 psql，无法执行恢复后 smoke test。'
}
& $psql.Source $TargetDatabaseUrl --command 'SELECT 1 AS restore_smoke_test;'
if ($LASTEXITCODE -ne 0) {
    throw "恢复后 smoke test 失败，退出码 $LASTEXITCODE。"
}
'restore_result=passed'
