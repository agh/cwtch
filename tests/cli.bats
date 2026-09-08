#!/usr/bin/env bats
# CLI surface — dispatch, help, `edit`, the deprecated `refresh` (SPEC-v6 §1.5),
# exit codes (§1.9) and output hygiene (§0).
# shellcheck disable=SC2154,SC2016,SC2312  # bats globals; child shells expand their own vars
bats_require_minimum_version 1.5.0

load helpers.bash

setup() { setup_test_env; }
teardown() { teardown_test_env; }

# --- dispatch ----------------------------------------------------------------

@test "no arguments prints the help and exits 0" {
  run cwtch
  assert_status 0
  assert_output_contains "USAGE"
}

@test "-h and --help print the help and exit 0" {
  run cwtch -h
  assert_status 0
  assert_output_contains "USAGE"
  run cwtch --help
  assert_status 0
  assert_output_contains "USAGE"
}

@test "an unknown command is a user error on stderr" {
  run --separate-stderr cwtch badcommand
  assert_status 1
  assert_stderr_contains "badcommand"
}

@test "an unknown sync subcommand is a user error" {
  run --separate-stderr cwtch sync bogus
  assert_status 1
  assert_stderr_contains "bogus"
}

@test "an unknown profile subcommand is a user error" {
  run --separate-stderr cwtch profile bogus
  assert_status 1
  assert_stderr_contains "bogus"
}

@test "profile with no subcommand is a user error" {
  run --separate-stderr cwtch profile
  assert_status 1
  [[ -n "${stderr}" ]]
}

@test "profile subcommands that need a name report the missing name" {
  local sub
  for sub in save save-key save-token setup use delete; do
    run --separate-stderr cwtch profile "${sub}"
    assert_status 1
    [[ -n "${stderr}" ]]
  done
}

@test "edit opens the Cwtchfile with EDITOR" {
  run env EDITOR=echo cwtch edit
  assert_status 0
  assert_output_contains "${HOME}/.cwtch/Cwtchfile"
}

# --- §1.5 refresh is deprecated ----------------------------------------------

@test "F16: refresh explains that it does nothing and exits 0" {
  write_oauth_profile personal
  run --separate-stderr cwtch refresh
  assert_status 0
  assert_stderr_contains "deprecated"
  assert_stderr_contains "/login"
  [[ -z "${output}" ]]
}

@test "F16: refresh -q says nothing at all" {
  write_oauth_profile personal
  run --separate-stderr cwtch refresh -q
  assert_status 0
  [[ -z "${output}" ]]
  [[ -z "${stderr}" ]]
}

@test "F16: refresh --quiet is silent wherever it appears in the arguments" {
  write_oauth_profile personal
  run --separate-stderr cwtch refresh personal --quiet
  assert_status 0
  [[ -z "${output}" ]]
  [[ -z "${stderr}" ]]
}

@test "F16: refresh with a profile name still exits 0" {
  write_token_profile tok
  run --separate-stderr cwtch refresh tok
  assert_status 0
}

@test "F16: refresh with no profiles at all exits 0" {
  run --separate-stderr cwtch refresh
  assert_status 0
}

@test "F16: refresh never spends a model turn or touches the Keychain" {
  write_oauth_profile personal
  set_mock_credential "$(oauth_credential "${TEST_TOKEN_A}")"
  run --separate-stderr cwtch refresh
  assert_status 0
  [[ -z "$(claude_calls)" ]]
  [[ -z "$(security_calls)" ]]
  [[ "$(keychain_token)" == "${TEST_TOKEN_A}" ]]
}

@test "F16: refresh does not rewrite a stored credential" {
  write_oauth_profile personal "${TEST_TOKEN_A}"
  set_mock_credential "$(oauth_credential "${TEST_TOKEN_B}")"
  run --separate-stderr cwtch refresh
  assert_status 0
  [[ "$(profile_cred_token personal)" == "${TEST_TOKEN_A}" ]]
}

# --- §1.9 exit codes ---------------------------------------------------------

@test "successful commands exit 0" {
  write_token_profile tok
  set_current tok
  create_cwtchfile "sources: []"
  run cwtch status
  assert_status 0
  run cwtch usage
  assert_status 0
  run cwtch profile list
  assert_status 0
  run cwtch profile current
  assert_status 0
  run cwtch sync check
  assert_status 0
  run cwtch sync
  assert_status 0
}

@test "user errors exit 1" {
  run --separate-stderr cwtch profile use ghost
  assert_status 1
  run --separate-stderr cwtch sync check
  assert_status 1
  run --separate-stderr cwtch profile env
  assert_status 1
  run --separate-stderr cwtch badcommand
  assert_status 1
}

@test "every error message reaches stderr, never stdout" {
  run --separate-stderr cwtch profile use ghost
  assert_status 1
  [[ -z "${output}" ]]
  [[ -n "${stderr}" ]]
}

# --- §0 output hygiene -------------------------------------------------------

@test "user-controlled text is printed literally, not as escape sequences" {
  run --separate-stderr cwtch profile use 'evil\e[31mred'
  assert_status 1
  assert_stderr_contains '\e[31m'
  [[ "${stderr}" != *$'\033'* ]]
}

@test "NO_COLOR suppresses every escape sequence" {
  write_token_profile tok
  set_current tok
  local cmd
  for cmd in status "profile list" usage; do
    run env NO_COLOR=1 bash -c "cwtch ${cmd}"
    assert_status 0
    [[ "${output}" != *$'\033'* ]]
    assert_output_lacks '\033'
  done
  create_cwtchfile "sources: []"
  run env NO_COLOR=1 cwtch sync check
  assert_status 0
  [[ "${output}" != *$'\033'* ]]
}

@test "TERM=dumb with NO_COLOR unset still produces no escape sequences" {
  write_token_profile tok
  set_current tok
  run env -u NO_COLOR TERM=dumb cwtch status
  assert_status 0
  [[ "${output}" != *$'\033'* ]]
}

@test "output piped to a file carries no escape sequences" {
  write_token_profile tok
  set_current tok
  run env -u NO_COLOR TERM=xterm-256color bash -c 'cwtch status > "${TEST_DIR}/out.txt" 2>&1'
  assert_status 0
  refute_file_matches "${TEST_DIR}/out.txt" $'\033'
}

@test "no command leaves a literal backslash-escape in its output" {
  create_cwtchfile "sources: []"
  run cwtch status
  assert_status 0
  assert_output_lacks '\033'
  assert_output_lacks '\n'
  run cwtch --help
  assert_status 0
  assert_output_lacks '\033'
}
