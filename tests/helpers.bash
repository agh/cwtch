#!/bin/bash
# Shared harness for the cwtch test suite (SPEC-v6 §3).
#
# Every test runs against a sandboxed HOME with strict mocks for the three
# external binaries cwtch drives: `security`, `claude` and `curl`. Real `git`,
# `jq` and `yq` are required — a mock YAML parser silently changes what the
# suite proves, so there is no fallback.
#
# Set CWTCH_ROOT to point the suite at a different tree (a scratch copy with a
# candidate fix, for example); it defaults to the repository this file lives in.
#
# Test names prefixed F<n> cite the numbered defect in the 7 September 2026
# revival audit, so a red test points straight at the item it pins.
#
# shellcheck disable=SC2312  # helpers deliberately read command output inline

# --- tree under test ---------------------------------------------------------

cwtch_root() {
  if [[ -n "${CWTCH_ROOT:-}" ]]; then
    (cd "${CWTCH_ROOT}" && pwd)
  else
    (cd "${BATS_TEST_DIRNAME:-.}/.." && pwd)
  fi
}

# --- portability -------------------------------------------------------------

# Octal permission bits of a path, on BSD (macOS) and GNU (Linux) stat alike.
# GNU stat accepts `-f` as --file-system and prints a block for the readable
# operand before failing, so the result is captured in an assignment: the
# fallback then overwrites it rather than appending to stdout.
perm_of() {
  local mode
  mode="$(stat -f '%Lp' "$1" 2>/dev/null)" || mode="$(stat -c '%a' "$1" 2>/dev/null)"
  printf '%s\n' "${mode}"
}

require_tool() {
  local tool missing=""
  for tool in "$@"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      missing="${missing} ${tool}"
    fi
  done
  if [[ -n "${missing}" ]]; then
    printf 'cwtch tests require these tools on PATH:%s\n' "${missing}" >&2
    return 1
  fi
}

# --- environment -------------------------------------------------------------

setup_test_env() {
  require_tool bats jq yq git || return 1

  ROOT="$(cwtch_root)"
  export ROOT

  if [[ -n "${BATS_TEST_TMPDIR:-}" ]]; then
    TEST_DIR="${BATS_TEST_TMPDIR}/home"
  else
    TEST_DIR="$(mktemp -d)"
  fi
  mkdir -p "${TEST_DIR}"
  export TEST_DIR
  export HOME="${TEST_DIR}"
  export TMPDIR="${TEST_DIR}/tmp"
  mkdir -p "${TMPDIR}"

  # Deterministic, colour-free, non-TTY output.
  export NO_COLOR=1
  export TERM=dumb
  unset CLAUDE_CONFIG_DIR CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
  unset ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX
  unset CLAUDE_CODE_USE_FOUNDRY EDITOR GIT_DIR GIT_WORK_TREE

  # Deterministic git, independent of the host's identity and defaultBranch.
  export GIT_AUTHOR_NAME="cwtch tests"
  export GIT_AUTHOR_EMAIL="tests@cwtch.invalid"
  export GIT_COMMITTER_NAME="cwtch tests"
  export GIT_COMMITTER_EMAIL="tests@cwtch.invalid"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="${TEST_DIR}/.gitconfig"
  printf '[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' \
    >"${GIT_CONFIG_GLOBAL}"

  # Mock call logs and scriptable responses.
  export MOCK_KEYCHAIN="${TEST_DIR}/.mock-keychain"
  export SECURITY_CALLS="${TEST_DIR}/.security-calls"
  export CLAUDE_CALLS="${TEST_DIR}/.claude-calls"
  export CURL_CALLS="${TEST_DIR}/.curl-calls"
  : >"${SECURITY_CALLS}"
  : >"${CLAUDE_CALLS}"
  : >"${CURL_CALLS}"
  unset MOCK_SECURITY_ADD_FAIL MOCK_CLAUDE_MODE
  unset MOCK_CURL_USAGE_BODY MOCK_CURL_RELEASE_HEADERS
  export MOCK_CURL_USAGE_EXIT=22
  export MOCK_CURL_RELEASE_EXIT=6

  MOCK_BIN="$(install_mocks)"
  export MOCK_BIN
  export PATH="${MOCK_BIN}:${ROOT}/bin:${PATH}"
}

teardown_test_env() {
  if [[ -n "${TEST_DIR:-}" ]] && [[ -d "${TEST_DIR}" ]]; then
    chmod -R u+rwX "${TEST_DIR}" 2>/dev/null || true
    rm -rf "${TEST_DIR}"
  fi
}

# --- mocks -------------------------------------------------------------------

# The mock scripts are written once per .bats file and read their behaviour from
# the environment, so they can be shared while the call logs stay per-test.
install_mocks() {
  local dir
  if [[ -n "${BATS_FILE_TMPDIR:-}" ]]; then
    dir="${BATS_FILE_TMPDIR}/mockbin"
  else
    dir="${TEST_DIR}/mockbin"
  fi
  if [[ -f "${dir}/.installed" ]]; then
    printf '%s\n' "${dir}"
    return 0
  fi
  mkdir -p "${dir}"
  write_mock_security "${dir}/security"
  write_mock_claude "${dir}/claude"
  write_mock_curl "${dir}/curl"
  : >"${dir}/.installed"
  printf '%s\n' "${dir}"
}

# Strict `security` mock. It fails the call unless cwtch passes the service and
# account it is contracted to pass, honours `-U` (update in place) the way the
# real tool does, and records every call with its -s/-a values.
write_mock_security() {
  cat >"$1" <<'MOCK'
#!/bin/bash
set -uo pipefail
sub="${1:-}"
shift || true

svc="" acct="" secret="" update=0 want_w=0 have_secret=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s) svc="${2:-}"; shift 2 ;;
    -a) acct="${2:-}"; shift 2 ;;
    -U) update=1; shift ;;
    -w)
      if [[ "${sub}" == "add-generic-password" ]]; then
        secret="${2:-}"; have_secret=1; shift 2
      else
        want_w=1; shift
      fi
      ;;
    *) shift ;;
  esac
done

printf 'call=%s service=%s account=%s update=%s secret_len=%s\n' \
  "${sub}" "${svc}" "${acct}" "${update}" "${#secret}" >> "${SECURITY_CALLS}"

expect_svc="${EXPECT_KEYCHAIN_SVC:-Claude Code-credentials}"
expect_acct="${EXPECT_KEYCHAIN_ACCT:-${USER:-$(id -un)}}"

if [[ "${svc}" != "${expect_svc}" ]]; then
  printf "security: unexpected service '%s' (want '%s')\\n" "${svc}" "${expect_svc}" >&2
  exit 44
fi

case "${sub}" in
  find-generic-password)
    if [[ ${want_w} -ne 1 ]]; then
      echo "security: mock expects -w on find-generic-password" >&2
      exit 2
    fi
    if [[ -f "${MOCK_KEYCHAIN}" ]]; then
      cat "${MOCK_KEYCHAIN}"
    else
      echo "security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain." >&2
      exit 44
    fi
    ;;
  add-generic-password)
    if [[ "${acct}" != "${expect_acct}" ]]; then
      printf "security: unexpected account '%s' (want '%s')\\n" "${acct}" "${expect_acct}" >&2
      exit 2
    fi
    if [[ ${have_secret} -ne 1 ]] || [[ -z "${secret}" ]]; then
      echo "security: mock requires a non-empty -w on add-generic-password" >&2
      exit 2
    fi
    if [[ -n "${MOCK_SECURITY_ADD_FAIL:-}" ]]; then
      echo "security: SecKeychainItemCreateFromContent: mock failure" >&2
      exit 45
    fi
    if [[ -f "${MOCK_KEYCHAIN}" ]] && [[ ${update} -eq 0 ]]; then
      echo "security: The specified item already exists in the keychain." >&2
      exit 45
    fi
    printf '%s' "${secret}" > "${MOCK_KEYCHAIN}"
    ;;
  delete-generic-password)
    [[ -f "${MOCK_KEYCHAIN}" ]] || exit 44
    rm -f "${MOCK_KEYCHAIN}"
    ;;
  *)
    printf "security: mock does not implement '%s'\\n" "${sub}" >&2
    exit 2
    ;;
esac
MOCK
  chmod +x "$1"
}

# Strict `claude` mock: rejects any argv other than the contracted one and
# scripts its output through MOCK_CLAUDE_MODE.
write_mock_claude() {
  cat >"$1" <<'MOCK'
#!/bin/bash
set -uo pipefail
printf 'argv=%s\n' "$*" >> "${CLAUDE_CALLS}"

expect="${EXPECT_CLAUDE_ARGV:-setup-token}"
if [[ "$*" != "${expect}" ]]; then
  printf "claude: unexpected argv '%s' (want '%s')\\n" "$*" "${expect}" >&2
  exit 3
fi

case "${MOCK_CLAUDE_MODE:-token}" in
  token)
    printf 'Create a long-lived authentication token.\n\n'
    printf '\033[1mYour token:\033[0m\n'
    printf '\033[32m%s\033[0m\n' "${MOCK_CLAUDE_TOKEN:-sk-ant-oat01-aaaabbbbccccddddeeeeffffgggghhhh}"
    printf '\nStore it somewhere safe.\n'
    ;;
  token-wrapped)
    # The real CLI colours and hard-wraps, so the token can straddle two lines.
    printf '\033[1mYour token:\033[0m\n'
    printf '\033[32msk-ant-oat01-aaaabbbbcccc \n'
    printf 'ddddeeeeffffgggghhhh\033[0m\n'
    ;;
  token-none)
    printf 'Login failed: no browser available.\n' >&2
    ;;
  token-two)
    printf 'Old token: sk-ant-oat01-aaaabbbbccccddddeeeeffffgggghhhh\n'
    printf 'New token: sk-ant-oat01-iiiijjjjkkkkllllmmmmnnnnoooopppp\n'
    ;;
  fail)
    printf 'claude: setup-token failed\n' >&2
    exit 1
    ;;
esac
exit 0
MOCK
  chmod +x "$1"
}

# Scriptable `curl` mock. Routes on the request URL so a single test file can
# script the usage endpoint and the release check independently, and records
# the URL, the headers and the full argv of every call.
#
# Responses are scripted with set_usage_response / set_usage_failure and
# set_latest_release / set_release_check_failure. Because cwtch calls curl with
# `-sf` and `-sIL`, an HTTP failure is observable only as curl's exit status:
# 22 = HTTP >= 400, 6 = could not resolve host, 28 = timeout.
write_mock_curl() {
  cat >"$1" <<'MOCK'
#!/bin/bash
set -uo pipefail

url="" prev=""
for arg in "$@"; do
  case "${prev}" in
    -H) printf 'header=%s\n' "${arg}" >> "${CURL_CALLS}" ;;
  esac
  case "${arg}" in
    http://* | https://*) [[ -z "${url}" ]] && url="${arg}" ;;
  esac
  prev="${arg}"
done
printf 'argv=%s\n' "$*" >> "${CURL_CALLS}"
printf 'url=%s\n' "${url}" >> "${CURL_CALLS}"

case "${url}" in
  *api.anthropic.com*)
    if [[ -f "${MOCK_CURL_USAGE_BODY:-/nonexistent}" ]]; then
      cat "${MOCK_CURL_USAGE_BODY}"
      exit 0
    fi
    exit "${MOCK_CURL_USAGE_EXIT:-22}"
    ;;
  *github.com*)
    if [[ -f "${MOCK_CURL_RELEASE_HEADERS:-/nonexistent}" ]]; then
      cat "${MOCK_CURL_RELEASE_HEADERS}"
      exit 0
    fi
    exit "${MOCK_CURL_RELEASE_EXIT:-6}"
    ;;
esac
exit 6
MOCK
  chmod +x "$1"
}

# --- mock accessors ----------------------------------------------------------

set_claude_mode() { export MOCK_CLAUDE_MODE="$1"; }
set_claude_token() { export MOCK_CLAUDE_TOKEN="$1"; }
fail_keychain_writes() { export MOCK_SECURITY_ADD_FAIL=1; }

security_calls() { cat "${SECURITY_CALLS}" 2>/dev/null || true; }
claude_calls() { cat "${CLAUDE_CALLS}" 2>/dev/null || true; }
curl_calls() { cat "${CURL_CALLS}" 2>/dev/null || true; }

set_mock_credential() { printf '%s' "$1" >"${MOCK_KEYCHAIN}"; }
clear_mock_credential() { rm -f "${MOCK_KEYCHAIN}"; }
keychain_cred() { cat "${MOCK_KEYCHAIN}" 2>/dev/null || true; }

keychain_token() {
  jq -r '.claudeAiOauth.accessToken // empty' <"${MOCK_KEYCHAIN}" 2>/dev/null || true
}

profile_cred_token() {
  jq -r '.claudeAiOauth.accessToken // empty' \
    <"${HOME}/.cwtch/profiles/$1/.credential" 2>/dev/null || true
}

set_usage_response() {
  printf '%s\n' "$1" >"${TEST_DIR}/.usage-body.json"
  export MOCK_CURL_USAGE_BODY="${TEST_DIR}/.usage-body.json"
}

set_usage_failure() {
  unset MOCK_CURL_USAGE_BODY
  export MOCK_CURL_USAGE_EXIT="${1:-22}"
}

# The redirect chain `curl -sIL` sees for /releases/latest; the *last* location
# header carries the tag.
set_latest_release() {
  {
    printf 'HTTP/2 301 \r\n'
    printf 'location: https://github.com/agh/cwtch/releases/latest\r\n'
    printf '\r\n'
    printf 'HTTP/2 302 \r\n'
    printf 'location: https://github.com/agh/cwtch/releases/tag/v%s\r\n' "$1"
    printf '\r\n'
    printf 'HTTP/2 200 \r\n'
    printf '\r\n'
  } >"${TEST_DIR}/.release-headers"
  export MOCK_CURL_RELEASE_HEADERS="${TEST_DIR}/.release-headers"
}

set_release_check_failure() {
  unset MOCK_CURL_RELEASE_HEADERS
  export MOCK_CURL_RELEASE_EXIT="${1:-6}"
}

# --- credential fixtures -----------------------------------------------------

export TEST_TOKEN_A="sk-ant-oat01-aaaabbbbccccddddeeeeffffgggghhhh"
export TEST_TOKEN_B="sk-ant-oat01-iiiijjjjkkkkllllmmmmnnnnoooopppp"
export TEST_APIKEY_A="sk-ant-api03-AAAABBBBCCCCDDDDEEEEFFFF"
export TEST_APIKEY_B="sk-ant-api03-ZZZZYYYYXXXXWWWWVVVVUUUU"

repeat_char() {
  local char="$1" count="$2" out=""
  while [[ ${#out} -lt ${count} ]]; do
    out="${out}${char}"
  done
  printf '%s\n' "${out}"
}

now_ms() { printf '%s\n' "$(($(date +%s) * 1000))"; }

# The Keychain secret shape Claude Code actually stores
# (see .audit/review/04-live-environment.md).
oauth_credential() {
  local token="${1:-access-token}" in_secs="${2:-7200}" now exp refresh_exp
  now="$(now_ms)"
  exp=$((now + in_secs * 1000))
  refresh_exp=$((now + 1296000000))
  printf '{"mcpOAuth":{},"claudeAiOauth":{"accessToken":"%s","refreshToken":"refresh-%s","expiresAt":%s,"refreshTokenExpiresAt":%s,"scopes":["user:file_upload","user:inference","user:mcp_servers","user:profile","user:sessions:claude_code"],"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}' \
    "${token}" "${token}" "${exp}" "${refresh_exp}"
}

# The /api/oauth/usage response shape, trimmed but structurally faithful.
usage_payload() {
  local five="${1:-83.4}" seven="${2:-12.9}"
  cat <<JSON
{"five_hour":{"utilization":${five},"resets_at":"2026-09-08T02:00:00.000000Z","limit_dollars":null,"used_dollars":null,"remaining_dollars":null,"locked_reason":null},
 "seven_day":{"utilization":${seven},"resets_at":"2026-09-14T02:00:00.000000Z","limit_dollars":null,"used_dollars":null,"remaining_dollars":null,"locked_reason":null},
 "seven_day_oauth_apps":null,"seven_day_opus":null,"seven_day_sonnet":null,"seven_day_cowork":null,
 "nimbus_quill":{"utilization":1.0,"resets_at":null},"cinder_cove":null,
 "extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null,"user_disabled":true,"spend_limit_reached":false,"credits_ever_enabled":true,"daily":null,"weekly":null},
 "limits":[{"kind":"dormant_limit","group":"default","percent":3,"severity":"none","resets_at":"2026-09-08T02:00:00.000000Z","scope":null,"is_active":false},
           {"kind":"weekly_opus","group":"opus","percent":41,"severity":"warning","resets_at":"2026-09-14T02:00:00.000000Z","scope":{"model":{"id":null,"display_name":"Opus"},"surface":null},"is_active":true}],
 "spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},"limit":null,"percent":0,"severity":"none","enabled":false},
 "member_dashboard_available":false}
JSON
}

# --- profile fixtures --------------------------------------------------------

profiles_dir() { printf '%s\n' "${HOME}/.cwtch/profiles"; }

write_oauth_profile() {
  local name="$1" token="${2:-${TEST_TOKEN_A}}"
  mkdir -p "${HOME}/.cwtch/profiles/${name}"
  oauth_credential "${token}" >"${HOME}/.cwtch/profiles/${name}/.credential"
  chmod 600 "${HOME}/.cwtch/profiles/${name}/.credential"
}

write_token_profile() {
  local name="$1" token="${2:-${TEST_TOKEN_A}}"
  mkdir -p "${HOME}/.cwtch/profiles/${name}"
  printf '%s\n' "${token}" >"${HOME}/.cwtch/profiles/${name}/.token"
  chmod 600 "${HOME}/.cwtch/profiles/${name}/.token"
}

write_apikey_profile() {
  local name="$1" key="${2:-${TEST_APIKEY_A}}"
  mkdir -p "${HOME}/.cwtch/profiles/${name}"
  printf '%s\n' "${key}" >"${HOME}/.cwtch/profiles/${name}/.apikey"
  chmod 600 "${HOME}/.cwtch/profiles/${name}/.apikey"
}

set_current() {
  mkdir -p "${HOME}/.cwtch"
  printf '%s\n' "$1" >"${HOME}/.cwtch/.current"
}

current_file_contents() { cat "${HOME}/.cwtch/.current" 2>/dev/null || true; }

# --- config fixtures ---------------------------------------------------------

create_cwtchfile() {
  mkdir -p "${HOME}/.cwtch"
  printf '%s\n' "$1" >"${HOME}/.cwtch/Cwtchfile"
}

# --- git fixtures ------------------------------------------------------------

# create_mock_repo <name> [branch] -> prints the absolute path of a git repo.
#
# The first repo built in a .bats file is cached and later ones are copied from
# it, which is roughly ten times cheaper than another init+commit.
create_mock_repo() {
  local name="$1" branch="${2:-main}"
  local dir="${TEST_DIR}/repos/${name}" cache=""

  if [[ -n "${BATS_FILE_TMPDIR:-}" ]]; then
    cache="${BATS_FILE_TMPDIR}/repo-template-${branch}"
  fi

  mkdir -p "$(dirname "${dir}")"
  if [[ -n "${cache}" ]] && [[ -d "${cache}" ]]; then
    cp -R "${cache}" "${dir}"
  else
    build_mock_repo "${dir}" "${branch}"
    if [[ -n "${cache}" ]]; then
      cp -R "${dir}" "${cache}"
    fi
  fi
  printf '%s\n' "${dir}"
}

build_mock_repo() {
  local dir="$1" branch="${2:-main}"
  mkdir -p "${dir}/skills/reviewer" "${dir}/skills/notes" "${dir}/skills/notaskill"
  mkdir -p "${dir}/commands" "${dir}/agents/nested" "${dir}/config"

  printf '%s\n' '---' 'name: reviewer' '---' '# Reviewer skill' >"${dir}/skills/reviewer/SKILL.md"
  printf '%s\n' '---' 'name: notes' '---' '# Notes skill' >"${dir}/skills/notes/SKILL.md"
  printf '%s\n' '# Not a skill: no SKILL.md here' >"${dir}/skills/notaskill/README.md"

  printf '%s\n' '# Deploy command' >"${dir}/commands/deploy.md"
  printf '%s\n' '# Review command' >"${dir}/commands/review.md"
  printf '%s\n' 'not markdown' >"${dir}/commands/notes.txt"

  printf '%s\n' '---' 'name: helper' '---' '# Helper agent' >"${dir}/agents/helper.md"
  printf '%s\n' '---' 'name: deep' '---' '# Deep agent' >"${dir}/agents/nested/deep.md"

  printf '%s\n' '{"mcpServers":{"demo":{"command":"demo","args":["--stdio"]}}}' >"${dir}/mcp.json"
  printf '%s\n' '{"bare":{"command":"bare-server"}}' >"${dir}/mcp-bare.json"
  printf '%s\n' '{"model":"sonnet","env":{"FROM_BASE":"1"},"permissions":{"defaultMode":"acceptEdits"}}' \
    >"${dir}/config/settings.json"
  printf '%s\n' '# Shared CLAUDE.md' 'From the source repo.' >"${dir}/config/CLAUDE.md"

  git -C "${dir}" init --quiet -b "${branch}"
  git -C "${dir}" add -A
  git -C "${dir}" commit --quiet -m "initial"
}

# repo_commit <repo-dir> <relative-path> <content> [message]
repo_commit() {
  local dir="$1" file="$2" content="$3" message="${4:-update}"
  mkdir -p "$(dirname "${dir}/${file}")"
  printf '%s\n' "${content}" >"${dir}/${file}"
  git -C "${dir}" add -A
  git -C "${dir}" commit --quiet -m "${message}"
}

# repo_add_branch <repo-dir> <branch> <relative-path> <content>
repo_add_branch() {
  local dir="$1" branch="$2" file="$3" content="$4" original
  original="$(git -C "${dir}" rev-parse --abbrev-ref HEAD)"
  git -C "${dir}" checkout --quiet -b "${branch}"
  repo_commit "${dir}" "${file}" "${content}" "on ${branch}"
  git -C "${dir}" checkout --quiet "${original}"
}

repo_add_tag() { git -C "$1" tag "$2"; }

# The single directory cwtch cloned into, for tests with exactly one source.
only_source_dir() {
  local entry
  for entry in "${HOME}"/.cwtch/sources/*; do
    if [[ -d "${entry}" ]]; then
      printf '%s\n' "${entry}"
      return 0
    fi
  done
  return 1
}

count_sources() {
  local entry count=0
  for entry in "${HOME}"/.cwtch/sources/*; do
    [[ -d "${entry}" ]] && count=$((count + 1))
  done
  printf '%s\n' "${count}"
}

# --- assertions --------------------------------------------------------------
#
# These read the globals `run` sets, and print the captured output on failure so
# a red test in CI is diagnosable without re-running it locally.
# shellcheck disable=SC2154  # status/output/stderr are set by bats' `run`

assert_status() {
  if [[ "${status}" -ne "$1" ]]; then
    printf 'expected exit status %s, got %s\n--- output ---\n%s\n' \
      "$1" "${status}" "${output}" >&2
    return 1
  fi
}

assert_output_contains() {
  if [[ "${output}" != *"$1"* ]]; then
    printf 'expected output to contain: %s\n--- output ---\n%s\n' "$1" "${output}" >&2
    return 1
  fi
}

assert_output_lacks() {
  if [[ "${output}" == *"$1"* ]]; then
    printf 'expected output NOT to contain: %s\n--- output ---\n%s\n' "$1" "${output}" >&2
    return 1
  fi
}

assert_stderr_contains() {
  if [[ "${stderr}" != *"$1"* ]]; then
    printf 'expected stderr to contain: %s\n--- stderr ---\n%s\n' "$1" "${stderr}" >&2
    return 1
  fi
}

assert_file_mode() {
  local mode
  mode="$(perm_of "$1")"
  if [[ "${mode}" != "$2" ]]; then
    printf 'expected %s to be mode %s, got %s\n' "$1" "$2" "${mode}" >&2
    return 1
  fi
}

# Regex forms. These are functions rather than `! grep …` because a bare `!` in
# a bats test body only fails the test when it is the final command.
assert_output_matches() {
  if ! printf '%s\n' "${output}" | grep -Eq "$1"; then
    printf 'expected output to match: %s\n--- output ---\n%s\n' "$1" "${output}" >&2
    return 1
  fi
}

refute_output_matches() {
  if printf '%s\n' "${output}" | grep -Eq "$1"; then
    printf 'expected output NOT to match: %s\n--- output ---\n%s\n' "$1" "${output}" >&2
    return 1
  fi
}

assert_file_contains() {
  if ! grep -q -- "$2" "$1"; then
    printf 'expected %s to contain: %s\n--- file ---\n%s\n' "$1" "$2" "$(cat "$1")" >&2
    return 1
  fi
}

refute_file_contains() {
  if grep -q -- "$2" "$1"; then
    printf 'expected %s NOT to contain: %s\n--- file ---\n%s\n' "$1" "$2" "$(cat "$1")" >&2
    return 1
  fi
}

refute_file_matches() {
  if grep -Eq -- "$2" "$1"; then
    printf 'expected %s NOT to match: %s\n--- file ---\n%s\n' "$1" "$2" "$(cat "$1")" >&2
    return 1
  fi
}

assert_symlink_to() {
  local resolved
  if [[ ! -L "$1" ]]; then
    printf 'expected %s to be a symlink\n' "$1" >&2
    return 1
  fi
  resolved="$(cd "$(dirname "$1")" && cd "$(dirname "$(readlink "$1")")" 2>/dev/null && pwd)/$(basename "$(readlink "$1")")"
  if [[ "$(readlink "$1")" != "$2" ]] && [[ "${resolved}" != "$2" ]]; then
    printf 'expected %s -> %s, got %s\n' "$1" "$2" "$(readlink "$1")" >&2
    return 1
  fi
}
