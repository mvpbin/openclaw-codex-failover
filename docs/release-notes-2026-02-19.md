# Release Notes — 2026-02-19

## Highlights
- Added beginner-friendly onboarding wizard: `scripts/onboard_profiles_wizard.sh`
- Added batch proxy health checker with concurrency: `scripts/check_proxy_pool_batch.sh`
- Added proxy login mode toggle: `OCX_USE_PROXY_LOGIN`
- Added fallback proxy option: `OCX_PROXY_AUTO_FALLBACK`
- Added proxy check cache + metrics:
  - `OCX_PROXY_CHECK_CACHE_TTL_SECONDS`
  - `OCX_PROXY_CHECK_METRICS_FILE`
  - `OCX_PROXY_CHECK_CONCURRENCY`
- Improved auth import compatibility for modern auth JSON layouts (including `openai` nested structure)
- Proxy format support now includes:
  - `host:port:username:password`
  - `socks5://...` / `socks5h://...`
  - `http://...` / `https://...`

## Validation Summary
- Script syntax checks: pass
- Preflight: `ok=19 warn=0 err=0`
- Proxy batch smoke test: pass
- Healthcheck dry-run state transition: pass (`Degraded` on simulated failure)
- Auth import regression (new auth layout): pass

## Notes
- Rotating proxies may fail clean checks intermittently by design; this is expected behavior.

## Additional (auditability)
- Added strict account↔proxy binding audit logger: `scripts/audit_account_proxy_binding.sh`
- Added 24h audit summary report script: `scripts/report_account_proxy_audit_24h.sh`
- `check_socks5_proxy_clean.sh` and proxy login flow now emit structured audit events for easier root-cause analysis.

## Additional (state/message consistency fix)
- Fixed report consistency: when state is `Healthy`/`Recovered`, `failedProfiles` is now forced empty.
- Fixed alert icon logic: healthy/recovered state is forced to PASS icon (`✅`), preventing stale warning icon confusion.

## Additional (smart circuit-breaker v2)
- Added failure-type-aware breaker classes: `auth` / `network` / `other` with separate thresholds/cooldowns.
- Added half-open probe window near cooldown expiry for earlier recovery.
- Added default-profile specific threshold/cooldown override.
- Added cooldown jitter to avoid synchronized retry storms.
- Added fail-count decay over time to reduce long-tail penalties after transient failures.
- Alert-noise tuning: cooldown-only warning suppression and wider dedup/remind windows.

## 2026-02-22 incremental update
- Smart circuit-breaker v2 landed: failure-type classes (`auth/network/other`), half-open probe, default-profile override, cooldown jitter, and fail-count decay.
- Alert noise tuning improved (cooldown-only suppression + wider dedup/remind windows).

## 2026-02-24 incremental update
- Added proxy quarantine TTL to avoid repeatedly reusing known-bad proxies.
- Added multi-attempt fallback with backoff (`OCX_PROXY_FALLBACK_MAX_ATTEMPTS`, `OCX_PROXY_FALLBACK_BACKOFF_SECONDS`).
- Added fallback success map persistence control (`OCX_PROXY_FALLBACK_PERSIST_MAP`).
- Updated env example and troubleshooting docs for quarantine/fallback tuning guidance.
