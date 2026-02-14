# 故障排查（小白版）

## 1) timer 没有 active

```bash
systemctl status openclaw-healthcheck.timer --no-pager -l
```

修复：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now openclaw-healthcheck.timer
```

---

## 2) 我没收到 Telegram 摘要

先看 OpenClaw 通道状态：

```bash
openclaw status --deep
```

看脚本里 target 是不是你的账号：

```bash
grep -n "message send --channel telegram" /data/openclaw/scripts/healthcheck_openai_codex_pool.sh
```

---

## 3) 报告里的账号数和你预期不一致

```bash
openclaw models status --json
```

说明：当前版本账号数**不设上限**，自动发现 `openai-codex:*`。
请检查你实际导入的 profile 是否都存在、命名是否正确。

---

## 4) 某个账号失效了怎么办

报告里会给出该账号的重登命令（只针对失效账号）。

先看报告：

```bash
cat /data/openclaw/reports/openai_codex_health_latest.json
```

找到 `reloginCommands`，复制对应 accXX 执行。

---

## 5) 想改自动检查时间

编辑：
`/etc/systemd/system/openclaw-healthcheck.timer`

修改：
```ini
OnCalendar=*-*-* 09:00:00 UTC
OnCalendar=*-*-* 21:00:00 UTC
```

然后：

```bash
sudo systemctl daemon-reload
sudo systemctl restart openclaw-healthcheck.timer
```

---

## 6) 一键重跑健康检查

```bash
/data/openclaw/scripts/healthcheck_openai_codex_pool.sh
```
