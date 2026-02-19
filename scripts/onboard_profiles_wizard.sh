#!/usr/bin/env bash
set -euo pipefail

# Beginner-friendly wizard for adding OpenClaw failover accounts.
# Supports proxy map editing + clean check + device-code login + onboarding.

DEFAULT_ENV_FILE="/etc/openclaw-healthcheck.env"
if [[ -f "$DEFAULT_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DEFAULT_ENV_FILE"
fi

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
MAP_FILE="${OCX_SOCKS5_MAP_FILE:-$BASE_DIR/config/openai-codex-socks5-map.env}"
CHECK_SCRIPT="$BASE_DIR/scripts/check_socks5_proxy_clean.sh"
LOGIN_SCRIPT="$BASE_DIR/scripts/login_openai_codex_profile_via_proxy.sh"
AUTH_PATH_DEFAULT="${OCX_CODEX_AUTH_PATH:-/root/.codex/auth.json}"

choose_proxy_mode() {
  say "这次是否使用代理登录？(y/n，默认 y)"
  read -r use_proxy
  use_proxy="${use_proxy:-y}"
  if [[ "$use_proxy" == "y" || "$use_proxy" == "Y" ]]; then
    export OCX_USE_PROXY_LOGIN=1
    echo "已设置：使用代理登录"
  else
    export OCX_USE_PROXY_LOGIN=0
    echo "已设置：不使用代理登录（直连）"
  fi
}

mkdir -p "$(dirname "$MAP_FILE")"
[[ -f "$MAP_FILE" ]] || touch "$MAP_FILE"

say() { echo -e "\n$*"; }

list_current() {
  say "=== 当前已导入的容灾账号 ==="
  openclaw models status --json | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const j=JSON.parse(d);const ps=(j.auth?.oauth?.profiles||[]).filter(p=>p.provider==="openai-codex").map(p=>p.profileId);console.log(ps.length?ps.join("\n"):"(空)");});'
  say "=== 代理映射（前30条）==="
  awk -F= '/^openai-codex:/{print $1"="$2}' "$MAP_FILE" | head -n 30 || true
}

upsert_map() {
  local profile="$1" proxy="$2"
  if grep -q "^${profile}=" "$MAP_FILE"; then
    sed -i "s#^${profile}=.*#${profile}=${proxy}#" "$MAP_FILE"
  else
    echo "${profile}=${proxy}" >> "$MAP_FILE"
  fi
}

add_or_update_mapping() {
  say "请输入账号 profile（例如 openai-codex:acc04）"
  read -r profile
  [[ -n "$profile" ]] || { echo "profile 不能为空"; return; }

  say "请输入代理（支持两种格式）"
  say "1) hostname:port:username:password"
  say "2) socks5h://user:pass@host:port 或 http://user:pass@host:port"
  read -r proxy
  [[ -n "$proxy" ]] || { echo "proxy 不能为空"; return; }

  upsert_map "$profile" "$proxy"
  echo "已保存映射: $profile"
}

test_one_proxy() {
  say "输入要测试的 profile（例如 openai-codex:acc04）"
  read -r profile
  [[ -n "$profile" ]] || { echo "profile 不能为空"; return; }
  "$CHECK_SCRIPT" "$profile"
}

onboard_one() {
  choose_proxy_mode
  say "输入要登录并导入的 profile（例如 openai-codex:acc04）"
  read -r profile
  [[ -n "$profile" ]] || { echo "profile 不能为空"; return; }

  say "auth.json 路径（直接回车使用默认: $AUTH_PATH_DEFAULT）"
  read -r auth_path
  auth_path="${auth_path:-$AUTH_PATH_DEFAULT}"

  "$LOGIN_SCRIPT" "$profile" "$auth_path"
  say "完成：$profile 已导入"
}

quick_add_and_onboard() {
  choose_proxy_mode
  say "输入 profile（例如 openai-codex:acc04）"
  read -r profile
  [[ -n "$profile" ]] || { echo "profile 不能为空"; return; }

  say "输入代理（hostname:port:username:password 或 URL 格式）"
  read -r proxy
  [[ -n "$proxy" ]] || { echo "proxy 不能为空"; return; }

  upsert_map "$profile" "$proxy"
  "$CHECK_SCRIPT" "$profile"
  "$LOGIN_SCRIPT" "$profile" "$AUTH_PATH_DEFAULT"
  say "完成：$profile 已配置并导入"
}

batch_onboard() {
  choose_proxy_mode
  say "输入起始编号（例如 4 表示 acc04）"
  read -r start
  say "输入结束编号（例如 10 表示 acc10）"
  read -r end

  if ! [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]]; then
    echo "编号必须是数字"; return
  fi
  if (( end < start )); then
    echo "结束编号不能小于起始编号"; return
  fi

  say "是否开启失败继续？(y/n，默认 y)"
  read -r cont
  cont="${cont:-y}"

  ok=0
  fail=0
  failed_list=""

  for i in $(seq "$start" "$end"); do
    profile=$(printf "openai-codex:acc%02d" "$i")
    say "---- 处理 $profile ----"

    if ! grep -q "^${profile}=" "$MAP_FILE"; then
      echo "跳过：$profile 未在映射文件中配置代理"
      fail=$((fail+1))
      failed_list+="$profile (no-map)\n"
      [[ "$cont" == "y" || "$cont" == "Y" ]] || return 1
      continue
    fi

    if ! "$CHECK_SCRIPT" "$profile"; then
      echo "失败：$profile 代理检测未通过"
      fail=$((fail+1))
      failed_list+="$profile (proxy-check-fail)\n"
      [[ "$cont" == "y" || "$cont" == "Y" ]] || return 1
      continue
    fi

    if ! "$LOGIN_SCRIPT" "$profile" "$AUTH_PATH_DEFAULT"; then
      echo "失败：$profile 登录/导入失败"
      fail=$((fail+1))
      failed_list+="$profile (login-or-import-fail)\n"
      [[ "$cont" == "y" || "$cont" == "Y" ]] || return 1
      continue
    fi

    ok=$((ok+1))
    echo "成功：$profile"
  done

  say "批量导入完成：成功 $ok，失败 $fail"
  if (( fail > 0 )); then
    echo -e "失败清单:\n$failed_list"
  fi
}

while true; do
  say "============================"
  echo "OpenClaw 容灾账号配置向导"
  echo "1) 查看当前账号与映射"
  echo "2) 添加/更新代理映射"
  echo "3) 测试某个 profile 的代理是否干净"
  echo "4) 通过代理登录并导入一个账号"
  echo "5) 一步完成（添加映射+测试+导入）"
  echo "6) 批量导入（accXX 区间）"
  echo "0) 退出"
  read -r -p "请选择: " c

  case "$c" in
    1) list_current ;;
    2) add_or_update_mapping ;;
    3) test_one_proxy ;;
    4) onboard_one ;;
    5) quick_add_and_onboard ;;
    6) batch_onboard ;;
    0) echo "已退出"; exit 0 ;;
    *) echo "无效选项" ;;
  esac
done