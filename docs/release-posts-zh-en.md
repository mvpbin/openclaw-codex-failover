# 发布文案（中英双语，复制即发）

## 0) 主页更新通知（2026-03-04 增量）

### 中文
主页与文档已更新（2026-03-04）：
- 落地 failover v2：失败账号硬隔离，生产轮换仅使用 active 池
- 新增按账号联动隔离：可按 `accountId` 隔离同账号全部 profiles
- 新增受控恢复门槛：隔离账号需连续健康 N 轮才回池
- 新增 fail-open 容量保护：active 过低时自动放宽隔离，避免服务断流
- README 首页日期与最新增量同步至 2026-03-04

### English
Homepage/docs updated (2026-03-04):
- Shipped failover v2: hard isolation for failed profiles; production rotation now uses active pool only
- Added account-level quarantine by `accountId` for sibling profiles
- Added controlled recovery gate (N consecutive healthy rounds before rejoin)
- Added fail-open capacity guard to prevent over-isolation outages
- README homepage/update-date markers synced to 2026-03-04


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