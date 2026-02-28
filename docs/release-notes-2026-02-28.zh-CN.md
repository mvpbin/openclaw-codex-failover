# 发布说明 — 2026-02-28

## 摘要
本次补丁修复了一个“看起来像挂了”的可观测性问题：健康快照文件在生命周期变化后可能停更，导致面板显示旧状态。

## 新增
- `scripts/watch_openai_codex_health_freshness.sh`
  - 检测 `/data/openclaw/reports/openai_codex_health_latest.json` 是否过期
  - 过期时强制执行一次健康检查
  - 若仍未恢复，可选重启 timer/service 进行自愈

## 运维用法

手动执行：

```bash
/data/openclaw/scripts/watch_openai_codex_health_freshness.sh
```

调整过期阈值（默认 1800 秒）：

```bash
OCX_MAX_STALE_SECONDS=900 /data/openclaw/scripts/watch_openai_codex_health_freshness.sh
```

## 价值
避免“容灾机制正常，但报告停更”的假故障，确保“健康状态与可视化一致”。
