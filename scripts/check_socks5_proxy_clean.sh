#!/usr/bin/env bash
set -euo pipefail

# Validate proxy egress IP before account login.
# Usage:
#   check_socks5_proxy_clean.sh <profileId> [proxy]

DEFAULT_ENV_FILE="/etc/openclaw-healthcheck.env"
if [[ -f "$DEFAULT_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DEFAULT_ENV_FILE"
fi

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
PROVIDER="${OCX_PROVIDER:-openai-codex}"
PROFILE_ID="${1:-}"
INPUT_PROXY="${2:-}"
PROXY_MAP_FILE="${OCX_SOCKS5_MAP_FILE:-$BASE_DIR/config/openai-codex-socks5-map.env}"
IP_DENYLIST_FILE="${OCX_SOCKS5_IP_DENYLIST_FILE:-$BASE_DIR/config/socks5-ip-denylist.txt}"
IP_ALLOWLIST_FILE="${OCX_SOCKS5_IP_ALLOWLIST_FILE:-}"
CONNECT_TIMEOUT="${OCX_SOCKS5_CONNECT_TIMEOUT_SECONDS:-12}"
MAX_TIME="${OCX_SOCKS5_MAX_TIME_SECONDS:-20}"
IP_CHECK_URLS="${OCX_SOCKS5_IP_CHECK_URLS:-https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com}"
CUSTOM_CHECK_CMD="${OCX_SOCKS5_CLEAN_CHECK_CMD:-}"

# Optimization toggles
CACHE_TTL_SECONDS="${OCX_PROXY_CHECK_CACHE_TTL_SECONDS:-600}"
CHECK_METRICS_FILE="${OCX_PROXY_CHECK_METRICS_FILE:-$BASE_DIR/reports/proxy-check-metrics.jsonl}"

if [[ -z "$PROFILE_ID" ]]; then
  echo "usage: $0 <profileId> [proxy]" >&2
  exit 2
fi
if [[ "$PROFILE_ID" != ${PROVIDER}:* ]]; then
  echo "profileId must start with ${PROVIDER}:" >&2
  exit 2
fi

mkdir -p "$BASE_DIR/run" "$BASE_DIR/reports"

lookup_proxy(){
  local profile="$1"
  local p=""
  if [[ -f "$PROXY_MAP_FILE" ]]; then
    p="$(awk -F= -v k="$profile" '$1==k{print substr($0,index($0,$2))}' "$PROXY_MAP_FILE" | tail -n1)"
  fi
  echo "$p"
}

urlencode(){
  local s="$1"
  node -e 'process.stdout.write(encodeURIComponent(process.argv[1]||""))' "$s"
}

normalize_proxy(){
  local raw="$1"
  local default_scheme="${OCX_PROXY_DEFAULT_SCHEME:-socks5h}"
  if [[ "$raw" == socks5://* || "$raw" == socks5h://* || "$raw" == http://* || "$raw" == https://* ]]; then
    echo "$raw"
    return 0
  fi

  local host="" port="" user="" pass="" extra=""
  IFS=':' read -r host port user pass extra <<< "$raw"
  if [[ -n "$host" && -n "$port" && -n "$user" && -n "$pass" && -z "$extra" ]]; then
    local user_enc pass_enc
    user_enc="$(urlencode "$user")"
    pass_enc="$(urlencode "$pass")"
    case "$default_scheme" in
      socks5|socks5h|http|https) ;;
      *) default_scheme="socks5h" ;;
    esac
    echo "${default_scheme}://${user_enc}:${pass_enc}@${host}:${port}"
    return 0
  fi

  return 1
}

metric(){
  local status="$1" ip="$2" reason="$3" proxy="$4"
  TS_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  PROFILE_ID="$PROFILE_ID" STATUS="$status" IP="$ip" REASON="$reason" PROXY="$proxy" FILE="$CHECK_METRICS_FILE" \
  node - <<'NODE' >/dev/null 2>&1 || true
const fs=require('fs');
const rec={
  ts:process.env.TS_NOW,
  profileId:process.env.PROFILE_ID,
  status:process.env.STATUS,
  ip:process.env.IP||null,
  reason:process.env.REASON||null,
  proxy:process.env.PROXY||null
};
fs.appendFileSync(process.env.FILE, JSON.stringify(rec)+'\n');
NODE
}

cache_key(){
  local s="$1"
  printf '%s' "$s" | sha256sum | awk '{print $1}'
}

cache_file_for(){
  local k="$1"
  echo "$BASE_DIR/run/proxy-check-cache-${k}.json"
}

try_cache(){
  local proxy="$1"
  local key file now
  key="$(cache_key "$proxy")"
  file="$(cache_file_for "$key")"
  [[ -f "$file" ]] || return 1
  now="$(date +%s)"
  CACHE_FILE="$file" NOW="$now" TTL="$CACHE_TTL_SECONDS" node - <<'NODE'
const fs=require('fs');
const f=process.env.CACHE_FILE;
const now=Number(process.env.NOW||0);
const ttl=Number(process.env.TTL||0);
const j=JSON.parse(fs.readFileSync(f,'utf8'));
if(!j.ok) process.exit(1);
if(!j.checkedAtEpoch || now-j.checkedAtEpoch>ttl) process.exit(1);
process.stdout.write(String(j.ip||''));
NODE
}

save_cache(){
  local proxy="$1" ok="$2" ip="$3" reason="$4"
  local key file now
  key="$(cache_key "$proxy")"
  file="$(cache_file_for "$key")"
  now="$(date +%s)"
  CACHE_FILE="$file" OK="$ok" IP="$ip" REASON="$reason" NOW="$now" node - <<'NODE'
const fs=require('fs');
const rec={
  ok: process.env.OK==='1',
  ip: process.env.IP||null,
  reason: process.env.REASON||null,
  checkedAtEpoch: Number(process.env.NOW||0)
};
fs.writeFileSync(process.env.CACHE_FILE, JSON.stringify(rec));
NODE
}

proxy_raw="${INPUT_PROXY:-$(lookup_proxy "$PROFILE_ID")}" 
proxy=""
if ! proxy="$(normalize_proxy "$proxy_raw")"; then
  echo "unsupported proxy format for $PROFILE_ID: $proxy_raw" >&2
  echo "use socks5://..., http://... or hostname:port:username:password" >&2
  metric fail "" "unsupported_proxy_format" "$proxy_raw"
  exit 1
fi
if [[ -z "$proxy" ]]; then
  echo "no proxy configured for $PROFILE_ID (map: $PROXY_MAP_FILE)" >&2
  metric fail "" "proxy_missing" "$proxy"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "missing command: curl" >&2
  metric fail "" "curl_missing" "$proxy"
  exit 2
fi

# Cache hit short-circuit
if [[ "$CACHE_TTL_SECONDS" -gt 0 ]]; then
  cached_ip="$(try_cache "$proxy" 2>/dev/null || true)"
  if [[ -n "$cached_ip" ]]; then
    echo "proxy clean (cached): $PROFILE_ID -> $cached_ip"
    metric pass "$cached_ip" "cache_hit" "$proxy"
    exit 0
  fi
fi

ip=""
for u in $IP_CHECK_URLS; do
  out="$(curl --silent --show-error --fail --proxy "$proxy" --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" "$u" 2>/dev/null || true)"
  out="$(printf '%s' "$out" | tr -d ' \r\n\t')"
  if [[ -n "$out" ]]; then
    ip="$out"
    break
  fi
done

if [[ -z "$ip" ]]; then
  echo "proxy check failed for $PROFILE_ID: cannot get egress IP" >&2
  save_cache "$proxy" 0 "" "egress_ip_missing"
  metric fail "" "egress_ip_missing" "$proxy"
  exit 1
fi

if ! node -e '
const ip=(process.argv[1]||"").trim();
const v4=/^(\d{1,3}\.){3}\d{1,3}$/;
const v6=/^[0-9a-fA-F:]+$/;
const fail=(m)=>{console.error(m); process.exit(1);};
if(v4.test(ip)){
  const a=ip.split(".").map(Number);
  if(a.some(x=>Number.isNaN(x)||x<0||x>255)) fail("invalid IPv4");
  const [x,y]=a;
  if(x===10||x===127||x===0||x===255) fail("private/reserved IPv4");
  if(x===169&&y===254) fail("link-local IPv4");
  if(x===192&&y===168) fail("private IPv4");
  if(x===172&&y>=16&&y<=31) fail("private IPv4");
  if(x===100&&y>=64&&y<=127) fail("carrier-grade NAT IPv4");
  if(x===198&&(y===18||y===19)) fail("benchmark IPv4");
  if(x>=224) fail("multicast/reserved IPv4");
  process.exit(0);
}
if(v6.test(ip) && ip.includes(":")){
  const s=ip.toLowerCase();
  if(s==="::1"||s==="::") fail("loopback/unspecified IPv6");
  if(s.startsWith("fc")||s.startsWith("fd")) fail("unique-local IPv6");
  if(s.startsWith("fe8")||s.startsWith("fe9")||s.startsWith("fea")||s.startsWith("feb")) fail("link-local IPv6");
  process.exit(0);
}
fail("invalid IP format");
' "$ip"; then
  echo "proxy check failed for $PROFILE_ID: dirty or invalid IP $ip" >&2
  save_cache "$proxy" 0 "$ip" "dirty_or_invalid_ip"
  metric fail "$ip" "dirty_or_invalid_ip" "$proxy"
  exit 1
fi

if [[ -f "$IP_DENYLIST_FILE" ]] && grep -Fqx "$ip" "$IP_DENYLIST_FILE"; then
  echo "proxy check failed for $PROFILE_ID: IP in denylist $ip" >&2
  save_cache "$proxy" 0 "$ip" "denylist_hit"
  metric fail "$ip" "denylist_hit" "$proxy"
  exit 1
fi

if [[ -n "$IP_ALLOWLIST_FILE" && -f "$IP_ALLOWLIST_FILE" ]]; then
  if ! grep -Fqx "$ip" "$IP_ALLOWLIST_FILE"; then
    echo "proxy check failed for $PROFILE_ID: IP not in allowlist $ip" >&2
    save_cache "$proxy" 0 "$ip" "allowlist_miss"
    metric fail "$ip" "allowlist_miss" "$proxy"
    exit 1
  fi
fi

if [[ -n "$CUSTOM_CHECK_CMD" ]]; then
  if ! OCX_PROXY_IP="$ip" OCX_PROFILE_ID="$PROFILE_ID" OCX_SOCKS5_PROXY="$proxy" bash -lc "$CUSTOM_CHECK_CMD"; then
    echo "proxy check failed for $PROFILE_ID: custom clean check rejected $ip" >&2
    save_cache "$proxy" 0 "$ip" "custom_check_rejected"
    metric fail "$ip" "custom_check_rejected" "$proxy"
    exit 1
  fi
fi

save_cache "$proxy" 1 "$ip" "ok"
metric pass "$ip" "ok" "$proxy"
echo "proxy clean: $PROFILE_ID -> $ip"