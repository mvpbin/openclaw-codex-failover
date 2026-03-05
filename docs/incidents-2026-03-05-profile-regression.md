# Incident: openai-codex profile pool regression (16 -> 11)

Date: 2026-03-05

## Symptom
- `auth-profiles.json` was expected to keep 16 profiles (`acc01..acc15 + default`).
- Runtime repeatedly observed fallback to 11 profiles (`acc01..acc10 + default`).
- Health report reflected the runtime pool count, so `discoveredCount` oscillated with the regression.

## Root cause
- Mixed runtime versions on the same host:
  - CLI updated to `openclaw 2026.3.2`
  - user service `openclaw-gateway.service` still running older app build (`v2026.2.17`)
- This version split caused profile persistence behavior mismatch and profile set rewrites.

## Verification evidence
1. Before mitigation, user service showed old version while CLI was new.
2. After force reinstall/restart of user gateway service:
   - service became `OpenClaw Gateway (v2026.3.2)`
3. Re-import test (`acc11..acc15`) + stability check:
   - immediate file count: 16
   - repeated `openclaw models status` checks: still 16
   - healthcheck report: `discoveredCount=16`

## Mitigation
1. `openclaw gateway install --force`
2. `openclaw gateway restart`
3. Verify service version (`systemctl --user status openclaw-gateway.service`)
4. Re-import missing profiles (if needed)
5. Re-run healthcheck and persistence checks

## Prevention checklist
- After any OpenClaw update, always verify **both**:
  - `openclaw --version`
  - `systemctl --user status openclaw-gateway.service` app version line
- Add post-update gate: do not proceed until CLI and gateway service versions are aligned.
- Run a profile persistence sanity test (3 repeated checks) before re-enabling automations.
