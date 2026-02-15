# OpenClaw Codex 容灾机制（小白友好版）

> 目标：让 `openai-codex:*` 账号池每天自动体检，出问题只提醒具体账号（accXX），并推送 Telegram 摘要。

---

## 你能得到什么

- ✅ 每 10 分钟自动检查一次（更快发现异常）
- ✅ 账号数量无限制（自动发现 `openai-codex:*`）
- ✅ 精准定位失效账号（只报 accXX）
- ✅ 异常首次触发立刻连发 3 次告警
- ✅ 未修复前每小时 1 次持续提醒（防刷屏）
- ✅ 异常账号可显示邮箱（默认脱敏）
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

## 新增：修复 + 删除替换功能

现在不仅能“发现异常”，还能执行“修复流程”：

- 修复脚本：`scripts/repair_openai_codex_pool.sh`
- 删除脚本：`scripts/decommission_openai_codex_profile.sh`
- 输入：最新健康报告中的 `failedProfiles`
- 动作：
  1) 尝试用映射的 auth.json 非交互修复
  2) 修复后自动 sync auth order
  3) 未修复账号输出两条路线：重登 / 删除后替换
  4) 生成修复报告：`openai_codex_repair_latest.json`

可选自动修复（告警时触发）：
- `OCX_AUTO_REPAIR=1`

映射文件示例：
- `config/openai-codex-auth-map.env.example`

---

## 本次已完成的细节增强

1. **路径可配置化**：统一走 `OCX_BASE_DIR`
2. **通知目标可配置**：支持 `/etc/openclaw-healthcheck.env`
3. **并发锁**：已加 `flock` 防重入
4. **日志治理**：脚本内置保留天数 + 提供 logrotate 示例
5. **dry-run**：支持 `--dry-run` 或 `OCX_DRY_RUN=1`（只检查不发消息）

附加文件：
- `openclaw-healthcheck.env.example`
- `logrotate.openclaw-healthcheck.example`

---

## 可选：启用环境文件（推荐）

```bash
sudo cp openclaw-healthcheck.env.example /etc/openclaw-healthcheck.env
sudo systemctl daemon-reload
sudo systemctl restart openclaw-healthcheck.timer
```

## 可选：只检查不发 Telegram

```bash
${OCX_BASE_DIR:-/data/openclaw}/scripts/healthcheck_openai_codex_pool.sh --dry-run
```

## 常见问题

看：[`docs/troubleshooting-zh.md`](docs/troubleshooting-zh.md)

## License

MIT

