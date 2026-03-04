# 发布说明 — 2026-03-04

## 摘要
本次发布落地 failover v2：把“软降权”升级为“硬隔离 + 受控恢复”。在健康容量充足时，失败账号不再进入生产轮换输入。

## 新增 / 变更
- 在 `scripts/healthcheck_openai_codex_pool.sh` 增加失败账号硬隔离
  - 新增变量：`OCX_HARD_DISABLE_FAILED=1`（默认开启）
  - 轮换输入优先使用 `activeProfiles`，隔离池 `quarantinedProfiles` 默认不参与
- 新增按账号联动隔离
  - 新增变量：`OCX_HARD_DISABLE_FAILED_ACCOUNT=1`（默认开启）
  - 新增变量：`OCX_ACCOUNT_QUARANTINE_SECONDS=7200`
  - 某 profile 失败时，可按 `accountId` 联动隔离同账号下其他 profiles
- 新增受控恢复门槛
  - 新增变量：`OCX_RECOVERY_SUCCESS_ROUNDS=2`
  - 隔离账号需连续健康通过 N 轮后才允许回池
- 新增 fail-open 安全阈值
  - 新增变量：`OCX_HARD_DISABLE_MIN_ACTIVE_PROFILES=2`
  - 新增变量：`OCX_HARD_DISABLE_MIN_ACTIVE_ACCOUNTS=1`
  - 当 active 容量过低时自动放宽隔离，避免可用性被压到 0
- 健康报告可观测性增强
  - 新增字段：`activeProfiles`、`activeProfileCount`、`activeAccountCount`、`quarantinedProfiles`、`quarantinedAccounts`、`orderInputProfiles`
- 批量导入稳定性加固
  - `sync_openclaw_auth_order.sh` 改为优先读取 `auth-profiles.json` 作为真值来源，避免快速导入时依赖状态标签产生漂移
  - `onboard_openai_codex_profile.sh` 新增批量安全开关：
    - `OCX_ONBOARD_SYNC_AFTER_ONBOARD`（默认 `1`）
    - `OCX_ONBOARD_POST_VERIFY`（默认 `1`）
  - 向导批量导入改为“逐条导入不做每条同步/验收，最后统一同步一次”

## 文档更新
- README 首页日期与“最新增量”更新到 `2026-03-04`
- 配置总表补充 failover v2 参数
- 新增本次中英双语发布说明

## 验证
- `bash -n scripts/healthcheck_openai_codex_pool.sh` 通过
- 运行报告可见硬隔离输出字段，且 order input 已只保留 active 池
- `openclaw logs` 可确认当前 Order override 已切为 active 池
