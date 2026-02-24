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
${OCX_BASE_DIR:-/data/openclaw}/scripts/onboard_openai_codex_profile.sh openai-codex:acc03 /root/.codex/auth.json
```

## 6) 想只验证逻辑不发消息
```bash
OCX_DRY_RUN=1 ${OCX_BASE_DIR:-/data/openclaw}/scripts/healthcheck_openai_codex_pool.sh
```

## 7) 报告文件位置
- 健康报告：`$OCX_BASE_DIR/reports/openai_codex_health_latest.json`
- 修复报告：`$OCX_BASE_DIR/reports/openai_codex_repair_latest.json`
- 删除报告：`$OCX_BASE_DIR/reports/openai_codex_decommission_latest.json`

## 8) 代理报 `quarantined (...)`，看起来一直被跳过
这是新加的“坏代理隔离池”在工作：
- 同一条代理在短时间内连续失败会进入隔离，防止反复踩雷。
- 到期后会自动解除。

可查看（如果你用默认目录）：
```bash
cat /data/openclaw/run/proxy-quarantine.tsv
```

可调整时长（`/etc/openclaw-healthcheck.env`）：
```env
OCX_PROXY_QUARANTINE_SECONDS=1800
OCX_PROXY_QUARANTINE_SECONDS_STRICT=3600
OCX_PROXY_QUARANTINE_SECONDS_SOFT=900
```

## 9) fallback 还是失败太快，想多试几条代理
在 `/etc/openclaw-healthcheck.env` 增加/调整：
```env
OCX_PROXY_FALLBACK_MAX_ATTEMPTS=6
OCX_PROXY_FALLBACK_BACKOFF_SECONDS=2
```

说明：会按“多次尝试 + 线性退避”执行，不再一次失败就结束。
