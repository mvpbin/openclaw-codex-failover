# Changelog

All notable changes to this project are documented here.

## [Unreleased]

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
