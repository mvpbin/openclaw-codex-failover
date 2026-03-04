#!/usr/bin/env bash
set -euo pipefail
PROVIDER="${1:-openai-codex}"
AGENT="${2:-main}"
AUTH_PROFILES_PATH="${OCX_AUTH_PROFILES_PATH:-/root/.openclaw/agents/${AGENT}/agent/auth-profiles.json}"

# Prefer auth-profiles.json as source of truth to avoid stale models-status cache
# causing profile loss during rapid/batch onboarding.
if [[ -f "$AUTH_PROFILES_PATH" ]]; then
  mapfile -t ids < <(AUTH_PROFILES_PATH="$AUTH_PROFILES_PATH" PROVIDER="$PROVIDER" node - <<'NODE'
const fs=require('fs');
const provider=String(process.env.PROVIDER||'openai-codex').trim();
const prefix=`${provider}:`;
let store={};
try{store=JSON.parse(fs.readFileSync(process.env.AUTH_PROFILES_PATH,'utf8'));}catch{}
const profiles=(store&&store.profiles&&typeof store.profiles==='object')?store.profiles:{};
const all=Object.keys(profiles).filter((id)=>String(id).startsWith(prefix));
const order=((store&&store.order&&Array.isArray(store.order[provider]))?store.order[provider]:[])
  .filter((id)=>all.includes(id));
const seen=new Set(order);
const merged=[...order, ...all.filter((id)=>!seen.has(id)).sort((a,b)=>a.localeCompare(b))];
for(const id of merged) console.log(id);
NODE
  )
else
  status_json="$(openclaw models status --json)"
  mapfile -t ids < <(STATUS_JSON="$status_json" PROVIDER="$PROVIDER" node - <<'NODE'
const obj=JSON.parse(process.env.STATUS_JSON||'{}');
const provider=(process.env.PROVIDER||'').toLowerCase();
const labels=((obj.auth?.providers||[]).find(p=>String(p.provider||'').toLowerCase()===provider)?.profiles?.labels)||[];
for (const l of labels) {
  const id=String(l).split('=')[0]?.trim();
  if (id && id.toLowerCase().startsWith(provider+':')) console.log(id);
}
NODE
  )
fi

if ((${#ids[@]}==0)); then
  echo "no profiles found for $PROVIDER" >&2
  exit 1
fi

openclaw models auth order set --agent "$AGENT" --provider "$PROVIDER" "${ids[@]}" >/dev/null
echo "synced $PROVIDER order for agent $AGENT: ${ids[*]}"
