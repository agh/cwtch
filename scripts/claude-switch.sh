#!/bin/bash
# Switch between Claude Code accounts.
set -euo pipefail

readonly CLAUDE_DIR="${HOME}/.claude"
readonly ACCOUNTS_DIR="${HOME}/.claude-accounts"
readonly CURRENT_FILE="${ACCOUNTS_DIR}/.current"
readonly KEYCHAIN_SVC="Claude Code-credentials"

err() { echo "[ERROR] $*" >&2; }
log() { echo "[claude-switch] $*"; }

get_cred() { security find-generic-password -s "${KEYCHAIN_SVC}" -w 2>/dev/null || true; }

save_cred() {
  echo "$1" > "$2/.credential"
  chmod 600 "$2/.credential"
}

restore_cred() {
  local f="$1/.credential" cred
  [[ -f "${f}" ]] || { err "No saved credential for this account"; exit 1; }
  cred="$(cat "${f}")"
  security delete-generic-password -s "${KEYCHAIN_SVC}" &>/dev/null || true
  security add-generic-password -s "${KEYCHAIN_SVC}" -a "${USER}" -w "${cred}"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  list         List all saved accounts
  current      Show current active account
  use <name>   Switch to account <name>
  save <name>  Save current session as <name>
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
    save)   [[ $# -lt 1 ]] && { err "Missing name"; exit 1; }; save_account "$1" ;;
    use)    [[ $# -lt 1 ]] && { err "Missing name"; exit 1; }; use_account "$1" ;;
    delete) [[ $# -lt 1 ]] && { err "Missing name"; exit 1; }; delete_account "$1" ;;
    -h|--help) usage ;;
    *) err "Unknown: ${cmd}"; usage; exit 1 ;;
  esac
}

main "$@"
