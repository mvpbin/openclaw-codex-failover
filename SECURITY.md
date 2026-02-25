# 安全策略 / Security Policy

> GitHub 的 Security 标签页默认展示 `SECURITY.md`。本文件提供中英双语说明。

## 适用范围 / Scope
本仓库面向公开复用。安全前提是：**真实凭据绝不进入 git 历史**，运行时配置遵循最小权限原则。  
This repository is public and reusable. Security depends on keeping real credentials out of git history and using least-privilege runtime configs.

## 严禁提交 / Never commit
- 私钥（`EXECUTOR_PRIVATE_KEY`、`FLASHBOTS_AUTH_PRIVATE_KEY`、助记词）  
  Private keys (`EXECUTOR_PRIVATE_KEY`, `FLASHBOTS_AUTH_PRIVATE_KEY`, seed phrases)
- 鉴权文件/令牌（`auth.json`、provider cookies、API tokens）  
  Auth files/tokens (`auth.json`, provider cookies, API tokens)
- 真实代理账号密码 / 内网端点  
  Real proxy credentials / internal endpoints
- 你认为敏感的真实通知目标  
  Real notification targets if sensitive

## 安全默认 / Safe defaults
- 公共文档仅使用占位示例（`*.example`）。  
  Use placeholder-only examples (`*.example`) in public docs.
- smoke 测试优先使用 burner/test key。  
  Prefer burner/test keys for smoke tests.
- 生产密钥只保存在本机运行文件（如 `/etc/openclaw-healthcheck.env`、本地 `.env`），不要提交。  
  Keep production secrets only in local runtime files (e.g. `/etc/openclaw-healthcheck.env`, local `.env`) and never commit.

## 发生泄露时 / If a secret is exposed
1. 立刻轮换密钥。 / Rotate immediately.  
2. 清理日志/备份中的敏感内容。 / Remove secret-bearing runtime artifacts from logs/backups where possible.  
3. 若已进入 git 历史，重写历史并强推。 / Rewrite git history and force-push if leaked in commits.  
4. 用新凭据重新验证全链路。 / Re-validate access from clean credentials only.

## 漏洞反馈 / Reporting
如发现安全问题，请先通过维护者私下渠道反馈，再考虑公开披露。  
If you find a security issue, contact the maintainer privately before public disclosure.
