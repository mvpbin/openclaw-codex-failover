# 快速开始（最终版）

## 0) 前置检查

```bash
openclaw --version
codex --version   # 若不存在：npm install -g @openai/codex
```

## 1) 安装

```bash
# 推荐路径
export OCX_BASE_DIR=/data/openclaw

sudo bash -lc '
set -e
: "${OCX_BASE_DIR:=/data/openclaw}"
mkdir -p "$OCX_BASE_DIR/scripts" "$OCX_BASE_DIR/reports" "$OCX_BASE_DIR/systemd" "$OCX_BASE_DIR/config"
cp scripts/*.sh "$OCX_BASE_DIR/scripts/"
cp systemd/* "$OCX_BASE_DIR/systemd/"
cp -n config/openai-codex-auth-map.env.example "$OCX_BASE_DIR/config/openai-codex-auth-map.env" || true
chmod +x "$OCX_BASE_DIR/scripts"/*.sh
cp "$OCX_BASE_DIR/systemd/openclaw-healthcheck.service" /etc/systemd/system/
cp "$OCX_BASE_DIR/systemd/openclaw-healthcheck.timer" /etc/systemd/system/
cp -n openclaw-healthcheck.env.example /etc/openclaw-healthcheck.env || true
systemctl daemon-reload
systemctl enable --now openclaw-healthcheck.timer
'
```

## 2) 验收

```bash
sudo systemctl start openclaw-healthcheck.service
systemctl status openclaw-healthcheck.timer --no-pager -l | sed -n '1,20p'
cat ${OCX_BASE_DIR:-/data/openclaw}/reports/openai_codex_health_latest.json
```

## 3) 异常时修复

```bash
${OCX_BASE_DIR:-/data/openclaw}/scripts/repair_openai_codex_pool.sh
```

## 4) 封禁时删除并补位（可选）

```bash
${OCX_BASE_DIR:-/data/openclaw}/scripts/decommission_openai_codex_profile.sh openai-codex:acc03 banned
codex logout && codex -c cli_auth_credentials_store='file' login --device-auth
${OCX_BASE_DIR:-/data/openclaw}/scripts/onboard_openai_codex_profile.sh openai-codex:acc03 /root/.codex/auth.json
```

## 5) systemd 用户与阈值建议（避免踩坑）

```bash
# 若机器没有 rdpuser，请改成 root（或你的实际运行用户）
sudo sed -i 's/^User=.*/User=root/' /etc/systemd/system/openclaw-healthcheck.service
sudo systemctl daemon-reload

# 单账号场景避免误报
sudo sed -i 's/^OCX_RECOMMENDED_MIN=.*/OCX_RECOMMENDED_MIN=1/' /etc/openclaw-healthcheck.env
```

## 6) 常用开关

```bash
# 只检查不通知
OCX_DRY_RUN=1 ${OCX_BASE_DIR:-/data/openclaw}/scripts/healthcheck_openai_codex_pool.sh

# 开启自动修复
sudo sed -i 's/^# OCX_AUTO_REPAIR=1/OCX_AUTO_REPAIR=1/' /etc/openclaw-healthcheck.env

# 删除建议设为可选（默认0，不提示删除）
# OCX_SUGGEST_DECOMMISSION=0
```
