#!/usr/bin/env bats
# Cwtchfile validation tests for cwtch.
bats_require_minimum_version 1.5.0

load helpers.bash

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

# --- sync check ---

@test "sync check fails without Cwtchfile" {
  run --separate-stderr cwtch sync check
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"Not found"* ]]
}

@test "sync check passes with valid Cwtchfile" {
  create_cwtchfile "sources:
  - repo: owner/repo
    commands: commands/
    as: test"
  run cwtch sync check
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Cwtchfile is valid"* ]]
}

@test "sync check shows settings and claude_md" {
  create_cwtchfile "settings: owner/base:settings.json
claude_md: owner/base:CLAUDE.md
sources:
  - repo: owner/repo
    as: test"
  run cwtch sync check
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"settings:"*"owner/base:settings.json"* ]]
  [[ "$output" == *"claude_md:"*"owner/base:CLAUDE.md"* ]]
}

@test "sync check shows source count" {
  create_cwtchfile "sources:
  - repo: owner/one
    as: one
  - repo: owner/two
    as: two"
  run cwtch sync check
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"sources:   2"* ]]
}

@test "sync check shows source details" {
  create_cwtchfile "sources:
  - repo: owner/repo
    as: myns"
  run cwtch sync check
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"owner/repo"*"myns"* ]]
}

# --- validation errors ---

@test "sync check fails on invalid settings format" {
  create_cwtchfile "settings: invalid-no-colon
sources:
  - repo: owner/repo
    as: test"
  run --separate-stderr cwtch sync check
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"'settings' must be in format 'repo:path'"* ]]
}

@test "sync check fails on invalid claude_md format" {
  create_cwtchfile "claude_md: invalid-no-colon
sources:
  - repo: owner/repo
    as: test"
  run --separate-stderr cwtch sync check
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"'claude_md' must be in format 'repo:path'"* ]]
}

@test "sync check fails when source missing repo" {
  # Create a source entry without repo field
  mkdir -p "${HOME}/.cwtch"
  cat > "${HOME}/.cwtch/Cwtchfile" << 'EOF'
sources:
  - as: test
    commands: commands/
EOF
  run --separate-stderr cwtch sync check
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"missing required 'repo'"* ]]
}

@test "sync check fails when source has commands without as" {
  create_cwtchfile "sources:
  - repo: owner/repo
    commands: commands/"
  run --separate-stderr cwtch sync check
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"requires 'as'"* ]]
}

@test "sync check fails when source has agents without as" {
  create_cwtchfile "sources:
  - repo: owner/repo
    agents: agents/"
  run --separate-stderr cwtch sync check
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"requires 'as'"* ]]
}

@test "sync check fails when source has hooks without as" {
  create_cwtchfile "sources:
  - repo: owner/repo
    hooks: hooks/"
  run --separate-stderr cwtch sync check
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"requires 'as'"* ]]
}

@test "sync check fails on invalid repo format" {
  create_cwtchfile "sources:
  - repo: noslash
    as: test"
  run --separate-stderr cwtch sync check
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"invalid repo format"* ]]
}

@test "sync check fails on duplicate namespaces" {
  create_cwtchfile "sources:
  - repo: owner/one
    commands: commands/
    as: same
  - repo: owner/two
    commands: commands/
    as: same"
  run --separate-stderr cwtch sync check
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"duplicate namespace"* ]]
}

# --- valid edge cases ---

@test "sync check passes with mcp-only source (no namespace needed)" {
  create_cwtchfile "sources:
  - repo: owner/mcp-servers
    mcp: servers.json"
  run cwtch sync check
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Cwtchfile is valid"* ]]
}

@test "sync check passes with full URL repo" {
  create_cwtchfile "sources:
  - repo: https://github.com/owner/repo.git
    commands: commands/
    as: test"
  run cwtch sync check
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Cwtchfile is valid"* ]]
}

@test "sync check passes with ssh URL repo" {
  create_cwtchfile "sources:
  - repo: git@github.com:owner/repo.git
    commands: commands/
    as: test"
  run cwtch sync check
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Cwtchfile is valid"* ]]
}
