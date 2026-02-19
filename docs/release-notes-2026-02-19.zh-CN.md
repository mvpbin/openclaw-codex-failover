# 发布说明 — 2026-02-19

## 重点更新
- 新增小白友好向导：`scripts/onboard_profiles_wizard.sh`
- 新增并发代理批量检测：`scripts/check_proxy_pool_batch.sh`
- 新增代理登录开关：`OCX_USE_PROXY_LOGIN`
- 新增代理失败回退开关：`OCX_PROXY_AUTO_FALLBACK`
- 新增代理检测缓存与指标：
  - `OCX_PROXY_CHECK_CACHE_TTL_SECONDS`
  - `OCX_PROXY_CHECK_METRICS_FILE`
  - `OCX_PROXY_CHECK_CONCURRENCY`
- 修复导入兼容性：支持新版 auth.json 结构（含 `openai` 嵌套字段）
- 代理格式支持扩展：
  - `host:port:username:password`
  - `socks5://...` / `socks5h://...`
  - `http://...` / `https://...`

## 验证结果
- 脚本语法检查：通过
- Preflight：`ok=19 warn=0 err=0`
- 代理批量检测 smoke：通过
- 健康检查 dry-run 状态切换：通过（模拟故障进入 `Degraded`）
- 导入回归测试（新版 auth 结构）：通过

## 说明
- 对于轮换 IP 代理，clean check 偶发失败属于预期行为（按策略拦截）。
## 补充更新（可审计性）
- 新增账号↔代理绑定审计脚本：`scripts/audit_account_proxy_binding.sh`
- 新增最近 24h 审计汇总脚本：`scripts/report_account_proxy_audit_24h.sh`
- 代理检测与登录流程已输出结构化审计事件，便于后续排障与追踪。
