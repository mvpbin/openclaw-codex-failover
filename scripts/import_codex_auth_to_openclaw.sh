#!/usr/bin/env bash
set -euo pipefail

# Import a Codex OAuth auth.json into OpenClaw auth-profiles.json
# Usage:
#   import_codex_auth_to_openclaw.sh <profileId> [agentId=main] [authJsonPath=/root/.codex/auth.json]

PROFILE_ID="${1:-}"
AGENT_ID="${2:-main}"
AUTH_JSON_PATH="${3:-/root/.codex/auth.json}"

if [[ -z "$PROFILE_ID" ]]; then
  echo "usage: $0 <profileId> [agentId] [authJsonPath]" >&2
  exit 2
fi
if [[ "$PROFILE_ID" != openai-codex:* ]]; then
  echo "profileId must start with openai-codex:" >&2
  exit 2
fi
if [[ ! -f "$AUTH_JSON_PATH" ]]; then
  echo "auth file not found: $AUTH_JSON_PATH" >&2
  exit 1
fi

AUTH_PROFILES_PATH="/root/.openclaw/agents/${AGENT_ID}/agent/auth-profiles.json"
mkdir -p "$(dirname "$AUTH_PROFILES_PATH")"

PROFILE_ID="$PROFILE_ID" AUTH_JSON_PATH="$AUTH_JSON_PATH" AUTH_PROFILES_PATH="$AUTH_PROFILES_PATH" node - <<'NODE'
const fs = require('fs');

const profileId = process.env.PROFILE_ID;
const authJsonPath = process.env.AUTH_JSON_PATH;
const authProfilesPath = process.env.AUTH_PROFILES_PATH;

const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const now = Date.now();

const src = readJson(authJsonPath);

// Accept common token field variants
const access = src.access_token || src.accessToken || src.access || src.token || src?.credentials?.access_token;
const refresh = src.refresh_token || src.refreshToken || src.refresh || src?.credentials?.refresh_token;

let expires = src.expires_at || src.expiresAt || src.expires || src.exp || src?.credentials?.expires_at;
if (typeof expires === 'string' && /^\d+$/.test(expires)) expires = Number(expires);
if (typeof expires === 'number' && expires < 1e12) expires = expires * 1000; // seconds -> ms
if (!expires || Number.isNaN(expires)) expires = now + 24 * 3600 * 1000;

const accountId = src.account_id || src.accountId || src.user_id || src.userId || src.sub || src?.user?.id || 'unknown';

if (!access || !refresh) {
  throw new Error('auth.json missing required access/refresh token fields');
}

let dst = { version: 1, profiles: {}, order: { 'openai-codex': [] }, lastGood: {}, usageStats: {} };
if (fs.existsSync(authProfilesPath)) {
  try { dst = readJson(authProfilesPath); } catch {}
}

dst.version = dst.version || 1;
dst.profiles = dst.profiles || {};
dst.order = dst.order || {};
dst.order['openai-codex'] = Array.isArray(dst.order['openai-codex']) ? dst.order['openai-codex'] : [];
dst.lastGood = dst.lastGood || {};
dst.usageStats = dst.usageStats || {};

dst.profiles[profileId] = {
  type: 'oauth',
  provider: 'openai-codex',
  access,
  refresh,
  expires,
  accountId: String(accountId)
};

// Put newly imported profile first for quick validation, keep others
const rest = dst.order['openai-codex'].filter((x) => x !== profileId);
dst.order['openai-codex'] = [profileId, ...rest];
dst.lastGood['openai-codex'] = profileId;

dst.usageStats[profileId] = dst.usageStats[profileId] || {
  ok: 0,
  fail: 0,
  lastOkAt: 0,
  lastFailAt: 0,
  updatedAt: now
};
dst.usageStats[profileId].updatedAt = now;

fs.writeFileSync(authProfilesPath, JSON.stringify(dst, null, 2));
console.log(`imported ${profileId} -> ${authProfilesPath}`);
NODE

openclaw models status --json >/dev/null

echo "done"