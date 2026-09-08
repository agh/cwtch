#!/usr/bin/env bats
# `cwtch version`, `-v`, `--version` and the help text — SPEC-v6 §1.8.
# Regression tests for audit item 15: the update check used the rate-limited
# GitHub API without -L or a timeout, and -v needed the network.
# shellcheck disable=SC2154,SC2016,SC2312  # bats globals; child shells expand their own vars
bats_require_minimum_version 1.5.0

load helpers.bash

setup() { setup_test_env; }
teardown() { teardown_test_env; }

repo_version() { tr -d '\n' < "${ROOT}/VERSION"; }

# --- -v / --version ----------------------------------------------------------

@test "F15: -v prints one line and makes no network request" {
  local version
  version="$(repo_version)"
  run cwtch -v
  assert_status 0
  [[ "${#lines[@]}" -eq 1 ]]
  assert_output_matches "^cwtch v?${version}$"
  [[ -z "$(curl_calls)" ]]
}

@test "F15: --version behaves the same as -v" {
  local version
  version="$(repo_version)"
  run cwtch --version
  assert_status 0
  assert_output_matches "^cwtch v?${version}$"
  [[ -z "$(curl_calls)" ]]
}

@test "F15: -v works with the update endpoint unreachable" {
  set_release_check_failure 6
  run cwtch -v
  assert_status 0
}

@test "F15: no git SHA appears in any version output" {
  set_latest_release "$(repo_version)"
  run cwtch -v
  assert_status 0
  refute_output_matches '\([0-9a-f]{7,40}\)'
  run cwtch version
  assert_status 0
  refute_output_matches '\([0-9a-f]{7,40}\)'
}

# --- version (with update check) ---------------------------------------------

@test "version starts with the same line as -v" {
  local version
  version="$(repo_version)"
  set_latest_release "${version}"
  run cwtch version
  assert_status 0
  [[ "${lines[0]}" =~ ^cwtch[[:space:]]?v?${version}$ ]]
}

@test "F15: version reports a newer release and how to upgrade" {
  set_latest_release "99.0.0"
  run cwtch version
  assert_status 0
  assert_output_contains "New version available"
  assert_output_contains "99.0.0"
  assert_output_contains "brew upgrade cwtch"
}

@test "F15: version reports being up to date" {
  set_latest_release "$(repo_version)"
  run cwtch version
  assert_status 0
  assert_output_contains "latest version"
  assert_output_lacks "New version available"
}

@test "F15: a release older than the local build is not an upgrade" {
  set_latest_release "0.0.1"
  run cwtch version
  assert_status 0
  assert_output_lacks "New version available"
}

@test "F15: an unreachable update endpoint is reported, never fatal" {
  set_release_check_failure 6
  run cwtch version
  assert_status 0
  assert_output_contains "Could not check for updates"
}

@test "F15: the update check follows redirects with a timeout" {
  set_latest_release "99.0.0"
  run cwtch version
  assert_status 0
  run curl_calls
  assert_output_contains "url=https://github.com/agh/cwtch/releases/latest"
  assert_output_contains "--max-time 3"
  assert_output_contains "-sIL"
}

@test "F15: the update check does not use the rate-limited API host" {
  set_latest_release "99.0.0"
  run cwtch version
  assert_status 0
  run curl_calls
  assert_output_lacks "api.github.com"
}

@test "version takes the final location header of the redirect chain" {
  set_latest_release "99.0.0"
  run cwtch version
  assert_status 0
  assert_output_contains "99.0.0"
  assert_output_lacks "releases/latest"
}

# --- help --------------------------------------------------------------------

@test "help lists every command" {
  run cwtch --help
  assert_status 0
  local entry
  for entry in "status" "usage" "sync" "sync init" "sync check" \
    "profile list" "profile current" "profile setup" "profile save" \
    "profile save-key" "profile save-token" "profile use" "profile delete" \
    "profile env" "profile token" "profile api-key" "edit" "version"; do
    assert_output_contains "${entry}"
  done
}

@test "F16: help does not advertise refresh as a current command" {
  run cwtch --help
  assert_status 0
  if [[ "${output}" == *"refresh"* ]]; then
    assert_output_contains "Deprecated"
  fi
}

@test "help mentions the version and short flags" {
  local version
  version="$(repo_version)"
  run cwtch --help
  assert_status 0
  assert_output_contains "${version}"
  assert_output_contains "--version"
}

@test "help command rows share one description column" {
  local line prefix rest desc start first="" rows=0
  run cwtch --help
  assert_status 0
  for line in "${lines[@]}"; do
    [[ "${line}" == "  "* ]] || continue
    [[ "${line}" == *"   "* ]] || continue
    prefix="${line%%   *}"
    [[ "${prefix}" == *[a-z]* ]] || continue
    rest="${line#"${prefix}"}"
    desc="${rest#"${rest%%[![:space:]]*}"}"
    [[ -n "${desc}" ]] || continue
    start=$((${#line} - ${#desc}))
    rows=$((rows + 1))
    if [[ -z "${first}" ]]; then
      first="${start}"
    elif [[ "${start}" -ne "${first}" ]]; then
      printf 'help rows are not aligned: %s starts at %s, expected %s\n' \
        "${line}" "${start}" "${first}" >&2
      return 1
    fi
  done
  [[ "${rows}" -ge 5 ]]
}
