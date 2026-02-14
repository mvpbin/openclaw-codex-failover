# OpenClaw Codex 容灾机制（小白友好版）

> 目标：让 `openai-codex:*` 账号池每天自动体检，出问题只提醒具体账号（accXX），并推送 Telegram 摘要。

---

## 你能得到什么

- ✅ 每天自动检查 2 次（UTC 09:00 / 21:00）
- ✅ **账号数量无限制**（自动发现 `openai-codex:*`）
- ✅ 精准定位失效账号（只报 accXX）
- ✅ Telegram 中文+emoji 摘要
- ✅ 自动生成重登建议命令（只针对失效账号）

---

## 账号数量建议（实战）

不是越多越好。建议：

- **推荐区间：5~12 个**（默认建议）
- 少于 5：容灾冗余偏弱
- 多于 12：维护成本明显上升（重登、排障、巡检压力大）

可通过环境变量调整：

- `OCX_RECOMMENDED_MIN`（默认 5）
- `OCX_RECOMMENDED_MAX`（默认 12）

---

## 0基础：一键安装（复制就行）

在服务器终端执行：

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
systemctl start openclaw-healthcheck.service || true
'
```

---

## 安装后怎么确认成功

### 1) 看 timer 是否在跑

```bash
systemctl status openclaw-healthcheck.timer --no-pager -l | sed -n '1,20p'
```

你应该看到：`active (waiting)`。

### 2) 看最新报告

```bash
cat /data/openclaw/reports/openai_codex_health_latest.json
```

重点看：
- `discoveredCount`（自动发现到的账号总数）
- `failedProfiles`（失效账号）
- `recommendations`（账号数量建议）
- `exitCode`：`0=PASS` / `1=WARN` / `2=CRITICAL`

---

## 手动马上跑一次

```bash
/data/openclaw/scripts/healthcheck_openai_codex_pool.sh
```

会做：
1. 检查账号池状态
2. 轻量调用 `Reply exactly: ok`
3. 发 Telegram 摘要（单条，避免重复轰炸）

---

## 如果要模拟“acc03失效”（无破坏）

```bash
SIMULATE_UNUSABLE=openai-codex:acc03 /data/openclaw/scripts/healthcheck_openai_codex_pool.sh || true
```

用于验证告警模板和精确定位是否正常。

---

## 最常用文件

- 主脚本：`/data/openclaw/scripts/healthcheck_openai_codex_pool.sh`
- 顺序同步：`/data/openclaw/scripts/sync_openclaw_auth_order.sh`
- 最新报告：`/data/openclaw/reports/openai_codex_health_latest.json`
- 每日日志：`/data/openclaw/reports/openai_codex_health_YYYYMMDD.log`

---

## 这次已做的细节改进

1. 去掉“写死 5 个账号”，改成自动发现 `openai-codex:*`
2. 新增账号规模建议（5~12 默认，可配置）
3. Telegram 改为单条摘要，避免 WARN/CRITICAL 重复推送
4. 轻量调用增加超时保护，减少脚本卡住风险
5. 通知目标、阈值、provider 改为环境变量可配置

---

## 常见问题

看这里：[`docs/troubleshooting-zh.md`](docs/troubleshooting-zh.md)

---

## 安全提醒

- 不要把 token / key 提交到仓库
- 凭证泄露后立即轮换

---

## License

MIT
