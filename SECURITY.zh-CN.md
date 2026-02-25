# 安全策略（Security Policy）

## 适用范围
本仓库面向公开复用。安全前提是：**真实凭据绝不进入 git 历史**，运行时配置遵循最小权限原则。

## 严禁提交
- 私钥（`EXECUTOR_PRIVATE_KEY`、`FLASHBOTS_AUTH_PRIVATE_KEY`、助记词）
- 鉴权文件/令牌（`auth.json`、provider cookie、API token）
- 真实代理账号密码 / 内网端点
- 你认为敏感的真实通知目标

## 安全默认
- 公共文档仅使用占位示例（`*.example`）。
- smoke 测试优先使用 burner/test key。
- 生产密钥只保存在本机运行文件（如 `/etc/openclaw-healthcheck.env`、本地 `.env`），不要提交。

## 发生泄露时
1. 立刻轮换密钥。
2. 尽可能清理含敏感信息的日志/备份。
3. 若已进入 git 历史，重写历史并强推。
4. 用新凭据重新验证全链路访问。

## 漏洞反馈
如发现安全问题，请先通过维护者私下渠道反馈，再考虑公开披露。