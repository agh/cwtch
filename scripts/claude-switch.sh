#!/bin/bash
# Switch between Claude Code accounts.
# shellcheck disable=SC2154
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  list          List all saved accounts
  current       Show current active account
  status        Show usage for all accounts
  use <name>    Switch to account <name>
  save <name>   Save current session as <name>
  delete <name> Delete saved account <name>
EOF
}

list_accounts() {
  mkdir -p "${ACCOUNTS_DIR}"
  local current=""; [[ -f "${CURRENT_FILE}" ]] && current="$(cat "${CURRENT_FILE}")"
  local found=0
  for dir in "${ACCOUNTS_DIR}"/*/; do
    [[ -d "${dir}" ]] || continue; found=1
    local name="${dir%/}"; name="${name##*/}"
    [[ "${name}" == "${current}" ]] && echo "* ${name} (active)" || echo "  ${name}"
  done
  [[ ${found} -eq 0 ]] && echo "No accounts saved."
  return 0
}

show_status() {
  mkdir -p "${ACCOUNTS_DIR}"
  local found=0
  for dir in "${ACCOUNTS_DIR}"/*/; do
    [[ -d "${dir}" ]] || continue; found=1
    local name="${dir%/}"; name="${name##*/}"
    local token; token="$(get_token "${dir}.credential")"
    echo "${name}:"
    if [[ -n "${token}" ]]; then
      fetch_usage "${token}" | format_usage | sed 's/^/  /'
    else
      echo "  (no credential)"
    fi
  done
  [[ ${found} -eq 0 ]] && echo "No accounts saved."
  return 0
}

save_account() {
  local name="$1" target="${ACCOUNTS_DIR}/${1}"
  mkdir -p "${ACCOUNTS_DIR}"
  [[ -d "${CLAUDE_DIR}" ]] || { err "No Claude session at ${CLAUDE_DIR}"; exit 1; }
  local cred; cred="$(get_cred)"
  [[ -z "${cred}" ]] && { err "No credential in keychain"; exit 1; }
  rm -rf "${target}"; cp -r "${CLAUDE_DIR}" "${target}"
  save_cred "${cred}" "${target}"
  echo "${name}" > "${CURRENT_FILE}"
  log "Saved '${name}'"
}

use_account() {
  local name="$1" source="${ACCOUNTS_DIR}/${1}"
  [[ -d "${source}" ]] || { err "Account '${name}' not found"; exit 1; }
  lsof +D "${CLAUDE_DIR}" &>/dev/null && { err "Claude is running. Exit first."; exit 1; }
  restore_cred "${source}"
  rm -rf "${CLAUDE_DIR}"; cp -r "${source}" "${CLAUDE_DIR}"
  rm -f "${CLAUDE_DIR}/.credential"
  echo "${name}" > "${CURRENT_FILE}"
  log "Switched to '${name}'"
}

delete_account() {
  local name="$1" target="${ACCOUNTS_DIR}/${1}" cur
  [[ -d "${target}" ]] || { err "Account '${name}' not found"; exit 1; }
  rm -rf "${target}"
  [[ -f "${CURRENT_FILE}" ]] && cur="$(cat "${CURRENT_FILE}")" && [[ "${cur}" == "${name}" ]] && rm -f "${CURRENT_FILE}"
  log "Deleted '${name}'"
}

main() {
  [[ $# -lt 1 ]] && { usage; exit 1; }
  local cmd="$1"; shift
  case "${cmd}" in
    list) list_accounts ;;
    current) [[ -f "${CURRENT_FILE}" ]] && cat "${CURRENT_FILE}" || echo "(none)" ;;
    status) show_status ;;
    save)   [[ $# -lt 1 ]] && { err "Missing name"; exit 1; }; save_account "$1" ;;
    use)    [[ $# -lt 1 ]] && { err "Missing name"; exit 1; }; use_account "$1" ;;
    delete) [[ $# -lt 1 ]] && { err "Missing name"; exit 1; }; delete_account "$1" ;;
    -h|--help) usage ;;
    *) err "Unknown: ${cmd}"; usage; exit 1 ;;
  esac
}

main "$@"
