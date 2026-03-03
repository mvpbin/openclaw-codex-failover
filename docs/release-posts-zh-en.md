# 发布文案（中英双语，复制即发）

## 0) 主页更新通知（2026-03-03 增量）

### 中文
主页与文档已更新（2026-03-03）：
- 修复容灾盲区：命中 `usage limit` / `token invalidated` / `connected | error` 时立即触发探针驱动熔断
- 新增探针冷却推导：支持从 `Try again in ~NNN min` 自动换算冷却时长
- 新增 `OCX_PROBE_HINT_DEMOTE_WITHOUT_AUTO_REORDER`：即使关闭 AUTO_REORDER，也会把疑似故障账号降到队尾
- 修复状态机误判：有 failed/expiring 账号不再显示 Healthy
- README 首页日期与最新增量同步至 2026-03-03

### English
Homepage/docs updated (2026-03-03):
- Fixed failover blind spot for probe outputs containing `usage limit`, `token invalidated`, and `connected | error`
- Added probe-driven cooldown derivation from `Try again in ~NNN min`
- Added `OCX_PROBE_HINT_DEMOTE_WITHOUT_AUTO_REORDER` to demote suspected bad profiles even when auto reorder is off
- Fixed state-machine false healthy reports when failed/expiring profiles exist
- README homepage/update-date markers synced to 2026-03-03


> 发布前请先按 README 的“隐私发布检查清单”做脱敏。

## 1) X / Twitter

### 中文
开源了一个 OpenClaw Codex 容灾工具（Beta）：
- 自动巡检账号池（每10分钟）
- 异常分级 + 熔断 + 修复建议
- 支持 device code 登录后快速补位
- 小白可用（有 preflight 一键预检）

欢迎试用和提 issue 🙌
Repo: https://github.com/mvpbin/openclaw-codex-failover

### English
I just open-sourced an OpenClaw Codex failover toolkit (Beta):
- Automatic pool health checks (every 10 min)
- Anomaly classification + circuit breaker + repair guidance
- Fast onboarding after device-code login
- Beginner-friendly with one-command preflight checks

Feedback and issues are welcome 🙌
Repo: https://github.com/mvpbin/openclaw-codex-failover

---

## 2) Reddit（r/selfhosted / r/opensource）

### Title
[Beta] OpenClaw Codex account-pool failover toolkit (healthcheck + repair + onboarding)

### Body (EN)
I built and tested a small failover toolkit for `openai-codex:*` profile pools in OpenClaw.

What it does:
- Periodic health checks (systemd timer)
- State machine (Healthy/Degraded/Repairing/Recovered)
- Circuit breaker + cooldown to avoid noisy loops
- Repair/onboarding scripts for fast account replacement
- Preflight script to verify dependencies and environment

Current status: Beta (validated on Ubuntu 22.04 + OpenClaw 2026.2.17)

Repo: https://github.com/mvpbin/openclaw-codex-failover

I’d love feedback on reliability edge-cases and portability.

---

## 3) V2EX

### 标题
[开源/Beta] OpenClaw Codex 容灾脚本：巡检 + 熔断 + 修复 + 补位

### 正文
我开源了一套 OpenClaw 的 Codex 账号池容灾脚本（Beta）：

- 每 10 分钟自动巡检
- Healthy / Degraded / Repairing / Recovered 状态机
- 熔断与冷却，避免异常反复触发
- 账号失效时提供修复与补位流程
- 提供 preflight 一键预检，方便小白部署

已在 Ubuntu 22.04 + OpenClaw 2026.2.17 实机验证。

仓库：
https://github.com/mvpbin/openclaw-codex-failover

欢迎提 issue/PR，我会持续迭代。