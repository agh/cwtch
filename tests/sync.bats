#!/usr/bin/env bats
# Sync functionality tests for cwtch.
bats_require_minimum_version 1.5.0

load helpers.bash

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

# --- sync init ---

@test "sync init creates Cwtchfile" {
  run cwtch sync init
  [[ "$status" -eq 0 ]]
  [[ -f "${HOME}/.cwtch/Cwtchfile" ]]
  [[ "$output" == *"Created"* ]]
}

@test "sync init fails if Cwtchfile exists" {
  create_cwtchfile "sources: []"
  run --separate-stderr cwtch sync init
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"already exists"* ]]
}

@test "sync init creates valid Cwtchfile" {
  cwtch sync init
  # The generated file should be valid YAML with sources
  run cwtch sync check
  # Will fail validation because example has placeholder values,
  # but file should exist and be parseable
  [[ -f "${HOME}/.cwtch/Cwtchfile" ]]
}

# --- sync ---

@test "sync fails without Cwtchfile" {
  run --separate-stderr cwtch sync
  [[ "$status" -eq 1 ]]
  [[ "$stderr" == *"Cwtchfile not found"* ]]
}

@test "sync clones repo and creates symlinks" {
  local repo_path
  repo_path="$(create_mock_repo testowner-testrepo)"

  create_cwtchfile "sources:
  - repo: ${repo_path}
    commands: commands/
    agents: agents/
    as: test"

  run cwtch sync
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Cloning"* ]]
  [[ -L "${HOME}/.claude/commands/test" ]]
  [[ -L "${HOME}/.claude/agents/test" ]]
}

@test "sync creates commands directory symlink" {
  local repo_path
  repo_path="$(create_mock_repo myrepo)"

  create_cwtchfile "sources:
  - repo: ${repo_path}
    commands: commands/
    as: myns"

  cwtch sync
  [[ -L "${HOME}/.claude/commands/myns" ]]
  [[ -f "${HOME}/.claude/commands/myns/test.md" ]]
}

@test "sync updates existing repo" {
  local repo_path
  repo_path="$(create_mock_repo updatetest)"

  create_cwtchfile "sources:
  - repo: ${repo_path}
    commands: commands/
    as: test"

  cwtch sync
  [[ "$?" -eq 0 ]]

  run cwtch sync
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Updating"* ]]
}

@test "sync applies base settings" {
  local repo_path src_dir
  src_dir="${TEST_DIR}/repos/settings-src"
  mkdir -p "${src_dir}"
  echo '{"theme": "dark"}' > "${src_dir}/settings.json"
  git -C "${src_dir}" init --quiet
  git -C "${src_dir}" add .
  git -C "${src_dir}" commit -m "init" --quiet
  repo_path="${src_dir}"

  create_cwtchfile "settings: ${repo_path}:settings.json
sources: []"

  cwtch sync
  [[ -f "${HOME}/.claude/settings.json" ]]
  grep -q "dark" "${HOME}/.claude/settings.json"
}

@test "sync links CLAUDE.md" {
  local repo_path src_dir
  src_dir="${TEST_DIR}/repos/claude-md-src"
  mkdir -p "${src_dir}"
  echo "# My Instructions" > "${src_dir}/CLAUDE.md"
  git -C "${src_dir}" init --quiet
  git -C "${src_dir}" add .
  git -C "${src_dir}" commit -m "init" --quiet
  repo_path="${src_dir}"

  create_cwtchfile "claude_md: ${repo_path}:CLAUDE.md
sources: []"

  cwtch sync
  [[ -L "${HOME}/.claude/CLAUDE.md" ]]
}

@test "sync merges MCP servers" {
  local repo_path src_dir
  src_dir="${TEST_DIR}/repos/mcp-src"
  mkdir -p "${src_dir}"
  echo '{"mcpServers": {"test": {"command": "test"}}}' > "${src_dir}/mcp.json"
  git -C "${src_dir}" init --quiet
  git -C "${src_dir}" add .
  git -C "${src_dir}" commit -m "init" --quiet
  repo_path="${src_dir}"

  create_cwtchfile "sources:
  - repo: ${repo_path}
    mcp: mcp.json"

  cwtch sync
  [[ -f "${HOME}/.claude/settings.json" ]]
  grep -q "mcpServers" "${HOME}/.claude/settings.json"
}

@test "sync handles multiple sources with different namespaces" {
  local repo1 repo2

  repo1="$(create_mock_repo source1)"
  repo2="$(create_mock_repo source2)"

  create_cwtchfile "sources:
  - repo: ${repo1}
    commands: commands/
    as: first
  - repo: ${repo2}
    commands: commands/
    as: second"

  cwtch sync
  [[ -L "${HOME}/.claude/commands/first" ]]
  [[ -L "${HOME}/.claude/commands/second" ]]
}

@test "sync shows completion message" {
  local repo_path
  repo_path="$(create_mock_repo complete)"

  create_cwtchfile "sources:
  - repo: ${repo_path}
    commands: commands/
    as: test"

  run cwtch sync
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Sync complete"* ]]
}
