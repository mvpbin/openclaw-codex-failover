# Release Notes - 2026-03-05

## Highlights

- Added durable profile persistence safeguards: file lock + atomic write on `auth-profiles.json` update paths.
- Added anti-rollback reconcile loop (`openclaw-profile-reconcile.service/.timer`) to restore missing profiles from auth map.
- Added per-profile auth snapshot materialization to avoid shared auth file overwrite issues.
- Fixed auth-store expiry interpretation so expired profiles are correctly marked failed.
- Added failover self-test script for quota injection and head-profile switch verification.

## Operational Notes

- New env knobs: `OCX_AUTH_SNAPSHOT_DIR`, `OCX_AUTH_SNAPSHOT_PERSIST`, `OCX_RECONCILE_MODE`, `OCX_RECONCILE_LOCK_FILE`.
- Reconcile timer default cadence: every 2 minutes.
- Recommended production setting: keep probes enabled (`OCX_DISABLE_PROBES=0`).
