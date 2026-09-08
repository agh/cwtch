#!/usr/bin/env bats
# `cwtch status` — SPEC-v6 §1.6. Never touches the network, never shows usage
# numbers, never looks up a profile overlay, and always exits 0.
# shellcheck disable=SC2154,SC2016,SC2312  # bats globals; child shells expand their own vars
bats_require_minimum_version 1.5.0

load helpers.bash

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "F2: status exits 0 with a profile active and a Cwtchfile present" {
  write_token_profile work
  set_current work
  create_cwtchfile "sources:
  - repo: owner/repo
    as: default
    agents: agents/"
  run cwtch status
  assert_status 0
  assert_output_contains "work"
  assert_output_contains "owner/repo"
}

@test "F2: status exits 0 for every profile type with a Cwtchfile present" {
  create_cwtchfile "settings: owner/repo:settings.json"
  write_oauth_profile personal
  write_token_profile tok
  write_apikey_profile api
  local name
  for name in personal tok api; do
    set_current "${name}"
    run cwtch status
    assert_status 0
  done
}

@test "F2: a profile overlay Cwtchfile is ignored, not reported" {
  write_token_profile work
  set_current work
  mkdir -p "${HOME}/.cwtch/profiles/work"
  printf 'sources: []\n' > "${HOME}/.cwtch/profiles/work/Cwtchfile"
  create_cwtchfile "sources: []"
  run cwtch status
  assert_status 0
  assert_output_lacks "Overlay"
}

@test "status prints the version from VERSION" {
  local version
  version="$(tr -d '\n' < "${ROOT}/VERSION")"
  run cwtch status
  assert_status 0
  assert_output_contains "cwtch v${version}"
}

@test "status makes no network request for an OAuth profile" {
  write_oauth_profile personal
  set_current personal
  set_usage_response "$(usage_payload)"
  run cwtch status
  assert_status 0
  [[ -z "$(curl_calls)" ]]
}

@test "status shows no usage percentages" {
  write_oauth_profile personal
  set_current personal
  set_usage_response "$(usage_payload)"
  run cwtch status
  assert_status 0
  assert_output_lacks "5h:"
  assert_output_lacks "7d:"
  assert_output_lacks "83"
}

@test "status without a profile offers a getting-started hint" {
  run cwtch status
  assert_status 0
  assert_output_contains "No profile active"
  assert_output_contains "cwtch profile setup"
}

@test "status names the active profile and its type" {
  write_oauth_profile personal
  set_current personal
  run cwtch status
  assert_status 0
  assert_output_contains "personal"
  assert_output_contains "(oauth)"
}

@test "status tells token and api-key users how to apply the profile" {
  write_token_profile tok
  set_current tok
  run cwtch status
  assert_status 0
  assert_output_contains 'eval "$(cwtch profile env)"'

  write_apikey_profile api
  set_current api
  run cwtch status
  assert_status 0
  assert_output_contains 'eval "$(cwtch profile env)"'
}

@test "status does not offer the eval hint for an OAuth profile" {
  write_oauth_profile personal
  set_current personal
  run cwtch status
  assert_status 0
  assert_output_lacks 'eval "$(cwtch profile env)"'
}

@test "status reports an unsynced source" {
  create_cwtchfile "sources:
  - repo: owner/repo
    as: default
    agents: agents/"
  run cwtch status
  assert_status 0
  assert_output_contains "owner/repo"
  assert_output_contains "not synced"
}

@test "status reports a synced source with its short commit" {
  local repo commit
  repo="$(create_mock_repo demo)"
  create_cwtchfile "sources:
  - repo: ${repo}
    as: demo
    agents: agents/"
  run cwtch sync
  assert_status 0
  commit="$(git -C "$(only_source_dir)" log -1 --format='%h')"
  run cwtch status
  assert_status 0
  assert_output_contains "${commit}"
  assert_output_lacks "not synced"
}

@test "status names the config file" {
  create_cwtchfile "sources: []"
  run cwtch status
  assert_status 0
  assert_output_contains "${HOME}/.cwtch/Cwtchfile"
}

@test "status without a Cwtchfile points at sync init" {
  run cwtch status
  assert_status 0
  assert_output_contains "cwtch sync init"
}

@test "status survives a .current naming a deleted profile" {
  set_current ghost
  create_cwtchfile "sources: []"
  run cwtch status
  assert_status 0
}

@test "status emits no ANSI escapes under NO_COLOR" {
  write_token_profile work
  set_current work
  run cwtch status
  assert_status 0
  assert_output_lacks $'\033'
  assert_output_lacks '\033'
  assert_output_lacks '\e['
}
