# 发布与恢复演练 Runbook

## Staging

1. PR 必须先通过 `.github/workflows/ci.yml`。
2. 冻结通过审核的完整 commit SHA；staging 和 production 都不得使用 `latest`。
3. 手动触发 `deploy-staging`，并在 GitHub `staging` environment 配置 `STAGING_DEPLOY_COMMAND`。
4. 部署命令必须按顺序执行：拉取 `IMAGE_TAG`、运行 `/app/luntan-migrate`、启动 API、检查 `/health` 和 `/ready`、观察 `/metrics`。
5. 迁移失败时停止 rollout，不允许跳过 migration 继续发布。

## Production

生产发布使用 `.github/workflows/deploy-production.yml`，必须手动提供完整的
`release_sha` 并确认 `confirm_production=true`。工作流会校验 checkout 后的 commit
与输入 SHA 完全一致，并要求 GHCR 中存在同一 SHA 的不可变镜像标签；不存在时不会
进入部署阶段。

GitHub `production` environment 必须配置 required reviewers，并保存
`PRODUCTION_DEPLOY_COMMAND` secret。该命令可使用工作流注入的 `IMAGE_TAG` 与
`RELEASE_SHA`，且必须按以下顺序执行：

1. 生产数据库备份、备份文件校验，必要时完成 restore drill。
2. 拉取精确的 `IMAGE_TAG`，禁止 `latest` 或重新构建未审计代码。
3. 运行 `/app/luntan-migrate`；迁移失败立即退出并停止 rollout。
4. 启动新 API/worker，检查 `/health`、`/ready`、smoke 和关键指标。
5. 完成切流量与短时观察后再结束命令；任何失败必须返回非零退出码。

生产迁移前先执行 `scripts/backup.ps1`，工作流本身不会替代数据库备份或生产环境
required reviewer 配置。

## Restore Drill

```powershell
$env:RESTORE_DATABASE_URL = 'postgres://.../luntan_restore'
./scripts/restore-drill.ps1 -BackupFile .\backups\luntan_20260823T000000Z.dump
```

恢复演练目标必须是新建的测试数据库，记录备份文件、SHA-256、恢复耗时、migration 结果和 smoke test 结果。
