#!/bin/bash
# Cwtchfile parsing and validation for cwtch.
# shellcheck disable=SC2154

# Helpers owned by lib/common.sh. Defined here only while they are missing so
# that this work package stands alone; the integrator drops this block.
if ! declare -F validate_name >/dev/null; then
  validate_name() {
    local name="${1:-}"
    if [[ "${name}" == "." ]] || [[ "${name}" == ".." ]] ||
      ! [[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
      err "Invalid name '${name}' (use letters, digits, '.', '_', '-'; max 64)"
      return 1
    fi
  }
fi
[[ -n "${CLAUDE_DIR:-}" ]] || CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
[[ -n "${CLAUDE_JSON:-}" ]] || CLAUDE_JSON="${CLAUDE_CONFIG_DIR:-${HOME}}/.claude.json"

# Print a note that may contain user-controlled text (never echo -e).
cwtch_note() { printf '%b%s%b\n' "${C_DIM}" "$*" "${C_RESET}"; }

config_exists() { [[ -f "${CWTCHFILE}" ]]; }

config_get() {
  { yq -r ".$1 // \"\"" "${CWTCHFILE}" 2>/dev/null || true; } | head -1
}

config_source_count() {
  local count
  count="$(yq -r '.sources | length' "${CWTCHFILE}" 2>/dev/null | head -1)" || true
  if [[ "${count}" =~ ^[0-9]+$ ]]; then printf '%s\n' "${count}"; else printf '0\n'; fi
}

config_source_get() {
  { yq -r ".sources[$1].$2 // \"\"" "${CWTCHFILE}" 2>/dev/null || true; } | head -1
}

config_source_indices() {
  local count
  count="$(config_source_count)"
  if [[ "${count}" -gt 0 ]]; then seq 0 $((count - 1)); fi
}

# 'repo:path' splits on the last colon so that ssh and https repos keep theirs.
config_ref_repo() { printf '%s\n' "${1%:*}"; }
config_ref_path() { printf '%s\n' "${1##*:}"; }

config_valid_ref() {
  # A leading dash would be read as a git option; check-ref-format has no '--'.
  [[ "$1" != -* ]] && git check-ref-format --allow-onelevel "$1" >/dev/null 2>&1
}

config_validate_ref_field() {
  local key="$1" value="$2" repo path
  [[ -n "${value}" ]] || return 0
  repo="$(config_ref_repo "${value}")"
  path="$(config_ref_path "${value}")"
  if [[ "${value}" != *:* ]] || [[ -z "${repo}" ]] || [[ -z "${path}" ]]; then
    err "Cwtchfile: '${key}' must be in format 'repo:path' (both parts non-empty)"
    return 1
  fi
}

config_validate_source() {
  local idx="$1" errors=0 repo ref as skills commands agents hooks
  repo="$(config_source_get "${idx}" repo)"
  ref="$(config_source_get "${idx}" ref)"
  as="$(config_source_get "${idx}" as)"
  skills="$(config_source_get "${idx}" skills)"
  commands="$(config_source_get "${idx}" commands)"
  agents="$(config_source_get "${idx}" agents)"
  hooks="$(config_source_get "${idx}" hooks)"

  if [[ -z "${repo}" ]]; then
    err "Cwtchfile: source[${idx}] missing required 'repo'"
    return 1
  fi
  if [[ "${repo}" == "owner/repo" ]]; then
    err "Cwtchfile: source[${idx}]: replace the 'owner/repo' placeholder from 'cwtch sync init'"
    errors=$((errors + 1))
  elif [[ "${repo}" != */* ]]; then
    err "Cwtchfile: source[${idx}] invalid repo format '${repo}'"
    errors=$((errors + 1))
  fi
  if [[ -n "${hooks}" ]]; then
    err "Cwtchfile: source[${idx}]: hooks: is not supported (register hooks in settings.json; see docs/configuration.md)"
    errors=$((errors + 1))
  fi
  if [[ -n "${skills}${commands}${agents}" ]] && [[ -z "${as}" ]]; then
    err "Cwtchfile: source[${idx}] (${repo}) requires 'as' when skills/commands/agents specified"
    errors=$((errors + 1))
  fi
  if [[ -n "${as}" ]] && ! validate_name "${as}"; then
    errors=$((errors + 1))
  fi
  if [[ -n "${ref}" ]] && ! config_valid_ref "${ref}"; then
    err "Cwtchfile: source[${idx}] invalid ref '${ref}'"
    errors=$((errors + 1))
  fi
  [[ ${errors} -eq 0 ]]
}

config_validate() {
  local errors=0 idx sources_type duplicates settings claude_md

  if ! config_exists; then
    err "Cwtchfile not found at ${CWTCHFILE}"
    return 1
  fi
  if ! yq '.' "${CWTCHFILE}" >/dev/null 2>&1; then
    err "Cwtchfile is not valid YAML"
    return 1
  fi

  sources_type="$(yq -r '.sources | type' "${CWTCHFILE}" 2>/dev/null | head -1)" || true
  case "${sources_type}" in
    '!!seq' | '!!null' | 'null' | '') ;;
    *)
      err "Cwtchfile: 'sources' must be a list"
      return 1
      ;;
  esac

  settings="$(config_get settings)"
  claude_md="$(config_get claude_md)"
  config_validate_ref_field settings "${settings}" || errors=$((errors + 1))
  config_validate_ref_field claude_md "${claude_md}" || errors=$((errors + 1))

  for idx in $(config_source_indices); do
    config_validate_source "${idx}" || errors=$((errors + 1))
  done

  duplicates="$(yq -r '.sources[].as // ""' "${CWTCHFILE}" 2>/dev/null | grep -v '^$' | sort | uniq -d)" || true
  if [[ -n "${duplicates}" ]]; then
    err "Cwtchfile: duplicate namespace(s): ${duplicates}"
    errors=$((errors + 1))
  fi

  [[ ${errors} -eq 0 ]]
}

config_check_targets() {
  local settings="$1" claude_md="$2" target
  target="${CLAUDE_DIR}/settings.json"
  if [[ -n "${settings}" ]] && [[ -f "${target}" ]]; then
    cwtch_note "  warning: ${target} exists; sync merges into it and keeps a .bak"
  fi
  target="${CLAUDE_DIR}/CLAUDE.md"
  if [[ -n "${claude_md}" ]] && [[ -e "${target}" ]] && [[ ! -L "${target}" ]]; then
    cwtch_note "  warning: ${target} exists and is not a symlink; sync needs --force"
  fi
}

config_check() {
  printf 'Checking %s...\n' "${CWTCHFILE}"

  if ! config_exists; then
    err "Not found: ${CWTCHFILE}"
    return 1
  fi
  if ! yq '.' "${CWTCHFILE}" >/dev/null 2>&1; then
    err "Invalid YAML syntax"
    return 1
  fi

  local settings claude_md idx repo as count
  settings="$(config_get settings)"
  claude_md="$(config_get claude_md)"
  count="$(config_source_count)"

  printf '  settings:  %s\n' "${settings:-"(none)"}"
  printf '  claude_md: %s\n' "${claude_md:-"(none)"}"
  printf '  sources:   %s\n' "${count}"

  for idx in $(config_source_indices); do
    repo="$(config_source_get "${idx}" repo)"
    as="$(config_source_get "${idx}" as)"
    printf '    [%s] %s %s %s\n' "${idx}" "${repo}" "${SYM_ARROW}" "${as:-"(no namespace)"}"
  done

  config_check_targets "${settings}" "${claude_md}"
  config_validate && log "Cwtchfile is valid"
}
