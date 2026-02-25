# Security Policy

## Scope
This repository is designed to be public and reusable. Security depends on keeping all real credentials out of git history and using least-privilege runtime configs.

## Never commit
- Private keys (`EXECUTOR_PRIVATE_KEY`, `FLASHBOTS_AUTH_PRIVATE_KEY`, wallet seed phrases)
- Auth files/tokens (`auth.json`, provider cookies, API tokens)
- Real proxy credentials / internal endpoints
- Real notification targets if you consider them sensitive

## Safe defaults
- Use placeholder-only examples (`*.example`) in public docs.
- Prefer burner/test keys for smoke tests.
- Keep production secrets only in local runtime files (e.g. `/etc/openclaw-healthcheck.env`, local `.env`) and never commit them.

## If a secret is exposed
1. Rotate it immediately.
2. Remove secret-bearing runtime files from logs/backups where possible.
3. If a commit leaked a secret, rewrite git history and force-push.
4. Re-validate access from clean credentials only.

## Reporting
If you find a security issue in this repo, open a private channel with the maintainer first before public disclosure.