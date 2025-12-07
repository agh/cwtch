#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  export TEST_DIR="$(mktemp -d)"
  export HOME="${TEST_DIR}"
  export MOCK_BIN="${TEST_DIR}/bin"
  mkdir -p "${MOCK_BIN}"
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
  export PATH="${MOCK_BIN}:${BATS_TEST_DIRNAME}/../bin:${PATH}"
}

teardown() {
  rm -rf "${TEST_DIR}"
}

@test "shows usage with no arguments" {
  run cwtch
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "shows usage with --help" {
  run cwtch --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "profile list shows no profiles when empty" {
  run cwtch profile list
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"No profiles saved"* ]]
}

@test "profile current shows none when no profile active" {
  run cwtch profile current
  [[ "$status" -eq 0 ]]
  [[ "$output" == "(none)" ]]
}

@test "profile save fails without claude session" {
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  run --separate-stderr cwtch profile save test
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"No Claude session"* ]]
}

@test "profile save fails without keychain credential" {
  mkdir -p "${HOME}/.claude"
  run --separate-stderr cwtch profile save test
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"No credential in keychain"* ]]
}

@test "profile save succeeds with session and credential" {
  mkdir -p "${HOME}/.claude"
  echo "test-data" > "${HOME}/.claude/settings.json"
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  run cwtch profile save work
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Saved 'work'"* ]]
  [[ -d "${HOME}/.claude-accounts/work" ]]
  [[ -f "${HOME}/.claude-accounts/work/.credential" ]]
}

@test "profile list shows saved profile" {
  mkdir -p "${HOME}/.claude"
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  cwtch profile save myprofile
  run cwtch profile list
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"myprofile"* ]]
  [[ "$output" == *"active"* ]]
}

@test "profile current shows active profile after save" {
  mkdir -p "${HOME}/.claude"
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  cwtch profile save work
  run cwtch profile current
  [[ "$status" -eq 0 ]]
  [[ "$output" == "work" ]]
}

@test "profile use fails for nonexistent profile" {
  run --separate-stderr cwtch profile use nonexistent
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"not found"* ]]
}

@test "profile use switches to saved profile" {
  mkdir -p "${HOME}/.claude"
  echo "work-cred" > "${HOME}/.mock-keychain-cred"
  echo "work-data" > "${HOME}/.claude/settings.json"
  cwtch profile save work

  echo "personal-cred" > "${HOME}/.mock-keychain-cred"
  echo "personal-data" > "${HOME}/.claude/settings.json"
  cwtch profile save personal

  run cwtch profile use work
  [[ "$status" -eq 0 ]]
  [[ "$(cat "${HOME}/.claude/settings.json")" == "work-data" ]]
  [[ "$(cat "${HOME}/.mock-keychain-cred")" == "work-cred" ]]
}

@test "profile delete removes profile" {
  mkdir -p "${HOME}/.claude"
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  cwtch profile save todelete
  run cwtch profile delete todelete
  [[ "$status" -eq 0 ]]
  [[ ! -d "${HOME}/.claude-accounts/todelete" ]]
}

@test "profile delete fails for nonexistent profile" {
  run --separate-stderr cwtch profile delete nonexistent
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"not found"* ]]
}

@test "usage shows no profiles when empty" {
  run cwtch usage
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"No profiles saved"* ]]
}

@test "status shows current profile" {
  mkdir -p "${HOME}/.claude"
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  cwtch profile save myprofile
  run cwtch status
  # Status may fail due to invalid mock credential JSON, but should still show profile
  [[ "$output" == *"Profile: myprofile"* ]]
}

@test "unknown command shows error" {
  run --separate-stderr cwtch badcommand
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"Unknown"* ]]
}

@test "profile save-key saves api key profile" {
  echo "sk-ant-test123" | cwtch profile save-key apitest
  run cwtch profile list
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"apitest"* ]]
  [[ "$output" == *"api-key"* ]]
  [[ -f "${HOME}/.claude-accounts/apitest/.apikey" ]]
}

@test "profile api-key outputs current api key" {
  echo "sk-ant-test456" | cwtch profile save-key mykey
  run cwtch profile api-key
  [[ "$status" -eq 0 ]]
  [[ "$output" == "sk-ant-test456" ]]
}

@test "profile api-key fails for oauth profile" {
  mkdir -p "${HOME}/.claude"
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  cwtch profile save oauthprofile
  run --separate-stderr cwtch profile api-key
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"not an API key profile"* ]]
}

@test "profile use switches to api-key profile" {
  echo "sk-ant-work" | cwtch profile save-key workapi
  echo "sk-ant-personal" | cwtch profile save-key personalapi
  run cwtch profile use workapi
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"api-key"* ]]
  run cwtch profile api-key
  [[ "$output" == "sk-ant-work" ]]
}

@test "status shows api-key profile type" {
  echo "sk-ant-test" | cwtch profile save-key myapiprofile
  run cwtch status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"api-key"* ]]
  [[ "$output" == *"no usage data"* ]]
}
