# OpenClaw Codex Failover Toolkit

面向 OpenClaw + `openai-codex` 多账号容灾的生产化工具包：

- 账号池健康检查（每日 2 次）
- 精准失效账号识别（accXX 级别）
- 过期预警（remainingMs < 24h）
- Telegram 摘要与告警推送
- 自动同步 auth order

## 功能清单

- `scripts/healthcheck_openai_codex_pool.sh`
  - 读取 `openclaw models status --json`
  - 输出可读日志 + JSON 报告
  - 退出码：`0=PASS` / `1=WARN` / `2=CRITICAL`
  - 轻量实测调用：`Reply exactly: ok`
  - 生成失效账号重登建议命令
- `scripts/sync_openclaw_auth_order.sh`
  - 自动刷新 `openai-codex` 容灾顺序
- `systemd/openclaw-healthcheck.service`
- `systemd/openclaw-healthcheck.timer`
  - UTC 每天 `09:00` / `21:00` 执行

## 目录结构

```bash
scripts/
  healthcheck_openai_codex_pool.sh
  sync_openclaw_auth_order.sh
systemd/
  openclaw-healthcheck.service
  openclaw-healthcheck.timer
docs/
  quickstart-zh.md
  troubleshooting-zh.md
```

## 快速开始

请直接看：[`docs/quickstart-zh.md`](docs/quickstart-zh.md)

## 报告与日志

- 最新报告：`/data/openclaw/reports/openai_codex_health_latest.json`
- 每日日志：`/data/openclaw/reports/openai_codex_health_YYYYMMDD.log`

## 安全建议

- 不要把任何 token / API key 提交到仓库。
- 使用后轮换临时凭证。
- 建议仓库设为 Private。

## License

MIT
