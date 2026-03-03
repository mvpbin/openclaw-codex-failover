# Release Notes — 2026-03-03

## Summary
This patch fixes a failover blind spot where provider runtime errors (`usage limit`, `token invalidated`, `connected | error`) did not trigger strong enough actions, causing long periods of no reply on Telegram.

## Added / Changed
- Probe-signal emergency breaker in `scripts/healthcheck_openai_codex_pool.sh`
  - New env: `OCX_PROBE_HINT_FORCE_TRIP=1` (default)
  - New env: `OCX_PROBE_HINT_MIN_COOLDOWN_SECONDS=1800` (default)
  - New env: `OCX_PROBE_HINT_MAX_COOLDOWN_SECONDS=259200` (default)
  - Supports deriving cooldown from probe text like `Try again in ~NNN min`
- Immediate probe-driven demotion when auto reorder is disabled
  - New env: `OCX_PROBE_HINT_DEMOTE_WITHOUT_AUTO_REORDER=1` (default)
  - Even with `OCX_AUTO_REORDER=0`, suspected failing profile is moved to order tail
- State-machine correction
  - `failedProfiles` / `expiringProfiles` now force Degraded state (no more false Healthy)

## Docs updates
- README homepage date and latest increment updated to `2026-03-03`
- Troubleshooting added a dedicated section for the exact error pattern above
- Release post template updated with 2026-03-03 announcement copy

## Validation
- `bash -n scripts/healthcheck_openai_codex_pool.sh` passed
- Dry-run healthcheck reports `Degraded` when failed/expiring profiles exist
- Regex validation matches:
  - `You have hit your ChatGPT usage limit`
  - `Your authentication token has been invalidated`
  - `connected | error`
