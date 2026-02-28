# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added
- Proxy quarantine TTL mechanism in `check_socks5_proxy_clean.sh` to suppress repeated reuse of known-bad proxies.
- Multi-attempt fallback with backoff in `login_openai_codex_profile_via_proxy.sh`.
- New env knobs for fallback/quarantine tuning in `openclaw-healthcheck.env.example`.
- `SECURITY.md` + `SECURITY.zh-CN.md` with public-repo safety policy and leak response steps.
- `scripts/bootstrap.sh` for one-command public-safe bootstrap (supports `OCX_BOOTSTRAP_LANG=zh-CN`).
- `config/public-safe.env.example` + `.zh-CN` placeholder-only runtime bootstrap configs.
- `scripts/watch_openai_codex_health_freshness.sh` to auto-heal stale `openai_codex_health_latest.json` reports.

### Changed
- README homepage/date and config table updated with 2026-02-28 freshness-watchdog notes and maintenance guidance.
- Added an explicit stale-report recovery runbook (`watch_openai_codex_health_freshness.sh`) in docs and operator guidance.
- Troubleshooting and release-note docs updated for quarantine/fallback operations.

## [2026-02-18] - Hardening + usability pass

### Added
- `scripts/import_codex_auth_to_openclaw.sh` to import Codex device-auth tokens into OpenClaw auth profiles.
- `scripts/preflight_openai_codex_failover.sh` for one-command readiness checks.

### Changed
- Parameterized Codex auth path via `OCX_CODEX_AUTH_PATH` (default `/root/.codex/auth.json`).
- Removed hardcoded `/data/openclaw/scripts/...` references in repair flow; now uses `OCX_BASE_DIR`.
- Updated onboarding/repair/healthcheck scripts to better match root-based deployments.
- Updated docs (`README.md`, `docs/quickstart-zh.md`, `docs/troubleshooting-zh.md`) for real-world install paths and preflight usage.
- Changed example `OCX_RECOMMENDED_MIN` default in env example to `1` for better first-run ergonomics.

### Notes
- Project status: **Beta** (validated in real deployment on Ubuntu 22.04 + OpenClaw 2026.2.17).
