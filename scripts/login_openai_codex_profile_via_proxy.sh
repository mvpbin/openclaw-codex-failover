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

next_fallback_proxy(){
  if [[ -f "$PROXY_POOL_FILE" ]]; then
    awk 'NF && $1 !~ /^#/{print; exit}' "$PROXY_POOL_FILE"
  fi
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

if [[ "$USE_PROXY_LOGIN" != "1" ]]; then
  if [[ "$FORCE_LOGOUT" == "1" ]]; then
    codex logout >/dev/null 2>&1 || true
  fi
  echo "proxy login disabled (OCX_USE_PROXY_LOGIN=$USE_PROXY_LOGIN), starting direct login for $PROFILE_ID"
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

  if ! "$BASE_DIR/scripts/check_socks5_proxy_clean.sh" "$PROFILE_ID" "$proxy"; then
    if [[ "$AUTO_FALLBACK" == "1" ]]; then
      fb_raw="$(next_fallback_proxy || true)"
      if [[ -n "$fb_raw" ]]; then
        if fb_proxy="$(normalize_proxy "$fb_raw" 2>/dev/null || true)"; then
          echo "primary proxy rejected, trying fallback pool proxy for $PROFILE_ID"
          "$BASE_DIR/scripts/check_socks5_proxy_clean.sh" "$PROFILE_ID" "$fb_proxy"
          proxy="$fb_proxy"
        else
          echo "fallback proxy format invalid: $fb_raw" >&2
          exit 1
        fi
      else
        echo "proxy rejected and no fallback proxy available" >&2
        exit 1
      fi
    else
      exit 1
    fi
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
echo "proxy login + onboard done: $PROFILE_ID"
