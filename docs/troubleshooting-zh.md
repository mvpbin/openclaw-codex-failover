# 故障排查（最终版）

## 1) timer 不 active
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now openclaw-healthcheck.timer
systemctl status openclaw-healthcheck.timer --no-pager -l
```

## 2) 没收到 Telegram 告警
```bash
openclaw status --deep
grep -E 'OCX_NOTIFY_CHANNEL|OCX_NOTIFY_TARGET' /etc/openclaw-healthcheck.env
```

## 3) 提示 another healthcheck is running
并发锁生效，避免重复执行。等当前任务结束再跑。

## 4) 一直某个 accXX 异常
```bash
${OCX_BASE_DIR:-/data/openclaw}/scripts/repair_openai_codex_pool.sh
```

## 5) 账号封禁不可恢复
```bash
${OCX_BASE_DIR:-/data/openclaw}/scripts/decommission_openai_codex_profile.sh openai-codex:acc03 banned
codex logout && codex -c cli_auth_credentials_store='file' login --device-auth
${OCX_BASE_DIR:-/data/openclaw}/scripts/onboard_openai_codex_profile.sh openai-codex:acc03 /home/rdpuser/.codex/auth.json
```

## 6) 想只验证逻辑不发消息
```bash
OCX_DRY_RUN=1 ${OCX_BASE_DIR:-/data/openclaw}/scripts/healthcheck_openai_codex_pool.sh
```

## 7) 报告文件位置
- 健康报告：`$OCX_BASE_DIR/reports/openai_codex_health_latest.json`
- 修复报告：`$OCX_BASE_DIR/reports/openai_codex_repair_latest.json`
- 删除报告：`$OCX_BASE_DIR/reports/openai_codex_decommission_latest.json`
