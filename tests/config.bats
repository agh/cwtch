#!/usr/bin/env bats
# Cwtchfile schema and validation — SPEC-v6 §2.1, exercised through
# `cwtch sync check` and by calling config_validate directly.
# shellcheck disable=SC2154,SC2016,SC2312  # bats globals; child shells expand their own vars
bats_require_minimum_version 1.5.0

load helpers.bash

setup() { setup_test_env; }
teardown() { teardown_test_env; }

# Call a lib function in a fresh shell with errexit on, the way a future caller
# would. Any landmine that aborts mid-function shows up as missing output.
run_lib() {
  run --separate-stderr bash -c '
    set -euo pipefail
    source "${ROOT}/lib/common.sh"
    source "${ROOT}/lib/config.sh"
    source "${ROOT}/lib/sync.sh"
    "$@"
  ' _ "$@"
}

# --- presence and syntax -----------------------------------------------------

@test "sync check fails when there is no Cwtchfile" {
  run --separate-stderr cwtch sync check
  assert_status 1
  assert_stderr_contains "${HOME}/.cwtch/Cwtchfile"
}

@test "sync check fails on invalid YAML" {
  create_cwtchfile "sources: [oops"
  run --separate-stderr cwtch sync check
  assert_status 1
}

@test "sync check accepts a valid file and says so" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch sync check
  assert_status 0
  assert_output_contains "valid"
}

# --- sources type ------------------------------------------------------------

@test "F13: a settings-only Cwtchfile with no sources key is valid" {
  create_cwtchfile "settings: owner/repo:config/settings.json"
  run cwtch sync check
  assert_status 0
  assert_output_contains "valid"
}

@test "F13: an explicitly null sources key is valid" {
  create_cwtchfile "sources:"
  run cwtch sync check
  assert_status 0
}

@test "F13: an empty sources list is valid" {
  create_cwtchfile "sources: []"
  run cwtch sync check
  assert_status 0
}

@test "F13: a mapping under sources is rejected" {
  create_cwtchfile "sources:
  first:
    repo: owner/repo"
  run --separate-stderr cwtch sync check
  assert_status 1
  assert_stderr_contains "sources"
}

@test "F13: a scalar under sources is rejected" {
  create_cwtchfile "sources: owner/repo"
  run --separate-stderr cwtch sync check
  assert_status 1
}

# --- repo:path fields --------------------------------------------------------

@test "F13: settings with a bare colon is rejected" {
  create_cwtchfile "sources: []
settings: \":\""
  run --separate-stderr cwtch sync check
  assert_status 1
  assert_stderr_contains "settings"
}

@test "F13: settings with an empty path is rejected" {
  create_cwtchfile "sources: []
settings: \"owner/repo:\""
  run --separate-stderr cwtch sync check
  assert_status 1
}

@test "F13: settings with an empty repo is rejected" {
  create_cwtchfile "sources: []
settings: \":config/settings.json\""
  run --separate-stderr cwtch sync check
  assert_status 1
}

@test "F13: settings without a colon is rejected" {
  create_cwtchfile "sources: []
settings: owner/repo"
  run --separate-stderr cwtch sync check
  assert_status 1
}

@test "F13: claude_md is validated the same way" {
  create_cwtchfile "sources: []
claude_md: \":\""
  run --separate-stderr cwtch sync check
  assert_status 1
  assert_stderr_contains "claude_md"
}

@test "a well-formed claude_md is accepted" {
  create_cwtchfile "sources: []
claude_md: owner/repo:config/CLAUDE.md"
  run cwtch sync check
  assert_status 0
}

# --- source entries ----------------------------------------------------------

@test "a source without repo is rejected" {
  create_cwtchfile "sources:
  - as: demo
    skills: skills/"
  run --separate-stderr cwtch sync check
  assert_status 1
  assert_stderr_contains "repo"
}

@test "F23: the sync init placeholder repo is rejected by name" {
  create_cwtchfile "sources:
  - repo: owner/repo
    as: demo
    skills: skills/"
  run --separate-stderr cwtch sync check
  assert_status 1
  assert_stderr_contains "placeholder"
}

@test "as is required when skills, commands or agents are given" {
  local field
  for field in skills commands agents; do
    create_cwtchfile "sources:
  - repo: someone/thing
    ${field}: ${field}/"
    run --separate-stderr cwtch sync check
    assert_status 1
    assert_stderr_contains "as"
  done
}

@test "a source with only repo and mcp needs no namespace" {
  create_cwtchfile "sources:
  - repo: someone/thing
    mcp: mcp.json"
  run cwtch sync check
  assert_status 0
}

@test "duplicate as values are rejected" {
  create_cwtchfile "sources:
  - repo: someone/one
    as: shared
    skills: skills/
  - repo: someone/two
    as: shared
    skills: skills/"
  run --separate-stderr cwtch sync check
  assert_status 1
  assert_stderr_contains "shared"
}

@test "F12: hooks is no longer a supported source field" {
  create_cwtchfile "sources:
  - repo: someone/thing
    as: demo
    hooks: hooks/"
  run --separate-stderr cwtch sync check
  assert_status 1
  assert_stderr_contains "hooks: is not supported"
  assert_stderr_contains "settings.json"
}

@test "a repo given as a URL or local path is accepted" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: https://example.invalid/someone/thing.git
    as: one
    skills: skills/
  - repo: git@example.invalid:someone/other.git
    as: two
    skills: skills/
  - repo: ${repo}
    as: three
    skills: skills/"
  run cwtch sync check
  assert_status 0
}

# --- error reporting ---------------------------------------------------------

@test "F19: every validation error is reported, not just the first" {
  create_cwtchfile "settings: \":\"
sources:
  - repo: someone/one
    as: ../bad
    skills: skills/
  - as: nameless
    skills: skills/"
  run --separate-stderr cwtch sync check
  assert_status 1
  assert_stderr_contains "settings"
  assert_stderr_contains "Invalid name"
  assert_stderr_contains "repo"
}

@test "F19: config_validate returns non-zero without aborting its caller" {
  create_cwtchfile "sources:
  - as: nameless
    skills: skills/"
  run --separate-stderr bash -c '
    set -euo pipefail
    source "${ROOT}/lib/common.sh"
    source "${ROOT}/lib/config.sh"
    rc=0
    config_validate || rc=$?
    printf "rc=%s\n" "${rc}"
  '
  assert_status 0
  assert_output_contains "rc=1"
}

@test "config_validate returns 0 for a valid file when called directly" {
  create_cwtchfile "sources: []
settings: owner/repo:config/settings.json"
  run_lib config_validate
  assert_status 0
}

# --- sync check reporting ----------------------------------------------------

@test "sync check summarises settings, claude_md and sources" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "settings: someone/base:config/settings.json
claude_md: someone/base:config/CLAUDE.md
sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch sync check
  assert_status 0
  assert_output_contains "someone/base:config/settings.json"
  assert_output_contains "someone/base:config/CLAUDE.md"
  assert_output_contains "demo"
}

@test "sync check warns when settings would touch an existing file" {
  mkdir -p "${HOME}/.claude"
  printf '{"model":"opus"}\n' > "${HOME}/.claude/settings.json"
  create_cwtchfile "sources: []
settings: someone/base:config/settings.json"
  run cwtch sync check
  assert_status 0
  assert_output_contains "settings.json"
  assert_output_matches "[Ee]xist"
}

@test "sync check warns when claude_md would replace a regular file" {
  mkdir -p "${HOME}/.claude"
  printf '# mine\n' > "${HOME}/.claude/CLAUDE.md"
  create_cwtchfile "sources: []
claude_md: someone/base:config/CLAUDE.md"
  run cwtch sync check
  assert_status 0
  assert_output_matches "[Ee]xist"
}

# --- sync init ---------------------------------------------------------------

@test "sync init creates a Cwtchfile" {
  run cwtch sync init
  assert_status 0
  [[ -f "${HOME}/.cwtch/Cwtchfile" ]]
}

@test "sync init refuses to overwrite an existing Cwtchfile" {
  create_cwtchfile "sources: []"
  run --separate-stderr cwtch sync init
  assert_status 1
  assert_stderr_contains "exists"
}

@test "F23: the generated Cwtchfile validates" {
  run cwtch sync init
  assert_status 0
  run cwtch sync check
  assert_status 0
  assert_output_contains "valid"
}

@test "F23: the generated Cwtchfile has every source commented out" {
  run cwtch sync init
  assert_status 0
  refute_file_matches "${HOME}/.cwtch/Cwtchfile" '^[[:space:]]*-[[:space:]]*repo:'
  assert_file_contains "${HOME}/.cwtch/Cwtchfile" "repo:"
}

@test "F23: sync on a freshly generated Cwtchfile is a no-op" {
  run cwtch sync init
  assert_status 0
  run cwtch sync
  assert_status 0
  assert_output_contains "Nothing to sync"
  [[ ! -d "${HOME}/.cwtch/sources" ]] || [[ -z "$(ls -A "${HOME}/.cwtch/sources")" ]]
}

# --- profile overlays are gone -----------------------------------------------

@test "F2: profile overlay Cwtchfiles are not consulted by sync" {
  local repo
  repo="$(create_mock_repo demo)"
  write_token_profile work
  set_current work
  printf 'sources:\n  - repo: /does/not/exist\n    as: overlay\n' \
    > "${HOME}/.cwtch/profiles/work/Cwtchfile"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  [[ ! -e "${HOME}/.claude/skills/overlay-reviewer" ]]
}
