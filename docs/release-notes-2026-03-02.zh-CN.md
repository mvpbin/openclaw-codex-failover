# 发布说明 — 2026-03-02

## 摘要
本次补丁聚焦于：当 profile 数量看起来很多、但真实上游账号数较少时，降低容灾切换抖动与误判。

## 新增 / 变更
- `scripts/healthcheck_openai_codex_pool.sh` 增强“账号多样化重排”
  - 新增环境变量：`OCX_AUTO_REORDER_ACCOUNT_DIVERSITY=1`（默认开启）
  - 重排策略从“仅按健康分”升级为“健康分优先 + 按 `accountId` 交错”
  - 目标：在 quota/auth 压力下，避免连续命中同一上游账号
- 新增 `accountId` 回填兜底
  - 新增环境变量：`OCX_AUTH_PROFILES_PATH`
  - 当 `openclaw models status --json` 不提供 `accountId` 时，从本地 auth profile store 回填
- 探针失败信号提示增强
  - 识别并标注 quota/auth 压力关键词：
    - usage limit / API rate limit reached
    - authentication token invalidated
  - 用于区分“纯网络故障”与“上游配额/鉴权压力”
- 重排一致性修复
  - 启用 `OCX_AUTO_REORDER=1` 时，跳过会覆盖新顺序的后续 sync，避免重排结果被刷回

## 文档同步
- README 主页日期与“最新增量”日期已同步到 `2026-03-02`
- env 示例与 changelog 已同步新增项与行为说明

## 验证
- `bash -n scripts/healthcheck_openai_codex_pool.sh` 语法校验通过
- dry-run 健康检查通过，账号顺序已体现按 `accountId` 交错
