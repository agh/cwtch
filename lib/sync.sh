#!/bin/bash
# Source synchronization for cwtch.
# shellcheck disable=SC2154

repo_to_url() {
  local repo="$1"
  # Already a URL or local path
  [[ "${repo}" == *"://"* ]] && { echo "${repo}"; return; }
  [[ "${repo}" == /* ]] && { echo "${repo}"; return; }
  [[ "${repo}" == git@* ]] && { echo "${repo}"; return; }
  # GitHub shorthand
  echo "https://github.com/${repo}.git"
}

repo_local_path() {
  local repo="$1"
  # For local paths, use basename
  if [[ "${repo}" == /* ]]; then
    echo "${SOURCES_DIR}/$(basename "${repo}" .git)"
  else
    # For remote repos, convert slashes to dashes
    echo "${SOURCES_DIR}/${repo//\//-}"
  fi
}

sync_repo() {
  local repo="$1" ref="${2:-main}" path url
  path="$(repo_local_path "${repo}")"
  url="$(repo_to_url "${repo}")"

  mkdir -p "${SOURCES_DIR}"
  if [[ -d "${path}/.git" ]]; then
    log "Updating ${repo}..." >&2
    git -C "${path}" fetch origin "${ref}" --quiet 2>/dev/null || { err "Failed to fetch ${repo}"; return 1; }
    git -C "${path}" checkout "${ref}" --quiet 2>/dev/null || true
    git -C "${path}" reset --hard "origin/${ref}" --quiet 2>/dev/null || true
  else
    log "Cloning ${repo}..." >&2
    git clone --branch "${ref}" --depth 1 --quiet "${url}" "${path}" 2>/dev/null || { err "Failed to clone ${repo}"; return 1; }
  fi
  echo "${path}"
}

link_namespace() {
  local src="$1" dest="$2" namespace="$3"
  [[ -d "${src}" ]] || return 0

  local target="${dest}/${namespace}"
  rm -rf "${target}"
  mkdir -p "${dest}"
  ln -sf "${src}" "${target}"

  find "${src}" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' '
}

merge_mcp() {
  local mcp_file="$1" settings_file="$2"
  [[ -f "${mcp_file}" ]] || return 0

  if [[ -f "${settings_file}" ]]; then
    jq -s '.[0] * {mcpServers: ((.[0].mcpServers // {}) * (.[1].mcpServers // .[1] // {}))}' \
      "${settings_file}" "${mcp_file}" > "${settings_file}.tmp" && mv "${settings_file}.tmp" "${settings_file}"
  else
    # If mcp_file has mcpServers key, wrap it; otherwise use as-is
    if jq -e '.mcpServers' "${mcp_file}" >/dev/null 2>&1; then
      cp "${mcp_file}" "${settings_file}"
    else
      jq '{mcpServers: .}' "${mcp_file}" > "${settings_file}"
    fi
  fi
}

sync_init() {
  if [[ -f "${CWTCHFILE}" ]]; then
    err "Cwtchfile already exists at ${CWTCHFILE}"; return 1
  fi
  mkdir -p "${CWTCH_DIR}"
  cat > "${CWTCHFILE}" << 'EOF'
# Cwtchfile - Configure your Claude Code environment
# See: https://github.com/agh/cwtch

# Base settings (optional)
# settings: owner/repo:path/to/settings.json

# Global CLAUDE.md (optional)
# claude_md: owner/repo:path/to/CLAUDE.md

# Sources to sync
sources:
  - repo: owner/repo
    ref: main
    commands: commands/
    agents: agents/
    as: default
EOF
  log "Created ${CWTCHFILE}"
  log "Edit with: cwtch edit"
}

do_sync() {
  config_validate || return 1

  local settings_ref claude_md_ref
  settings_ref="$(config_get settings)"
  claude_md_ref="$(config_get claude_md)"

  mkdir -p "${CLAUDE_DIR}"

  # Sync base settings
  if [[ -n "${settings_ref}" ]]; then
    local repo="${settings_ref%%:*}" file="${settings_ref#*:}" path
    path="$(sync_repo "${repo}")" || return 1
    [[ -f "${path}/${file}" ]] || { err "Settings file not found: ${path}/${file}"; return 1; }
    cp "${path}/${file}" "${CLAUDE_DIR}/settings.json"
    log "Applied base settings from ${repo}"
  fi

  # Sync base CLAUDE.md
  if [[ -n "${claude_md_ref}" ]]; then
    local repo="${claude_md_ref%%:*}" file="${claude_md_ref#*:}" path
    path="$(sync_repo "${repo}")" || return 1
    [[ -f "${path}/${file}" ]] || { err "CLAUDE.md not found: ${path}/${file}"; return 1; }
    ln -sf "${path}/${file}" "${CLAUDE_DIR}/CLAUDE.md"
    log "Linked CLAUDE.md from ${repo}"
  fi

  # Sync sources
  local idx
  for idx in $(config_source_indices); do
    local repo ref namespace commands agents hooks mcp path
    repo="$(config_source_get "${idx}" repo)"
    ref="$(config_source_get "${idx}" ref)"
    namespace="$(config_source_get "${idx}" as)"
    commands="$(config_source_get "${idx}" commands)"
    agents="$(config_source_get "${idx}" agents)"
    hooks="$(config_source_get "${idx}" hooks)"
    mcp="$(config_source_get "${idx}" mcp)"

    [[ -z "${repo}" ]] && continue
    path="$(sync_repo "${repo}" "${ref:-main}")" || continue

    local cmd_count=0 agent_count=0 hook_count=0
    if [[ -n "${namespace}" ]]; then
      [[ -n "${commands}" ]] && cmd_count="$(link_namespace "${path}/${commands}" "${CLAUDE_DIR}/commands" "${namespace}")"
      [[ -n "${agents}" ]] && agent_count="$(link_namespace "${path}/${agents}" "${CLAUDE_DIR}/agents" "${namespace}")"
      [[ -n "${hooks}" ]] && hook_count="$(link_namespace "${path}/${hooks}" "${CLAUDE_DIR}/hooks" "${namespace}")"
    fi
    [[ -n "${mcp}" ]] && merge_mcp "${path}/${mcp}" "${CLAUDE_DIR}/settings.json"

    local summary="${repo}"
    [[ -n "${namespace}" ]] && summary="${summary} → ${namespace}/"
    [[ ${cmd_count} -gt 0 ]] && summary="${summary} (${cmd_count} commands)"
    [[ ${agent_count} -gt 0 ]] && summary="${summary} (${agent_count} agents)"
    [[ ${hook_count} -gt 0 ]] && summary="${summary} (${hook_count} hooks)"
    log "${summary}"
  done

  log "Sync complete."
}
