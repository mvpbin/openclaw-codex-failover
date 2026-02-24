#!/usr/bin/env bash
set -euo pipefail

# Login a profile via SOCKS5 proxy and import into OpenClaw.
# Usage:
#   login_openai_codex_profile_via_proxy.sh openai-codex:acc03 [/root/.codex/auth.json]

DEFAULT_ENV_FILE="/etc/openclaw-healthcheck.env"
if [[ -f "$DEFAULT_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DEFAULT_ENV_FILE"
fi

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
PROVIDER="${OCX_PROVIDER:-openai-codex}"
PROFILE_ID="${1:-}"
DEFAULT_AUTH_JSON_PATH="${OCX_CODEX_AUTH_PATH:-/root/.codex/auth.json}"
AUTH_JSON_PATH="${2:-$DEFAULT_AUTH_JSON_PATH}"
PROXY_MAP_FILE="${OCX_SOCKS5_MAP_FILE:-$BASE_DIR/config/openai-codex-socks5-map.env}"
PROXY_POOL_FILE="${OCX_PROXY_POOL_FILE:-$BASE_DIR/config/openai-codex-proxy-pool.txt}"
FORCE_LOGOUT="${OCX_PROXY_LOGIN_FORCE_LOGOUT:-1}"
USE_PROXY_LOGIN="${OCX_USE_PROXY_LOGIN:-1}"
AUTO_FALLBACK="${OCX_PROXY_AUTO_FALLBACK:-1}"
FALLBACK_CURSOR_FILE="${OCX_PROXY_POOL_CURSOR_FILE:-$BASE_DIR/run/proxy-pool-cursor.idx}"
FALLBACK_PERSIST_MAP="${OCX_PROXY_FALLBACK_PERSIST_MAP:-1}"
FALLBACK_MAX_ATTEMPTS="${OCX_PROXY_FALLBACK_MAX_ATTEMPTS:-6}"
FALLBACK_BACKOFF_SECONDS="${OCX_PROXY_FALLBACK_BACKOFF_SECONDS:-2}"
AUDIT_SCRIPT="${OCX_ACCOUNT_PROXY_AUDIT_SCRIPT:-$BASE_DIR/scripts/audit_account_proxy_binding.sh}"

if [[ -z "$PROFILE_ID" ]]; then
  echo "usage: $0 <profileId> [auth.json path]" >&2
  exit 2
fi
if [[ "$PROFILE_ID" != ${PROVIDER}:* ]]; then
  echo "profileId must start with ${PROVIDER}:" >&2
  exit 2
fi

if [[ ! -x "$BASE_DIR/scripts/check_socks5_proxy_clean.sh" ]]; then
  echo "missing: $BASE_DIR/scripts/check_socks5_proxy_clean.sh" >&2
  exit 2
fi
if [[ ! -x "$BASE_DIR/scripts/onboard_openai_codex_profile.sh" ]]; then
  echo "missing: $BASE_DIR/scripts/onboard_openai_codex_profile.sh" >&2
  exit 2
fi

lookup_proxy(){
  local profile="$1"
  local p=""
  if [[ -f "$PROXY_MAP_FILE" ]]; then
    p="$(awk -F= -v k="$profile" '$1==k{print substr($0,index($0,$2))}' "$PROXY_MAP_FILE" | tail -n1)"
  fi
  echo "$p"
}

upsert_map(){
  local profile="$1" proxy="$2"
  mkdir -p "$(dirname "$PROXY_MAP_FILE")"
  [[ -f "$PROXY_MAP_FILE" ]] || touch "$PROXY_MAP_FILE"
  if grep -q "^${profile}=" "$PROXY_MAP_FILE"; then
    sed -i "s#^${profile}=.*#${profile}=${proxy}#" "$PROXY_MAP_FILE"
  else
    echo "${profile}=${proxy}" >> "$PROXY_MAP_FILE"
  fi
}

next_fallback_proxy(){
  local candidates=()

  if [[ -f "$PROXY_POOL_FILE" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" && ! "$line" =~ ^# ]] || continue
      candidates+=("$line")
    done < "$PROXY_POOL_FILE"
  fi

  # pool 为空时，退化到 map 里其它账号的代理（去重）
  if (( ${#candidates[@]} == 0 )) && [[ -f "$PROXY_MAP_FILE" ]]; then
    while IFS='=' read -r k v; do
      [[ "$k" == "${PROVIDER}:"* && -n "$v" ]] || continue
      candidates+=("$v")
    done < "$PROXY_MAP_FILE"
  fi

  (( ${#candidates[@]} > 0 )) || return 1

  mapfile -t _pool < <(printf '%s\n' "${candidates[@]}" | awk 'NF && $1 !~ /^#/' | awk '!seen[$0]++')
  local n="${#_pool[@]}"
  (( n > 0 )) || return 1

  mkdir -p "$(dirname "$FALLBACK_CURSOR_FILE")"
  local idx=0
  if [[ -f "$FALLBACK_CURSOR_FILE" ]]; then
    idx="$(cat "$FALLBACK_CURSOR_FILE" 2>/dev/null || echo 0)"
  fi
  [[ "$idx" =~ ^[0-9]+$ ]] || idx=0
  idx=$(( idx % n ))

  local proxy="${_pool[$idx]}"
  local next=$(( (idx + 1) % n ))
  echo "$next" > "$FALLBACK_CURSOR_FILE"
  echo "$proxy"
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

audit_binding(){
  local event="$1" proxy_raw="$2" proxy_norm="$3" ip="$4" status="$5" reason="$6"
  if [[ -x "$AUDIT_SCRIPT" ]]; then
    "$AUDIT_SCRIPT" "$event" "$PROFILE_ID" "$proxy_raw" "$proxy_norm" "$ip" "$status" "$reason" >/dev/null 2>&1 || true
  fi
}

if [[ "$USE_PROXY_LOGIN" != "1" ]]; then
  if [[ "$FORCE_LOGOUT" == "1" ]]; then
    codex logout >/dev/null 2>&1 || true
  fi
  echo "proxy login disabled (OCX_USE_PROXY_LOGIN=$USE_PROXY_LOGIN), starting direct login for $PROFILE_ID"
  audit_binding "login_start" "" "" "" "info" "direct_login"
  codex -c cli_auth_credentials_store='file' login --device-auth
else
  proxy_raw="$(lookup_proxy "$PROFILE_ID")"
  if [[ -z "$proxy_raw" ]]; then
    echo "no proxy configured for $PROFILE_ID (map: $PROXY_MAP_FILE)" >&2
    exit 1
  fi

  proxy=""
  if ! proxy="$(normalize_proxy "$proxy_raw")"; then
    echo "unsupported proxy format for $PROFILE_ID: $proxy_raw" >&2
    echo "use socks5://..., http://... or hostname:port:username:password" >&2
    exit 1
  fi

  audit_binding "login_start" "$proxy_raw" "$proxy" "" "info" "proxy_login"
  primary_check_out=""
  if ! primary_check_out="$("$BASE_DIR/scripts/check_socks5_proxy_clean.sh" "$PROFILE_ID" "$proxy" 2>&1)"; then
    echo "$primary_check_out" >&2
    if [[ "$AUTO_FALLBACK" == "1" ]]; then
      [[ "$FALLBACK_MAX_ATTEMPTS" =~ ^[0-9]+$ ]] || FALLBACK_MAX_ATTEMPTS=6
      [[ "$FALLBACK_BACKOFF_SECONDS" =~ ^[0-9]+$ ]] || FALLBACK_BACKOFF_SECONDS=2

      success=0
      attempt=1
      while (( attempt <= FALLBACK_MAX_ATTEMPTS )); do
        fb_raw="$(next_fallback_proxy || true)"
        if [[ -z "$fb_raw" ]]; then
          break
        fi

        fb_proxy="$(normalize_proxy "$fb_raw" 2>/dev/null || true)"
        if [[ -z "$fb_proxy" ]]; then
          echo "fallback proxy format invalid: $fb_raw" >&2
          audit_binding "proxy_fallback" "$proxy_raw" "$fb_raw" "" "warn" "fallback_proxy_format_invalid"
          attempt=$((attempt+1))
          continue
        fi

        if [[ "$fb_proxy" == "$proxy" ]]; then
          attempt=$((attempt+1))
          continue
        fi

        echo "primary proxy rejected, fallback attempt ${attempt}/${FALLBACK_MAX_ATTEMPTS} for $PROFILE_ID"
        fb_out=""
        if fb_out="$("$BASE_DIR/scripts/check_socks5_proxy_clean.sh" "$PROFILE_ID" "$fb_proxy" 2>&1)"; then
          echo "$fb_out"
          proxy="$fb_proxy"
          success=1
          audit_binding "proxy_fallback" "$proxy_raw" "$fb_proxy" "" "info" "fallback_selected"
          if [[ "$FALLBACK_PERSIST_MAP" == "1" ]]; then
            upsert_map "$PROFILE_ID" "$fb_raw"
            echo "fallback proxy persisted to map for $PROFILE_ID"
          fi
          break
        else
          echo "$fb_out" >&2
          audit_binding "proxy_fallback" "$proxy_raw" "$fb_proxy" "" "warn" "fallback_attempt_${attempt}_failed"
          sleep "$((FALLBACK_BACKOFF_SECONDS * attempt))"
        fi

        attempt=$((attempt+1))
      done

      if [[ "$success" != "1" ]]; then
        echo "proxy rejected and fallback attempts exhausted" >&2
        audit_binding "login_fail" "$proxy_raw" "$proxy" "" "fail" "fallback_exhausted"
        exit 1
      fi
    else
      audit_binding "login_fail" "$proxy_raw" "$proxy" "" "fail" "proxy_check_failed"
      exit 1
    fi
  else
    echo "$primary_check_out"
  fi

  if [[ "$FORCE_LOGOUT" == "1" ]]; then
    codex logout >/dev/null 2>&1 || true
  fi

  echo "starting codex login via proxy for $PROFILE_ID"
  ALL_PROXY="$proxy" HTTPS_PROXY="$proxy" HTTP_PROXY="$proxy" \
    codex -c cli_auth_credentials_store='file' login --device-auth
fi

if [[ ! -f "$AUTH_JSON_PATH" ]]; then
  echo "auth file not found after login: $AUTH_JSON_PATH" >&2
  exit 1
fi

"$BASE_DIR/scripts/onboard_openai_codex_profile.sh" "$PROFILE_ID" "$AUTH_JSON_PATH"
audit_binding "login_success" "${proxy_raw:-}" "${proxy:-}" "" "pass" "onboard_ok"
echo "proxy login + onboard done: $PROFILE_ID"
