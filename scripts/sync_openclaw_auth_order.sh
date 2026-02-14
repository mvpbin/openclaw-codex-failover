#!/usr/bin/env bash
set -euo pipefail
PROVIDER="${1:-openai-codex}"
AGENT="${2:-main}"

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

if ((${#ids[@]}==0)); then
  echo "no profiles found for $PROVIDER" >&2
  exit 1
fi

openclaw models auth order set --agent "$AGENT" --provider "$PROVIDER" "${ids[@]}" >/dev/null
echo "synced $PROVIDER order for agent $AGENT: ${ids[*]}"
