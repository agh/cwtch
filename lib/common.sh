#!/bin/bash
# Shared functions for Claude utilities.
# shellcheck disable=SC2034

readonly CLAUDE_DIR="${HOME}/.claude"
readonly ACCOUNTS_DIR="${HOME}/.claude-accounts"
readonly CURRENT_FILE="${ACCOUNTS_DIR}/.current"
readonly KEYCHAIN_SVC="Claude Code-credentials"
readonly USAGE_API="https://api.anthropic.com/api/oauth/usage"

err() { echo "[ERROR] $*" >&2; }
log() { echo "[claude-switch] $*"; }

get_cred() {
  security find-generic-password -s "${KEYCHAIN_SVC}" -w 2>/dev/null || true
}

save_cred() {
  echo "$1" > "$2/.credential"
  chmod 600 "$2/.credential"
}

restore_cred() {
  local f="$1/.credential" cred
  [[ -f "${f}" ]] || { err "No saved credential for this account"; return 1; }
  cred="$(cat "${f}")"
  security delete-generic-password -s "${KEYCHAIN_SVC}" &>/dev/null || true
  security add-generic-password -s "${KEYCHAIN_SVC}" -a "${USER}" -w "${cred}"
}

get_token() {
  local cred_file="$1"
  [[ -f "${cred_file}" ]] || return 1
  jq -r '.claudeAiOauth.accessToken' "${cred_file}" 2>/dev/null
}

fetch_usage() {
  local token="$1"
  curl -sf "${USAGE_API}" \
    -H "Accept: application/json" \
    -H "User-Agent: claude-code/2.0.32" \
    -H "Authorization: Bearer ${token}" \
    -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null
}

format_usage() {
  jq -r '
    def fmt: if . then (. | tostring | .[0:16] | sub("T"; " ")) + " UTC" else "N/A" end;
    "5h: \(.five_hour.utilization // 0 | floor)% (resets \(.five_hour.resets_at | fmt))",
    "7d: \(.seven_day.utilization // 0 | floor)% (resets \(.seven_day.resets_at | fmt))"
  ' 2>/dev/null
}
