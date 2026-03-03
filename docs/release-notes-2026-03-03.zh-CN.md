# 发布说明 — 2026-03-03

## 摘要
本次修复了一个容灾盲区：当运行时输出出现 `usage limit`、`token invalidated`、`connected | error` 时，之前动作不够强，可能导致 Telegram 长时间无回复。

## 新增 / 变更
- 在 `scripts/healthcheck_openai_codex_pool.sh` 增加探针信号紧急熔断
  - 新增变量：`OCX_PROBE_HINT_FORCE_TRIP=1`（默认开启）
  - 新增变量：`OCX_PROBE_HINT_MIN_COOLDOWN_SECONDS=1800`
  - 新增变量：`OCX_PROBE_HINT_MAX_COOLDOWN_SECONDS=259200`
  - 支持从 `Try again in ~NNN min` 自动推导冷却时长
- 新增“关闭 AUTO_REORDER 时的即时降级”
  - 新增变量：`OCX_PROBE_HINT_DEMOTE_WITHOUT_AUTO_REORDER=1`
  - 即使 `OCX_AUTO_REORDER=0`，也会把疑似故障账号降到顺序末尾
- 修复状态机误判
  - 只要存在 `failedProfiles` 或 `expiringProfiles`，状态必为 Degraded，不再误报 Healthy

## 文档更新
- README 首页日期与“最新增量”更新到 `2026-03-03`
- 故障排查新增本次问题的专门条目
- 发布文案模板更新为 2026-03-03 版本

## 验证
- `bash -n scripts/healthcheck_openai_codex_pool.sh` 通过
- dry-run 下存在失败/过期账号时会正确显示 `Degraded`
- 关键报错匹配验证通过：
  - `You have hit your ChatGPT usage limit`
  - `Your authentication token has been invalidated`
  - `connected | error`
