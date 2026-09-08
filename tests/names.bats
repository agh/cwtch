#!/usr/bin/env bats
# Name validation — SPEC-v6 §0 (validate_name, current_profile) and §2.1 (`as:`).
# Regression tests for audit item 1: unvalidated names become paths.
# shellcheck disable=SC2154,SC2016,SC2312  # bats globals; child shells expand their own vars
bats_require_minimum_version 1.5.0

load helpers.bash

setup() { setup_test_env; }
teardown() { teardown_test_env; }

# --- profile names -----------------------------------------------------------

@test "F1: profile save-key refuses a traversing name and writes nothing outside the store" {
  mkdir -p "${HOME}/.cwtch/sources/victim"
  run --separate-stderr bash -c 'printf "%s\n" "${TEST_APIKEY_A}" | cwtch profile save-key ../sources/evil'
  assert_status 1
  assert_stderr_contains "Invalid name"
  [[ ! -e "${HOME}/.cwtch/sources/evil" ]]
  [[ -d "${HOME}/.cwtch/sources/victim" ]]
}

@test "F1: profile save-token refuses a traversing name" {
  run --separate-stderr bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token ../evil'
  assert_status 1
  assert_stderr_contains "Invalid name"
  [[ ! -e "${HOME}/.cwtch/evil" ]]
}

@test "F1: profile save refuses an empty name and does not write profiles/.credential" {
  set_mock_credential "$(oauth_credential "${TEST_TOKEN_A}")"
  run --separate-stderr cwtch profile save ""
  assert_status 1
  [[ ! -f "${HOME}/.cwtch/profiles/.credential" ]]
  [[ ! -s "${HOME}/.cwtch/.current" ]]
}

@test "F1: profile delete refuses a traversing name and leaves the sibling directory" {
  mkdir -p "${HOME}/.cwtch/sources/keepme"
  write_token_profile work
  run --separate-stderr cwtch profile delete ../sources/keepme
  assert_status 1
  assert_stderr_contains "Invalid name"
  [[ -d "${HOME}/.cwtch/sources/keepme" ]]
}

@test "F1: profile delete refuses a profile whose realpath is outside the store" {
  mkdir -p "${HOME}/elsewhere/decoy"
  mkdir -p "${HOME}/.cwtch/profiles"
  ln -s "${HOME}/elsewhere/decoy" "${HOME}/.cwtch/profiles/decoy"
  run --separate-stderr cwtch profile delete decoy
  assert_status 1
  [[ -d "${HOME}/elsewhere/decoy" ]]
}

@test "F1: profile use refuses a traversing name" {
  run --separate-stderr cwtch profile use ../../etc
  assert_status 1
  assert_stderr_contains "Invalid name"
}

@test "validate_name rejects '.' and '..'" {
  run --separate-stderr cwtch profile use .
  assert_status 1
  assert_stderr_contains "Invalid name"
  run --separate-stderr cwtch profile use ..
  assert_status 1
  assert_stderr_contains "Invalid name"
}

@test "validate_name rejects a leading dash, dot and slash" {
  local bad
  for bad in "-lead" ".hidden" "a/b"; do
    run --separate-stderr cwtch profile use "${bad}"
    assert_status 1
    assert_stderr_contains "Invalid name"
  done
}

@test "validate_name rejects names longer than 64 characters" {
  local long65 long64
  long65="$(repeat_char a 65)"
  long64="$(repeat_char b 64)"
  run --separate-stderr bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token "$1"' _ "${long65}"
  assert_status 1
  assert_stderr_contains "Invalid name"
  run bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token "$1"' _ "${long64}"
  assert_status 0
  [[ -f "${HOME}/.cwtch/profiles/${long64}/.token" ]]
}

@test "validate_name accepts letters, digits, dot, underscore and dash" {
  local good
  for good in "work" "Work2" "a.b" "a_b" "a-b" "0"; do
    run bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token "$1"' _ "${good}"
    assert_status 0
    [[ -f "${HOME}/.cwtch/profiles/${good}/.token" ]]
  done
}

@test "invalid name error message names the offending value and the allowed set" {
  run --separate-stderr cwtch profile use "bad name"
  assert_status 1
  assert_stderr_contains "bad name"
  assert_stderr_contains "max 64"
}

# --- .current ----------------------------------------------------------------

@test "an invalid .current is ignored with a one-line warning" {
  write_token_profile work
  printf '%s\n' "../escape" > "${HOME}/.cwtch/.current"
  run --separate-stderr cwtch profile list
  assert_status 0
  assert_stderr_contains "Ignoring invalid .current"
  assert_output_lacks "active"
}

@test "an invalid .current makes profile env report no active profile" {
  write_token_profile work
  printf '%s\n' ".." > "${HOME}/.cwtch/.current"
  run --separate-stderr cwtch profile env
  assert_status 1
  assert_stderr_contains "No profile active"
}

@test "an empty .current is treated as no profile" {
  write_token_profile work
  : > "${HOME}/.cwtch/.current"
  run cwtch status
  assert_status 0
  assert_output_contains "No profile active"
}

@test "a valid .current naming a missing profile does not crash status" {
  set_current "ghost"
  run cwtch status
  assert_status 0
}

# --- Cwtchfile `as:` and `ref:` ----------------------------------------------

@test "F1: sync check rejects a traversing 'as' namespace" {
  create_cwtchfile "sources:
  - repo: owner/repo
    as: ../projects
    agents: agents/"
  run --separate-stderr cwtch sync check
  assert_status 1
  assert_stderr_contains "Invalid name"
}

@test "F1: sync never touches ~/.claude/projects for a traversing 'as'" {
  local repo
  repo="$(create_mock_repo demo)"
  mkdir -p "${HOME}/.claude/projects"
  printf 'session history\n' > "${HOME}/.claude/projects/keep.json"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: ../projects
    agents: agents/"
  run cwtch sync
  assert_status 1
  [[ -f "${HOME}/.claude/projects/keep.json" ]]
  [[ ! -L "${HOME}/.claude/projects" ]]
}

@test "F1: sync check rejects a ref that begins with a dash" {
  create_cwtchfile "sources:
  - repo: owner/x
    ref: --upload-pack=touch /tmp/pwned
    as: demo
    agents: agents/"
  run --separate-stderr cwtch sync check
  assert_status 1
}

@test "F1: a ref that is not a valid git ref is rejected" {
  create_cwtchfile "sources:
  - repo: owner/x
    ref: bad..ref
    as: demo
    agents: agents/"
  run --separate-stderr cwtch sync check
  assert_status 1
}

@test "valid refs pass validation" {
  local repo
  repo="$(create_mock_repo demo)"
  repo_add_branch "${repo}" "feature/x" "skills/extra/SKILL.md" "extra"
  create_cwtchfile "sources:
  - repo: ${repo}
    ref: feature/x
    as: demo
    agents: agents/"
  run cwtch sync check
  assert_status 0
}
