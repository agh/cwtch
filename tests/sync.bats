#!/usr/bin/env bats
# `cwtch sync` — SPEC-v6 §2.2 (repositories) and §2.3 (outputs).
# shellcheck disable=SC2154,SC2016,SC2312  # bats globals; child shells expand their own vars
bats_require_minimum_version 1.5.0

load helpers.bash

setup() { setup_test_env; }
teardown() { teardown_test_env; }

run_lib() {
  run bash -c '
    set -euo pipefail
    source "${ROOT}/lib/common.sh"
    source "${ROOT}/lib/config.sh"
    source "${ROOT}/lib/sync.sh"
    "$@"
  ' _ "$@"
}

# --- §2.2 repo_to_url / repo_local_path --------------------------------------

@test "repo_to_url expands the GitHub shorthand and passes URLs through" {
  run_lib repo_to_url "owner/repo"
  assert_status 0
  [[ "${output}" == "https://github.com/owner/repo.git" ]]
  run_lib repo_to_url "https://example.invalid/x.git"
  [[ "${output}" == "https://example.invalid/x.git" ]]
  run_lib repo_to_url "git@example.invalid:owner/repo.git"
  [[ "${output}" == "git@example.invalid:owner/repo.git" ]]
  run_lib repo_to_url "/srv/local/repo"
  [[ "${output}" == "/srv/local/repo" ]]
}

@test "repo_local_path slugifies a shorthand repo" {
  run_lib repo_local_path "owner/repo"
  assert_status 0
  [[ "${output}" == "${HOME}/.cwtch/sources/owner-repo" ]]
}

@test "F9: repo_local_path keeps characters outside the safe set out of the slug" {
  run_lib repo_local_path "git@example.invalid:owner/repo.git"
  assert_status 0
  assert_output_matches "^${HOME}/.cwtch/sources/[A-Za-z0-9._-]+$"
}

@test "F9: two local repos with the same basename get different directories" {
  run_lib repo_local_path "/srv/a/tools"
  local first="${output}"
  run_lib repo_local_path "/srv/b/tools"
  assert_status 0
  [[ "${first}" != "${output}" ]]
  [[ "${first}" =~ -[0-9a-f]{8}$ ]]
}

@test "F9: syncing two same-named local repos produces two clones" {
  local one two
  one="$(create_mock_repo a/tools)"
  two="$(create_mock_repo b/tools)"
  create_cwtchfile "sources:
  - repo: ${one}
    as: one
    skills: skills/
  - repo: ${two}
    as: two
    skills: skills/"
  run cwtch sync
  assert_status 0
  [[ "$(count_sources)" -eq 2 ]]
}

# --- §2.2 clone, ref and update ----------------------------------------------

@test "sync clones a source and reports the namespace" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  assert_output_contains "demo"
  [[ -d "$(only_source_dir)/.git" ]]
}

@test "F10: a repo whose default branch is not main syncs without an explicit ref" {
  local repo
  repo="$(create_mock_repo trunkrepo trunk)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  assert_output_contains "Sync complete"
  [[ -f "$(only_source_dir)/skills/reviewer/SKILL.md" ]]
}

@test "an explicit branch ref is checked out" {
  local repo
  repo="$(create_mock_repo demo)"
  repo_add_branch "${repo}" "next" "skills/nextonly/SKILL.md" "next only"
  create_cwtchfile "sources:
  - repo: ${repo}
    ref: next
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  [[ -f "$(only_source_dir)/skills/nextonly/SKILL.md" ]]
}

@test "a tag ref is checked out" {
  local repo
  repo="$(create_mock_repo demo)"
  repo_add_tag "${repo}" "v1.0.0"
  repo_commit "${repo}" "skills/after/SKILL.md" "after the tag"
  create_cwtchfile "sources:
  - repo: ${repo}
    ref: v1.0.0
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  [[ ! -e "$(only_source_dir)/skills/after/SKILL.md" ]]
}

@test "F9: changing ref on an existing clone switches the working tree" {
  local repo
  repo="$(create_mock_repo demo)"
  repo_add_branch "${repo}" "next" "skills/nextonly/SKILL.md" "next only"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  [[ ! -e "$(only_source_dir)/skills/nextonly/SKILL.md" ]]

  create_cwtchfile "sources:
  - repo: ${repo}
    ref: next
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  [[ -f "$(only_source_dir)/skills/nextonly/SKILL.md" ]]
}

@test "an existing clone is updated to the newest upstream commit" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  repo_commit "${repo}" "skills/fresh/SKILL.md" "brand new"
  run cwtch sync
  assert_status 0
  [[ -f "$(only_source_dir)/skills/fresh/SKILL.md" ]]
}

@test "local edits under sources/ are discarded on the next sync" {
  local repo dir
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  dir="$(only_source_dir)"
  printf 'local edit\n' > "${dir}/skills/reviewer/SKILL.md"
  run cwtch sync
  assert_status 0
  refute_file_contains "${dir}/skills/reviewer/SKILL.md" "local edit"
}

@test "F7: a source that cannot be cloned is an error and a non-zero exit" {
  create_cwtchfile "sources:
  - repo: ${TEST_DIR}/no-such-repo
    as: demo
    skills: skills/"
  run --separate-stderr cwtch sync
  assert_status 1
  assert_stderr_contains "${TEST_DIR}/no-such-repo"
}

@test "F7: the closing line counts the failures" {
  create_cwtchfile "sources:
  - repo: ${TEST_DIR}/no-such-repo
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 1
  assert_output_contains "Sync finished with 1 error"
  assert_output_lacks "Sync complete"
}

@test "F7: a good source is still applied when another one fails" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${TEST_DIR}/no-such-repo
    as: broken
    skills: skills/
  - repo: ${repo}
    as: good
    skills: skills/"
  run cwtch sync
  assert_status 1
  [[ -L "${HOME}/.claude/skills/good-reviewer" ]]
}

@test "F7: a missing ref on an existing clone is a failure, not a silent no-op" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  create_cwtchfile "sources:
  - repo: ${repo}
    ref: nonexistent-branch
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 1
}

# --- §2.3 skills -------------------------------------------------------------

@test "F12: each skill directory is linked as skills/<as>-<skill>" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  [[ -L "${HOME}/.claude/skills/demo-reviewer" ]]
  [[ -L "${HOME}/.claude/skills/demo-notes" ]]
  [[ -f "${HOME}/.claude/skills/demo-reviewer/SKILL.md" ]]
}

@test "F12: a directory without SKILL.md is not linked as a skill" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  [[ ! -e "${HOME}/.claude/skills/demo-notaskill" ]]
}

# --- §2.3 commands become skills ---------------------------------------------

@test "F12: each command markdown file becomes a skill directory" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    commands: commands/"
  run cwtch sync
  assert_status 0
  [[ -d "${HOME}/.claude/skills/demo-deploy" ]]
  [[ ! -L "${HOME}/.claude/skills/demo-deploy" ]]
  [[ -L "${HOME}/.claude/skills/demo-deploy/SKILL.md" ]]
  assert_file_contains "${HOME}/.claude/skills/demo-deploy/SKILL.md" "Deploy command"
  [[ -L "${HOME}/.claude/skills/demo-review/SKILL.md" ]]
}

@test "F12: non-markdown files in the commands directory are ignored" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    commands: commands/"
  run cwtch sync
  assert_status 0
  [[ ! -e "${HOME}/.claude/skills/demo-notes.txt" ]]
  [[ ! -e "${HOME}/.claude/skills/demo-notes" ]]
}

@test "F12: a legacy commands/<as> symlink into sources is removed" {
  local repo dir
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    commands: commands/"
  run cwtch sync
  assert_status 0
  dir="$(only_source_dir)"
  mkdir -p "${HOME}/.claude/commands"
  ln -s "${dir}/commands" "${HOME}/.claude/commands/demo"
  run cwtch sync
  assert_status 0
  [[ ! -e "${HOME}/.claude/commands/demo" ]]
}

# --- §2.3 agents -------------------------------------------------------------

@test "agents are linked as a single namespace directory" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    agents: agents/"
  run cwtch sync
  assert_status 0
  [[ -L "${HOME}/.claude/agents/demo" ]]
  [[ -f "${HOME}/.claude/agents/demo/helper.md" ]]
  [[ -f "${HOME}/.claude/agents/demo/nested/deep.md" ]]
}

# --- §2.3 settings -----------------------------------------------------------

@test "F3: settings are deep-merged, with the user's values winning" {
  local repo
  repo="$(create_mock_repo demo)"
  mkdir -p "${HOME}/.claude"
  printf '%s\n' '{"model":"opus","statusLine":{"type":"command"}}' > "${HOME}/.claude/settings.json"
  create_cwtchfile "sources: []
settings: ${repo}:config/settings.json"
  run cwtch sync
  assert_status 0
  [[ "$(jq -r '.model' "${HOME}/.claude/settings.json")" == "opus" ]]
  [[ "$(jq -r '.statusLine.type' "${HOME}/.claude/settings.json")" == "command" ]]
  [[ "$(jq -r '.env.FROM_BASE' "${HOME}/.claude/settings.json")" == "1" ]]
  [[ "$(jq -r '.permissions.defaultMode' "${HOME}/.claude/settings.json")" == "acceptEdits" ]]
}

@test "F3: the previous settings.json is backed up when the content changes" {
  local repo
  repo="$(create_mock_repo demo)"
  mkdir -p "${HOME}/.claude"
  printf '%s\n' '{"model":"opus"}' > "${HOME}/.claude/settings.json"
  create_cwtchfile "sources: []
settings: ${repo}:config/settings.json"
  run cwtch sync
  assert_status 0
  [[ -f "${HOME}/.claude/settings.json.bak" ]]
  [[ "$(jq -r '.model' "${HOME}/.claude/settings.json.bak")" == "opus" ]]
}

@test "F3: settings.json is created when it does not exist" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources: []
settings: ${repo}:config/settings.json"
  run cwtch sync
  assert_status 0
  [[ "$(jq -r '.model' "${HOME}/.claude/settings.json")" == "sonnet" ]]
}

@test "a missing settings file in the source is an error" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources: []
settings: ${repo}:config/nope.json"
  run --separate-stderr cwtch sync
  assert_status 1
}

# --- §2.3 CLAUDE.md ----------------------------------------------------------

@test "claude_md is linked when nothing is there" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources: []
claude_md: ${repo}:config/CLAUDE.md"
  run cwtch sync
  assert_status 0
  [[ -L "${HOME}/.claude/CLAUDE.md" ]]
  assert_file_contains "${HOME}/.claude/CLAUDE.md" "Shared CLAUDE.md"
}

@test "F3: an existing regular CLAUDE.md is protected" {
  local repo
  repo="$(create_mock_repo demo)"
  mkdir -p "${HOME}/.claude"
  printf '# my own notes\n' > "${HOME}/.claude/CLAUDE.md"
  create_cwtchfile "sources: []
claude_md: ${repo}:config/CLAUDE.md"
  run --separate-stderr cwtch sync
  assert_status 1
  assert_stderr_contains "not a symlink"
  assert_stderr_contains "--force"
  [[ ! -L "${HOME}/.claude/CLAUDE.md" ]]
  assert_file_contains "${HOME}/.claude/CLAUDE.md" "my own notes"
}

@test "F3: --force backs the regular CLAUDE.md up before replacing it" {
  local repo
  repo="$(create_mock_repo demo)"
  mkdir -p "${HOME}/.claude"
  printf '# my own notes\n' > "${HOME}/.claude/CLAUDE.md"
  create_cwtchfile "sources: []
claude_md: ${repo}:config/CLAUDE.md"
  run cwtch sync --force
  assert_status 0
  [[ -L "${HOME}/.claude/CLAUDE.md" ]]
  assert_file_contains "${HOME}/.claude/CLAUDE.md.bak" "my own notes"
}

@test "an existing CLAUDE.md symlink is replaced without --force" {
  local repo
  repo="$(create_mock_repo demo)"
  mkdir -p "${HOME}/.claude"
  printf 'old target\n' > "${HOME}/old.md"
  ln -s "${HOME}/old.md" "${HOME}/.claude/CLAUDE.md"
  create_cwtchfile "sources: []
claude_md: ${repo}:config/CLAUDE.md"
  run cwtch sync
  assert_status 0
  [[ -L "${HOME}/.claude/CLAUDE.md" ]]
  assert_file_contains "${HOME}/.claude/CLAUDE.md" "Shared CLAUDE.md"
}

# --- §2.3 MCP ----------------------------------------------------------------

@test "F11: mcp servers are merged into ~/.claude.json, not settings.json" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    mcp: mcp.json"
  run cwtch sync
  assert_status 0
  [[ "$(jq -r '.mcpServers.demo.command' "${HOME}/.claude.json")" == "demo" ]]
  if [[ -f "${HOME}/.claude/settings.json" ]]; then
    [[ "$(jq -r '.mcpServers // "absent"' "${HOME}/.claude/settings.json")" == "absent" ]]
  fi
}

@test "F11: existing servers in ~/.claude.json survive the merge" {
  local repo
  repo="$(create_mock_repo demo)"
  printf '%s\n' '{"numStartups":7,"mcpServers":{"github":{"command":"gh-mcp"}}}' > "${HOME}/.claude.json"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    mcp: mcp.json"
  run cwtch sync
  assert_status 0
  [[ "$(jq -r '.mcpServers.github.command' "${HOME}/.claude.json")" == "gh-mcp" ]]
  [[ "$(jq -r '.mcpServers.demo.command' "${HOME}/.claude.json")" == "demo" ]]
  [[ "$(jq -r '.numStartups' "${HOME}/.claude.json")" == "7" ]]
}

@test "F11: ~/.claude.json is backed up before it is rewritten" {
  local repo
  repo="$(create_mock_repo demo)"
  printf '%s\n' '{"mcpServers":{"github":{"command":"gh-mcp"}}}' > "${HOME}/.claude.json"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    mcp: mcp.json"
  run cwtch sync
  assert_status 0
  [[ -f "${HOME}/.claude.json.bak" ]]
  [[ "$(jq -r '.mcpServers.github.command' "${HOME}/.claude.json.bak")" == "gh-mcp" ]]
}

@test "F11: a bare server map is accepted" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    mcp: mcp-bare.json"
  run cwtch sync
  assert_status 0
  [[ "$(jq -r '.mcpServers.bare.command' "${HOME}/.claude.json")" == "bare-server" ]]
}

@test "F11: a server of the same name is replaced by the source's definition" {
  local repo
  repo="$(create_mock_repo demo)"
  printf '%s\n' '{"mcpServers":{"demo":{"command":"stale"}}}' > "${HOME}/.claude.json"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    mcp: mcp.json"
  run cwtch sync
  assert_status 0
  [[ "$(jq -r '.mcpServers.demo.command' "${HOME}/.claude.json")" == "demo" ]]
}

@test "F21: CLAUDE_CONFIG_DIR moves both the config tree and .claude.json" {
  local repo
  repo="$(create_mock_repo demo)"
  mkdir -p "${HOME}/custom"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/
    mcp: mcp.json"
  run env CLAUDE_CONFIG_DIR="${HOME}/custom" cwtch sync
  assert_status 0
  [[ -L "${HOME}/custom/skills/demo-reviewer" ]]
  [[ -f "${HOME}/custom/.claude.json" ]]
  [[ ! -e "${HOME}/.claude.json" ]]
}

# --- §2.3 manifest -----------------------------------------------------------

@test "F8: sync records the links it created in a manifest" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  [[ -f "${HOME}/.cwtch/state/links" ]]
  assert_file_contains "${HOME}/.cwtch/state/links" "${HOME}/.claude/skills/demo-reviewer"
}

@test "F8: removing a source prunes the links it owned" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/
  - repo: ${repo}
    as: extra
    agents: agents/"
  run cwtch sync
  assert_status 0
  [[ -L "${HOME}/.claude/agents/extra" ]]

  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  [[ -L "${HOME}/.claude/skills/demo-reviewer" ]]
  [[ ! -e "${HOME}/.claude/agents/extra" ]]
}

@test "F8: pruning removes the parent directory when it is left empty" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    agents: agents/"
  run cwtch sync
  assert_status 0
  create_cwtchfile "sources: []"
  run cwtch sync
  assert_status 0
  [[ ! -e "${HOME}/.claude/agents/demo" ]]
  [[ ! -d "${HOME}/.claude/agents" ]]
}

@test "F8: renaming a namespace does not leave the old link behind" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: oldname
    skills: skills/"
  run cwtch sync
  assert_status 0
  create_cwtchfile "sources:
  - repo: ${repo}
    as: newname
    skills: skills/"
  run cwtch sync
  assert_status 0
  [[ -L "${HOME}/.claude/skills/newname-reviewer" ]]
  [[ ! -e "${HOME}/.claude/skills/oldname-reviewer" ]]
}

# --- §2.3 summary ------------------------------------------------------------

@test "sync summarises skill and agent counts and finishes cleanly" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/
    agents: agents/"
  run cwtch sync
  assert_status 0
  assert_output_contains "skills"
  assert_output_contains "agents"
  assert_output_contains "2"
  assert_output_contains "Sync complete"
}

@test "sync without a Cwtchfile fails" {
  run --separate-stderr cwtch sync
  assert_status 1
}

@test "sync is idempotent" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/
    agents: agents/
    commands: commands/"
  run cwtch sync
  assert_status 0
  run cwtch sync
  assert_status 0
  assert_output_contains "Sync complete"
  [[ -L "${HOME}/.claude/skills/demo-reviewer" ]]
  [[ -L "${HOME}/.claude/agents/demo" ]]
  [[ -L "${HOME}/.claude/skills/demo-deploy/SKILL.md" ]]
}

@test "sync --dry-run changes nothing" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch --help
  if [[ "${output}" != *"--dry-run"* ]]; then
    skip "sync --dry-run is optional in SPEC-v6 §2.3 and is not advertised"
  fi
  run cwtch sync --dry-run
  assert_status 0
  [[ ! -e "${HOME}/.claude/skills/demo-reviewer" ]]
}
