# 发布与恢复演练 Runbook

## Staging

1. PR 必须先通过 `.github/workflows/ci.yml`。
2. 冻结通过审核的完整 commit SHA；staging 和 production 都不得使用 `latest`。
3. GitHub `staging` environment 必须配置以下 SSH secrets：
   `STAGING_SSH_HOST`、`STAGING_SSH_USER`、`STAGING_SSH_PRIVATE_KEY`；可选
   `STAGING_SSH_PORT`，默认 22。禁止把服务器密码、私钥或数据库连接串提交到仓库。
4. 手动触发 `deploy-staging` 并填写完整 40 位 `release_sha`。workflow 会对同一 SHA
   执行 Go/Flutter 验证、构建服务器归档、推送同 SHA 的 GHCR 镜像，并把归档交给
   `scripts/deploy-staging.sh`。
5. 目标机使用不可变 release 目录：先备份数据库，再运行该 release 的
   `luntan-migrate`，然后切换 systemd 的 API/worker 与 Nginx Web 链接，最后执行
   `scripts/staging-smoke.sh` 检查 `/health`、`/ready`、Feed、商城、发布清单、媒体
   网关、迁移状态和 outbox。任一步失败会自动回指上一份应用 release。
6. 迁移失败时停止 rollout，不允许跳过 migration 继续发布。应用回滚不会自动执行
   数据库 down migration；增量迁移必须保持旧版本可兼容，必要时使用备份恢复演练。

目标机手工部署（仅用于没有 GitHub runner 的受控运维场景）：

```bash
bash scripts/deploy-staging.sh /opt/luntan-qa/staging/incoming/staging-release-<sha>.tar.gz <sha>
```

手工回滚到指定目录：

```bash
bash scripts/rollback-staging.sh /opt/luntan-qa/releases/<sha>-<timestamp>
```

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
