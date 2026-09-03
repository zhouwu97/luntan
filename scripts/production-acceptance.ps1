#!/usr/bin/env pwsh
<#
.SYNOPSIS
生产环境验收脚本 - 媒体私有化和部署配置验证

.DESCRIPTION
验证媒体网关部署闭环和生产环境配置的完整性。
必须在生产环境部署后、正式上线前运行。

.PARAMETER ServerHost
生产服务器地址，例如 43.161.249.91 或 api.shengbeijiang.com

.PARAMETER DatabaseUrl
生产数据库连接串（仅用于验证查询）

.PARAMETER SmtpProbeEmail
已验证的生产邮箱地址。脚本会通过真实验证码接口发送一次探测邮件，
用于确认 SMTP 投递链路，而不是只确认接口能返回参数错误。

.PARAMETER SkipMediaValidation
跳过媒体私有化验证（仅用于测试脚本本身）

.EXAMPLE
./scripts/production-acceptance.ps1 -ServerHost 43.161.249.91 -DatabaseUrl $env:DATABASE_URL
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ServerHost,

    [Parameter(Mandatory=$false)]
    [string]$DatabaseUrl = $env:DATABASE_URL,

    [Parameter(Mandatory=$false)]
    [string]$SmtpProbeEmail = $env:PRODUCTION_ACCEPTANCE_EMAIL,

    [Parameter(Mandatory=$false)]
    [switch]$SkipMediaValidation = $false
)

$ErrorActionPreference = 'Stop'
$script:FailedChecks = @()
$script:PassedChecks = @()
$script:WarningChecks = @()

# 验收请求使用源码中的当前客户端版本，避免验收脚本长期固定在旧版本。
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pubspecVersion = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') |
    Where-Object { $_ -match '^\s*version:\s*(?<name>[0-9A-Za-z._-]+)\+(?<code>[1-9][0-9]*)\s*$' } |
    Select-Object -First 1
if ($null -eq $pubspecVersion -or $pubspecVersion -notmatch '^\s*version:\s*(?<name>[0-9A-Za-z._-]+)\+(?<code>[1-9][0-9]*)\s*$') {
    throw 'pubspec.yaml 必须包含合法的 version: name+code'
}
$clientVersionName = $Matches['name']
$clientVersionCode = $Matches['code']

function Write-Header {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $Message" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Write-CheckResult {
    param(
        [string]$Name,
        [string]$Status,  # Pass, Fail, Warning
        [string]$Message
    )

    $symbol = switch ($Status) {
        'Pass' { '✓'; $script:PassedChecks += $Name; 'Green' }
        'Fail' { '✗'; $script:FailedChecks += $Name; 'Red' }
        'Warning' { '⚠'; $script:WarningChecks += $Name; 'Yellow' }
    }

    Write-Host "[$symbol[0]] " -ForegroundColor $symbol[1] -NoNewline
    Write-Host "$Name" -NoNewline
    if ($Message) {
        Write-Host ": $Message" -ForegroundColor Gray
    } else {
        Write-Host ""
    }
}

function Test-HttpEndpoint {
    param(
        [string]$Url,
        [string]$Method = 'GET',
        [int]$ExpectedStatus = 200,
        [hashtable]$Headers = @{},
        [string]$Body = $null,
        [string]$ContentType = 'application/json'
    )

    try {
        $requestOptions = @{
            Uri = $Url
            Method = $Method
            Headers = $Headers
            SkipHttpErrorCheck = $true
            MaximumRedirection = 0
            TimeoutSec = 10
        }
        if ($null -ne $Body) {
            $requestOptions.Body = $Body
            $requestOptions.ContentType = $ContentType
        }
        $response = Invoke-WebRequest @requestOptions
        return @{
            Reachable = $true
            Success = ($response.StatusCode -eq $ExpectedStatus)
            StatusCode = $response.StatusCode
            Content = [string]$response.Content
            Location = $response.Headers['Location']
        }
    } catch {
        return @{
            Reachable = $false
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Test-DatabaseQuery {
    param(
        [string]$Query,
        [string]$ConnectionString
    )

    if (-not $ConnectionString) {
        throw "数据库连接串未提供"
    }

    try {
        # 使用 psql 执行查询
        $result = psql $ConnectionString -t -c $Query 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "查询失败: $result"
        }
        return $result.Trim()
    } catch {
        throw "数据库查询错误: $_"
    }
}

# ============================================
# 1. 基础连接性检查
# ============================================

Write-Header "1. 基础连接性检查"

$apiBaseUrl = "https://$ServerHost"

# 1.1 健康检查
Write-Host "检查 API 健康状态..." -ForegroundColor Gray
$healthCheck = Test-HttpEndpoint -Url "$apiBaseUrl/health"
if ($healthCheck.Success) {
    Write-CheckResult "API 健康检查" "Pass" "/health 返回 200"
} else {
    Write-CheckResult "API 健康检查" "Fail" "无法访问或返回非 200 状态"
}

# 1.2 就绪检查
Write-Host "检查 API 就绪状态..." -ForegroundColor Gray
$readyCheck = Test-HttpEndpoint -Url "$apiBaseUrl/ready"
if ($readyCheck.Success) {
    Write-CheckResult "API 就绪检查" "Pass" "/ready 返回 200"
} else {
    Write-CheckResult "API 就绪检查" "Fail" "服务未就绪"
}

# 1.3 发布版本信息
Write-Host "获取当前发布版本..." -ForegroundColor Gray
$versionCheck = Test-HttpEndpoint -Url "$apiBaseUrl/api/v1/app/releases/latest"
if ($versionCheck.Success) {
    Write-CheckResult "API 版本信息" "Pass" "发布清单可访问"
    Write-Host "  版本详情: $($versionCheck.Content)" -ForegroundColor DarkGray
} else {
    Write-CheckResult "API 版本信息" "Fail" "无法获取发布清单（状态: $($versionCheck.StatusCode)）"
}

# ============================================
# 2. 媒体私有化验证
# ============================================

if (-not $SkipMediaValidation) {
    Write-Header "2. 媒体私有化验证"

    # 2.1 数据库：pending_backfill 检查
    Write-Host "检查待回填媒体数量..." -ForegroundColor Gray

    $backfillQuery = @"
SELECT count(*) AS pending_backfill
FROM media_assets ma
WHERE ma.status = 'ready' AND ma.deleted_at IS NULL AND ma.mime_type LIKE 'image/%'
  AND NOT (
    EXISTS (SELECT 1 FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'original' AND mv.status = 'ready')
    AND EXISTS (SELECT 1 FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'detail' AND mv.status = 'ready')
    AND EXISTS (SELECT 1 FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'thumb' AND mv.status = 'ready')
  );
"@

    try {
        $pendingBackfill = Test-DatabaseQuery -Query $backfillQuery -ConnectionString $DatabaseUrl
        if ($pendingBackfill -eq "0") {
            Write-CheckResult "媒体 backfill" "Pass" "pending_backfill = 0，所有图片已回填"
        } else {
            Write-CheckResult "媒体 backfill" "Fail" "pending_backfill = $pendingBackfill，仍有图片未回填"
        }
    } catch {
        Write-CheckResult "媒体 backfill" "Fail" "无法查询数据库: $_"
    }

    # 2.2 数据库：outbox 失败事件检查
    Write-Host "检查 outbox 失败事件..." -ForegroundColor Gray

    $outboxQuery = @"
SELECT count(*) AS failed_events
FROM outbox_events
WHERE event_type IN ('media.process', 'media.delete') AND status = 'failed';
"@

    try {
        $failedEvents = Test-DatabaseQuery -Query $outboxQuery -ConnectionString $DatabaseUrl
        if ($failedEvents -eq "0") {
            Write-CheckResult "Outbox 失败事件" "Pass" "failed_events = 0"
        } else {
            Write-CheckResult "Outbox 失败事件" "Fail" "failed_events = $failedEvents"
        }
    } catch {
        Write-CheckResult "Outbox 失败事件" "Fail" "无法查询数据库: $_"
    }

    # 2.3 旧媒体路径应返回 404
    Write-Host "验证旧媒体路径已禁用..." -ForegroundColor Gray
    $oldMediaCheck = Test-HttpEndpoint -Url "$apiBaseUrl/media/test.jpg" -ExpectedStatus 404
    if ($oldMediaCheck.Success) {
        Write-CheckResult "旧媒体路径禁用" "Pass" "/media/ 返回 404"
    } else {
        Write-CheckResult "旧媒体路径禁用" "Fail" "/media/ 仍可访问（状态: $($oldMediaCheck.StatusCode)）"
    }

    # 2.4 内部加速路径不应公开访问
    Write-Host "验证内部加速路径不可公开访问..." -ForegroundColor Gray
    $internalCheck = Test-HttpEndpoint -Url "$apiBaseUrl/_protected_media/test.jpg" -ExpectedStatus 404
    if ($internalCheck.StatusCode -in @(404, 403)) {
        Write-CheckResult "内部路径保护" "Pass" "/_protected_media/ 不可公开访问"
    } else {
        Write-CheckResult "内部路径保护" "Fail" "/_protected_media/ 可公开访问（状态: $($internalCheck.StatusCode)）"
    }

    # 2.5 媒体网关端点应正常工作
    Write-Host "验证媒体网关端点..." -ForegroundColor Gray

    # 获取一个真实的媒体 ID 进行测试
    $mediaIdQuery = @"
SELECT m.id
FROM media_assets m
WHERE m.status = 'ready' AND m.deleted_at IS NULL AND m.mime_type LIKE 'image/%'
  AND EXISTS (
      SELECT 1 FROM media_variants mv
      WHERE mv.media_id = m.id AND mv.variant = 'thumb' AND mv.status = 'ready'
  )
  AND (
      EXISTS (
          SELECT 1 FROM post_media pm
          JOIN posts p ON p.id = pm.post_id
          WHERE pm.media_id = m.id AND p.deleted_at IS NULL
            AND p.publication_status = 'published' AND p.moderation_status = 'normal'
      ) OR EXISTS (
          SELECT 1 FROM comment_media cm
          JOIN comments c ON c.id = cm.comment_id
          WHERE cm.media_id = m.id AND c.deleted_at IS NULL
            AND c.publication_status = 'published' AND c.moderation_status = 'normal'
      )
  )
ORDER BY m.created_at DESC, m.id DESC
LIMIT 1;
"@

    try {
        $testMediaId = Test-DatabaseQuery -Query $mediaIdQuery -ConnectionString $DatabaseUrl
        if ($testMediaId) {
            $mediaGatewayCheck = Test-HttpEndpoint -Url "$apiBaseUrl/api/v1/media-file/$testMediaId/thumb"
            if ($mediaGatewayCheck.Success) {
                Write-CheckResult "媒体网关端点" "Pass" "可通过网关访问媒体"
            } else {
                Write-CheckResult "媒体网关端点" "Fail" "网关返回状态: $($mediaGatewayCheck.StatusCode)"
            }
        } else {
            Write-CheckResult "媒体网关端点" "Fail" "没有可用于匿名网关验收的公开 ready 媒体"
        }
    } catch {
        Write-CheckResult "媒体网关端点" "Fail" "无法查询或测试: $_"
    }

} else {
    Write-Host "`n[跳过] 媒体私有化验证（--SkipMediaValidation）`n" -ForegroundColor Yellow
}

# ============================================
# 3. 安全配置验证
# ============================================

Write-Header "3. 安全配置验证"

# 3.1 HTTPS 强制
Write-Host "检查 HTTPS 强制..." -ForegroundColor Gray
$httpCheck = Test-HttpEndpoint -Url "http://$ServerHost/health"
if ($httpCheck.Reachable -and $httpCheck.StatusCode -in @(301, 302, 307, 308) -and $httpCheck.Location -match '^https://') {
    Write-CheckResult "HTTPS 重定向" "Pass" "HTTP 请求收到原始 $($httpCheck.StatusCode) 并重定向到 HTTPS"
} elseif ($httpCheck.Reachable) {
    Write-CheckResult "HTTPS 重定向" "Fail" "HTTP 请求未严格重定向到 HTTPS（状态: $($httpCheck.StatusCode)，Location: $($httpCheck.Location)）"
} else {
    Write-CheckResult "HTTPS 重定向" "Pass" "HTTP 端口不可访问（已关闭）"
}

# 3.2 敏感端点保护
Write-Host "检查敏感端点保护..." -ForegroundColor Gray
$metricsCheck = Test-HttpEndpoint -Url "$apiBaseUrl/metrics" -ExpectedStatus 403
if ($metricsCheck.StatusCode -in @(403, 404)) {
    Write-CheckResult "Metrics 端点保护" "Pass" "/metrics 不可公开访问"
} else {
    Write-CheckResult "Metrics 端点保护" "Fail" "/metrics 可公开访问（状态: $($metricsCheck.StatusCode)）"
}

# 3.3 管理员端点需要认证
Write-Host "检查管理员端点认证..." -ForegroundColor Gray
$adminCheck = Test-HttpEndpoint -Url "$apiBaseUrl/api/v1/admin/users" -ExpectedStatus 401
if ($adminCheck.StatusCode -eq 401) {
    Write-CheckResult "管理员端点认证" "Pass" "未认证请求返回 401"
} else {
    Write-CheckResult "管理员端点认证" "Fail" "管理员端点可能未正确保护（状态: $($adminCheck.StatusCode)）"
}

# ============================================
# 4. APK 更新链路验证
# ============================================

Write-Header "4. APK 更新链路验证"

# 4.1 检查与服务端实际路由一致的发布接口
Write-Host "检查 APK 发布清单和更新 API..." -ForegroundColor Gray
$latestReleaseCheck = Test-HttpEndpoint -Url "$apiBaseUrl/api/v1/app/releases/latest"
$updateApiCheck = Test-HttpEndpoint -Url "$apiBaseUrl/api/v1/app/update?platform=android&channel=stable&version_name=$clientVersionName&version_code=$clientVersionCode"
if ($latestReleaseCheck.Success -and $updateApiCheck.Success) {
    Write-CheckResult "APK 更新 API" "Pass" "发布清单与更新接口均可访问"

    try {
        $releaseInfo = $latestReleaseCheck.Content | ConvertFrom-Json
        $updateInfo = $updateApiCheck.Content | ConvertFrom-Json
        $downloadUrl = [string]$releaseInfo.download_url
        if (-not $downloadUrl) {
            $downloadUrl = [string]$updateInfo.download_url
        }
        if (-not $downloadUrl) {
            throw "响应未返回 download_url"
        }
        Write-Host "  下载 URL: $downloadUrl" -ForegroundColor DarkGray

        try {
            $downloadUri = [System.Uri]$downloadUrl
        } catch {
            throw "download_url 不是有效 URL"
        }
        if ($downloadUri.Scheme -eq 'https') {
            Write-CheckResult "APK 下载 HTTPS" "Pass" "下载 URL 使用 HTTPS"
        } else {
            Write-CheckResult "APK 下载 HTTPS" "Fail" "下载 URL 未使用 HTTPS"
        }

        $configuredDownloadHosts = $env:PRODUCTION_ALLOWED_DOWNLOAD_HOSTS
        $allowedHosts = if ($configuredDownloadHosts) {
            $configuredDownloadHosts.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }
        } else {
            @('download.shengbeijiang.com')
        }
        $urlHost = $downloadUri.Host.ToLowerInvariant()
        if ($downloadUri.Scheme -eq 'https' -and $urlHost -in $allowedHosts) {
            Write-CheckResult "APK 下载域名" "Pass" "下载域名在白名单中: $urlHost"
        } else {
            Write-CheckResult "APK 下载域名" "Fail" "下载域名 $urlHost 不在生产白名单中"
        }
    } catch {
        Write-CheckResult "APK 更新响应解析" "Fail" "无法解析完整发布响应: $_"
    }
} else {
    Write-CheckResult "APK 更新 API" "Fail" "发布清单或更新 API 不可访问（latest=$($latestReleaseCheck.StatusCode), update=$($updateApiCheck.StatusCode)）"
}

# ============================================
# 5. 数据库迁移状态
# ============================================

Write-Header "5. 数据库迁移状态"

Write-Host "检查数据库迁移状态..." -ForegroundColor Gray

try {
    # 旧环境的 schema_migrations 只有 version/applied_at；当前迁移器会补齐
    # dirty 列。先探测列是否存在，避免验收脚本自身阻断已完成的旧环境迁移。
    $hasDirtyColumn = Test-DatabaseQuery -Query @"
SELECT CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'schema_migrations' AND column_name = 'dirty'
) THEN '1' ELSE '0' END;
"@ -ConnectionString $DatabaseUrl
    $migrationQuery = if ($hasDirtyColumn -eq '1') {
        "SELECT version || '|' || CASE WHEN dirty THEN 't' ELSE 'f' END FROM schema_migrations ORDER BY version::int DESC LIMIT 1;"
    } else {
        "SELECT version || '|f' FROM schema_migrations ORDER BY version::int DESC LIMIT 1;"
    }
    $migrationStatus = Test-DatabaseQuery -Query $migrationQuery -ConnectionString $DatabaseUrl
    if ($migrationStatus) {
        $parts = $migrationStatus -split '\|'
        if ($parts.Count -ne 2) {
            throw "迁移状态格式无效: $migrationStatus"
        }
        $version = $parts[0].Trim()
        $dirty = $parts[1].Trim()

        if ($dirty -eq 'f') {
            Write-CheckResult "数据库迁移" "Pass" "最新版本: $version, 状态: 干净"
        } else {
            Write-CheckResult "数据库迁移" "Fail" "迁移状态 dirty=true，需要修复"
        }
    } else {
        Write-CheckResult "数据库迁移" "Fail" "无法获取迁移状态"
    }
} catch {
    Write-CheckResult "数据库迁移" "Fail" "无法查询迁移表: $_"
}

# ============================================
# 6. SMTP 配置验证（真实投递链路）
# ============================================

Write-Header "6. SMTP 配置验证"

Write-Host "检查 SMTP 配置（通过真实验证码 API）..." -ForegroundColor Gray

if (-not $SmtpProbeEmail) {
    Write-CheckResult "SMTP 配置" "Fail" "必须提供 -SmtpProbeEmail 或 PRODUCTION_ACCEPTANCE_EMAIL"
} else {
    $escapedProbeEmail = $SmtpProbeEmail.Replace("'", "''")
    $probeUserQuery = "SELECT CASE WHEN EXISTS (SELECT 1 FROM users WHERE lower(email) = lower('$escapedProbeEmail') AND email_verified = true AND deleted_at IS NULL) THEN '1' ELSE '0' END;"
    try {
        $probeUserExists = Test-DatabaseQuery -Query $probeUserQuery -ConnectionString $DatabaseUrl
        if ($probeUserExists -ne '1') {
            Write-CheckResult "SMTP 配置" "Fail" "探测邮箱不是已验证的生产账号，无法证明真实投递链路"
        } else {
            # 当前服务端真实路由是 POST /api/v1/auth/code/request；携带已注册邮箱
            # 才会进入 SMTP 发送分支，而不是因为邮箱不存在直接返回 202。
            $smtpBody = (@{ email = $SmtpProbeEmail; scene = 'login' } | ConvertTo-Json -Compress)
            $smtpTestCheck = Test-HttpEndpoint -Url "$apiBaseUrl/api/v1/auth/code/request" `
                -Method 'POST' -Body $smtpBody -ExpectedStatus 200
            if ($smtpTestCheck.Success) {
                Write-CheckResult "SMTP 配置" "Pass" "验证码接口成功受理真实投递"
            } else {
                Write-CheckResult "SMTP 配置" "Fail" "验证码接口未返回 200（状态: $($smtpTestCheck.StatusCode)）"
            }
        }
    } catch {
        Write-CheckResult "SMTP 配置" "Fail" "无法验证探测邮箱或 SMTP: $_"
    }
}

# ============================================
# 生成报告
# ============================================

Write-Header "验收报告"

$totalChecks = $script:PassedChecks.Count + $script:FailedChecks.Count + $script:WarningChecks.Count

Write-Host "总计检查项: $totalChecks" -ForegroundColor White
Write-Host "通过: $($script:PassedChecks.Count)" -ForegroundColor Green
Write-Host "警告: $($script:WarningChecks.Count)" -ForegroundColor Yellow
Write-Host "失败: $($script:FailedChecks.Count)" -ForegroundColor Red

if ($script:FailedChecks.Count -gt 0) {
    Write-Host "`n失败的检查项:" -ForegroundColor Red
    $script:FailedChecks | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "`n❌ 生产环境验收未通过，请修复上述问题后重新验收" -ForegroundColor Red
    exit 1
} elseif ($script:WarningChecks.Count -gt 0) {
    Write-Host "`n警告的检查项:" -ForegroundColor Yellow
    $script:WarningChecks | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host "`n❌ 生产环境验收未通过：存在未决警告项，请先将其明确为通过或失败" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`n✅ 生产环境验收完全通过，可以正式上线" -ForegroundColor Green
    exit 0
}
