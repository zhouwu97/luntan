# 发布与恢复演练 Runbook

## Staging

1. PR 必须先通过 `.github/workflows/ci.yml`。
2. 手动触发 `deploy-staging`，并在 GitHub `staging` environment 配置 `STAGING_DEPLOY_COMMAND`。
3. 部署命令必须按顺序执行：拉取 `IMAGE_TAG`、运行 `/app/luntan-migrate`、启动 API、检查 `/health` 和 `/ready`、观察 `/metrics`。
4. 迁移失败时停止 rollout，不允许跳过 migration 继续发布。

## Production

生产发布必须使用独立的受保护 environment，并由人工批准后执行同样的迁移、健康检查和指标观察流程；生产迁移前先执行 `scripts/backup.ps1`。

## Restore Drill

```powershell
$env:RESTORE_DATABASE_URL = 'postgres://.../luntan_restore'
./scripts/restore-drill.ps1 -BackupFile .\backups\luntan_20260823T000000Z.dump
```

恢复演练目标必须是新建的测试数据库，记录备份文件、SHA-256、恢复耗时、migration 结果和 smoke test 结果。
