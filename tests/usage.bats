#!/usr/bin/env bats
# `cwtch usage` — SPEC-v6 §1.7. Best effort, always exit 0, never aborts on a
# corrupt credential (audit item 17).
# shellcheck disable=SC2154,SC2016,SC2312  # bats globals; child shells expand their own vars
bats_require_minimum_version 1.5.0

load helpers.bash

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "usage exits 0 with no profiles saved" {
  run cwtch usage
  assert_status 0
  assert_output_contains "No profiles saved"
}

@test "usage carries the best-effort header" {
  run cwtch usage
  assert_status 0
  assert_output_contains "Usage by Profile"
  assert_output_contains "best effort"
  assert_output_contains "/usage"
}

@test "usage labels token and api-key profiles without calling the API" {
  write_token_profile tok
  write_apikey_profile api
  run cwtch usage
  assert_status 0
  assert_output_contains "(token)"
  assert_output_contains "(api-key)"
  [[ -z "$(curl_calls)" ]]
}

@test "usage renders 5h and 7d percentages for an OAuth profile" {
  write_oauth_profile personal
  set_usage_response "$(usage_payload 83.4 12.9)"
  run cwtch usage
  assert_status 0
  assert_output_contains "83"
  assert_output_contains "12"
}

@test "usage renders each active limit with its severity" {
  write_oauth_profile personal
  set_usage_response "$(usage_payload)"
  run cwtch usage
  assert_status 0
  assert_output_contains "weekly_opus"
  assert_output_contains "41"
  assert_output_contains "warning"
}

@test "usage omits inactive limits" {
  write_oauth_profile personal
  set_usage_response "$(usage_payload)"
  run cwtch usage
  assert_status 0
  assert_output_lacks "dormant_limit"
}

@test "F17: a corrupt .credential is reported, not fatal" {
  mkdir -p "${HOME}/.cwtch/profiles/broken"
  printf 'this is not json\n' > "${HOME}/.cwtch/profiles/broken/.credential"
  chmod 600 "${HOME}/.cwtch/profiles/broken/.credential"
  run cwtch usage
  assert_status 0
  assert_output_contains "broken"
  assert_output_contains "(unreadable credential)"
}

@test "F17: a credential with no accessToken is reported, not fatal" {
  mkdir -p "${HOME}/.cwtch/profiles/empty"
  printf '{"mcpOAuth":{}}\n' > "${HOME}/.cwtch/profiles/empty/.credential"
  chmod 600 "${HOME}/.cwtch/profiles/empty/.credential"
  run cwtch usage
  assert_status 0
  assert_output_contains "(unreadable credential)"
}

@test "F17: one corrupt profile does not stop the others being rendered" {
  mkdir -p "${HOME}/.cwtch/profiles/aaa-broken"
  printf 'nope\n' > "${HOME}/.cwtch/profiles/aaa-broken/.credential"
  write_token_profile zzz-token
  run cwtch usage
  assert_status 0
  assert_output_contains "(unreadable credential)"
  assert_output_contains "zzz-token"
}

@test "usage reports a failed fetch and keeps going" {
  write_oauth_profile personal
  write_token_profile tok
  set_usage_failure 22
  run cwtch usage
  assert_status 0
  assert_output_contains "(usage unavailable)"
  assert_output_contains "tok"
}

@test "usage marks the active profile" {
  write_token_profile tok
  set_current tok
  run cwtch usage
  assert_status 0
  assert_output_contains "active"
}

@test "usage requests the documented endpoint with a timeout" {
  write_oauth_profile personal
  set_usage_response "$(usage_payload)"
  run cwtch usage
  assert_status 0
  run curl_calls
  assert_output_contains "url=https://api.anthropic.com/api/oauth/usage"
  assert_output_contains "--max-time 10"
}

@test "usage keeps the Claude Code request headers" {
  write_oauth_profile personal
  set_usage_response "$(usage_payload)"
  run cwtch usage
  assert_status 0
  run curl_calls
  assert_output_contains "header=Accept: application/json"
  assert_output_contains "header=anthropic-beta: oauth-2025-04-20"
  assert_output_contains "header=User-Agent: claude-code/"
  assert_output_contains "header=Authorization:"
}

@test "usage sends the profile's own access token" {
  # fetch_usage takes the token as an argument; the Authorization header in the
  # audited copy of lib/common.sh is redacted, so this pins it back to the token.
  write_oauth_profile personal "${TEST_TOKEN_B}"
  set_usage_response "$(usage_payload)"
  run cwtch usage
  assert_status 0
  run curl_calls
  assert_output_contains "${TEST_TOKEN_B}"
}

@test "usage exits 0 even when every profile fails" {
  write_oauth_profile a
  write_oauth_profile b
  set_usage_failure 6
  run cwtch usage
  assert_status 0
}
