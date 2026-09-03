# 生产环境验收清单

本文档提供生产环境上线前的完整验收流程，包括自动化验收脚本和手工测试清单。

## 前置条件

- [ ] 所有 P0/P1/P2 代码问题已修复并通过 CI
- [ ] Staging 环境已完成部署和测试
- [ ] 生产数据库已备份
- [ ] 部署窗口已与团队确认

## 一、自动化验收

### 1.1 运行验收脚本

```powershell
# 设置数据库连接串
$env:DATABASE_URL = "postgresql://user:password@43.161.249.91:5432/luntan"

# 运行完整验收（必须使用一个已验证的生产邮箱做真实 SMTP 探测）
$env:PRODUCTION_ACCEPTANCE_EMAIL = "ops@example.com"
./scripts/production-acceptance.ps1 -ServerHost 43.161.249.91 -SmtpProbeEmail $env:PRODUCTION_ACCEPTANCE_EMAIL
```

**预期结果**：
- 所有检查项通过（绿色 ✓）
- 无失败项（红色 ✗）
- 无未决警告项；脚本遇到警告也会以退出码 1 终止

**验收脚本检查内容**：

| 类别 | 检查项 | 重要性 |
|------|--------|--------|
| 基础连接 | `/health` 返回 200 | 必须 |
| 基础连接 | `/ready` 返回 200 | 必须 |
| 基础连接 | `/api/v1/app/releases/latest` 发布清单可访问 | 必须 |
| 媒体私有化 | `pending_backfill = 0` | 必须 |
| 媒体私有化 | outbox `media.process` 和 `media.delete` 的 `failed = 0` | 必须 |
| 媒体私有化 | `/media/` 返回 404 | 必须 |
| 媒体私有化 | `/_protected_media/` 不可公开访问 | 必须 |
| 媒体私有化 | 媒体网关端点正常工作 | 必须 |
| 安全配置 | HTTP → HTTPS 返回原始 301/302/307/308，且 Location 为 HTTPS | 必须（HTTP 端口关闭时可通过） |
| 安全配置 | `/metrics` 不可公开访问 | 必须 |
| 安全配置 | 管理员端点需要认证 | 必须 |
| APK 更新 | `/api/v1/app/releases/latest` 与 `/api/v1/app/update` 可访问 | 必须 |
| APK 更新 | 下载 URL 使用 HTTPS | 必须 |
| APK 更新 | 下载域名在 `PRODUCTION_ALLOWED_DOWNLOAD_HOSTS` 白名单中 | 必须 |
| 数据库 | 迁移状态干净 (dirty=false) | 必须 |
| SMTP | `POST /api/v1/auth/code/request` 使用已验证账号真实发送验证码 | 必须 |

### 1.2 验收脚本失败时的处理

如果验收脚本报告失败，按以下步骤处理：

#### 媒体 backfill 未完成
```sql
-- 检查待回填数量
SELECT count(*) FROM media_assets ma
WHERE ma.status = 'ready' AND ma.deleted_at IS NULL
  AND ma.mime_type LIKE 'image/%'
  AND NOT EXISTS (
    SELECT 1 FROM media_variants mv 
    WHERE mv.media_id = ma.id AND mv.variant = 'original' 
    AND mv.status = 'ready'
  );
```

**修复**：
```bash
# 重新运行 backfill
/app/luntan-media-backfill

# 等待 worker 处理完成
# 观察 outbox_events 表中 media.process 和 media.delete 事件的状态
```

#### Outbox 失败事件
```sql
-- 查看失败详情
SELECT id, event_type, payload, error, created_at 
FROM outbox_events 
WHERE status = 'failed' 
ORDER BY created_at DESC 
LIMIT 10;
```

**修复**：
1. 分析失败原因（存储权限、网络、格式错误等）
2. 修复根本原因
3. 重置失败事件状态：
```sql
UPDATE outbox_events 
SET status = 'pending', attempts = 0 
WHERE id = '<event_id>';
```

#### 旧媒体路径仍可访问

检查 Nginx 配置：
```nginx
location ^~ /media/ {
    return 404;
}
```

重新加载 Nginx：
```bash
nginx -t && nginx -s reload
```

---

## 二、手工功能测试

### 2.1 图片审核大图 OOM 测试

**目的**：验证 P1 修复 - 大图不会导致内存溢出

**步骤**：

1. 准备测试图片
   - [ ] 创建或下载接近 40MP 的测试图片（例如 6000×6000 像素）
   - [ ] 确认图片大小 > 10MB

2. 上传测试图片
   - [ ] 使用管理员账号登录
   - [ ] 创建新帖子并上传大图
   - [ ] 发布帖子

3. 打开图片审核页面
   - [ ] 进入帖子详情
   - [ ] 点击"图片审核"按钮
   - [ ] 观察页面加载是否顺畅

4. 执行打码操作
   - [ ] 使用画笔涂抹区域
   - [ ] 切换马赛克/模糊效果
   - [ ] 执行撤销/重做
   - [ ] 使用橡皮擦删除
   - [ ] 保存打码

**预期结果**：
- [ ] 页面加载顺畅，无长时间卡顿
- [ ] 内存使用稳定，无突然飙升
- [ ] 不出现应用崩溃或 OOM 错误
- [ ] 保存成功，服务端生成打码图

**验证方式**：
- Android Studio Profiler 观察内存曲线
- 或使用 Android 设置 > 开发者选项 > 内存使用情况

**失败标准**：
- 内存使用超过 300MB
- 应用崩溃或无响应
- 保存失败

---

### 2.2 兑换审核状态切换测试

**目的**：验证 P2 修复 - 审核状态切换无串页、无卡死

**步骤**：

1. 准备测试数据
   - [ ] 创建至少 3 个"待审核"兑换申请
   - [ ] 创建至少 2 个"已通过"兑换申请
   - [ ] 创建至少 2 个"已驳回"兑换申请

2. 测试快速切换
   - [ ] 进入兑换审核页面
   - [ ] 选择"待审核"，等待加载完成
   - [ ] 立即切换到"已通过"
   - [ ] 再次快速切换到"已驳回"
   - [ ] 切换回"待审核"

3. 测试加载更多后切换
   - [ ] 选择"待审核"
   - [ ] 向下滚动，点击"加载更多"
   - [ ] 在加载过程中立即切换到"已通过"
   - [ ] 观察底部状态

4. 测试并发切换
   - [ ] 快速连续点击不同的状态筛选
   - [ ] 在网络较慢时（可用开发者工具模拟）重复测试

**预期结果**：
- [ ] 每次切换后显示的数据与选中状态一致
- [ ] 不出现其他状态的数据混入
- [ ] 加载更多后切换，底部不会永久显示 loading
- [ ] 切换流畅，无异常状态

**失败标准**：
- 显示数据与选中状态不符
- 底部永久显示 loading 图标
- 出现 "加载更多" 按钮但点击无响应

---

### 2.3 商城订单加载失败测试

**目的**：验证 P2 修复 - 订单加载失败时 fail-closed

**步骤**：

1. 模拟网络故障
   - [ ] 使用浏览器开发者工具或代理工具
   - [ ] 配置拦截 `/me/store-orders` 请求返回 500 错误

2. 打开兑换商店
   - [ ] 进入兑换商店页面
   - [ ] 观察页面状态

3. 尝试兑换
   - [ ] 点击任意商品的"兑换"按钮
   - [ ] 观察按钮状态和提示信息

4. 测试重试
   - [ ] 点击"重试"按钮
   - [ ] 恢复网络正常
   - [ ] 观察页面是否正常加载

5. 测试多次重试竞态
   - [ ] 配置订单接口随机延迟（1-3秒）
   - [ ] 快速点击多次"重试"
   - [ ] 观察最终状态是否正确

**预期结果**：
- [ ] 加载失败时显示明确错误提示
- [ ] 显示"兑换记录加载失败，无法确认是否存在待审核申请"
- [ ] 显示"重试"按钮
- [ ] 所有商品的兑换按钮被禁用
- [ ] 不显示"还没有兑换记录"这样的误导信息
- [ ] 重试成功后恢复正常
- [ ] 多次重试不会出现状态混乱

**失败标准**：
- 加载失败时仍可点击兑换
- 显示"还没有兑换记录"
- 重试后状态不正确

---

### 2.4 商城兑换后状态测试

**目的**：验证兑换成功后的短窗口保护

**步骤**：

1. 准备账号
   - [ ] 使用有足够积分的账号
   - [ ] 确认无待审核兑换申请

2. 执行兑换
   - [ ] 进入兑换商店
   - [ ] 点击商品"兑换"按钮
   - [ ] 观察其他商品状态
   - [ ] 尝试快速点击另一个商品

3. 等待订单刷新
   - [ ] 观察订单列表更新
   - [ ] 确认"审核中"提示出现

**预期结果**：
- [ ] 兑换请求提交后，所有商品立即显示"审核中"状态
- [ ] 所有兑换按钮立即被禁用
- [ ] 即使订单列表尚未刷新完成，也无法点击其他商品
- [ ] 订单刷新完成后状态保持一致

**失败标准**：
- 兑换成功后有短暂时间可以点击其他商品
- 服务端虽然会拒绝，但客户端状态不严密

---

### 2.5 媒体私有化端到端测试

**目的**：验证媒体文件真正无法绕过网关直接访问

**步骤**：

1. 获取测试媒体
   - [ ] 上传一张新图片
   - [ ] 记录 media_id

2. 测试网关访问（应该成功）
   ```bash
   # 测试 thumb
   curl -I https://api.shengbeijiang.com/api/v1/media-file/{media_id}/thumb
   # 预期: 200 OK
   
   # 测试 detail
   curl -I https://api.shengbeijiang.com/api/v1/media-file/{media_id}/detail
   # 预期: 200 OK
   ```

3. 测试直接访问源文件（应该失败）
   ```bash
   # 从数据库获取 object_key
   SELECT object_key FROM media_assets WHERE id = '{media_id}';
   
   # 尝试直接访问
   curl -I {object_key}
   # 预期: 403 Forbidden 或 404 Not Found
   ```

4. 测试旧路径（应该失败）
   ```bash
   curl -I https://api.shengbeijiang.com/media/test.jpg
   # 预期: 404 Not Found
   ```

5. 测试内部路径（应该失败）
   ```bash
   curl -I https://api.shengbeijiang.com/_protected_media/test.jpg
   # 预期: 404 Not Found 或 403 Forbidden
   ```

6. 测试打码图片的 original（应该失败）
   - [ ] 打码一张图片
   - [ ] 获取该 media_id
   ```bash
   # 尝试访问 original
   curl -I https://api.shengbeijiang.com/api/v1/media-file/{media_id}/original
   # 预期: 404 Not Found（普通用户；管理员也必须被通用媒体网关拒绝）
   ```

7. 测试管理员访问审核源图（应该成功）
   - [ ] 使用管理员 token
   ```bash
   curl -I -H "Authorization: Bearer {admin_token}" \
     https://api.shengbeijiang.com/api/v1/admin/media/{media_id}/source
   # 预期: 200 OK，Cache-Control: private, no-store
   ```

8. 测试管理员审核预览（应该成功）
   - [ ] 使用管理员 token
   ```bash
   curl -I -H "Authorization: Bearer {admin_token}" \
     https://api.shengbeijiang.com/api/v1/admin/media/{media_id}/preview
   # 预期: 200 OK，Cache-Control: private, no-store；pending/hidden 附件也可访问
   ```

**预期结果**：
- [ ] 网关访问 thumb/detail 成功
- [ ] 直接访问源文件失败
- [ ] 旧路径访问失败
- [ ] 内部路径公网访问失败
- [ ] 打码图片 original 普通用户访问失败
- [ ] 打码图片 original 管理员通过通用网关访问也失败
- [ ] 管理员通过 `/api/v1/admin/media/{id}/source` 可访问源图
- [ ] 管理员通过 `/api/v1/admin/media/{id}/preview` 可查看 pending/hidden 附件

**失败标准**：
- 任何源文件可以绕过网关直接访问
- 旧路径仍可访问
- 内部路径可公开访问

---

### 2.6 APK 更新完整流程测试

**目的**：验证正式 APK 签名和更新流程

**前置条件**：
- [ ] 已准备正式签名密钥
- [ ] 已构建并签名新版本 APK
- [ ] 新版本已上传到 `download.shengbeijiang.com`
- [ ] 更新 API 已配置新版本信息

**步骤**：

1. 准备旧版本应用
   - [ ] 在测试设备安装当前正式版本
   - [ ] 确认版本号和签名

2. 触发更新检查
   - [ ] 打开应用
   - [ ] 进入设置页面
   - [ ] 点击"检查更新"

3. 验证更新提示
   - [ ] 确认显示新版本信息
   - [ ] 确认版本号正确
   - [ ] 确认更新说明正确

4. 执行下载
   - [ ] 点击"立即更新"
   - [ ] 观察下载进度
   - [ ] 确认下载来源域名

5. 验证签名
   - [ ] 下载完成后观察提示
   - [ ] 不应该出现"包名不一致"错误
   - [ ] 不应该出现"签名不一致"错误
   - [ ] 不应该出现"版本回退"警告

6. 安装更新
   - [ ] 点击安装
   - [ ] 观察系统安装器
   - [ ] 确认安装成功

7. 验证更新后状态
   - [ ] 打开应用
   - [ ] 确认版本号已更新
   - [ ] 确认登录状态保持
   - [ ] 确认数据正常

**预期结果**：
- [ ] 检测到更新
- [ ] 下载 URL 使用 HTTPS
- [ ] 下载完成并通过签名验证
- [ ] 包名一致
- [ ] 签名证书集合一致
- [ ] 版本号正确递增
- [ ] 安装成功
- [ ] 覆盖升级后数据和状态保持

**失败标准**：
- 签名验证失败
- 包名不一致无法安装
- 安装后数据丢失或登录状态丢失
- 出现版本回退警告

### 2.7 审核来源筛选与图片证据测试

1. 准备跨页案件：第一页全部为自动规则案件，下一页至少有一个用户举报案件。
2. 在审核中心选择“用户举报”，确认请求携带 `source=user_report`，列表直接显示跨页的用户举报案件。
3. 在用户举报案件详情中确认帖子和评论附件都显示在“图片证据”区域。
4. 使用 pending 或 hidden 帖子重复测试，确认图片通过管理员 JWT 预览接口加载，不因公开媒体可见性返回 404。
5. 在加载更多请求尚未返回时切换来源，确认新来源仍可继续加载下一页，不出现永久 loading。

**失败标准**：
- 只在当前页本地筛来源导致真实案件显示为空
- 评论附件未出现在案件详情
- pending/hidden 附件依赖公开网关而无法查看
- 切换来源后“加载更多”永久不可用

---

## 三、性能验收

### 3.1 API 响应时间

使用压测工具验证关键接口性能：

```bash
# 首页帖子列表
ab -n 1000 -c 10 https://api.shengbeijiang.com/api/v1/feed/latest

# 预期: p95 < 500ms, p99 < 1000ms
```

### 3.2 媒体网关响应时间

```bash
# 测试缩略图访问
ab -n 100 -c 5 https://api.shengbeijiang.com/api/v1/media-file/{media_id}/thumb

# 预期: p95 < 300ms
```

### 3.3 数据库连接池

```sql
-- 检查活跃连接数
SELECT count(*) FROM pg_stat_activity 
WHERE datname = 'luntan' AND state = 'active';

-- 预期: < 20
```

---

## 四、监控和告警验收

### 4.1 日志记录

- [ ] 应用启动日志正常
- [ ] 错误日志包含完整堆栈
- [ ] 访问日志记录请求详情
- [ ] 敏感信息（密码、token）已脱敏

### 4.2 指标采集

```bash
curl https://api.shengbeijiang.com/metrics
# 应返回 403（公网不可访问）

# 从监控网段访问
curl -H "X-Forwarded-For: {monitoring_ip}" https://api.shengbeijiang.com/metrics
# 应返回 Prometheus 格式指标
```

### 4.3 健康检查

验证负载均衡器健康检查配置：
- [ ] `/health` 用于浅层健康检查
- [ ] `/ready` 用于就绪检查（包括数据库连接）
- [ ] 检查频率合理（建议 10-30 秒）
- [ ] 失败阈值合理（建议 2-3 次）

---

## 五、回滚预案验证

### 5.1 数据库回滚

```bash
# 1. 停止应用
systemctl stop luntan-api

# 2. 恢复数据库备份
pg_restore -d luntan_rollback backup.dump

# 3. 回滚到前一个迁移版本
/app/luntan-migrate down 1

# 4. 启动旧版本应用
docker run -d ghcr.io/zhouwu97/luntan:{old_version}
```

### 5.2 应用回滚

```bash
# 使用前一个镜像版本
docker pull ghcr.io/zhouwu97/luntan:{previous_version}
docker stop luntan-api-current
docker run -d --name luntan-api-rollback ghcr.io/zhouwu97/luntan:{previous_version}
```

### 5.3 验证回滚成功

- [ ] 应用正常启动
- [ ] `/health` 返回 200
- [ ] 关键功能正常
- [ ] 数据库查询正常

---

## 六、验收签字

| 角色 | 姓名 | 签字 | 日期 |
|------|------|------|------|
| 开发负责人 | | | |
| 测试负责人 | | | |
| 运维负责人 | | | |
| 产品负责人 | | | |

**最终决定**：

- [ ] ✅ 通过验收，批准上线
- [ ] ⚠️  有条件通过，需在上线后 X 天内修复以下问题：
  - 
- [ ] ❌ 不通过验收，需修复以下问题后重新验收：
  - 

**备注**：

---

## 附录

### A. 验收环境信息

- 服务器地址: `43.161.249.91`
- API 域名: `https://api.shengbeijiang.com`
- 数据库版本: PostgreSQL 14+
- Go 版本: 1.22+
- Flutter 版本: 3.x
- 当前代码版本: 以本次部署使用的 Git commit SHA 为准

### B. 紧急联系方式

| 角色 | 联系人 | 联系方式 |
|------|--------|----------|
| 后端负责人 | | |
| 前端负责人 | | |
| 运维负责人 | | |
| 紧急联系人 | | |

### C. 相关文档

- [媒体网关部署](./media-gateway.md)
- [环境隔离](./environments.md)
- [发布 Runbook](./release-runbook.md)
- [生产验收脚本](../../scripts/production-acceptance.ps1)
