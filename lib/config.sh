#!/bin/bash
# Cwtchfile parsing and validation for cwtch.
# shellcheck disable=SC2154

config_exists() { [[ -f "${CWTCHFILE}" ]]; }

config_get() {
  local key="$1"
  yq -r ".${key} // empty" "${CWTCHFILE}" 2>/dev/null
}

config_source_count() {
  local count
  count="$(yq -r '.sources | length' "${CWTCHFILE}" 2>/dev/null | head -1)"
  # Ensure we return a number
  [[ "${count}" =~ ^[0-9]+$ ]] && echo "${count}" || echo 0
}

config_source_get() {
  local idx="$1" field="$2"
  yq -r ".sources[${idx}].${field} // empty" "${CWTCHFILE}" 2>/dev/null | head -1
}

config_source_indices() {
  local count
  count="$(config_source_count)"
  if [[ "${count}" =~ ^[0-9]+$ ]] && [[ "${count}" -gt 0 ]]; then
    seq 0 $((count - 1))
  fi
}

config_profile_overlay() {
  local profile="${1:-}"
  [[ -z "${profile}" || "${profile}" == "(none)" ]] && return
  local overlay="${PROFILES_DIR}/${profile}/Cwtchfile"
  [[ -f "${overlay}" ]] && echo "${overlay}"
}

config_validate() {
  local errors=0

  if ! config_exists; then
    err "Cwtchfile not found at ${CWTCHFILE}"; return 1
  fi

  if ! yq '.' "${CWTCHFILE}" >/dev/null 2>&1; then
    err "Cwtchfile is not valid YAML"; return 1
  fi

  local sources_type; sources_type="$(yq -r '.sources | type' "${CWTCHFILE}" 2>/dev/null)"
  if [[ "${sources_type}" != "!!seq" ]] && [[ "${sources_type}" != "null" ]]; then
    err "Cwtchfile: 'sources' must be a list"; ((errors++))
  fi

  local settings; settings="$(config_get settings)"
  if [[ -n "${settings}" ]] && [[ "${settings}" != *":"* ]]; then
    err "Cwtchfile: 'settings' must be in format 'repo:path'"; ((errors++))
  fi

  local claude_md; claude_md="$(config_get claude_md)"
  if [[ -n "${claude_md}" ]] && [[ "${claude_md}" != *":"* ]]; then
    err "Cwtchfile: 'claude_md' must be in format 'repo:path'"; ((errors++))
  fi

  local idx
  for idx in $(config_source_indices); do
    local repo as commands agents hooks
    repo="$(config_source_get "${idx}" repo)"
    as="$(config_source_get "${idx}" as)"
    commands="$(config_source_get "${idx}" commands)"
    agents="$(config_source_get "${idx}" agents)"
    hooks="$(config_source_get "${idx}" hooks)"

    if [[ -z "${repo}" ]]; then
      err "Cwtchfile: source[${idx}] missing required 'repo'"; ((errors++)); continue
    fi

    if [[ -n "${commands}" || -n "${agents}" || -n "${hooks}" ]] && [[ -z "${as}" ]]; then
      err "Cwtchfile: source[${idx}] (${repo}) requires 'as' when commands/agents/hooks specified"
      ((errors++))
    fi

    if [[ "${repo}" != *"/"* ]]; then
      err "Cwtchfile: source[${idx}] invalid repo format '${repo}'"; ((errors++))
    fi
  done

  local namespaces duplicates
  namespaces="$(yq -r '.sources[].as // empty' "${CWTCHFILE}" 2>/dev/null | grep -v '^$' | sort)"
  duplicates="$(echo "${namespaces}" | uniq -d)"
  if [[ -n "${duplicates}" ]]; then
    err "Cwtchfile: duplicate namespace(s): ${duplicates}"; ((errors++))
  fi

  [[ ${errors} -eq 0 ]]
}

config_check() {
  echo "Checking ${CWTCHFILE}..."

  if ! config_exists; then
    err "Not found: ${CWTCHFILE}"; return 1
  fi

  if ! yq '.' "${CWTCHFILE}" >/dev/null 2>&1; then
    err "Invalid YAML syntax"; return 1
  fi

  local settings claude_md source_count
  settings="$(config_get settings)"
  claude_md="$(config_get claude_md)"
  source_count="$(config_source_count)"

  echo "  settings:  ${settings:-"(none)"}"
  echo "  claude_md: ${claude_md:-"(none)"}"
  echo "  sources:   ${source_count}"

  local idx
  for idx in $(config_source_indices); do
    local repo as; repo="$(config_source_get "${idx}" repo)"; as="$(config_source_get "${idx}" as)"
    echo "    [${idx}] ${repo} → ${as:-"(no namespace)"}"
  done

  config_validate && log "Cwtchfile is valid"
}
