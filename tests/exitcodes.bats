#!/usr/bin/env bats
# Exit code tests - ensure commands exit 0 on success, non-zero on failure.
bats_require_minimum_version 1.5.0

load helpers.bash

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

# Success cases should exit 0

@test "exit 0: no args shows help" {
  run cwtch
  [[ "$status" -eq 0 ]]
}

@test "exit 0: --help" {
  run cwtch --help
  [[ "$status" -eq 0 ]]
}

@test "exit 0: -h" {
  run cwtch -h
  [[ "$status" -eq 0 ]]
}

@test "exit 0: status with no profile" {
  run cwtch status
  [[ "$status" -eq 0 ]]
}

@test "exit 0: status with profile" {
  set_mock_credential "test-cred"
  cwtch profile save testprofile
  run cwtch status
  [[ "$status" -eq 0 ]]
}

@test "exit 0: status with Cwtchfile" {
  create_cwtchfile "sources:
  - repo: test/repo
    as: test"
  run cwtch status
  [[ "$status" -eq 0 ]]
}

@test "exit 0: usage with no profiles" {
  run cwtch usage
  [[ "$status" -eq 0 ]]
}

@test "exit 0: usage with profiles" {
  echo "test-key" | cwtch profile save-key testapi
  run cwtch usage
  [[ "$status" -eq 0 ]]
}

@test "exit 0: profile list empty" {
  run cwtch profile list
  [[ "$status" -eq 0 ]]
}

@test "exit 0: profile list with profiles" {
  echo "test-key" | cwtch profile save-key testapi
  run cwtch profile list
  [[ "$status" -eq 0 ]]
}

@test "exit 0: profile current with no profile" {
  run cwtch profile current
  [[ "$status" -eq 0 ]]
}

@test "exit 0: profile current with profile" {
  echo "test-key" | cwtch profile save-key testapi
  run cwtch profile current
  [[ "$status" -eq 0 ]]
}

@test "exit 0: profile save with credential" {
  set_mock_credential "test-cred"
  run cwtch profile save myprofile
  [[ "$status" -eq 0 ]]
}

@test "exit 0: profile save-key" {
  run bash -c 'echo "sk-test" | cwtch profile save-key testapi'
  [[ "$status" -eq 0 ]]
}

@test "exit 0: profile use existing" {
  echo "test-key" | cwtch profile save-key testapi
  run cwtch profile use testapi
  [[ "$status" -eq 0 ]]
}

@test "exit 0: profile delete existing" {
  echo "test-key" | cwtch profile save-key testapi
  run cwtch profile delete testapi
  [[ "$status" -eq 0 ]]
}

@test "exit 0: profile api-key with api-key profile" {
  echo "test-key" | cwtch profile save-key testapi
  run cwtch profile api-key
  [[ "$status" -eq 0 ]]
}

@test "exit 0: sync init" {
  run cwtch sync init
  [[ "$status" -eq 0 ]]
}

@test "exit 0: sync check valid" {
  create_cwtchfile "sources:
  - repo: test/repo
    as: test"
  run cwtch sync check
  [[ "$status" -eq 0 ]]
}

@test "exit 0: edit with echo editor" {
  export EDITOR="echo"
  run cwtch edit
  [[ "$status" -eq 0 ]]
}

# Failure cases should exit non-zero

@test "exit 1: unknown command" {
  run cwtch unknowncommand
  [[ "$status" -eq 1 ]]
}

@test "exit 1: unknown sync subcommand" {
  run cwtch sync unknownsub
  [[ "$status" -eq 1 ]]
}

@test "exit 1: unknown profile subcommand" {
  run cwtch profile unknownsub
  [[ "$status" -eq 1 ]]
}

@test "exit 1: profile save without credential" {
  run cwtch profile save noexist
  [[ "$status" -eq 1 ]]
}

@test "exit 1: profile save-key without key" {
  run bash -c 'echo "" | cwtch profile save-key testapi'
  [[ "$status" -eq 1 ]]
}

@test "exit 1: profile use nonexistent" {
  run cwtch profile use nonexistent
  [[ "$status" -eq 1 ]]
}

@test "exit 1: profile delete nonexistent" {
  run cwtch profile delete nonexistent
  [[ "$status" -eq 1 ]]
}

@test "exit 1: profile api-key with oauth profile" {
  set_mock_credential "test-cred"
  cwtch profile save oauthprofile
  run cwtch profile api-key
  [[ "$status" -eq 1 ]]
}

@test "exit 1: sync without Cwtchfile" {
  run cwtch sync
  [[ "$status" -eq 1 ]]
}

@test "exit 1: sync check without Cwtchfile" {
  run cwtch sync check
  [[ "$status" -eq 1 ]]
}

@test "exit 1: sync check invalid yaml" {
  mkdir -p "${HOME}/.cwtch"
  echo "invalid: yaml: :" > "${HOME}/.cwtch/Cwtchfile"
  run cwtch sync check
  [[ "$status" -eq 1 ]]
}

@test "exit 1: sync check missing repo" {
  create_cwtchfile "sources:
  - as: test"
  run cwtch sync check
  [[ "$status" -eq 1 ]]
}

@test "exit 1: sync init when exists" {
  cwtch sync init
  run cwtch sync init
  [[ "$status" -eq 1 ]]
}
