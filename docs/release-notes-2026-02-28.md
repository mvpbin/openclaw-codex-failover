# Release Notes — 2026-02-28

## Summary
This patch closes a reliability gap where Codex failover health looked "stuck" because the latest health snapshot file stopped refreshing after lifecycle changes.

## Added
- `scripts/watch_openai_codex_health_freshness.sh`
  - Detects stale `/data/openclaw/reports/openai_codex_health_latest.json`
  - Forces one healthcheck run when stale
  - Optionally restarts timer/service if freshness is not restored

## Operational Guidance

Run manually:

```bash
/data/openclaw/scripts/watch_openai_codex_health_freshness.sh
```

Override stale threshold (default 1800s):

```bash
OCX_MAX_STALE_SECONDS=900 /data/openclaw/scripts/watch_openai_codex_health_freshness.sh
```

## Why this matters
Without this watchdog, the failover engine can be healthy while dashboards still show old data. This patch restores “fresh report = true health visibility.”
