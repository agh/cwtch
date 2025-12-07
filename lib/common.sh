#!/bin/bash
# Shared functions for cwtch.
# shellcheck disable=SC2034

readonly CLAUDE_DIR="${HOME}/.claude"
readonly CWTCH_DIR="${HOME}/.cwtch"
readonly ACCOUNTS_DIR="${CWTCH_DIR}/profiles"
readonly CURRENT_FILE="${CWTCH_DIR}/.current"
readonly KEYCHAIN_SVC="Claude Code-credentials"
readonly USAGE_API="https://api.anthropic.com/api/oauth/usage"

err() { echo "[ERROR] $*" >&2; }
log() { echo "[cwtch] $*"; }

is_apikey_profile() { [[ -f "${ACCOUNTS_DIR}/$1/.apikey" ]]; }

get_cred() { security find-generic-password -s "${KEYCHAIN_SVC}" -w 2>/dev/null || true; }

save_cred() { echo "$1" > "$2/.credential"; chmod 600 "$2/.credential"; }

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
  mkdir -p "${ACCOUNTS_DIR}"
  local current="" found=0
  [[ -f "${CURRENT_FILE}" ]] && current="$(cat "${CURRENT_FILE}")"
  for dir in "${ACCOUNTS_DIR}"/*/; do
    [[ -d "${dir}" ]] || continue; found=1
    local name="${dir%/}"; name="${name##*/}"
    local type="oauth"; is_apikey_profile "${name}" && type="api-key"
    local marker="  "; [[ "${name}" == "${current}" ]] && marker="* "
    echo "${marker}${name} (${type})$( [[ "${name}" == "${current}" ]] && echo " active" )"
  done
  [[ ${found} -eq 0 ]] && echo "No profiles saved."; return 0
}

profile_save() {
  local name="$1" target="${ACCOUNTS_DIR}/${1}" cred
  mkdir -p "${ACCOUNTS_DIR}"
  [[ -d "${CLAUDE_DIR}" ]] || { err "No Claude session at ${CLAUDE_DIR}"; exit 1; }
  cred="$(get_cred)"; [[ -z "${cred}" ]] && { err "No credential in keychain"; exit 1; }
  rm -rf "${target}"; cp -r "${CLAUDE_DIR}" "${target}"
  save_cred "${cred}" "${target}"; echo "${name}" > "${CURRENT_FILE}"; log "Saved '${name}' (oauth)"
}

profile_save_key() {
  local name="$1" key="$2" target="${ACCOUNTS_DIR}/${1}"
  mkdir -p "${target}"
  echo "${key}" > "${target}/.apikey"; chmod 600 "${target}/.apikey"
  echo "${name}" > "${CURRENT_FILE}"; log "Saved '${name}' (api-key)"
}

profile_use() {
  local name="$1" source="${ACCOUNTS_DIR}/${1}"
  [[ -d "${source}" ]] || { err "Profile '${name}' not found"; exit 1; }
  if is_apikey_profile "${name}"; then
    echo "${name}" > "${CURRENT_FILE}"; log "Switched to '${name}' (api-key)"
    log "Configure Claude Code: apiKeyHelper = \"cwtch api-key\""
  else
    lsof +D "${CLAUDE_DIR}" &>/dev/null && { err "Claude is running. Exit first."; exit 1; }
    restore_cred "${source}"; rm -rf "${CLAUDE_DIR}"; cp -r "${source}" "${CLAUDE_DIR}"
    rm -f "${CLAUDE_DIR}/.credential"; echo "${name}" > "${CURRENT_FILE}"; log "Switched to '${name}' (oauth)"
  fi
}

profile_delete() {
  local name="$1" target="${ACCOUNTS_DIR}/${1}" cur
  [[ -d "${target}" ]] || { err "Profile '${name}' not found"; exit 1; }
  rm -rf "${target}"
  [[ -f "${CURRENT_FILE}" ]] && cur="$(cat "${CURRENT_FILE}")" && [[ "${cur}" == "${name}" ]] && rm -f "${CURRENT_FILE}"
  log "Deleted '${name}'"
}

get_current_apikey() {
  local name keyfile
  [[ -f "${CURRENT_FILE}" ]] && name="$(cat "${CURRENT_FILE}")" || return 1
  keyfile="${ACCOUNTS_DIR}/${name}/.apikey"
  if [[ -f "${keyfile}" ]]; then cat "${keyfile}"; else return 1; fi
}
