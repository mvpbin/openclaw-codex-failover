# Release Notes — 2026-03-04

## Summary
This release ships failover v2 with hard isolation and controlled recovery. Failed profiles no longer stay in rotation input when healthy capacity is sufficient.

## Added / Changed
- Hard isolation of failed profiles in `scripts/healthcheck_openai_codex_pool.sh`
  - New env: `OCX_HARD_DISABLE_FAILED=1` (default)
  - Rotation order input now prefers `activeProfiles` and excludes `quarantinedProfiles`
- Account-level quarantine support
  - New env: `OCX_HARD_DISABLE_FAILED_ACCOUNT=1` (default)
  - New env: `OCX_ACCOUNT_QUARANTINE_SECONDS=7200`
  - If a profile fails, sibling profiles under the same `accountId` can be quarantined together
- Controlled recovery gate
  - New env: `OCX_RECOVERY_SUCCESS_ROUNDS=2`
  - Quarantined profiles must pass consecutive healthy rounds before rejoining rotation
- Fail-open safety guard
  - New env: `OCX_HARD_DISABLE_MIN_ACTIVE_PROFILES=2`
  - New env: `OCX_HARD_DISABLE_MIN_ACTIVE_ACCOUNTS=1`
  - Automatically relaxes strict isolation if active capacity drops too low
- Health report observability extended
  - New fields: `activeProfiles`, `activeProfileCount`, `activeAccountCount`, `quarantinedProfiles`, `quarantinedAccounts`, `orderInputProfiles`

## Docs updates
- README homepage date + latest increment updated to `2026-03-04`
- Config table updated with failover v2 knobs
- Added release notes in both EN/ZH

## Validation
- `bash -n scripts/healthcheck_openai_codex_pool.sh` passed
- Runtime report confirms hard isolation output fields and active-only order input
- `openclaw logs` confirms current order override uses active pool only
