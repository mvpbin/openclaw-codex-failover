#!/usr/bin/env bash
set -euo pipefail

# Summarize proxy/account audit in last N hours (default 24h)
# Usage:
#   report_account_proxy_audit_24h.sh [hours=24] [topN=5]

DEFAULT_ENV_FILE="/etc/openclaw-healthcheck.env"
if [[ -f "$DEFAULT_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DEFAULT_ENV_FILE"
fi

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
AUDIT_FILE="${OCX_ACCOUNT_PROXY_AUDIT_FILE:-$BASE_DIR/reports/account-proxy-audit.jsonl}"
HOURS="${1:-24}"
TOPN="${2:-5}"

if [[ ! -f "$AUDIT_FILE" ]]; then
  echo "audit file not found: $AUDIT_FILE" >&2
  exit 2
fi

node - "$AUDIT_FILE" "$HOURS" "$TOPN" <<'NODE'
const fs=require('fs');
const [file,hoursRaw,topNRaw]=process.argv.slice(2);
const hours=Math.max(1, Number(hoursRaw||24));
const topN=Math.max(1, Number(topNRaw||5));
const since=Date.now()-hours*3600*1000;

const lines=fs.readFileSync(file,'utf8').split('\n').filter(Boolean);
const recs=[];
for(const line of lines){
  try{ const j=JSON.parse(line); if(new Date(j.ts).getTime()>=since) recs.push(j);}catch{}
}

const byProfile=new Map();
const reasonCounts=new Map();
for(const r of recs){
  const p=String(r.profileId||'unknown');
  if(!byProfile.has(p)) byProfile.set(p,{total:0,pass:0,fail:0,reasons:new Map()});
  const o=byProfile.get(p);
  o.total++;
  if(String(r.status)==='pass') o.pass++;
  if(String(r.status)==='fail'){
    o.fail++;
    const reason=String(r.reason||'unknown');
    o.reasons.set(reason,(o.reasons.get(reason)||0)+1);
    reasonCounts.set(reason,(reasonCounts.get(reason)||0)+1);
  }
}

const profiles=[...byProfile.entries()].map(([profile,v])=>{
  const rate=v.total? (v.pass*100/v.total):0;
  const topReasons=[...v.reasons.entries()].sort((a,b)=>b[1]-a[1]).slice(0,topN).map(([k,c])=>({reason:k,count:c}));
  return {profile,total:v.total,pass:v.pass,fail:v.fail,successRate:Number(rate.toFixed(2)),topFailReasons:topReasons};
}).sort((a,b)=>a.profile.localeCompare(b.profile));

const globalTop=[...reasonCounts.entries()].sort((a,b)=>b[1]-a[1]).slice(0,topN).map(([reason,count])=>({reason,count}));

console.log(`windowHours=${hours}`);
console.log(`records=${recs.length}`);
console.log('\n=== Per-profile summary ===');
for(const p of profiles){
  console.log(`${p.profile} | total=${p.total} pass=${p.pass} fail=${p.fail} successRate=${p.successRate}%`);
  if(p.topFailReasons.length){
    console.log(`  topFailReasons: ${p.topFailReasons.map(x=>`${x.reason}:${x.count}`).join(', ')}`);
  }
}
console.log('\n=== Global fail reason TopN ===');
if(globalTop.length===0) console.log('(none)');
for(const x of globalTop){
  console.log(`${x.reason}: ${x.count}`);
}
NODE