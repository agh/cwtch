#!/usr/bin/env bats
# `cwtch profile env` — SPEC-v6 §1.4.
# Regression tests for audit item 6: env never unset the other variable, so a
# stale CLAUDE_CODE_OAUTH_TOKEN kept winning over the Keychain login.
# shellcheck disable=SC2154,SC2016,SC2312  # bats globals; child shells expand their own vars
bats_require_minimum_version 1.5.0

load helpers.bash

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "profile env fails when no profile is active" {
  run --separate-stderr cwtch profile env
  assert_status 1
  assert_stderr_contains "No profile active"
  [[ -z "${output}" ]]
}

@test "F6: env unsets both credential variables before exporting anything" {
  write_token_profile tok
  set_current tok
  run cwtch profile env
  assert_status 0
  [[ "${lines[0]}" == "unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY" ]]
}

@test "F6: a token profile exports only CLAUDE_CODE_OAUTH_TOKEN" {
  write_token_profile tok
  set_current tok
  run cwtch profile env
  assert_status 0
  assert_output_contains "export CLAUDE_CODE_OAUTH_TOKEN='${TEST_TOKEN_A}'"
  assert_output_lacks "export ANTHROPIC_API_KEY="
}

@test "F6: an api-key profile exports only ANTHROPIC_API_KEY" {
  write_apikey_profile api
  set_current api
  run cwtch profile env
  assert_status 0
  assert_output_contains "export ANTHROPIC_API_KEY='${TEST_APIKEY_A}'"
  assert_output_lacks "export CLAUDE_CODE_OAUTH_TOKEN="
}

@test "F6: an OAuth profile exports nothing and says so in a comment" {
  write_oauth_profile personal
  set_current personal
  run cwtch profile env
  assert_status 0
  assert_output_contains "unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY"
  assert_output_contains "# OAuth profile 'personal'"
  assert_output_contains "Keychain"
  assert_output_lacks "export "
}

@test "F6: switching from a token profile to OAuth clears the stale variable" {
  write_token_profile tok
  write_oauth_profile personal
  set_current tok
  run bash -c 'eval "$(cwtch profile env)"; printf "%s\n" "${CLAUDE_CODE_OAUTH_TOKEN:-unset}"'
  assert_status 0
  [[ "${output}" == "${TEST_TOKEN_A}" ]]

  set_current personal
  run bash -c 'export CLAUDE_CODE_OAUTH_TOKEN=stale; eval "$(cwtch profile env)"; printf "%s\n" "${CLAUDE_CODE_OAUTH_TOKEN:-unset}"'
  assert_status 0
  [[ "${output}" == "unset" ]]
}

@test "the output is safe to eval for every profile type" {
  write_apikey_profile api
  set_current api
  run bash -c 'set -euo pipefail; eval "$(cwtch profile env)"; printf "%s\n" "${ANTHROPIC_API_KEY}"'
  assert_status 0
  [[ "${output}" == "${TEST_APIKEY_A}" ]]
}

@test "env refuses to print a credential that no longer validates" {
  mkdir -p "${HOME}/.cwtch/profiles/tok"
  printf "%s\n" "sk-ant-oat01-'; rm -rf \$HOME; '" > "${HOME}/.cwtch/profiles/tok/.token"
  chmod 600 "${HOME}/.cwtch/profiles/tok/.token"
  set_current tok
  run --separate-stderr cwtch profile env
  assert_status 1
  assert_output_lacks "rm -rf"
}

@test "F6: env warns that ANTHROPIC_AUTH_TOKEN takes precedence" {
  write_token_profile tok
  set_current tok
  run env ANTHROPIC_AUTH_TOKEN=something cwtch profile env
  assert_status 0
  assert_output_contains "ANTHROPIC_AUTH_TOKEN"
  assert_output_contains "precedence"
  assert_output_matches "^#.*ANTHROPIC_AUTH_TOKEN"
}

@test "F6: env warns about each cloud-provider override" {
  write_token_profile tok
  set_current tok
  local var
  for var in CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY; do
    run env "${var}=1" cwtch profile env
    assert_status 0
    assert_output_contains "${var}"
    assert_output_contains "precedence"
  done
}

@test "env prints no warning when no overriding variable is set" {
  write_token_profile tok
  set_current tok
  run cwtch profile env
  assert_status 0
  assert_output_lacks "precedence"
}
