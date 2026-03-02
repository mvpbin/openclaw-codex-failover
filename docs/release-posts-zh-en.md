# 发布文案（中英双语，复制即发）

## 0) 主页更新通知（2026-03-02 增量）

### 中文
主页与文档已更新（2026-03-02）：
- 新增账号多样化重排（按 `accountId` 交错，避免同账号连续命中）
- 增加 `accountId` 回填兜底（`OCX_AUTH_PROFILES_PATH`）
- 探针失败新增 quota/auth 压力提示，减少“纯网络故障”误判
- 启用 `AUTO_REORDER` 时避免后续 sync 覆盖新顺序
- README 首页日期与更新记录同步至 2026-03-02

### English
Homepage/docs updated (2026-03-02):
- Added account-diversity reorder (interleave by `accountId` to avoid same-account streaks)
- Added `accountId` fallback enrichment via `OCX_AUTH_PROFILES_PATH`
- Probe failures now surface quota/auth pressure hints (clearer than generic network-only failures)
- Prevented post-reorder sync from overriding newly computed order when auto-reorder is enabled
- README homepage/update-date markers synced to 2026-03-02


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