#!/bin/bash
# Shared functions for cwtch.
# shellcheck disable=SC2034

# Colors - respect NO_COLOR and detect TTY
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ "${TERM:-}" != "dumb" ]]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_YELLOW='\033[33m'
  C_BLUE='\033[34m'
  C_CYAN='\033[36m'
  C_WHITE='\033[37m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_WHITE=''
fi

# Symbols
SYM_CHECK="✓"
SYM_CROSS="✗"
SYM_ARROW="→"
SYM_DOT="•"
SYM_STAR="★"

readonly CLAUDE_DIR="${HOME}/.claude"
readonly CWTCH_DIR="${HOME}/.cwtch"
readonly PROFILES_DIR="${CWTCH_DIR}/profiles"
readonly SOURCES_DIR="${CWTCH_DIR}/sources"
readonly CWTCHFILE="${CWTCH_DIR}/Cwtchfile"
readonly CURRENT_FILE="${CWTCH_DIR}/.current"
readonly KEYCHAIN_SVC="Claude Code-credentials"
readonly USAGE_API="https://api.anthropic.com/api/oauth/usage"

err() { echo -e "${C_RED}${SYM_CROSS}${C_RESET} $*" >&2; }
log() { echo -e "${C_GREEN}${SYM_CHECK}${C_RESET} $*"; }
info() { echo -e "${C_CYAN}${SYM_DOT}${C_RESET} $*"; }
header() { echo -e "\n${C_BOLD}${C_WHITE}$*${C_RESET}"; }
dim() { echo -e "${C_DIM}$*${C_RESET}"; }

is_apikey_profile() { [[ -f "${PROFILES_DIR}/$1/.apikey" ]]; }

get_cred() { security find-generic-password -s "${KEYCHAIN_SVC}" -w 2>/dev/null || true; }

restore_cred() {
  local f="$1/.credential" cred
  [[ -f "${f}" ]] || { err "No saved credential for this profile"; return 1; }
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
  curl -sf "${USAGE_API}" \
    -H "Accept: application/json" \
    -H "User-Agent: claude-code/2.0.32" \
    -H "Authorization: Bearer $1" \
    -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null
}

format_usage() {
  jq -r '
    def fmt: if . then (. | tostring | .[0:16] | sub("T"; " ")) + " UTC" else "N/A" end;
    "5h: \(.five_hour.utilization // 0 | floor)% (resets \(.five_hour.resets_at | fmt))",
    "7d: \(.seven_day.utilization // 0 | floor)% (resets \(.seven_day.resets_at | fmt))"
  ' 2>/dev/null
}

profile_list() {
  mkdir -p "${PROFILES_DIR}"
  local current="" found=0
  [[ -f "${CURRENT_FILE}" ]] && current="$(cat "${CURRENT_FILE}")"
  for dir in "${PROFILES_DIR}"/*/; do
    [[ -d "${dir}" ]] || continue; found=1
    local name="${dir%/}"; name="${name##*/}"
    local type="oauth"; is_apikey_profile "${name}" && type="api-key"
    if [[ "${name}" == "${current}" ]]; then
      echo -e "  ${C_GREEN}${SYM_STAR}${C_RESET} ${C_BOLD}${name}${C_RESET} ${C_DIM}(${type})${C_RESET} ${C_GREEN}active${C_RESET}"
    else
      echo -e "    ${name} ${C_DIM}(${type})${C_RESET}"
    fi
  done
  [[ ${found} -eq 0 ]] && dim "  No profiles saved."; return 0
}

profile_save() {
  local name="$1" target="${PROFILES_DIR}/${1}" cred
  mkdir -p "${PROFILES_DIR}"
  cred="$(get_cred)"; [[ -z "${cred}" ]] && { err "No credential in keychain"; return 1; }
  mkdir -p "${target}"
  echo "${cred}" > "${target}/.credential"; chmod 600 "${target}/.credential"
  echo "${name}" > "${CURRENT_FILE}"; log "Saved credential for '${name}'"
}

profile_save_key() {
  local name="$1" key="$2" target="${PROFILES_DIR}/${1}"
  mkdir -p "${target}"
  echo "${key}" > "${target}/.apikey"; chmod 600 "${target}/.apikey"
  echo "${name}" > "${CURRENT_FILE}"; log "Saved '${name}' (api-key)"
}

profile_use() {
  local name="$1" source="${PROFILES_DIR}/${1}"
  [[ -d "${source}" ]] || { err "Profile '${name}' not found"; return 1; }
  if is_apikey_profile "${name}"; then
    echo "${name}" > "${CURRENT_FILE}"; log "Switched to '${name}' (api-key)"
  else
    [[ -f "${source}/.credential" ]] || { err "No credential for '${name}'"; return 1; }
    restore_cred "${source}"
    echo "${name}" > "${CURRENT_FILE}"; log "Switched to '${name}' (oauth)"
  fi
}

profile_delete() {
  local name="$1" target="${PROFILES_DIR}/${1}" cur
  [[ -d "${target}" ]] || { err "Profile '${name}' not found"; return 1; }
  rm -rf "${target}"
  [[ -f "${CURRENT_FILE}" ]] && cur="$(cat "${CURRENT_FILE}")" && [[ "${cur}" == "${name}" ]] && rm -f "${CURRENT_FILE}"
  log "Deleted '${name}'"
}

get_current_apikey() {
  local name keyfile
  [[ -f "${CURRENT_FILE}" ]] && name="$(cat "${CURRENT_FILE}")" || return 1
  keyfile="${PROFILES_DIR}/${name}/.apikey"
  if [[ -f "${keyfile}" ]]; then cat "${keyfile}"; else return 1; fi
}
