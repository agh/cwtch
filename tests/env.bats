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

@test "F6: an OAuth profile prints only shell statements and explains Keychain on stderr" {
  write_oauth_profile personal
  set_current personal
  run --separate-stderr cwtch profile env
  assert_status 0
  [[ "${output}" == "unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY" ]]
  assert_stderr_contains "OAuth profile 'personal'"
  assert_stderr_contains "Keychain"
}

@test "F6: switching from a token profile to OAuth clears the stale variable" {
  write_token_profile tok
  write_oauth_profile personal
  set_current tok
  run --separate-stderr bash -c 'cwtch_env="$(cwtch profile env)" && eval "${cwtch_env}"; printf "%s\n" "${CLAUDE_CODE_OAUTH_TOKEN:-unset}"'
  assert_status 0
  [[ "${output}" == "${TEST_TOKEN_A}" ]]

  set_current personal
  run --separate-stderr bash -c 'export CLAUDE_CODE_OAUTH_TOKEN=stale; cwtch_env="$(cwtch profile env)" && eval "${cwtch_env}"; printf "%s\n" "${CLAUDE_CODE_OAUTH_TOKEN:-unset}"'
  assert_status 0
  [[ "${output}" == "unset" ]]
}

@test "the checked env output evaluates for every profile type in bash and available zsh" {
  write_token_profile tok
  write_apikey_profile api
  write_oauth_profile oauth
  local shell
  for shell in bash zsh; do
    if ! command -v "${shell}" >/dev/null 2>&1; then
      continue
    fi
    set_current tok
    run --separate-stderr "${shell}" -f -c 'set -eu; export ANTHROPIC_API_KEY=stale; cwtch_env="$(cwtch profile env)" && eval "${cwtch_env}"; test "${CLAUDE_CODE_OAUTH_TOKEN}" = "${TEST_TOKEN_A}"; test "${ANTHROPIC_API_KEY:-unset}" = unset'
    assert_status 0
    set_current api
    run --separate-stderr "${shell}" -f -c 'set -eu; export CLAUDE_CODE_OAUTH_TOKEN=stale; cwtch_env="$(cwtch profile env)" && eval "${cwtch_env}"; test "${ANTHROPIC_API_KEY}" = "${TEST_APIKEY_A}"; test "${CLAUDE_CODE_OAUTH_TOKEN:-unset}" = unset'
    assert_status 0
    set_current oauth
    run --separate-stderr "${shell}" -f -c 'set -eu; export CLAUDE_CODE_OAUTH_TOKEN=stale ANTHROPIC_API_KEY=stale; cwtch_env="$(cwtch profile env)" && eval "${cwtch_env}"; test "${CLAUDE_CODE_OAUTH_TOKEN:-unset}" = unset; test "${ANTHROPIC_API_KEY:-unset}" = unset'
    assert_status 0
  done
}

@test "the checked env recipe returns failure visibly without evaluating empty output" {
  run --separate-stderr bash -c 'cwtch_env="$(cwtch profile env)" && eval "${cwtch_env}"'
  assert_status 1
  assert_stderr_contains "No profile active"
  [[ -z "${output}" ]]
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
  run --separate-stderr env ANTHROPIC_AUTH_TOKEN=something cwtch profile env
  assert_status 0
  assert_stderr_contains "! ANTHROPIC_AUTH_TOKEN"
  assert_stderr_contains "precedence"
  assert_output_lacks "ANTHROPIC_AUTH_TOKEN"
  assert_output_lacks "precedence"
}

@test "F6: env warns about each cloud-provider override" {
  write_token_profile tok
  set_current tok
  local var
  for var in CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY; do
    run --separate-stderr env "${var}=1" cwtch profile env
    assert_status 0
    assert_stderr_contains "${var}"
    assert_stderr_contains "precedence"
    assert_output_lacks "${var}"
    assert_output_lacks "precedence"
  done
}

@test "env prints no warning when no overriding variable is set" {
  write_token_profile tok
  set_current tok
  run cwtch profile env
  assert_status 0
  assert_output_lacks "precedence"
}
