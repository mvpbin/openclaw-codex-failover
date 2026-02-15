# OpenClaw Codex 容灾机制（小白友好最终版）

> 目标：`openai-codex:*` 账号池自动巡检、异常告警、自动/手动修复、可选删除、快速补位。

---

## 一句话流程

**检测 → 告警 → 修复 →（可选）删除 → 补位**

---

## 你能得到什么

- ✅ 账号池自动检测（默认每10分钟）
- ✅ 异常首次连发3次告警，未修复每小时提醒1次
- ✅ 精准定位失效账号（accXX）
- ✅ 修复脚本（自动尝试 + 手动命令）
- ✅ 删除脚本（封禁账号下线）
- ✅ 补位脚本（新账号快速补回 accXX）

---

## 路径选择（必须先看）

```bash
# 推荐（有 /data）
export OCX_BASE_DIR=/data/openclaw

# 或默认兼容
# export OCX_BASE_DIR=$HOME/.openclaw/openclaw-tools
```

---

## 最小可跑（3步）

### 1) 一键安装
```bash
sudo bash -lc '
set -e
: "${OCX_BASE_DIR:=/data/openclaw}"
mkdir -p "$OCX_BASE_DIR/scripts" "$OCX_BASE_DIR/reports" "$OCX_BASE_DIR/systemd"
cp scripts/*.sh "$OCX_BASE_DIR/scripts/"
cp systemd/* "$OCX_BASE_DIR/systemd/"
chmod +x "$OCX_BASE_DIR/scripts"/*.sh
cp "$OCX_BASE_DIR/systemd/openclaw-healthcheck.service" /etc/systemd/system/
cp "$OCX_BASE_DIR/systemd/openclaw-healthcheck.timer" /etc/systemd/system/
cp -n openclaw-healthcheck.env.example /etc/openclaw-healthcheck.env || true
systemctl daemon-reload
systemctl enable --now openclaw-healthcheck.timer
'
```

### 2) 手动跑一次
```bash
sudo systemctl start openclaw-healthcheck.service
```

### 3) 看结果
```bash
cat ${OCX_BASE_DIR:-/data/openclaw}/reports/openai_codex_health_latest.json
```

---

## 异常处理（实战）

### A) 手动修复（推荐先做）
```bash
${OCX_BASE_DIR:-/data/openclaw}/scripts/repair_openai_codex_pool.sh
```

### B) 封禁账号删除（可选）
```bash
${OCX_BASE_DIR:-/data/openclaw}/scripts/decommission_openai_codex_profile.sh openai-codex:acc03 banned
```

### C) 新账号补位
```bash
codex logout && codex -c cli_auth_credentials_store='file' login --device-auth
${OCX_BASE_DIR:-/data/openclaw}/scripts/onboard_openai_codex_profile.sh openai-codex:acc03 /home/rdpuser/.codex/auth.json
```

---

## 配置总表（OCX_*）

| 变量 | 默认值 | 作用 |
|---|---|---|
| `OCX_BASE_DIR` | `/data/openclaw` | 工作根目录 |
| `OCX_PROVIDER` | `openai-codex` | Provider 名称 |
| `OCX_MIN_PROFILES` | `1` | 最低账号数（低于则 CRITICAL） |
| `OCX_RECOMMENDED_MIN` | `5` | 建议最小账号数 |
| `OCX_RECOMMENDED_MAX` | `12` | 建议最大账号数 |
| `OCX_EXPIRING_HOURS` | `24` | 即将过期阈值 |
| `OCX_NOTIFY_CHANNEL` | `telegram` | 告警渠道 |
| `OCX_NOTIFY_TARGET` | `182211955` | 告警目标 |
| `OCX_ALERT_BURST_COUNT` | `3` | 首次异常告警次数 |
| `OCX_ALERT_REMIND_SECONDS` | `3600` | 持续异常提醒间隔 |
| `OCX_AGENT_TIMEOUT_SECONDS` | `45` | 轻量调用超时 |
| `OCX_LOG_RETENTION_DAYS` | `30` | 日志保留天数 |
| `OCX_DRY_RUN` | `0` | 1=只检查不发消息 |
| `OCX_AUTO_REPAIR` | `0` | 1=异常时自动触发修复 |
| `OCX_SUGGEST_DECOMMISSION` | `0` | 1=在修复建议中显示删除命令 |

---

## 常用命令

```bash
# 仅检查不发通知
${OCX_BASE_DIR:-/data/openclaw}/scripts/healthcheck_openai_codex_pool.sh --dry-run

# 无破坏模拟掉线
SIMULATE_UNUSABLE=openai-codex:acc03 ${OCX_BASE_DIR:-/data/openclaw}/scripts/healthcheck_openai_codex_pool.sh || true

# 查看 timer
systemctl status openclaw-healthcheck.timer --no-pager -l | sed -n '1,20p'
```

---

## 相关文档

- 快速开始：`docs/quickstart-zh.md`
- 故障排查：`docs/troubleshooting-zh.md`

## License

MIT
