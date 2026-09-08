#!/usr/bin/env bats
# Sync safety — SPEC-v6 §2.3. cwtch only ever creates or replaces symlinks it
# owns; anything else in ~/.claude is a source failure, never something to
# delete. Regressions for audit items 1, 3, 7 and 8.
# shellcheck disable=SC2154,SC2016,SC2312  # bats globals; child shells expand their own vars
bats_require_minimum_version 1.5.0

load helpers.bash

setup() { setup_test_env; }
teardown() { teardown_test_env; }

# --- occupied targets --------------------------------------------------------

@test "F1: a real agents/<as> directory is never destroyed" {
  local repo
  repo="$(create_mock_repo demo)"
  mkdir -p "${HOME}/.claude/agents/work"
  printf '# my own agent\n' > "${HOME}/.claude/agents/work/mine.md"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: work
    agents: agents/"
  run --separate-stderr cwtch sync
  assert_status 1
  assert_stderr_contains "not a symlink"
  [[ -f "${HOME}/.claude/agents/work/mine.md" ]]
  [[ ! -L "${HOME}/.claude/agents/work" ]]
}

@test "F1: a real skills/<as>-<skill> directory is never destroyed" {
  local repo
  repo="$(create_mock_repo demo)"
  mkdir -p "${HOME}/.claude/skills/demo-reviewer"
  printf '# my own skill\n' > "${HOME}/.claude/skills/demo-reviewer/SKILL.md"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run --separate-stderr cwtch sync
  assert_status 1
  assert_stderr_contains "not a symlink"
  assert_file_contains "${HOME}/.claude/skills/demo-reviewer/SKILL.md" "my own skill"
}

@test "F1: the occupied-target error names the path" {
  local repo
  repo="$(create_mock_repo demo)"
  mkdir -p "${HOME}/.claude/agents/work"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: work
    agents: agents/"
  run --separate-stderr cwtch sync
  assert_status 1
  assert_stderr_contains "${HOME}/.claude/agents/work"
}

@test "F1: a plain file where a skill link belongs is a failure, not a deletion" {
  local repo
  repo="$(create_mock_repo demo)"
  mkdir -p "${HOME}/.claude/skills"
  printf 'not a skill dir\n' > "${HOME}/.claude/skills/demo-notes"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run --separate-stderr cwtch sync
  assert_status 1
  [[ -f "${HOME}/.claude/skills/demo-notes" ]]
  assert_file_contains "${HOME}/.claude/skills/demo-notes" "not a skill dir"
}

@test "an existing cwtch symlink is replaced without complaint" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    agents: agents/"
  run cwtch sync
  assert_status 0
  run cwtch sync
  assert_status 0
  assert_output_contains "Sync complete"
  [[ -L "${HOME}/.claude/agents/demo" ]]
}

# --- ref injection -----------------------------------------------------------

@test "F1: a ref that smuggles a git option never reaches git" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    ref: \"--upload-pack=touch ${HOME}/pwned\"
    as: demo
    skills: skills/"
  run --separate-stderr cwtch sync
  assert_status 1
  [[ ! -e "${HOME}/pwned" ]]
}

@test "F1: an option-shaped repo string does not become a git flag" {
  create_cwtchfile "sources:
  - repo: \"--upload-pack=touch ${HOME}/pwned\"
    as: demo
    skills: skills/"
  run --separate-stderr cwtch sync
  [[ "${status}" -ne 0 ]]
  [[ ! -e "${HOME}/pwned" ]]
}

# --- live Claude Code state --------------------------------------------------

@test "F3: an existing settings.json is never replaced wholesale" {
  local repo
  repo="$(create_mock_repo demo)"
  mkdir -p "${HOME}/.claude"
  printf '%s\n' '{"permissions":{"allow":["Bash"]},"hooks":{"PreToolUse":[]},"enabledPlugins":{"x":true},"theme":"dark"}' \
    > "${HOME}/.claude/settings.json"
  create_cwtchfile "sources: []
settings: ${repo}:config/settings.json"
  run cwtch sync
  assert_status 0
  [[ "$(jq -r '.permissions.allow[0]' "${HOME}/.claude/settings.json")" == "Bash" ]]
  [[ "$(jq -r '.enabledPlugins.x' "${HOME}/.claude/settings.json")" == "true" ]]
  [[ "$(jq -r '.theme' "${HOME}/.claude/settings.json")" == "dark" ]]
  [[ "$(jq -r 'has("hooks")' "${HOME}/.claude/settings.json")" == "true" ]]
}

@test "F11: settings.json never gains an mcpServers key" {
  local repo
  repo="$(create_mock_repo demo)"
  mkdir -p "${HOME}/.claude"
  printf '%s\n' '{"model":"opus"}' > "${HOME}/.claude/settings.json"
  create_cwtchfile "settings: ${repo}:config/settings.json
sources:
  - repo: ${repo}
    as: demo
    mcp: mcp.json"
  run cwtch sync
  assert_status 0
  [[ "$(jq -r 'has("mcpServers")' "${HOME}/.claude/settings.json")" == "false" ]]
}

@test "F3: a failing source leaves earlier outputs intact" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: good
    skills: skills/
  - repo: ${TEST_DIR}/missing
    as: bad
    skills: skills/"
  run cwtch sync
  assert_status 1
  [[ -L "${HOME}/.claude/skills/good-reviewer" ]]
  [[ -f "${HOME}/.claude/skills/good-reviewer/SKILL.md" ]]
}

@test "F7: errors are printed as they happen, on stderr" {
  create_cwtchfile "sources:
  - repo: ${TEST_DIR}/missing-one
    as: one
    skills: skills/
  - repo: ${TEST_DIR}/missing-two
    as: two
    skills: skills/"
  run --separate-stderr cwtch sync
  assert_status 1
  assert_stderr_contains "missing-one"
  assert_stderr_contains "missing-two"
  assert_output_contains "2 error"
}

# --- manifest pruning is conservative ----------------------------------------

@test "F8: pruning refuses to remove a link pointing outside sources/" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    agents: agents/"
  run cwtch sync
  assert_status 0

  # The user repoints the link at their own directory; cwtch must not delete it.
  mkdir -p "${HOME}/mine"
  rm -f "${HOME}/.claude/agents/demo"
  ln -s "${HOME}/mine" "${HOME}/.claude/agents/demo"
  create_cwtchfile "sources: []"
  run cwtch sync
  assert_status 0
  [[ -L "${HOME}/.claude/agents/demo" ]]
  [[ -d "${HOME}/mine" ]]
}

@test "F8: pruning does not touch a real directory that replaced a link" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    agents: agents/"
  run cwtch sync
  assert_status 0
  rm -f "${HOME}/.claude/agents/demo"
  mkdir -p "${HOME}/.claude/agents/demo"
  printf '# mine\n' > "${HOME}/.claude/agents/demo/mine.md"
  create_cwtchfile "sources: []"
  run cwtch sync
  assert_status 0
  [[ -f "${HOME}/.claude/agents/demo/mine.md" ]]
}

@test "F8: unrelated content in ~/.claude survives a sync" {
  local repo
  repo="$(create_mock_repo demo)"
  mkdir -p "${HOME}/.claude/projects/session" "${HOME}/.claude/skills/mine"
  printf 'history\n' > "${HOME}/.claude/projects/session/log.jsonl"
  printf '# mine\n' > "${HOME}/.claude/skills/mine/SKILL.md"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch sync
  assert_status 0
  [[ -f "${HOME}/.claude/projects/session/log.jsonl" ]]
  [[ -f "${HOME}/.claude/skills/mine/SKILL.md" ]]
}
