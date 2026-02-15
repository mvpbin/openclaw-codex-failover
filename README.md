# OpenClaw Codex 容灾机制（小白友好版）

> 目标：让 `openai-codex:*` 账号池每天自动体检，出问题只提醒具体账号（accXX），并推送 Telegram 摘要。

---

## 你能得到什么

- ✅ 每天自动检查 2 次（UTC 09:00 / 21:00）
- ✅ 账号数量无限制（自动发现 `openai-codex:*`）
- ✅ 精准定位失效账号（只报 accXX）
- ✅ Telegram 中文+emoji 摘要
- ✅ 自动生成重登建议命令（只针对失效账号）

---

## 先选路径（关键）

本项目**不是强制默认路径**。你可以选：

- 推荐（有大盘）：`/data/openclaw`
- 默认兼容（无 /data 时）：`$HOME/.openclaw/openclaw-tools`

设置方式（2选1）：

```bash
# 方案A：推荐
export OCX_BASE_DIR=/data/openclaw

# 方案B：默认兼容
export OCX_BASE_DIR=$HOME/.openclaw/openclaw-tools
```

后续命令都基于 `$OCX_BASE_DIR`，不写死。

---

## 账号数量建议（实战）

- 推荐区间：**5~12 个**（默认建议）
- 少于 5：容灾冗余偏弱
- 多于 12：维护成本明显上升

可调参数：
- `OCX_RECOMMENDED_MIN`（默认 5）
- `OCX_RECOMMENDED_MAX`（默认 12）

---

## 0基础：一键安装（复制就行）

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
systemctl daemon-reload
systemctl enable --now openclaw-healthcheck.timer
systemctl start openclaw-healthcheck.service || true
'
```

---

## 安装后怎么确认成功

```bash
systemctl status openclaw-healthcheck.timer --no-pager -l | sed -n '1,20p'
cat ${OCX_BASE_DIR:-/data/openclaw}/reports/openai_codex_health_latest.json
```

重点看：
- `discoveredCount`
- `failedProfiles`
- `recommendations`
- `exitCode`（0/1/2）

---

## 手动执行与模拟

```bash
${OCX_BASE_DIR:-/data/openclaw}/scripts/healthcheck_openai_codex_pool.sh
SIMULATE_UNUSABLE=openai-codex:acc03 ${OCX_BASE_DIR:-/data/openclaw}/scripts/healthcheck_openai_codex_pool.sh || true
```

---

## 进一步改进（我已识别）

1. **路径可配置化**（本次已改）
2. **target chat 可配置**：将 Telegram target 从脚本硬编码改为 `.env` 读取（下个版本）
3. **并发锁**：防止手动执行与 timer 同时跑（下个版本）
4. **日志轮转**：避免长期增长（下个版本）
5. **退出码映射文档化**：给 systemd/监控平台更清晰对接示例（下个版本）

---

## 常见问题

看：[`docs/troubleshooting-zh.md`](docs/troubleshooting-zh.md)

## License

MIT
