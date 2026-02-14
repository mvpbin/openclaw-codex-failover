# 快速开始（超简版）

## 第1步：复制项目到服务器

如果你已经在服务器上有这份代码，跳过。

## 第2步：一键安装

```bash
sudo bash -lc '
set -e
mkdir -p /data/openclaw/scripts /data/openclaw/reports /data/openclaw/systemd
cp scripts/*.sh /data/openclaw/scripts/
cp systemd/* /data/openclaw/systemd/
chmod +x /data/openclaw/scripts/*.sh
cp /data/openclaw/systemd/openclaw-healthcheck.service /etc/systemd/system/
cp /data/openclaw/systemd/openclaw-healthcheck.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now openclaw-healthcheck.timer
'
```

## 第3步：手动跑一次

```bash
sudo systemctl start openclaw-healthcheck.service
```

## 第4步：看结果

```bash
cat /data/openclaw/reports/openai_codex_health_latest.json
```

- `exitCode=0` => PASS
- `exitCode=1` => WARN
- `exitCode=2` => CRITICAL

## 第5步：验证 Telegram 摘要

```bash
/data/openclaw/scripts/healthcheck_openai_codex_pool.sh
```

你应收到中文+emoji 摘要。

## 可选：模拟某账号失效（无破坏）

```bash
SIMULATE_UNUSABLE=openai-codex:acc03 /data/openclaw/scripts/healthcheck_openai_codex_pool.sh || true
```
