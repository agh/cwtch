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
readonly KEYCHAIN_OWNER_FILE="${CWTCH_DIR}/.keychain-owner"
readonly KEYCHAIN_SVC="Claude Code-credentials"
readonly KEYCHAIN_ACCT="${USER:-$(id -un)}"
readonly USAGE_API="https://api.anthropic.com/api/oauth/usage"
readonly NAME_RE='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
readonly TOKEN_RE='^sk-ant-oat01-[A-Za-z0-9_-]{20,}$'
readonly SETUP_TOKEN_LEN=108
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

# Write <name> to a temporary file beside <path> and print its path, so a
# caller can prove the write will succeed before changing anything else.
stage_profile_name() {
  local path="$1" name="$2" tmp
  validate_name "${name}" || return 1
  mkdir -p "${CWTCH_DIR}" || return 1
  if [[ -d "${path}" ]]; then
    err "Could not write ${path}: is a directory"
    return 1
  fi
  tmp="$(mktemp "${path}.XXXXXX")" || {
    err "Could not create a temporary file for ${path}"
    return 1
  }
  if ! printf '%s\n' "${name}" >"${tmp}"; then
    rm -f "${tmp}"
    err "Could not write ${path}"
    return 1
  fi
  printf '%s\n' "${tmp}"
}

write_profile_name() {
  local path="$1" tmp
  tmp="$(stage_profile_name "${path}" "$2")" || return 1
  mv -f "${tmp}" "${path}" || {
    rm -f "${tmp}"
    err "Could not write ${path}"
    return 1
  }
}

set_current() {
  local owner
  # Preserve the migration fallback before a non-OAuth selection hides it.
  if [[ ! -e "${KEYCHAIN_OWNER_FILE}" ]] && [[ ! -L "${KEYCHAIN_OWNER_FILE}" ]]; then
    owner="$(keychain_owner)" || owner=""
    [[ -z "${owner}" ]] || set_keychain_owner "${owner}" || return 1
  fi
  write_profile_name "${CURRENT_FILE}" "$1"
}
set_keychain_owner() { write_profile_name "${KEYCHAIN_OWNER_FILE}" "$1"; }

# 0 = owner printed, 1 = no owner, 2 = .keychain-owner exists but is unreadable or invalid.
keychain_owner() {
  local name
  if [[ -e "${KEYCHAIN_OWNER_FILE}" ]] || [[ -L "${KEYCHAIN_OWNER_FILE}" ]]; then
    name="$(cat "${KEYCHAIN_OWNER_FILE}" 2>/dev/null)" || return 2
    validate_name "${name}" 2>/dev/null || return 2
  else
    name="$(current_profile)" || return 1
    [[ "$(profile_type "${name}")" == "oauth" ]] || return 1
  fi
  printf '%s\n' "${name}"
}

# Write a secret file at mode 0600 from creation, keeping one .bak of the
# previous contents when they differ.
write_secret() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "${path}")" || return 1
  if [[ -d "${path}" ]]; then
    err "Could not write ${path}: is a directory"
    return 1
  fi
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

require_profile() {
  local name="$1"
  validate_name "${name}" || return 1
  [[ -d "${PROFILES_DIR}/${name}" ]] || {
    err "Profile '${name}' not found"
    return 1
  }
}

validate_expiry_date() {
  local value="$1" parsed=""
  if [[ "${value}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    parsed="$(date -u -j -f '%Y-%m-%d' "${value}" '+%Y-%m-%d' 2>/dev/null)" ||
      parsed="$(date -u -d "${value}" '+%Y-%m-%d' 2>/dev/null)" || parsed=""
  fi
  if [[ -z "${parsed}" ]] || [[ "${parsed}" != "${value}" ]]; then
    err "Invalid expiry date '${value}'; use a real calendar date in YYYY-MM-DD format"
    return 1
  fi
}

date_after_days() {
  local day="$1" days="$2" result
  result="$(date -u -j -v+"${days}"d -f '%Y-%m-%d' "${day}" '+%Y-%m-%d' 2>/dev/null)" ||
    result="$(date -u -d "${day} +${days} days" '+%Y-%m-%d' 2>/dev/null)" || {
    err "Could not calculate a UTC expiry date"
    return 1
  }
  printf '%s\n' "${result}"
}

write_profile_metadata() {
  local name="$1" type="$2" source="$3" expires="${4:-}" basis="${5:-}"
  local created metadata
  created="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" || {
    err "Could not read the UTC creation time for '${name}'"
    return 1
  }
  if [[ "${source}" == "setup" ]]; then
    expires="$(date_after_days "${created%%T*}" 365)" || return 1
    basis="estimated"
  fi
  metadata="$(jq -n --arg type "${type}" --arg created "${created}" \
    --arg source "${source}" --arg expires "${expires}" --arg basis "${basis}" \
    '{type: $type, created: $created, source: $source,
      expires: (if $expires == "" then null else $expires end),
      expires_basis: (if $basis == "" then null else $basis end)}')" || {
    err "Could not build metadata for '${name}'"
    return 1
  }
  write_secret "${PROFILES_DIR}/${name}/meta.json" "${metadata}" || {
    err "Could not write metadata for '${name}'"
    return 1
  }
}

# Metadata is advisory: a failure must not leave a half-saved credential, so it
# only warns once the credential itself is safely written.
save_profile_metadata() {
  write_profile_metadata "$@" 2>/dev/null ||
    warn "Could not write metadata for '$1'; its expiry will show as unknown"
  return 0
}

read_token_metadata() {
  jq -se '
    if length == 1 and (.[0] | type == "object" and .type == "token" and
      (.created == null or
        (.created | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))) and
      (.source == "setup" or .source == "import") and
      ((.expires == null and .expires_basis == null) or
        ((.expires | type == "string") and
          (.expires_basis == "estimated" or .expires_basis == "explicit"))))
    then .[0] else error("invalid token metadata") end
  ' "${PROFILES_DIR}/$1/meta.json" 2>/dev/null
}

# Missing metadata is normal for profiles saved before 6.1.
token_expiry() {
  local name="$1" path="${PROFILES_DIR}/$1/meta.json" metadata expires basis
  [[ -e "${path}" ]] || [[ -L "${path}" ]] || return 0
  # Only a regular file is read: a FIFO or device here would block jq.
  if [[ ! -f "${path}" ]] || ! metadata="$(read_token_metadata "${name}")"; then
    warn "Invalid metadata for '${name}'; expiry unknown"
    return 0
  fi
  expires="$(printf '%s' "${metadata}" | jq -r '.expires // empty')"
  [[ -n "${expires}" ]] || return 0
  if ! validate_expiry_date "${expires}" 2>/dev/null; then
    warn "Invalid metadata for '${name}'; expiry unknown"
    return 0
  fi
  basis="$(printf '%s' "${metadata}" | jq -r '.expires_basis')"
  printf '%s %s\n' "${expires}" "${basis}"
}

token_expiry_label() {
  local expiry
  expiry="$(token_expiry "$1")"
  if [[ -z "${expiry}" ]]; then
    printf '%s\n' "expiry unknown"
  elif [[ "${expiry#* }" == "estimated" ]]; then
    printf 'expires ~%s (estimated)\n' "${expiry% *}"
  else
    printf 'expires %s\n' "${expiry% *}"
  fi
}

warn_token_expiry() {
  local name="$1" expiry expires today threshold estimated=""
  expiry="$(token_expiry "${name}")"
  [[ -n "${expiry}" ]] || return 0
  expires="${expiry% *}"
  [[ "${expiry#* }" == "estimated" ]] && estimated=" (estimated)"
  if ! today="$(date -u '+%Y-%m-%d')" ||
    ! threshold="$(date_after_days "${today}" 30)"; then
    warn "Could not check token expiry for '${name}'"
    return 0
  fi
  if [[ "${expires}" < "${today}" ]]; then
    warn "Token for '${name}' expired on ${expires}${estimated}; run 'cwtch profile setup ${name}'"
  elif [[ "${expires}" < "${threshold}" ]] || [[ "${expires}" == "${threshold}" ]]; then
    warn "Token for '${name}' expires on ${expires}${estimated} (within 30 days); run 'cwtch profile setup ${name}'"
  fi
  return 0
}

profile_expires() {
  local name="$1" expires="$2" metadata
  require_profile "${name}" || return 1
  [[ "$(profile_type "${name}")" == "token" ]] || {
    err "Profile '${name}' is not a token profile"
    return 1
  }
  validate_expiry_date "${expires}" || return 1
  if [[ -e "${PROFILES_DIR}/${name}/meta.json" ]] || [[ -L "${PROFILES_DIR}/${name}/meta.json" ]]; then
    metadata="$(read_token_metadata "${name}")" || {
      err "Invalid metadata for '${name}'; save the token again before setting its expiry"
      return 1
    }
    metadata="$(printf '%s' "${metadata}" | jq --arg expires "${expires}" \
      '.expires = $expires | .expires_basis = "explicit"')" || return 1
    write_secret "${PROFILES_DIR}/${name}/meta.json" "${metadata}" || {
      err "Could not write metadata for '${name}'"
      return 1
    }
  else
    # Saved before 6.1: when the token was issued is unknown, so record no date.
    metadata="$(jq -n --arg expires "${expires}" \
      '{type: "token", created: null, source: "import",
        expires: $expires, expires_basis: "explicit"}')" || return 1
    write_secret "${PROFILES_DIR}/${name}/meta.json" "${metadata}" || {
      err "Could not write metadata for '${name}'"
      return 1
    }
  fi
  log "Set expiry for '${name}' to ${expires}"
}

get_cred() { security find-generic-password -s "${KEYCHAIN_SVC}" -a "${KEYCHAIN_ACCT}" -w 2>/dev/null || true; }

# Longest command line 'security -i' reads intact; Claude Code uses the same
# limit and falls back to argv beyond it.
readonly SECURITY_STDIN_MAX=4032

# Replace the Keychain item in place; no delete step, so a failure leaves the
# existing login untouched.
set_cred() {
  local hex command service="${KEYCHAIN_SVC}" account="${KEYCHAIN_ACCT}"
  hex="$(printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n')" || return 1
  service="${service//\\/\\\\}"
  service="${service//\"/\\\"}"
  account="${account//\\/\\\\}"
  account="${account//\"/\\\"}"
  command="$(printf 'add-generic-password -U -s "%s" -a "%s" -X "%s"' \
    "${service}" "${account}" "${hex}")"
  if [[ ${#command} -le ${SECURITY_STDIN_MAX} ]]; then
    printf '%s\n' "${command}" | security -i >/dev/null 2>&1
  else
    # Too long for one interactive line; a truncated line would store a corrupt item.
    security add-generic-password -U -s "${KEYCHAIN_SVC}" -a "${KEYCHAIN_ACCT}" -X "${hex}" >/dev/null 2>&1
  fi
}

is_oauth_json() {
  printf '%s' "$1" | jq -se '
    length == 1 and (.[0] | type == "object" and
      (.claudeAiOauth | type == "object" and
        (.accessToken | type == "string" and length > 0)))
  ' >/dev/null 2>&1
}

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
  printf 'Authorization: Bearer %s\n' "$1" | curl -sf --max-time 10 "${USAGE_API}" \
    -H "Accept: application/json" \
    -H "User-Agent: claude-code/2.0.32" \
    -H @- \
    -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null
}

profile_list() {
  mkdir -p "${PROFILES_DIR}"
  local current found=0 dir name type expiry
  current="$(current_profile)" || current=""
  for dir in "${PROFILES_DIR}"/*/; do
    [[ -d "${dir}" ]] || continue
    found=1
    name="${dir%/}"
    name="${name##*/}"
    type="$(profile_type "${name}")"
    expiry=""
    [[ "${type}" != "token" ]] || expiry=" $(token_expiry_label "${name}")"
    if [[ "${name}" == "${current}" ]]; then
      printf '%b%s%b%s\n' "  ${C_GREEN}${SYM_STAR}${C_RESET} ${C_BOLD}" "${name}" \
        "${C_RESET} ${C_DIM}(${type})${C_RESET} ${C_GREEN}active${C_RESET}" "${expiry}"
    else
      printf '    %s%b%s\n' "${name}" " ${C_DIM}(${type})${C_RESET}" "${expiry}"
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
  is_oauth_json "${cred}" || {
    err "Keychain credential is not valid OAuth JSON; not saved"
    return 1
  }
  write_secret "${target}/.credential" "${cred}" || {
    err "Could not write credential for '${name}'"
    return 1
  }
  save_profile_metadata "${name}" oauth import
  prune_other_creds "${name}" .credential
  set_keychain_owner "${name}" || return 1
  set_current "${name}" || return 1
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
  save_profile_metadata "${name}" api-key import
  prune_other_creds "${name}" .apikey
  set_current "${name}" || return 1
  log "Saved '${name}' (api-key)"
}

profile_save_token() {
  local name="$1" token="$2" source="${3:-import}" expires="${4:-}" basis="" target
  validate_name "${name}" || return 1
  if [[ -n "${expires}" ]]; then
    validate_expiry_date "${expires}" || return 1
    basis="explicit"
  fi
  [[ "${token}" =~ ${TOKEN_RE} ]] || {
    err "Credential has an unexpected format; not saved"
    return 1
  }
  target="${PROFILES_DIR}/${name}"
  write_secret "${target}/.token" "${token}" || {
    err "Could not write token for '${name}'"
    return 1
  }
  save_profile_metadata "${name}" token "${source}" "${expires}" "${basis}"
  prune_other_creds "${name}" .token
  set_current "${name}" || return 1
  log "Saved '${name}' (token)"
}

# Snapshot the live Keychain credential into the outgoing OAuth profile before
# switching: Claude Code refreshes that credential in place.
snapshot_outgoing_cred() {
  local owner live rc=0
  owner="$(keychain_owner)" || rc=$?
  if [[ ${rc} -eq 2 ]]; then
    err "Cannot read ${KEYCHAIN_OWNER_FILE}; fix or remove it before switching OAuth profiles"
    return 1
  fi
  [[ ${rc} -eq 0 ]] || return 0
  [[ "$(profile_type "${owner}")" == "oauth" ]] || return 0
  live="$(get_cred)"
  [[ -n "${live}" ]] || return 0
  is_oauth_json "${live}" || return 0
  write_secret "${PROFILES_DIR}/${owner}/.credential" "${live}" || {
    err "Could not snapshot the Keychain credential into '${owner}'; switch aborted"
    return 1
  }
}

profile_use_oauth() {
  local name="$1" cred previous owner_tmp
  keychain_config_warning
  cred="$(cat "${PROFILES_DIR}/${name}/.credential")"
  is_oauth_json "${cred}" || {
    err "Credential for '${name}' is not valid OAuth JSON; nothing changed"
    return 1
  }
  snapshot_outgoing_cred || return 1
  # A snapshot may have refreshed this very profile.
  cred="$(cat "${PROFILES_DIR}/${name}/.credential")" || return 1
  previous="$(get_cred)"
  # The owner record must follow the Keychain exactly, or a later snapshot
  # would file one account's login under another; stage it before the switch.
  owner_tmp="$(stage_profile_name "${KEYCHAIN_OWNER_FILE}" "${name}")" || {
    err "Could not record the Keychain owner; nothing changed"
    return 1
  }
  set_cred "${cred}" || {
    rm -f "${owner_tmp}"
    err "Keychain update failed; nothing changed"
    return 1
  }
  if ! mv -f "${owner_tmp}" "${KEYCHAIN_OWNER_FILE}"; then
    rm -f "${owner_tmp}"
    if [[ -n "${previous}" ]] && set_cred "${previous}"; then
      err "Could not record the Keychain owner; restored the previous login"
    else
      err "Could not record the Keychain owner; the Keychain now holds '${name}'"
    fi
    return 1
  fi
  set_current "${name}" || return 1
  log "Switched to '${name}' (oauth)"
  if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]] || [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    warn "CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY is set in this shell and overrides the Keychain login"
    # shellcheck disable=SC2016 # printed for the calling shell to evaluate
    dim '  Apply to this shell: cwtch_env="$(cwtch profile env)" && eval "${cwtch_env}"' >&2
  fi
}

profile_use() {
  local name="$1" type
  require_profile "${name}" || return 1
  type="$(profile_type "${name}")"
  case "${type}" in
    token | api-key)
      [[ "${type}" != "token" ]] || warn_token_expiry "${name}"
      set_current "${name}" || return 1
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
  local name="$1" target real expected current owner
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
  owner="$(keychain_owner)" || owner=""
  rm -rf "${target}"
  current="$(current_profile 2>/dev/null)" || current=""
  [[ "${current}" == "${name}" ]] && rm -f "${CURRENT_FILE}"
  [[ "${owner}" == "${name}" ]] && rm -f "${KEYCHAIN_OWNER_FILE}"
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
