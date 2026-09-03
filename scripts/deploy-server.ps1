# 服务器部署脚本 + APK 上传
# 用法: 在 Claude Code 提示符输入 ! .\scripts\deploy-server.ps1

$server = "root@43.161.249.91"
$repoPath = "/root/bb"
$apkLocal = "E:\AI\bb\build\app\outputs\flutter-apk\app-release.apk"
$apkRemote = "/var/www/html/app-release.apk"
$downloadUrl = "https://shengbeijiang.com/app-release.apk"

Write-Host "=== 步骤 1: 上传 APK ===" -ForegroundColor Cyan
Write-Host "本地: $apkLocal" -ForegroundColor Yellow
Write-Host "远程: $apkRemote" -ForegroundColor Yellow
Write-Host "下载地址: $downloadUrl" -ForegroundColor Magenta
Write-Host ""

scp $apkLocal "${server}:${apkRemote}"

if ($LASTEXITCODE -ne 0) {
    Write-Host "APK 上传失败" -ForegroundColor Red
    exit 1
}
Write-Host "✓ APK 上传成功" -ForegroundColor Green

Write-Host "`n=== 步骤 2: 拉取代码并重启服务 ===" -ForegroundColor Cyan

$commands = @(
    "cd $repoPath",
    "git fetch origin",
    "git pull origin main",
    "cd server",
    "go build -o /root/luntan-api ./cmd/api",
    "systemctl restart luntan-api || (pkill luntan-api; nohup /root/luntan-api > /root/api.log 2>&1 &)",
    "sleep 2",
    "curl -f http://localhost:8080/health || echo 'Health check failed'"
)

$remoteCmd = $commands -join ' && '

Write-Host "执行命令: $remoteCmd" -ForegroundColor Yellow
Write-Host ""

ssh $server $remoteCmd

Write-Host "`n=== 部署完成 ===" -ForegroundColor Green
Write-Host "APK 下载地址: $downloadUrl" -ForegroundColor Cyan
