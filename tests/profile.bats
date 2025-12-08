#!/usr/bin/env bats
# Profile management tests for cwtch.
bats_require_minimum_version 1.5.0

load helpers.bash

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

# --- profile list ---

@test "profile list shows no profiles when empty" {
  run cwtch profile list
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"No profiles saved"* ]]
}

@test "profile list shows saved profile" {
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  cwtch profile save myprofile
  run cwtch profile list
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"myprofile"* ]]
  [[ "$output" == *"active"* ]]
}

@test "profile list shows api-key profile type" {
  echo "sk-ant-test" | cwtch profile save-key apiprofile
  run cwtch profile list
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"apiprofile"* ]]
  [[ "$output" == *"api-key"* ]]
}

# --- profile current ---

@test "profile current shows none when no profile active" {
  run cwtch profile current
  [[ "$status" -eq 0 ]]
  [[ "$output" == "(none)" ]]
}

@test "profile current shows active profile after save" {
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  cwtch profile save work
  run cwtch profile current
  [[ "$status" -eq 0 ]]
  [[ "$output" == "work" ]]
}

# --- profile save ---

@test "profile save fails without keychain credential" {
  run --separate-stderr cwtch profile save test
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"No credential in keychain"* ]]
}

@test "profile save succeeds with credential" {
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  run cwtch profile save work
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Saved credential"* ]]
  [[ -f "${HOME}/.cwtch/profiles/work/.credential" ]]
}

@test "profile save only stores credential not claude dir" {
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  mkdir -p "${HOME}/.claude"
  echo "settings" > "${HOME}/.claude/settings.json"

  cwtch profile save work

  # Credential should exist
  [[ -f "${HOME}/.cwtch/profiles/work/.credential" ]]
  # But not the whole claude dir contents
  [[ ! -f "${HOME}/.cwtch/profiles/work/settings.json" ]]
}

# --- profile save-key ---

@test "profile save-key saves api key profile" {
  echo "sk-ant-test123" | cwtch profile save-key apitest
  run cwtch profile list
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"apitest"* ]]
  [[ "$output" == *"api-key"* ]]
  [[ -f "${HOME}/.cwtch/profiles/apitest/.apikey" ]]
}

@test "profile save-key fails without key" {
  run --separate-stderr bash -c 'echo "" | cwtch profile save-key nokey'
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"No API key"* ]]
}

# --- profile api-key ---

@test "profile api-key outputs current api key" {
  echo "sk-ant-test456" | cwtch profile save-key mykey
  run cwtch profile api-key
  [[ "$status" -eq 0 ]]
  [[ "$output" == "sk-ant-test456" ]]
}

@test "profile api-key fails for oauth profile" {
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  cwtch profile save oauthprofile
  run --separate-stderr cwtch profile api-key
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"not an API key profile"* ]]
}

# --- profile use ---

@test "profile use fails for nonexistent profile" {
  run --separate-stderr cwtch profile use nonexistent
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"not found"* ]]
}

@test "profile use switches to oauth profile" {
  echo "work-cred" > "${HOME}/.mock-keychain-cred"
  cwtch profile save work

  echo "personal-cred" > "${HOME}/.mock-keychain-cred"
  cwtch profile save personal

  run cwtch profile use work
  [[ "$status" -eq 0 ]]
  [[ "$(cat "${HOME}/.mock-keychain-cred")" == "work-cred" ]]
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

@test "profile use does not touch claude dir" {
  echo "cred1" > "${HOME}/.mock-keychain-cred"
  cwtch profile save one

  echo "cred2" > "${HOME}/.mock-keychain-cred"
  cwtch profile save two

  # Create some content in ~/.claude
  mkdir -p "${HOME}/.claude/commands"
  echo "# test" > "${HOME}/.claude/commands/test.md"

  # Switch profiles
  cwtch profile use one

  # Claude dir should be untouched
  [[ -f "${HOME}/.claude/commands/test.md" ]]
}

# --- profile delete ---

@test "profile delete removes profile" {
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  cwtch profile save todelete
  run cwtch profile delete todelete
  [[ "$status" -eq 0 ]]
  [[ ! -d "${HOME}/.cwtch/profiles/todelete" ]]
}

@test "profile delete fails for nonexistent profile" {
  run --separate-stderr cwtch profile delete nonexistent
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"not found"* ]]
}

@test "profile delete clears current if deleted profile was active" {
  echo "mock-cred" > "${HOME}/.mock-keychain-cred"
  cwtch profile save active
  [[ "$(cwtch profile current)" == "active" ]]
  cwtch profile delete active
  [[ "$(cwtch profile current)" == "(none)" ]]
}
