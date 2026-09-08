#!/usr/bin/env bats
# Profiles — SPEC-v6 §1.1 (types and files), §1.2 (credential validation),
# §1.3 (save/save-key/save-token/setup/use/delete) and write_secret (§0).
# shellcheck disable=SC2154,SC2016,SC2312  # bats globals; child shells expand their own vars
bats_require_minimum_version 1.5.0

load helpers.bash

setup() { setup_test_env; }
teardown() { teardown_test_env; }

# --- §1.1 one credential file per profile ------------------------------------

@test "save-token writes .token at mode 600 and nothing else" {
  run bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token work'
  assert_status 0
  [[ -f "${HOME}/.cwtch/profiles/work/.token" ]]
  assert_file_mode "${HOME}/.cwtch/profiles/work/.token" 600
  [[ ! -f "${HOME}/.cwtch/profiles/work/.apikey" ]]
  [[ ! -f "${HOME}/.cwtch/profiles/work/.credential" ]]
}

@test "save-key writes .apikey at mode 600" {
  run bash -c 'printf "%s\n" "${TEST_APIKEY_A}" | cwtch profile save-key api'
  assert_status 0
  [[ -f "${HOME}/.cwtch/profiles/api/.apikey" ]]
  assert_file_mode "${HOME}/.cwtch/profiles/api/.apikey" 600
}

@test "profile save writes the Keychain credential at mode 600" {
  set_mock_credential "$(oauth_credential "${TEST_TOKEN_A}")"
  run cwtch profile save personal
  assert_status 0
  assert_file_mode "${HOME}/.cwtch/profiles/personal/.credential" 600
  [[ "$(profile_cred_token personal)" == "${TEST_TOKEN_A}" ]]
}

@test "profile save fails when the Keychain is empty" {
  clear_mock_credential
  run --separate-stderr cwtch profile save personal
  assert_status 1
  [[ ! -d "${HOME}/.cwtch/profiles/personal" ]]
}

@test "F14: saving a name as a different type removes the previous credential file" {
  run bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token dual'
  assert_status 0
  run bash -c 'printf "%s\n" "${TEST_APIKEY_A}" | cwtch profile save-key dual'
  assert_status 0
  [[ -f "${HOME}/.cwtch/profiles/dual/.apikey" ]]
  [[ ! -f "${HOME}/.cwtch/profiles/dual/.token" ]]
}

@test "F14: saving an OAuth snapshot over a token profile removes .token" {
  write_token_profile dual
  set_mock_credential "$(oauth_credential "${TEST_TOKEN_B}")"
  run cwtch profile save dual
  assert_status 0
  [[ -f "${HOME}/.cwtch/profiles/dual/.credential" ]]
  [[ ! -f "${HOME}/.cwtch/profiles/dual/.token" ]]
}

@test "F14: profile list flags a profile carrying more than one credential file" {
  write_token_profile mixed
  write_apikey_profile mixed
  run cwtch profile list
  assert_status 0
  assert_output_contains "mixed"
  assert_output_contains "(mixed!)"
}

@test "profile list labels each type" {
  write_token_profile tok
  write_apikey_profile key
  write_oauth_profile oauth
  run cwtch profile list
  assert_status 0
  assert_output_contains "(token)"
  assert_output_contains "(api-key)"
  assert_output_contains "(oauth)"
}

@test "profile list marks only the active profile" {
  write_token_profile one
  write_token_profile two
  set_current two
  run cwtch profile list
  assert_status 0
  assert_output_matches "two.*active"
  refute_output_matches "one.*active"
}

@test "profile list reports an empty store" {
  run cwtch profile list
  assert_status 0
  assert_output_contains "No profiles saved"
}

# --- §1.2 credential value validation ----------------------------------------

@test "save-token rejects a value that is not an sk-ant-oat01 token" {
  run --separate-stderr bash -c 'printf "%s\n" "sk-ant-api03-nope" | cwtch profile save-token work'
  assert_status 1
  assert_stderr_contains "unexpected format"
  [[ ! -f "${HOME}/.cwtch/profiles/work/.token" ]]
}

@test "save-token rejects a token that is too short" {
  run --separate-stderr bash -c 'printf "%s\n" "sk-ant-oat01-short" | cwtch profile save-token work'
  assert_status 1
  assert_stderr_contains "unexpected format"
}

@test "save-token never echoes the rejected value" {
  run bash -c 'printf "%s\n" "sk-ant-oat01-bad!secret9999" | cwtch profile save-token work 2>&1'
  assert_status 1
  assert_output_lacks "secret9999"
}

@test "save-key rejects a value with characters that break the documented eval" {
  local bad="AAAABBBBCCCC'DDDDEEEEFFFF"
  run --separate-stderr bash -c 'printf "%s\n" "$1" | cwtch profile save-key api' _ "${bad}"
  assert_status 1
  assert_stderr_contains "unexpected format"
  [[ ! -f "${HOME}/.cwtch/profiles/api/.apikey" ]]
}

@test "save-key rejects a key shorter than 20 characters" {
  run --separate-stderr bash -c 'printf "%s\n" "sk-ant-short" | cwtch profile save-key api'
  assert_status 1
  assert_stderr_contains "unexpected format"
}

@test "save-key accepts a plain 20+ character key" {
  run bash -c 'printf "%s\n" "AAAABBBBCCCCDDDDEEEE" | cwtch profile save-key api'
  assert_status 0
  [[ -f "${HOME}/.cwtch/profiles/api/.apikey" ]]
}

@test "save-token and save-key fail when nothing is supplied" {
  run --separate-stderr bash -c 'printf "\n" | cwtch profile save-token work'
  assert_status 1
  run --separate-stderr bash -c 'printf "\n" | cwtch profile save-key api'
  assert_status 1
}

# --- §0 write_secret ---------------------------------------------------------

@test "write_secret keeps one .bak of a replaced credential, also at mode 600" {
  run bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token work'
  assert_status 0
  run bash -c 'printf "%s\n" "${TEST_TOKEN_B}" | cwtch profile save-token work'
  assert_status 0
  [[ -f "${HOME}/.cwtch/profiles/work/.token.bak" ]]
  assert_file_mode "${HOME}/.cwtch/profiles/work/.token.bak" 600
  assert_file_contains "${HOME}/.cwtch/profiles/work/.token.bak" "${TEST_TOKEN_A}"
  assert_file_contains "${HOME}/.cwtch/profiles/work/.token" "${TEST_TOKEN_B}"
}

@test "write_secret keeps only the most recent .bak" {
  run bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token work'
  run bash -c 'printf "%s\n" "${TEST_TOKEN_B}" | cwtch profile save-token work'
  run bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token work'
  assert_status 0
  assert_file_contains "${HOME}/.cwtch/profiles/work/.token.bak" "${TEST_TOKEN_B}"
  [[ ! -f "${HOME}/.cwtch/profiles/work/.token.bak.bak" ]]
}

@test "write_secret makes no .bak when the content is unchanged" {
  run bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token work'
  run bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token work'
  assert_status 0
  [[ ! -f "${HOME}/.cwtch/profiles/work/.token.bak" ]]
}

# --- §1.3 profile use: OAuth -------------------------------------------------

@test "F12: switching away snapshots the outgoing OAuth credential into its profile" {
  write_oauth_profile personal "${TEST_TOKEN_A}"
  write_oauth_profile work "${TEST_TOKEN_B}"
  set_current personal
  # Claude Code refreshed the live login in place while 'personal' was current.
  set_mock_credential "$(oauth_credential refreshed-v2)"

  run cwtch profile use work
  assert_status 0
  [[ "$(profile_cred_token personal)" == "refreshed-v2" ]]
  [[ "$(keychain_token)" == "${TEST_TOKEN_B}" ]]
}

@test "F12: the outgoing snapshot is skipped when the Keychain holds no parsable credential" {
  write_oauth_profile personal "${TEST_TOKEN_A}"
  write_oauth_profile work "${TEST_TOKEN_B}"
  set_current personal
  set_mock_credential "not json at all"

  run cwtch profile use work
  assert_status 0
  [[ "$(profile_cred_token personal)" == "${TEST_TOKEN_A}" ]]
  [[ "$(keychain_token)" == "${TEST_TOKEN_B}" ]]
}

@test "F12: no snapshot is taken when the outgoing profile is a token profile" {
  write_token_profile tok
  write_oauth_profile work "${TEST_TOKEN_B}"
  set_current tok
  set_mock_credential "$(oauth_credential live-login)"

  run cwtch profile use work
  assert_status 0
  [[ ! -f "${HOME}/.cwtch/profiles/tok/.credential" ]]
}

@test "F4: the Keychain is updated in place, never deleted then re-added" {
  write_oauth_profile work "${TEST_TOKEN_B}"
  set_mock_credential "$(oauth_credential "${TEST_TOKEN_A}")"
  run cwtch profile use work
  assert_status 0
  run security_calls
  assert_output_contains "call=add-generic-password"
  assert_output_contains "update=1"
  assert_output_lacks "call=delete-generic-password"
}

@test "F4: the Keychain write carries the expected service and account" {
  write_oauth_profile work "${TEST_TOKEN_B}"
  run cwtch profile use work
  assert_status 0
  run security_calls
  assert_output_contains "service=Claude Code-credentials"
  assert_output_contains "account=${USER:-$(id -un)}"
}

@test "F4: a failed Keychain update changes nothing and reports it" {
  write_oauth_profile personal "${TEST_TOKEN_A}"
  write_oauth_profile work "${TEST_TOKEN_B}"
  set_current personal
  set_mock_credential "$(oauth_credential "${TEST_TOKEN_A}")"
  fail_keychain_writes

  run --separate-stderr cwtch profile use work
  assert_status 1
  assert_stderr_contains "Keychain update failed"
  [[ "$(current_file_contents)" == "personal" ]]
  [[ "$(keychain_token)" == "${TEST_TOKEN_A}" ]]
}

@test "profile use on an OAuth profile writes .current and announces the type" {
  write_oauth_profile work "${TEST_TOKEN_B}"
  run cwtch profile use work
  assert_status 0
  assert_output_contains "Switched to 'work' (oauth)"
  [[ "$(current_file_contents)" == "work" ]]
}

@test "profile use with USER unset still writes the Keychain with the login name" {
  write_oauth_profile work "${TEST_TOKEN_B}"
  run env -u USER cwtch profile use work
  assert_status 0
  [[ "$(keychain_token)" == "${TEST_TOKEN_B}" ]]
}

# --- §1.3 profile use: token and api-key -------------------------------------

@test "profile use on a token profile prints the shell hint and touches no Keychain" {
  write_token_profile tok
  run cwtch profile use tok
  assert_status 0
  assert_output_contains "Switched to 'tok' (token)"
  assert_output_contains 'eval "$(cwtch profile env)"'
  [[ "$(current_file_contents)" == "tok" ]]
  [[ -z "$(security_calls)" ]]
}

@test "profile use on an api-key profile prints the shell hint" {
  write_apikey_profile api
  run cwtch profile use api
  assert_status 0
  assert_output_contains "Switched to 'api' (api-key)"
  assert_output_contains 'eval "$(cwtch profile env)"'
}

@test "profile use fails for a profile that does not exist" {
  run --separate-stderr cwtch profile use ghost
  assert_status 1
  assert_stderr_contains "ghost"
  [[ ! -f "${HOME}/.cwtch/.current" ]]
}

# --- §1.3 profile delete -----------------------------------------------------

@test "profile delete removes the profile directory" {
  write_token_profile work
  run cwtch profile delete work
  assert_status 0
  [[ ! -d "${HOME}/.cwtch/profiles/work" ]]
}

@test "profile delete clears .current when the deleted profile was active" {
  write_token_profile work
  set_current work
  run cwtch profile delete work
  assert_status 0
  [[ ! -f "${HOME}/.cwtch/.current" ]]
}

@test "profile delete leaves .current alone when another profile is active" {
  write_token_profile work
  write_token_profile other
  set_current other
  run cwtch profile delete work
  assert_status 0
  [[ "$(current_file_contents)" == "other" ]]
}

@test "profile delete fails for a profile that does not exist" {
  run --separate-stderr cwtch profile delete ghost
  assert_status 1
}

# --- §1.3 profile setup ------------------------------------------------------

@test "profile setup extracts the token from claude setup-token output" {
  set_claude_mode token
  run cwtch profile setup ci
  assert_status 0
  [[ -f "${HOME}/.cwtch/profiles/ci/.token" ]]
  assert_file_contains "${HOME}/.cwtch/profiles/ci/.token" "${TEST_TOKEN_A}"
}

@test "profile setup invokes exactly 'claude setup-token'" {
  set_claude_mode token
  run cwtch profile setup ci
  assert_status 0
  run claude_calls
  assert_output_contains "argv=setup-token"
}

@test "profile setup joins a token that the CLI wrapped across lines" {
  set_claude_mode token-wrapped
  run cwtch profile setup ci
  assert_status 0
  assert_file_contains "${HOME}/.cwtch/profiles/ci/.token" "${TEST_TOKEN_A}"
}

@test "profile setup never echoes the raw claude output" {
  set_claude_mode token
  run cwtch profile setup ci
  assert_status 0
  assert_output_lacks "${TEST_TOKEN_A}"
}

@test "profile setup fails when the output holds no token" {
  set_claude_mode token-none
  run --separate-stderr cwtch profile setup ci
  assert_status 1
  assert_stderr_contains "Could not find a token"
  [[ ! -f "${HOME}/.cwtch/profiles/ci/.token" ]]
}

@test "profile setup refuses to guess between multiple candidate tokens" {
  set_claude_mode token-two
  run --separate-stderr cwtch profile setup ci
  assert_status 1
  assert_stderr_contains "Found 2 candidate tokens"
  [[ ! -f "${HOME}/.cwtch/profiles/ci/.token" ]]
}

@test "profile setup fails when claude setup-token fails" {
  set_claude_mode fail
  run --separate-stderr cwtch profile setup ci
  assert_status 1
  [[ ! -f "${HOME}/.cwtch/profiles/ci/.token" ]]
}

@test "profile setup leaves no temporary file behind and prints the shell hint" {
  set_claude_mode token
  run cwtch profile setup ci
  assert_status 0
  assert_output_contains 'eval "$(cwtch profile env)"'
  run bash -c 'ls -A "${TMPDIR}"'
  [[ -z "${output}" ]]
}

@test "profile setup validates the name before running claude" {
  set_claude_mode token
  run --separate-stderr cwtch profile setup ../evil
  assert_status 1
  assert_stderr_contains "Invalid name"
  [[ -z "$(claude_calls)" ]]
}

# --- §1.4 profile token / api-key --------------------------------------------

@test "profile token prints the active token profile's token" {
  write_token_profile tok
  set_current tok
  run cwtch profile token
  assert_status 0
  [[ "${output}" == "${TEST_TOKEN_A}" ]]
}

@test "profile token fails for a non-token profile" {
  write_apikey_profile api
  set_current api
  run --separate-stderr cwtch profile token
  assert_status 1
  assert_stderr_contains "token"
}

@test "profile api-key prints the active api-key profile's key" {
  write_apikey_profile api
  set_current api
  run cwtch profile api-key
  assert_status 0
  [[ "${output}" == "${TEST_APIKEY_A}" ]]
}

@test "profile api-key fails for an OAuth profile" {
  write_oauth_profile personal
  set_current personal
  run --separate-stderr cwtch profile api-key
  assert_status 1
}

@test "profile current prints the active profile and (none) otherwise" {
  run cwtch profile current
  assert_status 0
  [[ "${output}" == "(none)" ]]
  write_token_profile work
  set_current work
  run cwtch profile current
  assert_status 0
  [[ "${output}" == "work" ]]
}
