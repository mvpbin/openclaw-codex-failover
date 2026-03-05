#!/usr/bin/env bash
set -euo pipefail

DEFAULT_ENV_FILE="/etc/openclaw-healthcheck.env"
if [[ -f "$DEFAULT_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DEFAULT_ENV_FILE"
fi

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
PROVIDER="${OCX_PROVIDER:-openai-codex}"
AGENT="${OCX_AGENT:-main}"
AUTH_PROFILES_PATH="${OCX_AUTH_PROFILES_PATH:-/root/.openclaw/agents/${AGENT}/agent/auth-profiles.json}"
AUTH_MAP_FILE="${OCX_AUTH_MAP_FILE:-$BASE_DIR/config/openai-codex-auth-map.env}"
AUTH_SNAPSHOT_DIR="${OCX_AUTH_SNAPSHOT_DIR:-$BASE_DIR/auth/${PROVIDER}}"

if [[ ! -f "$AUTH_PROFILES_PATH" ]]; then
  echo "auth profiles not found: $AUTH_PROFILES_PATH" >&2
  exit 1
fi

mkdir -p "$AUTH_SNAPSHOT_DIR" "$(dirname "$AUTH_MAP_FILE")"

AUTH_PROFILES_PATH="$AUTH_PROFILES_PATH" PROVIDER="$PROVIDER" AUTH_SNAPSHOT_DIR="$AUTH_SNAPSHOT_DIR" AUTH_MAP_FILE="$AUTH_MAP_FILE" node - <<'NODE'
const fs=require('fs');
const path=require('path');

const authProfilesPath=process.env.AUTH_PROFILES_PATH;
const provider=String(process.env.PROVIDER||'openai-codex');
const prefix=`${provider}:`;
const snapshotRoot=process.env.AUTH_SNAPSHOT_DIR;
const mapFile=process.env.AUTH_MAP_FILE;

let store={};
try{store=JSON.parse(fs.readFileSync(authProfilesPath,'utf8'));}catch(e){
  console.error(`failed to parse ${authProfilesPath}: ${e.message}`);
  process.exit(1);
}

const profiles=store.profiles||{};
const ids=Object.keys(profiles).filter((id)=>id.startsWith(prefix)).sort();
const mapRows=[];

for(const id of ids){
  const row=profiles[id]||{};
  const suffix=id.slice(prefix.length);
  const dir=path.join(snapshotRoot, suffix);
  const filePath=path.join(dir, 'auth.json');
  fs.mkdirSync(dir,{recursive:true});

  const payload={
    openai:{
      access_token: row.access || '',
      refresh_token: row.refresh || '',
      expires_at: Number(row.expires || 0),
      account_id: String(row.accountId || '')
    }
  };
  fs.writeFileSync(filePath, JSON.stringify(payload,null,2));
  fs.chmodSync(filePath, 0o600);
  mapRows.push(`${id}=${filePath}`);
}

let existing=[];
try{existing=fs.readFileSync(mapFile,'utf8').split('\n');}catch{}
const keep=[];
for(const line of existing){
  const t=line.trim();
  if(!t || t.startsWith('#')){ keep.push(line); continue; }
  const i=t.indexOf('=');
  if(i<=0){ keep.push(line); continue; }
  const k=t.slice(0,i).trim();
  if(!k.startsWith(prefix)) keep.push(line);
}

const out=[...keep.filter(Boolean), ...mapRows];
fs.writeFileSync(mapFile, out.join('\n')+'\n');
console.log(`materialized snapshots: ${ids.length}`);
console.log(`updated map: ${mapFile}`);
NODE
