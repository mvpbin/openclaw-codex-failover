# 故障排查（中文）

## Q1: timer 没有 active

检查：

```bash
systemctl status openclaw-healthcheck.timer --no-pager -l
```

修复：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now openclaw-healthcheck.timer
```

---

## Q2: service 执行失败

查看日志：

```bash
journalctl -u openclaw-healthcheck.service -n 200 --no-pager
```

同时查看脚本日志：

```bash
tail -n 200 /data/openclaw/reports/openai_codex_health_$(date -u +%Y%m%d).log
```

---

## Q3: 报告里账号数量不对

手动核对：

```bash
openclaw models status --json
```

确认你的 profile 命名是否为：

- `openai-codex:acc01`
- `openai-codex:acc02`
- `openai-codex:acc03`
- `openai-codex:acc04`
- `openai-codex:acc05`

---

## Q4: Telegram 没收到摘要

检查 channel 是否可用：

```bash
openclaw status --deep
```

检查脚本 target 是否正确：

```bash
grep -n "message send --channel telegram" /data/openclaw/scripts/healthcheck_openai_codex_pool.sh
```

---

## Q5: 想临时测试某账号失效，不破坏线上

```bash
SIMULATE_UNUSABLE=openai-codex:acc04 /data/openclaw/scripts/healthcheck_openai_codex_pool.sh || true
```

---

## Q6: 修改执行时间

编辑 timer 文件中的 `OnCalendar`：

```ini
OnCalendar=*-*-* 09:00:00 UTC
OnCalendar=*-*-* 21:00:00 UTC
```

修改后执行：

```bash
sudo systemctl daemon-reload
sudo systemctl restart openclaw-healthcheck.timer
```
