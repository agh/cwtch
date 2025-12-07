#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  export TEST_DIR="$(mktemp -d)"
  export HOME="${TEST_DIR}"
  export MOCK_BIN="${TEST_DIR}/bin"
  mkdir -p "${MOCK_BIN}"
  # Mock security command for keychain operations
  cat > "${MOCK_BIN}/security" << 'MOCK'
#!/bin/bash
MOCK_CRED="${HOME}/.mock-keychain-cred"
case "$1" in
  find-generic-password) [[ -f "${MOCK_CRED}" ]] && cat "${MOCK_CRED}" ;;
  delete-generic-password) rm -f "${MOCK_CRED}" ;;
  add-generic-password) shift; while [[ $# -gt 0 ]]; do [[ "$1" == "-w" ]] && { echo "$2" > "${MOCK_CRED}"; break; }; shift; done ;;
esac
MOCK
  chmod +x "${MOCK_BIN}/security"
  export PATH="${MOCK_BIN}:${BATS_TEST_DIRNAME}/../scripts:${PATH}"
}

teardown() {
  rm -rf "${TEST_DIR}"
}

@test "shows usage with no arguments" {
  run claude-switch.sh
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "shows usage with --help" {
  run claude-switch.sh --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "list shows no accounts when empty" {
  run claude-switch.sh list
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"No accounts saved"* ]]
}

@test "current shows none when no account active" {
  run claude-switch.sh current
  [[ "$status" -eq 0 ]]
  [[ "$output" == "(none)" ]]
}

@test "save fails without claude session" {
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  run --separate-stderr claude-switch.sh save test
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"No Claude session"* ]]
}

@test "save fails without keychain credential" {
  mkdir -p "${HOME}/.claude"
  run --separate-stderr claude-switch.sh save test
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"No credential in keychain"* ]]
}

@test "save succeeds with claude session and credential" {
  mkdir -p "${HOME}/.claude"
  echo "test-data" > "${HOME}/.claude/settings.json"
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"

  run claude-switch.sh save work
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Saved 'work'"* ]]
  [[ -d "${HOME}/.claude-accounts/work" ]]
  [[ -f "${HOME}/.claude-accounts/work/.credential" ]]
}

@test "list shows saved account" {
  mkdir -p "${HOME}/.claude"
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  claude-switch.sh save myaccount

  run claude-switch.sh list
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"myaccount"* ]]
  [[ "$output" == *"(active)"* ]]
}

@test "current shows active account after save" {
  mkdir -p "${HOME}/.claude"
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  claude-switch.sh save work

  run claude-switch.sh current
  [[ "$status" -eq 0 ]]
  [[ "$output" == "work" ]]
}

@test "use fails for nonexistent account" {
  run --separate-stderr claude-switch.sh use nonexistent
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"not found"* ]]
}

@test "use switches to saved account" {
  mkdir -p "${HOME}/.claude"
  echo "work-cred" > "${HOME}/.mock-keychain-cred"
  echo "work-data" > "${HOME}/.claude/settings.json"
  claude-switch.sh save work

  echo "personal-cred" > "${HOME}/.mock-keychain-cred"
  echo "personal-data" > "${HOME}/.claude/settings.json"
  claude-switch.sh save personal

  run claude-switch.sh use work
  [[ "$status" -eq 0 ]]
  [[ "$(cat "${HOME}/.claude/settings.json")" == "work-data" ]]
  [[ "$(cat "${HOME}/.mock-keychain-cred")" == "work-cred" ]]
}

@test "delete removes account" {
  mkdir -p "${HOME}/.claude"
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  claude-switch.sh save todelete

  run claude-switch.sh delete todelete
  [[ "$status" -eq 0 ]]
  [[ ! -d "${HOME}/.claude-accounts/todelete" ]]
}

@test "delete fails for nonexistent account" {
  run --separate-stderr claude-switch.sh delete nonexistent
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"not found"* ]]
}

@test "unknown command shows error" {
  run --separate-stderr claude-switch.sh badcommand
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"Unknown"* ]]
}
