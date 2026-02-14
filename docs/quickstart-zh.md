# 快速开始（中文）

## 1) 准备目录

```bash
sudo mkdir -p /data/openclaw/scripts /data/openclaw/reports /data/openclaw/systemd
```

## 2) 复制脚本与 systemd 文件

把本仓库里的 `scripts/*` 和 `systemd/*` 放到：

- `/data/openclaw/scripts/`
- `/data/openclaw/systemd/`

并赋权：

```bash
sudo chmod +x /data/openclaw/scripts/*.sh
```

## 3) 安装 systemd 定时任务

```bash
sudo cp /data/openclaw/systemd/openclaw-healthcheck.service /etc/systemd/system/
sudo cp /data/openclaw/systemd/openclaw-healthcheck.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now openclaw-healthcheck.timer
```

## 4) 手动跑一次验收

```bash
sudo systemctl start openclaw-healthcheck.service
systemctl status openclaw-healthcheck.timer --no-pager -l | sed -n '1,20p'
cat /data/openclaw/reports/openai_codex_health_latest.json
```

## 5) 无破坏模拟（验证 accXX 精准识别）

```bash
SIMULATE_UNUSABLE=openai-codex:acc03 /data/openclaw/scripts/healthcheck_openai_codex_pool.sh || true
```

## 6) 退出码约定

- `0`：全健康（PASS）
- `1`：告警（WARN，例如即将过期）
- `2`：严重故障（CRITICAL）

## 7) Telegram 推送

脚本默认推送到 `182211955`。如需改目标，请编辑脚本中的：

```bash
openclaw message send --channel telegram --target 182211955 ...
```

## 8) 重登建议

当某账号失效时，报告内会包含对应重登命令（仅失效账号），示例：

```bash
codex logout && codex -c cli_auth_credentials_store='file' login --device-auth && /data/openclaw/scripts/import_codex_auth_to_openclaw.sh openai-codex:acc03 main /home/rdpuser/.codex/auth.json
```
