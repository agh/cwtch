#!/usr/bin/env bats
# Non-secret profile metadata and advisory setup-token expiry.
# shellcheck disable=SC2154,SC2016,SC2312
bats_require_minimum_version 1.5.0

load helpers.bash

setup() {
  setup_test_env
  export REAL_DATE
  REAL_DATE="$(command -v date)"
  mkdir "${TEST_DIR}/datebin"
  cat > "${TEST_DIR}/datebin/date" <<'DATE'
#!/bin/bash
case "$*" in
  '-u +%Y-%m-%d') printf '%s\n' '2026-10-27' ;;
  '-u +%Y-%m-%dT%H:%M:%SZ') printf '%s\n' '2026-10-27T12:00:00Z' ;;
  *) exec "${REAL_DATE}" "$@" ;;
esac
DATE
  chmod +x "${TEST_DIR}/datebin/date"
  export PATH="${TEST_DIR}/datebin:${PATH}"
}

teardown() { teardown_test_env; }

write_expiry() {
  jq -n --arg expires "$1" --arg basis "${2:-explicit}" \
    '{type: "token", created: "2026-10-27T12:00:00Z", source: "import",
      expires: $expires, expires_basis: $basis}' > "${HOME}/.cwtch/profiles/work/meta.json"
  chmod 600 "${HOME}/.cwtch/profiles/work/meta.json"
}

@test "setup writes mode-600 metadata with a UTC creation time and 365-day estimate" {
  run cwtch profile setup work
  assert_status 0
  assert_file_mode "${HOME}/.cwtch/profiles/work/meta.json" 600
  run jq -e '
    keys == ["created", "expires", "expires_basis", "source", "type"] and
    .type == "token" and .source == "setup" and
    .created == "2026-10-27T12:00:00Z" and
    .expires == "2027-10-27" and .expires_basis == "estimated" and
    .expires == (.created | fromdateiso8601 + 365 * 86400 | strftime("%Y-%m-%d"))
  ' "${HOME}/.cwtch/profiles/work/meta.json"
  assert_status 0
  refute_file_contains "${HOME}/.cwtch/profiles/work/meta.json" "${TEST_TOKEN_A}"
}

@test "save-token imports have unknown expiry unless explicitly supplied" {
  run bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token work'
  assert_status 0
  assert_file_mode "${HOME}/.cwtch/profiles/work/meta.json" 600
  run jq -e '.type == "token" and .source == "import" and
    .created == "2026-10-27T12:00:00Z" and .expires == null and .expires_basis == null' \
    "${HOME}/.cwtch/profiles/work/meta.json"
  assert_status 0

  run bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token work --expires 2027-07-12'
  assert_status 0
  run jq -e '.type == "token" and .source == "import" and
    .expires == "2027-07-12" and .expires_basis == "explicit"' \
    "${HOME}/.cwtch/profiles/work/meta.json"
  assert_status 0
  assert_file_mode "${HOME}/.cwtch/profiles/work/meta.json.bak" 600
}

@test "save-key and OAuth save write metadata with null expiry" {
  run bash -c 'printf "%s\n" "${TEST_APIKEY_A}" | cwtch profile save-key api'
  assert_status 0
  set_mock_credential "$(oauth_credential "${TEST_TOKEN_A}")"
  run cwtch profile save oauth
  assert_status 0
  local name type
  for name in api oauth; do
    type=oauth
    [[ "${name}" != api ]] || type=api-key
    assert_file_mode "${HOME}/.cwtch/profiles/${name}/meta.json" 600
    run jq -e --arg type "${type}" '.type == $type and .source == "import" and
      .created == "2026-10-27T12:00:00Z" and .expires == null and .expires_basis == null' \
      "${HOME}/.cwtch/profiles/${name}/meta.json"
    assert_status 0
    refute_file_contains "${HOME}/.cwtch/profiles/${name}/meta.json" "${TEST_TOKEN_A}"
    refute_file_contains "${HOME}/.cwtch/profiles/${name}/meta.json" "${TEST_APIKEY_A}"
  done
}

@test "save-token validates real calendar dates before reading or saving a credential" {
  local expiry
  for expiry in 2027-02-29 2026-02-30 2026-04-31 2026-00-01 2026-13-01 \
    2026-01-00 2026-1-01 '2026-10-27T00:00:00Z' '' "2026-10-27'"; do
    run --separate-stderr cwtch profile save-token work --expires "${expiry}" </dev/null
    assert_status 1
    assert_stderr_contains "Invalid expiry date"
    [[ -z "${output}" ]]
    [[ ! -e "${HOME}/.cwtch/profiles/work" ]]
  done
  run bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token work --expires 2028-02-29'
  assert_status 0
}

@test "save-token rejects malformed expiry options" {
  local args
  for args in '--expires' '--unknown 2027-07-12' '--expires 2027-07-12 extra'; do
    run --separate-stderr bash -c 'cwtch profile save-token work $1 </dev/null' _ "${args}"
    assert_status 1
    assert_stderr_contains "Usage:"
    [[ -z "${output}" ]]
    [[ ! -e "${HOME}/.cwtch/profiles/work" ]]
  done
}

@test "UTC day arithmetic handles a leap year and supports BSD and GNU date syntax" {
  run bash -c 'source "${ROOT}/lib/common.sh"; date_after_days 2024-02-29 365; date_after_days 2026-12-15 30'
  assert_status 0
  [[ "${output}" == $'2025-02-28\n2027-01-14' ]]

  export DATE_STYLE DATE_CALLS="${TEST_DIR}/date-calls"
  cat > "${TEST_DIR}/datebin/date" <<'DATE'
#!/bin/bash
printf '%s\n' "$*" >> "${DATE_CALLS}"
if [[ "${DATE_STYLE}" == bsd ]] &&
  [[ "$*" == '-u -j -v+365d -f %Y-%m-%d 2024-02-29 +%Y-%m-%d' ]]; then
  printf '%s\n' '2025-02-28'
elif [[ "${DATE_STYLE}" == gnu ]] &&
  [[ "$*" == '-u -d 2024-02-29 +365 days +%Y-%m-%d' ]]; then
  printf '%s\n' '2025-02-28'
else
  exit 1
fi
DATE
  local style
  for style in bsd gnu; do
    DATE_STYLE="${style}"
    : > "${DATE_CALLS}"
    run bash -c 'source "${ROOT}/lib/common.sh"; date_after_days 2024-02-29 365'
    assert_status 0
    [[ "${output}" == '2025-02-28' ]]
    if [[ "${style}" == gnu ]]; then
      assert_file_contains "${DATE_CALLS}" '-u -d 2024-02-29 +365 days'
    fi
  done
}

@test "profile expires preserves an existing token, provenance, creation time, and selection" {
  run cwtch profile setup work
  assert_status 0
  set_current another
  printf '%s\n' owner > "${HOME}/.cwtch/.keychain-owner"
  run cwtch profile expires work 2027-07-12
  assert_status 0
  run jq -e '.source == "setup" and .created == "2026-10-27T12:00:00Z" and
    .expires == "2027-07-12" and .expires_basis == "explicit"' \
    "${HOME}/.cwtch/profiles/work/meta.json"
  assert_status 0
  [[ "$(cat "${HOME}/.cwtch/profiles/work/.token")" == "${TEST_TOKEN_A}" ]]
  [[ ! -e "${HOME}/.cwtch/profiles/work/.token.bak" ]]
  [[ "$(current_file_contents)" == another ]]
  [[ "$(cat "${HOME}/.cwtch/.keychain-owner")" == owner ]]
  assert_file_mode "${HOME}/.cwtch/profiles/work/meta.json" 600
  assert_file_mode "${HOME}/.cwtch/profiles/work/meta.json.bak" 600
  [[ -z "$(security_calls)" ]]
}

@test "profile expires adds metadata to a legacy token without guessing its age" {
  write_token_profile work
  touch -t 200001010000 "${HOME}/.cwtch/profiles/work/.token"
  run cwtch profile expires work 2027-07-12
  assert_status 0
  run jq -e '.type == "token" and .source == "import" and
    .created == null and
    .expires == "2027-07-12" and .expires_basis == "explicit"' \
    "${HOME}/.cwtch/profiles/work/meta.json"
  assert_status 0
  [[ ! -e "${HOME}/.cwtch/.current" ]]
}

@test "profile expires accepts past dates and rejects invalid dates without changing metadata" {
  write_token_profile work
  run cwtch profile expires work 2026-10-01
  assert_status 0
  local before expiry
  before="$(cat "${HOME}/.cwtch/profiles/work/meta.json")"
  for expiry in 2027-02-29 2026-04-31 '2026-1-02' ''; do
    run --separate-stderr cwtch profile expires work "${expiry}"
    assert_status 1
    assert_stderr_contains "Invalid expiry date"
    [[ "$(cat "${HOME}/.cwtch/profiles/work/meta.json")" == "${before}" ]]
  done
}

@test "profile expires rejects missing arguments, unknown names, invalid names, and non-token profiles" {
  run --separate-stderr cwtch profile expires
  assert_status 1
  assert_stderr_contains "Usage:"
  run --separate-stderr cwtch profile expires work
  assert_status 1
  run --separate-stderr cwtch profile expires work 2027-07-12 extra
  assert_status 1
  write_oauth_profile oauth
  write_apikey_profile api
  write_token_profile mixed
  write_apikey_profile mixed
  mkdir -p "${HOME}/.cwtch/profiles/empty"
  local name
  for name in '../outside' ghost oauth api mixed empty; do
    run --separate-stderr cwtch profile expires "${name}" 2027-07-12
    assert_status 1
    [[ -z "${output}" ]]
    [[ -n "${stderr}" ]]
  done
}

@test "re-saving rewrites metadata and clears the old expiry and basis" {
  run cwtch profile setup work
  assert_status 0
  run bash -c 'printf "%s\n" "${TEST_TOKEN_B}" | cwtch profile save-token work'
  assert_status 0
  run jq -e '.type == "token" and .source == "import" and
    .expires == null and .expires_basis == null' "${HOME}/.cwtch/profiles/work/meta.json"
  assert_status 0
  run jq -e '.source == "setup" and .expires_basis == "estimated"' \
    "${HOME}/.cwtch/profiles/work/meta.json.bak"
  assert_status 0
  run bash -c 'printf "%s\n" "${TEST_APIKEY_A}" | cwtch profile save-key work'
  assert_status 0
  run jq -e '.type == "api-key" and .expires == null and .expires_basis == null' \
    "${HOME}/.cwtch/profiles/work/meta.json"
  assert_status 0
  set_mock_credential "$(oauth_credential)"
  run cwtch profile save work
  assert_status 0
  run jq -e '.type == "oauth" and .expires == null and .expires_basis == null' \
    "${HOME}/.cwtch/profiles/work/meta.json"
  assert_status 0
}

@test "profile type ignores metadata even when no credential exists" {
  write_token_profile work
  write_expiry 2027-07-12
  run bash -c 'source "${ROOT}/lib/common.sh"; profile_type work'
  assert_status 0
  [[ "${output}" == token ]]
  rm "${HOME}/.cwtch/profiles/work/.token"
  run bash -c 'source "${ROOT}/lib/common.sh"; profile_type work'
  assert_status 0
  [[ "${output}" == empty ]]
}

@test "deleting a profile removes metadata and its backup" {
  write_token_profile work
  run cwtch profile expires work 2027-07-12
  assert_status 0
  run cwtch profile expires work 2027-08-12
  assert_status 0
  [[ -f "${HOME}/.cwtch/profiles/work/meta.json.bak" ]]
  run cwtch profile delete work
  assert_status 0
  [[ ! -e "${HOME}/.cwtch/profiles/work" ]]
}

@test "list and status render explicit, estimated, and unknown token expiry offline" {
  write_token_profile work
  set_current work
  local basis
  for basis in explicit estimated; do
    write_expiry 2027-07-12 "${basis}"
    run cwtch profile list
    assert_status 0
    if [[ "${basis}" == explicit ]]; then
      assert_output_contains "expires 2027-07-12"
    else
      assert_output_contains "expires ~2027-07-12 (estimated)"
    fi
    run cwtch status
    assert_status 0
    if [[ "${basis}" == explicit ]]; then
      assert_output_contains "expires 2027-07-12"
    else
      assert_output_contains "expires ~2027-07-12 (estimated)"
    fi
  done
  rm "${HOME}/.cwtch/profiles/work/meta.json"
  touch -t 200001010000 "${HOME}/.cwtch/profiles/work/.token"
  run cwtch profile list
  assert_status 0
  assert_output_contains "expiry unknown"
  run cwtch status
  assert_status 0
  assert_output_contains "expiry unknown"
  [[ ! -e "${HOME}/.cwtch/profiles/work/meta.json" ]]
  [[ -z "$(curl_calls)" ]]
  [[ -z "$(security_calls)" ]]
}

@test "non-token list and status output does not show expiry" {
  write_apikey_profile api
  write_oauth_profile oauth
  run cwtch profile list
  assert_status 0
  assert_output_lacks "expiry"
  assert_output_lacks "expires"
  local name
  for name in api oauth; do
    set_current "${name}"
    run cwtch status
    assert_status 0
    assert_output_lacks "expiry"
    assert_output_lacks "expires"
  done
}

@test "env, use, and run warn at exactly 30 UTC days without blocking activation" {
  write_token_profile work
  write_expiry 2026-11-26
  set_current work
  run --separate-stderr cwtch profile env work
  assert_status 0
  assert_stderr_contains "expires on 2026-11-26"
  assert_stderr_contains "within 30 days"
  assert_stderr_contains "cwtch profile setup work"
  assert_output_lacks "expires"
  run --separate-stderr cwtch profile env
  assert_status 0
  assert_stderr_contains "expires on 2026-11-26"
  run --separate-stderr cwtch profile use work
  assert_status 0
  assert_stderr_contains "expires on 2026-11-26"
  run --separate-stderr cwtch run work sh -c 'test "${CWTCH_PROFILE}" = work; exit 7'
  assert_status 7
  assert_stderr_contains "expires on 2026-11-26"
  [[ -z "${output}" ]]
}

@test "env, use, and run do not warn at 31 days or for unknown expiry" {
  write_token_profile work
  set_current work
  local state
  for state in future absent unknown; do
    case "${state}" in
      future) write_expiry 2026-11-27 ;;
      absent) rm "${HOME}/.cwtch/profiles/work/meta.json" ;;
      unknown)
        run bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token work'
        assert_status 0
        ;;
      *) return 1 ;;
    esac
    run --separate-stderr cwtch profile env work
    assert_status 0
    [[ -z "${stderr}" ]]
    run --separate-stderr cwtch profile use work
    assert_status 0
    [[ -z "${stderr}" ]]
    run --separate-stderr cwtch run work sh -c 'exit 0'
    assert_status 0
    [[ -z "${stderr}" ]]
  done
}

@test "expired tokens warn on every activation and estimated warnings stay labelled" {
  write_token_profile work
  write_expiry 2026-10-26 estimated
  run --separate-stderr cwtch profile env work
  assert_status 0
  assert_stderr_contains "expired on 2026-10-26 (estimated)"
  assert_stderr_contains "cwtch profile setup work"
  run --separate-stderr cwtch profile use work
  assert_status 0
  assert_stderr_contains "expired on 2026-10-26"
  run --separate-stderr cwtch run work sh -c 'exit 0'
  assert_status 0
  assert_stderr_contains "expired on 2026-10-26"
}

@test "a token expiring today warns but remains activatable" {
  write_token_profile work
  write_expiry 2026-10-27
  run --separate-stderr cwtch run work sh -c 'test -n "${CLAUDE_CODE_OAUTH_TOKEN}"'
  assert_status 0
  assert_stderr_contains "expires on 2026-10-27"
}

@test "malformed metadata is reported as unknown and never blocks activation" {
  write_token_profile work
  set_current work
  local bad
  for bad in 'not json' '{}' '{} {}'; do
    printf '%s\n' "${bad}" > "${HOME}/.cwtch/profiles/work/meta.json"
    run --separate-stderr cwtch profile env work
    assert_status 0
    assert_stderr_contains "Invalid metadata"
    assert_output_lacks "Invalid metadata"
    run --separate-stderr cwtch profile list
    assert_status 0
    assert_output_contains "expiry unknown"
    assert_stderr_contains "Invalid metadata"
  done
  write_expiry 2027-02-29
  run --separate-stderr cwtch run work sh -c 'exit 0'
  assert_status 0
  assert_stderr_contains "Invalid metadata"
  run --separate-stderr cwtch profile use work
  assert_status 0
  assert_stderr_contains "Invalid metadata"
  run --separate-stderr cwtch status
  assert_status 0
  assert_output_contains "expiry unknown"
  assert_stderr_contains "Invalid metadata"
}

@test "profile expires refuses malformed metadata instead of inventing provenance" {
  write_token_profile work
  printf '%s\n' 'not json' > "${HOME}/.cwtch/profiles/work/meta.json"
  run --separate-stderr cwtch profile expires work 2027-07-12
  assert_status 1
  assert_stderr_contains "save the token again"
  [[ "$(cat "${HOME}/.cwtch/profiles/work/meta.json")" == 'not json' ]]
}

@test "a metadata write failure warns but leaves a complete, single-credential profile" {
  write_apikey_profile work
  mkdir "${HOME}/.cwtch/profiles/work/meta.json"
  run --separate-stderr bash -c 'printf "%s\n" "${TEST_TOKEN_A}" | cwtch profile save-token work'
  assert_status 0
  assert_stderr_contains "Could not write metadata for 'work'; its expiry will show as unknown"
  [[ -f "${HOME}/.cwtch/profiles/work/.token" ]]
  [[ ! -e "${HOME}/.cwtch/profiles/work/.apikey" ]]
  run cwtch profile env work
  assert_status 0
  assert_output_contains "export CWTCH_PROFILE='work'"
}

@test "a non-regular meta.json is never read, so activation cannot block on it" {
  write_token_profile work
  mkfifo "${HOME}/.cwtch/profiles/work/meta.json"
  run --separate-stderr cwtch profile env work
  assert_status 0
  assert_output_contains "export CWTCH_PROFILE='work'"
  assert_stderr_contains "Invalid metadata for 'work'; expiry unknown"
}
