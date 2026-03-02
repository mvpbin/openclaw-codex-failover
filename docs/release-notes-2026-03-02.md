# Release Notes — 2026-03-02

## Summary
This patch focuses on reducing failover flapping when multiple profiles map to only a few real upstream accounts.

## Added / Changed
- Account-diversity auto reorder in `scripts/healthcheck_openai_codex_pool.sh`
  - New env: `OCX_AUTO_REORDER_ACCOUNT_DIVERSITY=1` (default)
  - Reorder now prefers high health score **and** interleaves by `accountId`
  - Goal: avoid consecutive hits on the same upstream account under quota/auth pressure
- AccountId enrichment fallback
  - New env: `OCX_AUTH_PROFILES_PATH`
  - When `openclaw models status --json` does not expose `accountId`, script backfills from auth profile store
- Probe signal classification hinting
  - Probe failures now emit concise hints for quota/auth pressure patterns:
    - usage limit / API rate limit reached
    - authentication token invalidated
  - Helps distinguish non-network pressure from pure network outages
- Auto-reorder consistency fix
  - When `OCX_AUTO_REORDER=1`, skip post-reorder sync override that could revert the newly computed order

## Docs updates
- README homepage date and latest-increment date were refreshed to `2026-03-02`
- Env examples and changelog updated with new knobs and behavior notes

## Validation
- `bash -n scripts/healthcheck_openai_codex_pool.sh` passed
- Dry-run healthcheck completed with account-diversity reorder effective on active profile order
