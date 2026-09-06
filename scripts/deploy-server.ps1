# 服务器部署脚本 + APK 上传
# 用法: .\scripts\deploy-server.ps1

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
    "go build -o /root/luntan-worker ./cmd/worker",
    "systemctl restart luntan-api",
    "curl --retry 10 --retry-delay 1 --retry-connrefused -f http://localhost:8080/health",
    "systemctl restart luntan-worker",
    "systemctl is-active --quiet luntan-api luntan-worker",
    "sleep 2",
    "curl -f http://localhost:8080/health"
)

$remoteCmd = $commands -join ' && '

Write-Host "执行命令: $remoteCmd" -ForegroundColor Yellow
Write-Host ""

ssh $server $remoteCmd
if ($LASTEXITCODE -ne 0) { throw "服务器部署或健康检查失败" }

Write-Host "`n=== 部署完成 ===" -ForegroundColor Green
Write-Host "APK 下载地址: $downloadUrl" -ForegroundColor Cyan
