#!/bin/bash
# Source synchronisation for cwtch.
# shellcheck disable=SC2154

LINKS_MANIFEST="${CWTCH_DIR}/state/links"
SYNC_FORCE=false
SYNC_DRY_RUN=false
SYNC_SKIPPED=false
SYNC_NEW_LINKS=""
SYNC_SEEN=""
SYNC_MISSING=""
SYNC_REPO_PATH=""
SYNC_COUNT=0

repo_to_url() {
  case "$1" in
    *://* | /* | git@*) printf '%s\n' "$1" ;;
    *) printf 'https://github.com/%s.git\n' "$1" ;;
  esac
}

repo_local_path() {
  local repo="$1" slug digest
  slug="$(printf '%s' "${repo}" | LC_ALL=C sed -e 's/[^A-Za-z0-9._-]/-/g' -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//')"
  [[ -n "${slug}" ]] || slug="source"
  if [[ "${repo}" == /* ]]; then
    # Local paths share basenames far too easily; key them by the full path.
    digest="$(printf '%s' "${repo}" | shasum -a 256 | cut -c1-8 || true)"
    slug="${slug}-${digest}"
  fi
  printf '%s\n' "${SOURCES_DIR}/${slug}"
}

sync_default_ref() {
  local url="$1" ref
  ref="$(git ls-remote --symref -- "${url}" HEAD 2>/dev/null |
    sed -n 's|^ref: refs/heads/\([^[:space:]]*\).*|\1|p' | head -1)" || true
  printf '%s\n' "${ref:-main}"
}

# Clone or update <repo> at <ref>; sets SYNC_REPO_PATH.
# 0 = ready, 1 = failed, 2 = dry run with nothing on disk yet.
sync_repo() {
  local repo="$1" ref="${2:-}" path url
  path="$(repo_local_path "${repo}")"
  url="$(repo_to_url "${repo}")"
  [[ -n "${ref}" ]] || ref="$(sync_default_ref "${url}")"
  SYNC_REPO_PATH="${path}"

  if printf '%s' "${SYNC_SEEN}" | grep -Fxq -e "${path} ${ref}"; then return 0; fi

  if [[ "${SYNC_DRY_RUN}" == true ]]; then
    if [[ -d "${path}/.git" ]]; then
      info "would update ${repo} (${ref})"
      SYNC_SEEN="${SYNC_SEEN}${path} ${ref}"$'\n'
      return 0
    fi
    if ! printf '%s' "${SYNC_MISSING}" | grep -Fxq -e "${path}"; then
      info "would clone ${repo} (${ref})"
      SYNC_MISSING="${SYNC_MISSING}${path}"$'\n'
    fi
    SYNC_SKIPPED=true
    return 2
  fi

  mkdir -p "${SOURCES_DIR}" || return 1
  if [[ -d "${path}/.git" ]]; then
    info "Updating ${repo}..."
    git -C "${path}" fetch --quiet --depth 1 origin -- "${ref}" ||
      {
        err "Failed to fetch '${ref}' from ${repo}"
        return 1
      }
    git -C "${path}" checkout --quiet -B "${ref}" FETCH_HEAD ||
      {
        err "Failed to check out '${ref}' of ${repo}"
        return 1
      }
    # Managed checkouts are disposable: drop any local edits to tracked files.
    git -C "${path}" reset --quiet --hard FETCH_HEAD ||
      {
        err "Failed to reset '${ref}' of ${repo}"
        return 1
      }
  else
    info "Cloning ${repo}..."
    git clone --quiet --depth 1 --branch "${ref}" -- "${url}" "${path}" ||
      {
        err "Failed to clone ${repo} (${ref})"
        return 1
      }
  fi
  SYNC_SEEN="${SYNC_SEEN}${path} ${ref}"$'\n'
}

sync_record() { SYNC_NEW_LINKS="${SYNC_NEW_LINKS}${1}"$'\n'; }

sync_owned_link() {
  # True when <path> is a symlink cwtch could have made, i.e. into SOURCES_DIR.
  local target
  [[ -L "$1" ]] || return 1
  target="$(readlink "$1")" || return 1
  case "${target}" in
    "${SOURCES_DIR}"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Create or replace a symlink. Anything else at the target is a failure.
sync_link() {
  local src="$1" target="$2"
  if [[ "${SYNC_DRY_RUN}" == true ]]; then
    if { [[ -e "${target}" ]] || [[ -L "${target}" ]]; } && [[ ! -L "${target}" ]]; then
      cwtch_note "    conflict: ${target} exists and is not a symlink"
    else
      cwtch_note "    would link ${target}"
    fi
    sync_record "${target}"
    return 0
  fi
  if [[ -e "${target}" ]] || [[ -L "${target}" ]]; then
    if [[ ! -L "${target}" ]]; then
      err "target exists and is not a symlink: ${target}"
      return 1
    fi
    rm -f "${target}" || return 1
  fi
  mkdir -p "$(dirname "${target}")" || return 1
  ln -s "${src}" "${target}" || return 1
  sync_record "${target}"
}

# A real directory holding a SKILL.md symlink (the commands/ conversion).
sync_skill_dir() {
  local dir="$1"
  if [[ -L "${dir}" ]]; then
    if ! sync_owned_link "${dir}"; then
      err "target exists and is not a symlink: ${dir}"
      return 1
    fi
    [[ "${SYNC_DRY_RUN}" == true ]] || rm -f "${dir}" || return 1
  elif [[ -e "${dir}" ]] && [[ ! -d "${dir}" ]]; then
    err "target exists and is not a symlink: ${dir}"
    return 1
  fi
  [[ "${SYNC_DRY_RUN}" == true ]] && return 0
  mkdir -p "${dir}"
}

sync_skills() {
  local dir="$1" ns="$2" entry name count=0
  SYNC_COUNT=0
  for entry in "${dir}"/*/; do
    [[ -f "${entry}SKILL.md" ]] || continue
    name="$(basename "${entry}")"
    if ! validate_name "${name}" 2>/dev/null; then
      cwtch_note "    skipping skill with an unusable name: ${name}"
      continue
    fi
    sync_link "${entry%/}" "${CLAUDE_DIR}/skills/${ns}-${name}" || return 1
    count=$((count + 1))
  done
  SYNC_COUNT=${count}
}

# Legacy flat commands become one skill each: skills/<as>-<name>/SKILL.md.
sync_commands() {
  local dir="$1" ns="$2" file name skill count=0
  SYNC_COUNT=0
  for file in "${dir}"/*.md; do
    [[ -f "${file}" ]] || continue
    name="$(basename "${file}" .md)"
    if ! validate_name "${name}" 2>/dev/null; then
      cwtch_note "    skipping command with an unusable name: ${name}"
      continue
    fi
    skill="${CLAUDE_DIR}/skills/${ns}-${name}"
    sync_skill_dir "${skill}" || return 1
    sync_link "${file}" "${skill}/SKILL.md" || return 1
    count=$((count + 1))
  done
  SYNC_COUNT=${count}
}

sync_agents() {
  local dir="$1" ns="$2"
  SYNC_COUNT=0
  sync_link "${dir}" "${CLAUDE_DIR}/agents/${ns}" || return 1
  SYNC_COUNT="$(find "${dir}" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ' || true)"
}

# Namespaced commands/ links are how cwtch < 6 worked; Claude Code ignores them.
sync_drop_legacy() {
  local legacy="${CLAUDE_DIR}/commands/$1"
  sync_owned_link "${legacy}" || return 0
  if [[ "${SYNC_DRY_RUN}" == true ]]; then
    cwtch_note "    would remove legacy link ${legacy}"
    return 0
  fi
  rm -f "${legacy}"
  rmdir "${CLAUDE_DIR}/commands" 2>/dev/null || true
  cwtch_note "    removed legacy link ${legacy}"
}

sync_write_json() {
  local target="$1" content="$2"
  mkdir -p "$(dirname "${target}")" || return 1
  printf '%s\n' "${content}" >"${target}.tmp" || return 1
  mv "${target}.tmp" "${target}"
}

# Base settings supply defaults; whatever is already in settings.json wins.
sync_settings() {
  local base="$1" target="${CLAUDE_DIR}/settings.json" merged existing
  if ! jq . "${base}" >/dev/null 2>&1; then
    err "Settings file is not valid JSON: ${base}"
    return 1
  fi
  if [[ -e "${target}" ]]; then
    if ! jq . "${target}" >/dev/null 2>&1; then
      err "${target} is not valid JSON; refusing to merge"
      return 1
    fi
    merged="$(jq -s '.[0] * .[1]' "${base}" "${target}")" || return 1
    existing="$(cat "${target}")"
    [[ "${merged}" == "${existing}" ]] && return 0
    if [[ "${SYNC_DRY_RUN}" == true ]]; then
      cwtch_note "    would merge settings into ${target} (backup ${target}.bak)"
      return 0
    fi
    cp "${target}" "${target}.bak" || return 1
  else
    merged="$(jq . "${base}")" || return 1
    if [[ "${SYNC_DRY_RUN}" == true ]]; then
      cwtch_note "    would create ${target}"
      return 0
    fi
  fi
  sync_write_json "${target}" "${merged}"
}

# User-scope MCP servers live in ~/.claude.json, never in settings.json.
sync_mcp() {
  local file="$1" target="${CLAUDE_JSON}" servers merged existing
  servers="$(jq -c 'if type == "object" and has("mcpServers") then .mcpServers else . end' "${file}" 2>/dev/null)" ||
    {
      err "MCP file is not valid JSON: ${file}"
      return 1
    }
  if ! printf '%s' "${servers}" | jq -e 'type == "object"' >/dev/null 2>&1; then
    err "MCP file must hold an object of servers: ${file}"
    return 1
  fi
  if [[ -e "${target}" ]]; then
    if ! jq . "${target}" >/dev/null 2>&1; then
      err "${target} is not valid JSON; refusing to merge MCP servers"
      return 1
    fi
    merged="$(jq --argjson new "${servers}" '.mcpServers = ((.mcpServers // {}) * $new)' "${target}")" || return 1
    existing="$(cat "${target}")"
    [[ "${merged}" == "${existing}" ]] && return 0
    if [[ "${SYNC_DRY_RUN}" == true ]]; then
      cwtch_note "    would merge MCP servers into ${target} (backup ${target}.bak)"
      return 0
    fi
    cp "${target}" "${target}.bak" || return 1
  else
    merged="$(jq -n --argjson new "${servers}" '{mcpServers: $new}')" || return 1
    if [[ "${SYNC_DRY_RUN}" == true ]]; then
      cwtch_note "    would create ${target} with the MCP servers"
      return 0
    fi
  fi
  sync_write_json "${target}" "${merged}"
}

sync_claude_md() {
  local src="$1" target="${CLAUDE_DIR}/CLAUDE.md"
  if [[ -f "${target}" ]] && [[ ! -L "${target}" ]]; then
    if [[ "${SYNC_FORCE}" != true ]]; then
      err "CLAUDE.md exists and is not a symlink; move it or run 'cwtch sync --force'"
      return 1
    fi
    if [[ "${SYNC_DRY_RUN}" == true ]]; then
      cwtch_note "    would replace ${target} with a symlink (backup ${target}.bak)"
      sync_record "${target}"
      return 0
    fi
    cp "${target}" "${target}.bak" && rm -f "${target}" || return 1
  fi
  sync_link "${src}" "${target}"
}

# Links from the last run that this run did not recreate and that still point
# into SOURCES_DIR belong to declarations the user has removed.
sync_prune_links() {
  local old parent
  [[ -f "${LINKS_MANIFEST}" ]] || return 0
  while IFS= read -r old; do
    [[ -n "${old}" ]] || continue
    if printf '%s' "${SYNC_NEW_LINKS}" | grep -Fxq -e "${old}"; then continue; fi
    sync_owned_link "${old}" || continue
    if [[ "${SYNC_DRY_RUN}" == true ]]; then
      cwtch_note "  would remove ${old}"
      continue
    fi
    rm -f "${old}"
    parent="$(dirname "${old}")"
    case "${parent}" in
      "${CLAUDE_DIR}"/*) rmdir "${parent}" 2>/dev/null || true ;;
      *) ;;
    esac
    cwtch_note "  removed ${old}"
  done <"${LINKS_MANIFEST}"
}

sync_write_manifest() {
  local keep_old="$1"
  mkdir -p "$(dirname "${LINKS_MANIFEST}")" || return 1
  {
    printf '%s' "${SYNC_NEW_LINKS}"
    [[ "${keep_old}" == true ]] && [[ -f "${LINKS_MANIFEST}" ]] && cat "${LINKS_MANIFEST}"
    true
  } | grep -v '^$' | sort -u >"${LINKS_MANIFEST}.tmp" || true
  mv "${LINKS_MANIFEST}.tmp" "${LINKS_MANIFEST}"
}

sync_tilde() {
  if [[ -n "${HOME:-}" ]]; then printf '%s\n' "${1/#${HOME}/~}"; else printf '%s\n' "$1"; fi
}

sync_init() {
  if [[ -f "${CWTCHFILE}" ]]; then
    err "Cwtchfile already exists at ${CWTCHFILE}"
    return 1
  fi
  mkdir -p "${CWTCH_DIR}"
  cat >"${CWTCHFILE}" <<'EOF'
# Cwtchfile - configure your Claude Code environment.
# See: https://github.com/agh/cwtch
#
# Base settings, deep-merged into ~/.claude/settings.json (your values win):
# settings: owner/repo:path/to/settings.json
#
# Global instructions, symlinked to ~/.claude/CLAUDE.md:
# claude_md: owner/repo:path/to/CLAUDE.md
#
# Sources to sync. Uncomment and edit - every line below is an example.
# sources:
#   - repo: owner/repo      # or https://..., git@..., /absolute/path
#     ref: main             # optional; defaults to the remote's HEAD branch
#     as: personal          # namespace: letters, digits, '.', '_', '-'
#     skills: skills/       # directories that each contain a SKILL.md
#     commands: commands/   # legacy *.md commands, linked as skills
#     agents: agents/       # agent definitions, linked as a directory
#     mcp: mcp.json         # MCP servers, merged into ~/.claude.json
EOF
  log "Created ${CWTCHFILE}"
  log "Edit with: cwtch edit"
}

sync_summary() {
  local repo="$1" ns="$2" parts="$3" summary="" mark="${C_GREEN}${SYM_CHECK}${C_RESET}"
  [[ -n "${parts}" ]] && summary=" ${C_DIM}(${parts})${C_RESET}"
  [[ "${SYNC_DRY_RUN}" == true ]] && mark="${C_CYAN}${SYM_DOT}${C_RESET}"
  if [[ -n "${ns}" ]]; then
    printf '  %b %s %b %b%s/%b%b\n' "${mark}" "${repo}" \
      "${C_CYAN}${SYM_ARROW}${C_RESET}" "${C_BOLD}" "${ns}" "${C_RESET}" "${summary}"
  else
    printf '  %b %s%b\n' "${mark}" "${repo}" "${summary}"
  fi
}

sync_one_source() {
  local idx="$1" repo ref ns skills commands agents mcp path parts="" rc=0
  repo="$(config_source_get "${idx}" repo)"
  ref="$(config_source_get "${idx}" ref)"
  ns="$(config_source_get "${idx}" as)"
  skills="$(config_source_get "${idx}" skills)"
  commands="$(config_source_get "${idx}" commands)"
  agents="$(config_source_get "${idx}" agents)"
  mcp="$(config_source_get "${idx}" mcp)"
  [[ -n "${repo}" ]] || return 0

  sync_repo "${repo}" "${ref}" || rc=$?
  [[ ${rc} -eq 2 ]] && return 0
  [[ ${rc} -eq 0 ]] || return 1
  path="${SYNC_REPO_PATH}"

  if [[ -n "${ns}" ]]; then
    sync_drop_legacy "${ns}"
    if [[ -n "${skills}" ]]; then
      [[ -d "${path}/${skills}" ]] || {
        err "skills directory not found: ${path}/${skills}"
        return 1
      }
      sync_skills "${path}/${skills%/}" "${ns}" || return 1
      parts="${parts:+${parts}, }${SYNC_COUNT} skills"
    fi
    if [[ -n "${commands}" ]]; then
      [[ -d "${path}/${commands}" ]] || {
        err "commands directory not found: ${path}/${commands}"
        return 1
      }
      sync_commands "${path}/${commands%/}" "${ns}" || return 1
      parts="${parts:+${parts}, }${SYNC_COUNT} commands"
    fi
    if [[ -n "${agents}" ]]; then
      [[ -d "${path}/${agents}" ]] || {
        err "agents directory not found: ${path}/${agents}"
        return 1
      }
      sync_agents "${path}/${agents%/}" "${ns}" || return 1
      parts="${parts:+${parts}, }${SYNC_COUNT} agents"
    fi
  fi
  if [[ -n "${mcp}" ]]; then
    [[ -f "${path}/${mcp}" ]] || {
      err "MCP file not found: ${path}/${mcp}"
      return 1
    }
    sync_mcp "${path}/${mcp}" || return 1
    parts="${parts:+${parts}, }mcp"
  fi

  sync_summary "${repo}" "${ns}" "${parts}"
}

sync_top_level() {
  # $1 = settings|claude_md, $2 = 'repo:path'
  local kind="$1" value="$2" repo file rc=0
  repo="$(config_ref_repo "${value}")"
  file="$(config_ref_path "${value}")"
  sync_repo "${repo}" "" || rc=$?
  [[ ${rc} -eq 2 ]] && return 0
  [[ ${rc} -eq 0 ]] || return 1
  if [[ ! -f "${SYNC_REPO_PATH}/${file}" ]]; then
    err "${kind} file not found: ${SYNC_REPO_PATH}/${file}"
    return 1
  fi
  if [[ "${kind}" == "settings" ]]; then
    sync_settings "${SYNC_REPO_PATH}/${file}" || return 1
    if [[ "${SYNC_DRY_RUN}" == true ]]; then
      info "would apply base settings from ${repo}"
    else
      log "Applied base settings from ${repo}"
    fi
  else
    sync_claude_md "${SYNC_REPO_PATH}/${file}" || return 1
    if [[ "${SYNC_DRY_RUN}" == true ]]; then
      info "would link CLAUDE.md from ${repo}"
    else
      log "Linked CLAUDE.md from ${repo}"
    fi
  fi
}

do_sync() {
  local errors=0 idx settings_ref claude_md_ref count
  SYNC_FORCE=false SYNC_DRY_RUN=false SYNC_SKIPPED=false SYNC_NEW_LINKS="" SYNC_SEEN="" SYNC_MISSING=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) SYNC_FORCE=true ;;
      --dry-run) SYNC_DRY_RUN=true ;;
      *)
        err "Unknown sync option: $1"
        return 1
        ;;
    esac
    shift
  done

  config_validate || return 1

  settings_ref="$(config_get settings)"
  claude_md_ref="$(config_get claude_md)"
  count="$(config_source_count)"
  if [[ -z "${settings_ref}" ]] && [[ -z "${claude_md_ref}" ]] && [[ "${count}" -eq 0 ]]; then
    if [[ "${SYNC_DRY_RUN}" != true ]] && [[ -f "${LINKS_MANIFEST}" ]]; then
      sync_prune_links
      sync_write_manifest false
    fi
    info "Nothing to sync (edit $(sync_tilde "${CWTCHFILE}" || true))"
    return 0
  fi

  if [[ "${SYNC_DRY_RUN}" == true ]]; then
    header "Sync plan"
  else
    header "Syncing"
    mkdir -p "${CLAUDE_DIR}"
  fi

  [[ -z "${settings_ref}" ]] || sync_top_level settings "${settings_ref}" || errors=$((errors + 1))
  [[ -z "${claude_md_ref}" ]] || sync_top_level claude_md "${claude_md_ref}" || errors=$((errors + 1))

  for idx in $(config_source_indices); do
    sync_one_source "${idx}" || errors=$((errors + 1))
  done

  if [[ "${SYNC_DRY_RUN}" == true ]]; then
    [[ "${SYNC_SKIPPED}" == true ]] || sync_prune_links
    printf '\n'
    info "Dry run: nothing was changed"
    return 0
  fi

  if [[ ${errors} -eq 0 ]]; then
    sync_prune_links
    sync_write_manifest false
  else
    sync_write_manifest true
  fi

  printf '\n'
  [[ ${errors} -eq 0 ]] && {
    log "Sync complete"
    return 0
  }
  printf '%b %s\n' "${C_RED}${SYM_CROSS}${C_RESET}" "Sync finished with ${errors} error(s)"
  return 1
}
