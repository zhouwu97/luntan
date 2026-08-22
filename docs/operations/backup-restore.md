# PostgreSQL 备份与恢复演练

## 备份

生产环境使用托管 PostgreSQL 的自动备份和 PITR；对象存储启用版本控制与生命周期策略。备份不能替代迁移文件，`server/migrations/` 必须和应用版本一起发布。

## 恢复演练

1. 创建隔离测试数据库，禁止覆盖生产数据库。
2. 从最近备份恢复数据。
3. 执行 `go test ./server/internal/platform/database -run TestMigrationsAgainstPostgres` 或等价迁移流程。
4. 启动 API 与 worker，验证 `/health`、`/ready`、认证、Feed、帖子、评论和媒体状态读取。
5. 记录 Restore Result、Restore Time、数据缺口和修复动作。

恢复完成前不得把测试数据库切换成生产流量。
