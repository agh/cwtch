#!/usr/bin/env bats
# Named child-process activation, without changing the global selection.
# shellcheck disable=SC2154,SC2016,SC2312
bats_require_minimum_version 1.5.0

load helpers.bash

setup() {
  setup_test_env
  cat > "${TEST_DIR}/probe" <<'PROBE'
#!/bin/bash
token="${CLAUDE_CODE_OAUTH_TOKEN:-}"
key="${ANTHROPIC_API_KEY:-}"
printf 'profile=%s token_set=%s token_len=%s key_set=%s key_len=%s\n' \
  "${CWTCH_PROFILE:-}" "${CLAUDE_CODE_OAUTH_TOKEN+yes}" "${#token}" \
  "${ANTHROPIC_API_KEY+yes}" "${#key}"
printf 'argc=%s\n' "$#"
for arg in "$@"; do
  printf 'arg=<%s>\n' "${arg}"
done
PROBE
  chmod +x "${TEST_DIR}/probe"
}

teardown() { teardown_test_env; }

@test "run exports only the selected token and label to the child" {
  write_token_profile work
  run --separate-stderr env ANTHROPIC_API_KEY=stale CLAUDE_CODE_OAUTH_TOKEN=stale \
    CWTCH_PROFILE=stale cwtch run work "${TEST_DIR}/probe"
  assert_status 0
  [[ "${output}" == "profile=work token_set=yes token_len=${#TEST_TOKEN_A} key_set= key_len=0"$'\nargc=0' ]]
  [[ -z "${stderr}" ]]
  assert_output_lacks "${TEST_TOKEN_A}"
}

@test "run exports only the selected API key and label to the child" {
  write_apikey_profile api
  run --separate-stderr env CLAUDE_CODE_OAUTH_TOKEN=stale ANTHROPIC_API_KEY=stale \
    cwtch run api "${TEST_DIR}/probe"
  assert_status 0
  [[ "${output}" == "profile=api token_set= token_len=0 key_set=yes key_len=${#TEST_APIKEY_A}"$'\nargc=0' ]]
  [[ -z "${stderr}" ]]
  assert_output_lacks "${TEST_APIKEY_A}"
}

@test "run preserves spaces, empty arguments, globs, and a second separator" {
  write_token_profile work
  run cwtch run work -- "${TEST_DIR}/probe" 'two words' '' '*.bats' -- '-n' 'a\b'
  assert_status 0
  [[ "${lines[1]}" == "argc=6" ]]
  [[ "${lines[2]}" == "arg=<two words>" ]]
  [[ "${lines[3]}" == "arg=<>" ]]
  [[ "${lines[4]}" == "arg=<*.bats>" ]]
  [[ "${lines[5]}" == "arg=<-->" ]]
  [[ "${lines[6]}" == "arg=<-n>" ]]
  [[ "${lines[7]}" == 'arg=<a\b>' ]]

  run -127 --separate-stderr cwtch run work -- -- "${TEST_DIR}/probe"
  assert_status 127
  [[ -z "${output}" ]]
}

@test "run defaults to the claude mock with or without a separator" {
  write_token_profile work
  run env MOCK_CLAUDE_MODE=run cwtch run work
  assert_status 0
  [[ "${output}" == "profile=work" ]]
  run env MOCK_CLAUDE_MODE=run cwtch run work --
  assert_status 0
  [[ "${output}" == "profile=work" ]]
  [[ "$(claude_calls)" == $'argv=\nargv=' ]]
}

@test "run can pass non-setup arguments to claude" {
  write_token_profile work
  run env MOCK_CLAUDE_MODE=run EXPECT_CLAUDE_ARGV='--resume example' cwtch run work claude --resume example
  assert_status 0
  [[ "$(claude_calls)" == 'argv=--resume example' ]]
  refute_file_contains "${CLAUDE_CALLS}" "${TEST_TOKEN_A}"
}

@test "run propagates the child exit status" {
  write_token_profile work
  run cwtch run work sh -c 'exit 7'
  assert_status 7
}

@test "run execs the child in place and preserves signal termination" {
  write_token_profile work
  run bash -c 'export expected_pid=$$; exec cwtch run work sh -c '\''test "$$" = "${expected_pid}"'\'''
  assert_status 0
  run cwtch run work sh -c 'kill -TERM "$$"'
  assert_status 143
}

@test "run leaves selection and Keychain ownership untouched and unread" {
  write_token_profile work
  set_current '../invalid'
  printf '%s\n' '../owner' > "${HOME}/.cwtch/.keychain-owner"
  run --separate-stderr cwtch run work "${TEST_DIR}/probe"
  assert_status 0
  [[ -z "${stderr}" ]]
  [[ "$(current_file_contents)" == '../invalid' ]]
  [[ "$(cat "${HOME}/.cwtch/.keychain-owner")" == '../owner' ]]
  [[ -z "$(security_calls)" ]]
}

@test "run does not create selection or ownership files" {
  write_token_profile work
  run cwtch run work "${TEST_DIR}/probe"
  assert_status 0
  [[ ! -e "${HOME}/.cwtch/.current" ]]
  [[ ! -e "${HOME}/.cwtch/.keychain-owner" ]]
}

@test "run rejects missing, unknown, invalid, mixed, empty, and OAuth profiles" {
  run --separate-stderr cwtch run
  assert_status 1
  assert_stderr_contains "Usage:"
  write_oauth_profile oauth
  write_token_profile mixed
  write_apikey_profile mixed
  mkdir -p "${HOME}/.cwtch/profiles/empty"
  local name
  for name in ghost '../outside' '' "bad'name" empty mixed oauth; do
    run --separate-stderr cwtch run "${name}" "${TEST_DIR}/probe"
    assert_status 1
    [[ -z "${output}" ]]
    [[ -n "${stderr}" ]]
  done
  assert_stderr_contains "Keychain login is global"
  assert_stderr_contains "cwtch profile use oauth"
  [[ -z "$(security_calls)" ]]
}

@test "run rejects malformed stored credentials without exposing them" {
  write_token_profile bad-token "sk-ant-oat01-invalid!secret"
  write_apikey_profile bad-key "api-key'bad-secret"
  local name
  for name in bad-token bad-key; do
    run --separate-stderr cwtch run "${name}" "${TEST_DIR}/probe"
    assert_status 1
    [[ -z "${output}" ]]
    assert_stderr_contains "unexpected format"
    [[ "${stderr}" != *"secret"* ]]
  done
}

@test "run keeps every precedence warning on stderr before the child executes" {
  write_token_profile work
  local var
  for var in ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY; do
    run --separate-stderr env "${var}=1" cwtch run work "${TEST_DIR}/probe"
    assert_status 0
    assert_stderr_contains "${var}"
    assert_stderr_contains "precedence"
    assert_output_lacks "precedence"
  done
  run bash -c 'ANTHROPIC_AUTH_TOKEN=1 cwtch run work sh -c '\''printf "%s\n" child >&2'\'' 2>&1'
  assert_status 0
  [[ "${lines[0]}" == *"precedence"* ]]
  [[ "${lines[1]}" == child ]]
}

@test "run returns 127 for a missing command" {
  write_token_profile work
  run -127 --separate-stderr cwtch run work cwtch-command-that-does-not-exist
  assert_status 127
  [[ -z "${output}" ]]
  assert_stderr_contains "not found"
}
