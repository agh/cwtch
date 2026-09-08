#!/usr/bin/env bats
# End-to-end checks of real output, moved out of .github/workflows/ci.yml so
# they are versioned and runnable locally. The one test that needs the network
# is gated on CWTCH_E2E=1.
# shellcheck disable=SC2154,SC2016,SC2312  # bats globals; child shells expand their own vars
bats_require_minimum_version 1.5.0

load helpers.bash

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "e2e: help output runs" {
  run cwtch --help
  assert_status 0
  assert_output_contains "cwtch"
}

@test "e2e: profile list is empty on a fresh machine" {
  run cwtch profile list
  assert_status 0
  assert_output_contains "No profiles saved"
}

@test "e2e: profile current reports none on a fresh machine" {
  run cwtch profile current
  assert_status 0
  [[ "${output}" == "(none)" ]]
}

@test "e2e: an api-key profile can be saved and listed" {
  run bash -c 'printf "%s\n" "${TEST_APIKEY_A}" | cwtch profile save-key testapi'
  assert_status 0
  run cwtch profile list
  assert_status 0
  assert_output_contains "testapi"
  assert_output_contains "api-key"
}

@test "e2e: status shows the saved profile" {
  run bash -c 'printf "%s\n" "${TEST_APIKEY_A}" | cwtch profile save-key testapi'
  assert_status 0
  run cwtch profile use testapi
  assert_status 0
  run cwtch status
  assert_status 0
  assert_output_contains "testapi"
  assert_output_contains "api-key"
}

@test "e2e: sync init creates a Cwtchfile" {
  run cwtch sync init
  assert_status 0
  [[ -f "${HOME}/.cwtch/Cwtchfile" ]]
  assert_file_contains "${HOME}/.cwtch/Cwtchfile" "sources:"
}

@test "e2e: sync check validates the generated Cwtchfile" {
  run cwtch sync init
  assert_status 0
  run cwtch sync check
  assert_status 0
  assert_output_contains "Cwtchfile is valid"
}

@test "e2e: status lists a configured source" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    skills: skills/"
  run cwtch status
  assert_status 0
  assert_output_contains "${repo}"
  assert_output_contains "demo"
}

@test "e2e: edit references the Cwtchfile" {
  run env EDITOR=echo cwtch edit
  assert_status 0
  assert_output_contains "/.cwtch/Cwtchfile"
}

@test "e2e: a full sync of a local source builds ~/.claude" {
  local repo
  repo="$(create_mock_repo demo)"
  create_cwtchfile "settings: ${repo}:config/settings.json
claude_md: ${repo}:config/CLAUDE.md
sources:
  - repo: ${repo}
    as: demo
    skills: skills/
    commands: commands/
    agents: agents/
    mcp: mcp.json"
  run cwtch sync
  assert_status 0
  assert_output_contains "Sync complete"
  [[ -L "${HOME}/.claude/skills/demo-reviewer" ]]
  [[ -L "${HOME}/.claude/skills/demo-deploy/SKILL.md" ]]
  [[ -L "${HOME}/.claude/agents/demo" ]]
  [[ -L "${HOME}/.claude/CLAUDE.md" ]]
  [[ -f "${HOME}/.claude/settings.json" ]]
  [[ "$(jq -r '.mcpServers.demo.command' "${HOME}/.claude.json")" == "demo" ]]
}

@test "e2e: sync clones a real GitHub repository" {
  if [[ -z "${CWTCH_E2E:-}" ]]; then
    skip "needs the network; set CWTCH_E2E=1"
  fi
  create_cwtchfile "sources:
  - repo: agh/cwtch
    ref: main
    as: cwtchself
    agents: .github/"
  run cwtch sync
  assert_status 0
  [[ -d "${HOME}/.cwtch/sources/agh-cwtch/.git" ]]
  [[ -L "${HOME}/.claude/agents/cwtchself" ]]
}
