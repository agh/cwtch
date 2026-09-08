#!/bin/bash
# Shared functions for cwtch.
# shellcheck disable=SC2034  # colours, symbols and globals are consumed by bin/cwtch

# Colours - respect NO_COLOR, TERM=dumb and non-TTY output.
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ "${TERM:-}" != "dumb" ]]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_YELLOW='\033[33m'
  C_CYAN='\033[36m'
  C_WHITE='\033[37m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_WHITE=''
fi

# Symbols
SYM_CHECK="✓"
SYM_CROSS="✗"
SYM_ARROW="→"
SYM_DOT="•"
SYM_STAR="★"

readonly CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
readonly CLAUDE_JSON="${CLAUDE_CONFIG_DIR:-${HOME}}/.claude.json"
readonly CWTCH_DIR="${HOME}/.cwtch"
readonly PROFILES_DIR="${CWTCH_DIR}/profiles"
readonly SOURCES_DIR="${CWTCH_DIR}/sources"
readonly CWTCHFILE="${CWTCH_DIR}/Cwtchfile"
readonly CURRENT_FILE="${CWTCH_DIR}/.current"
readonly KEYCHAIN_SVC="Claude Code-credentials"
readonly KEYCHAIN_ACCT="${USER:-$(id -un)}"
readonly USAGE_API="https://api.anthropic.com/api/oauth/usage"
readonly NAME_RE='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
readonly TOKEN_RE='^sk-ant-oat01-[A-Za-z0-9_-]{20,}$'
readonly APIKEY_RE='^[A-Za-z0-9_-]{20,}$'

# Output helpers. Untrusted text always goes through %s; only our own colour
# codes are expanded with %b.
err() { printf '%b %s\n' "${C_RED}${SYM_CROSS}${C_RESET}" "$*" >&2; }
warn() { printf '%b %s\n' "${C_YELLOW}!${C_RESET}" "$*" >&2; }
log() { printf '%b %s\n' "${C_GREEN}${SYM_CHECK}${C_RESET}" "$*"; }
info() { printf '%b %s\n' "${C_CYAN}${SYM_DOT}${C_RESET}" "$*"; }
header() { printf '\n%b%s%b\n' "${C_BOLD}${C_WHITE}" "$*" "${C_RESET}"; }
dim() { printf '%b%s%b\n' "${C_DIM}" "$*" "${C_RESET}"; }

# Names become path components, so they are restricted to a safe basename.
validate_name() {
  local name="${1:-}"
  if [[ "${name}" == "." ]] || [[ "${name}" == ".." ]] || ! [[ "${name}" =~ ${NAME_RE} ]]; then
    err "Invalid name '${name}' (use letters, digits, '.', '_', '-'; max 64)"
    return 1
  fi
}

current_profile() {
  local name
  [[ -f "${CURRENT_FILE}" ]] || return 1
  name="$(cat "${CURRENT_FILE}")"
  if validate_name "${name}" 2>/dev/null; then
    printf '%s\n' "${name}"
    return 0
  fi
  printf '%s\n' "Ignoring invalid .current" >&2
  return 1
}

set_current() {
  mkdir -p "${CWTCH_DIR}"
  printf '%s\n' "$1" >"${CURRENT_FILE}"
}

# Write a secret file at mode 0600 from creation, keeping one .bak of the
# previous contents when they differ.
write_secret() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "${path}")" || return 1
  if [[ -f "${path}" ]] && [[ "$(cat "${path}")" != "${content}" ]]; then
    (
      umask 077
      rm -f "${path}.bak" && cat "${path}" >"${path}.bak"
    ) || return 1
  fi
  (
    umask 077
    rm -f "${path}.tmp" && printf '%s\n' "${content}" >"${path}.tmp"
  ) || return 1
  mv -f "${path}.tmp" "${path}"
}

is_apikey_profile() { [[ -f "${PROFILES_DIR}/$1/.apikey" ]]; }
is_token_profile() { [[ -f "${PROFILES_DIR}/$1/.token" ]]; }

# oauth | token | api-key | mixed! | empty
profile_type() {
  local dir="${PROFILES_DIR}/$1" type="empty" count=0
  if [[ -f "${dir}/.credential" ]]; then
    type="oauth"
    count=$((count + 1))
  fi
  if [[ -f "${dir}/.token" ]]; then
    type="token"
    count=$((count + 1))
  fi
  if [[ -f "${dir}/.apikey" ]]; then
    type="api-key"
    count=$((count + 1))
  fi
  [[ ${count} -gt 1 ]] && type="mixed!"
  printf '%s\n' "${type}"
}

get_cred() { security find-generic-password -s "${KEYCHAIN_SVC}" -w 2>/dev/null || true; }

# Replace the Keychain item in place; no delete step, so a failure leaves the
# existing login untouched.
set_cred() {
  security add-generic-password -U -s "${KEYCHAIN_SVC}" -a "${KEYCHAIN_ACCT}" -w "$1" >/dev/null 2>&1
}

is_oauth_json() { printf '%s' "$1" | jq -e '.claudeAiOauth.accessToken' >/dev/null 2>&1; }

keychain_config_warning() {
  [[ -n "${CLAUDE_CONFIG_DIR:-}" ]] || return 0
  warn "CLAUDE_CONFIG_DIR is set: Claude Code keys its Keychain entry to that directory, so cwtch is using the default '${KEYCHAIN_SVC}' entry"
}

get_token() {
  local cred_file="$1" token
  [[ -f "${cred_file}" ]] || return 1
  token="$(jq -r '.claudeAiOauth.accessToken // empty' "${cred_file}" 2>/dev/null)" || return 1
  [[ -n "${token}" ]] || return 1
  printf '%s\n' "${token}"
}

fetch_usage() {
  curl -sf --max-time 10 "${USAGE_API}" \
    -H "Accept: application/json" \
    -H "User-Agent: claude-code/2.0.32" \
    -H "Authorization: Bearer $1" \
    -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null
}

profile_list() {
  mkdir -p "${PROFILES_DIR}"
  local current found=0 dir name type
  current="$(current_profile)" || current=""
  for dir in "${PROFILES_DIR}"/*/; do
    [[ -d "${dir}" ]] || continue
    found=1
    name="${dir%/}"
    name="${name##*/}"
    type="$(profile_type "${name}")"
    if [[ "${name}" == "${current}" ]]; then
      printf '%b%s%b\n' "  ${C_GREEN}${SYM_STAR}${C_RESET} ${C_BOLD}" "${name}" \
        "${C_RESET} ${C_DIM}(${type})${C_RESET} ${C_GREEN}active${C_RESET}"
    else
      printf '    %s%b\n' "${name}" " ${C_DIM}(${type})${C_RESET}"
    fi
  done
  [[ ${found} -eq 0 ]] && dim "  No profiles saved."
  return 0
}

# Drop the credential files of the other two profile types.
prune_other_creds() {
  local dir="${PROFILES_DIR}/$1" keep="$2" f
  for f in .credential .token .apikey; do
    [[ "${f}" == "${keep}" ]] && continue
    rm -f "${dir}/${f}"
  done
  return 0
}

profile_save() {
  local name="$1" target cred
  validate_name "${name}" || return 1
  target="${PROFILES_DIR}/${name}"
  keychain_config_warning
  cred="$(get_cred)"
  [[ -n "${cred}" ]] || {
    err "No credential in keychain"
    return 1
  }
  write_secret "${target}/.credential" "${cred}" || {
    err "Could not write credential for '${name}'"
    return 1
  }
  prune_other_creds "${name}" .credential
  set_current "${name}"
  log "Saved credential for '${name}'"
}

profile_save_key() {
  local name="$1" key="$2" target
  validate_name "${name}" || return 1
  [[ "${key}" =~ ${APIKEY_RE} ]] || {
    err "Credential has an unexpected format; not saved"
    return 1
  }
  target="${PROFILES_DIR}/${name}"
  write_secret "${target}/.apikey" "${key}" || {
    err "Could not write API key for '${name}'"
    return 1
  }
  prune_other_creds "${name}" .apikey
  set_current "${name}"
  log "Saved '${name}' (api-key)"
}

profile_save_token() {
  local name="$1" token="$2" target
  validate_name "${name}" || return 1
  [[ "${token}" =~ ${TOKEN_RE} ]] || {
    err "Credential has an unexpected format; not saved"
    return 1
  }
  target="${PROFILES_DIR}/${name}"
  write_secret "${target}/.token" "${token}" || {
    err "Could not write token for '${name}'"
    return 1
  }
  prune_other_creds "${name}" .token
  set_current "${name}"
  log "Saved '${name}' (token)"
}

# Snapshot the live Keychain credential into the outgoing OAuth profile before
# switching: Claude Code refreshes that credential in place.
snapshot_outgoing_cred() {
  local current live
  current="$(current_profile 2>/dev/null)" || return 0
  [[ -f "${PROFILES_DIR}/${current}/.credential" ]] || return 0
  live="$(get_cred)"
  [[ -n "${live}" ]] || return 0
  is_oauth_json "${live}" || return 0
  write_secret "${PROFILES_DIR}/${current}/.credential" "${live}" ||
    warn "Could not snapshot the current credential into '${current}'"
  return 0
}

profile_use_oauth() {
  local name="$1" cred
  keychain_config_warning
  snapshot_outgoing_cred
  cred="$(cat "${PROFILES_DIR}/${name}/.credential")"
  [[ -n "${cred}" ]] || {
    err "No credential for '${name}'"
    return 1
  }
  set_cred "${cred}" || {
    err "Keychain update failed; nothing changed"
    return 1
  }
  set_current "${name}"
  log "Switched to '${name}' (oauth)"
}

profile_use() {
  local name="$1" type
  validate_name "${name}" || return 1
  [[ -d "${PROFILES_DIR}/${name}" ]] || {
    err "Profile '${name}' not found"
    return 1
  }
  type="$(profile_type "${name}")"
  case "${type}" in
    token | api-key)
      set_current "${name}"
      log "Switched to '${name}' (${type})"
      printf '  Apply to this shell: %b\n' "${C_CYAN}eval \"\$(cwtch profile env)\"${C_RESET}"
      ;;
    oauth) profile_use_oauth "${name}" ;;
    'mixed!')
      err "Profile '${name}' holds more than one credential; save it again to fix it"
      return 1
      ;;
    *)
      err "No credential for '${name}'"
      return 1
      ;;
  esac
}

profile_delete() {
  local name="$1" target real expected current
  validate_name "${name}" || return 1
  target="${PROFILES_DIR}/${name}"
  [[ -d "${target}" ]] || {
    err "Profile '${name}' not found"
    return 1
  }
  real="$(cd "${target}" 2>/dev/null && pwd -P)" || real=""
  expected="$(cd "${PROFILES_DIR}" 2>/dev/null && pwd -P)/${name}" || expected=""
  if [[ -z "${real}" ]] || [[ "${real}" != "${expected}" ]]; then
    err "Refusing to delete '${name}': not a profile directory"
    return 1
  fi
  rm -rf "${target}"
  current="$(current_profile 2>/dev/null)" || current=""
  [[ "${current}" == "${name}" ]] && rm -f "${CURRENT_FILE}"
  log "Deleted '${name}'"
}

get_current_apikey() {
  local name
  name="$(current_profile)" || return 1
  [[ -f "${PROFILES_DIR}/${name}/.apikey" ]] || return 1
  cat "${PROFILES_DIR}/${name}/.apikey"
}

get_current_token() {
  local name
  name="$(current_profile)" || return 1
  [[ -f "${PROFILES_DIR}/${name}/.token" ]] || return 1
  cat "${PROFILES_DIR}/${name}/.token"
}
