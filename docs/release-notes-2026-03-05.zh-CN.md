# 发布说明 - 2026-03-05

## 重点更新

- 增加 `auth-profiles.json` 持久化保护：关键写入链路统一文件锁 + 原子写，降低并发回写覆盖风险。
- 增加反回滚守护：`openclaw-profile-reconcile.service/.timer`，可按映射表自动补齐缺失 profile。
- 增加每 profile 独立凭据快照能力，避免共享 auth 文件导致串号或回收。
- 修复 auth-store 过期判定链路，过期 profile 可正确进入 failed 并参与隔离。
- 增加限额切号自测脚本，支持验证“注入限额后在时限内自动切号”。

## 运维提示

- 新增环境变量：`OCX_AUTH_SNAPSHOT_DIR`、`OCX_AUTH_SNAPSHOT_PERSIST`、`OCX_RECONCILE_MODE`、`OCX_RECONCILE_LOCK_FILE`。
- Reconcile 定时器默认每 2 分钟执行一次。
- 生产建议保持 `OCX_DISABLE_PROBES=0`（开启探针）。
