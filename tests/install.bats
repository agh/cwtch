#!/usr/bin/env bats
# Source installer safety, always below the sandboxed HOME.
# shellcheck disable=SC2154,SC2312
bats_require_minimum_version 1.5.0

load helpers.bash

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "installer links the executable and accepts its existing link" {
  run "${ROOT}/scripts/install.sh"
  assert_status 0
  assert_symlink_to "${HOME}/.local/bin/cwtch" "${ROOT}/bin/cwtch"
  run "${ROOT}/scripts/install.sh"
  assert_status 0
  assert_symlink_to "${HOME}/.local/bin/cwtch" "${ROOT}/bin/cwtch"
  [[ ! -e "${HOME}/.local/bin/cwtch.bak" ]]
}

@test "installer refuses an unrelated file or symlink without --force" {
  mkdir -p "${HOME}/.local/bin"
  printf '%s\n' 'own executable' > "${HOME}/.local/bin/cwtch"
  run --separate-stderr "${ROOT}/scripts/install.sh"
  assert_status 1
  assert_stderr_contains "Refusing to replace"
  [[ "$(cat "${HOME}/.local/bin/cwtch")" == 'own executable' ]]
  mv "${HOME}/.local/bin/cwtch" "${HOME}/own-cwtch"
  ln -s "${HOME}/own-cwtch" "${HOME}/.local/bin/cwtch"
  run --separate-stderr "${ROOT}/scripts/install.sh"
  assert_status 1
  assert_symlink_to "${HOME}/.local/bin/cwtch" "${HOME}/own-cwtch"
}

@test "installer --force backs up an unrelated file before linking" {
  mkdir -p "${HOME}/.local/bin"
  printf '%s\n' 'own executable' > "${HOME}/.local/bin/cwtch"
  run "${ROOT}/scripts/install.sh" --force
  assert_status 0
  assert_symlink_to "${HOME}/.local/bin/cwtch" "${ROOT}/bin/cwtch"
  [[ "$(cat "${HOME}/.local/bin/cwtch.bak")" == 'own executable' ]]
}

@test "installer --force backs up the symlink rather than its target" {
  mkdir -p "${HOME}/.local/bin"
  printf '%s\n' 'own executable' > "${HOME}/own-cwtch"
  ln -s "${HOME}/own-cwtch" "${HOME}/.local/bin/cwtch"
  run "${ROOT}/scripts/install.sh" --force
  assert_status 0
  assert_symlink_to "${HOME}/.local/bin/cwtch" "${ROOT}/bin/cwtch"
  assert_symlink_to "${HOME}/.local/bin/cwtch.bak" "${HOME}/own-cwtch"
  [[ "$(cat "${HOME}/own-cwtch")" == 'own executable' ]]
}

@test "installer backup directory blocks --force and leaves the original intact" {
  mkdir -p "${HOME}/.local/bin/cwtch.bak"
  printf '%s\n' 'own executable' > "${HOME}/.local/bin/cwtch"
  run --separate-stderr "${ROOT}/scripts/install.sh" --force
  assert_status 1
  assert_stderr_contains "Could not back up"
  [[ ! -L "${HOME}/.local/bin/cwtch" ]]
  [[ "$(cat "${HOME}/.local/bin/cwtch")" == 'own executable' ]]
  [[ ! -e "${HOME}/.local/bin/cwtch.bak/cwtch" ]]

  mv "${HOME}/.local/bin/cwtch" "${HOME}/own-cwtch"
  ln -s "${HOME}/own-cwtch" "${HOME}/.local/bin/cwtch"
  run --separate-stderr "${ROOT}/scripts/install.sh" --force
  assert_status 1
  assert_stderr_contains "Could not back up"
  assert_symlink_to "${HOME}/.local/bin/cwtch" "${HOME}/own-cwtch"
  [[ ! -e "${HOME}/.local/bin/cwtch.bak/cwtch" ]]
}

@test "installer checks mv failure for both file and symlink backups" {
  mkdir -p "${HOME}/.local/bin" "${TEST_DIR}/failbin"
  printf '%s\n' '#!/bin/bash' 'exit 1' > "${TEST_DIR}/failbin/mv"
  chmod +x "${TEST_DIR}/failbin/mv"
  printf '%s\n' 'own executable' > "${HOME}/.local/bin/cwtch"
  run --separate-stderr env PATH="${TEST_DIR}/failbin:${PATH}" "${ROOT}/scripts/install.sh" --force
  assert_status 1
  assert_stderr_contains "Could not back up"
  [[ "$(cat "${HOME}/.local/bin/cwtch")" == 'own executable' ]]
  mv "${HOME}/.local/bin/cwtch" "${HOME}/own-cwtch"
  ln -s "${HOME}/own-cwtch" "${HOME}/.local/bin/cwtch"
  run --separate-stderr env PATH="${TEST_DIR}/failbin:${PATH}" "${ROOT}/scripts/install.sh" --force
  assert_status 1
  assert_stderr_contains "Could not back up"
  assert_symlink_to "${HOME}/.local/bin/cwtch" "${HOME}/own-cwtch"
  [[ ! -e "${HOME}/.local/bin/cwtch.bak" ]]
}
