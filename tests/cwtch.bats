#!/usr/bin/env bats
# Top-level CLI tests for cwtch.
bats_require_minimum_version 1.5.0

load helpers.bash

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "shows usage with no arguments" {
  run cwtch
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"USAGE"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "shows usage with --help" {
  run cwtch --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"USAGE"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "shows usage with -h" {
  run cwtch -h
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"USAGE"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "unknown command shows error" {
  run --separate-stderr cwtch badcommand
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"Unknown"* ]]
}

@test "status shows no profile when none active" {
  run cwtch status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"No profile active"* ]] || [[ "$output" == *"Profile: (none)"* ]]
}

@test "status shows sources not configured without Cwtchfile" {
  run cwtch status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Not configured"* ]] || [[ "$output" == *"Sources: not configured"* ]]
  [[ "$output" == *"cwtch sync init"* ]]
}

@test "status shows sources when Cwtchfile exists" {
  create_cwtchfile "sources:
  - repo: test/repo
    as: test"
  run cwtch status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"test/repo"* ]]
}

@test "edit command references correct file" {
  export EDITOR="echo"
  run cwtch edit
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"/.cwtch/Cwtchfile"* ]]
}
