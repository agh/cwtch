#!/bin/bash
# Refuse Bash 4+ constructs in code that has to run on macOS' /bin/bash 3.2.57.
#
# `bash -n` on its own is not a compatibility gate: `mapfile -t x < f` parses
# cleanly under 3.2 and only blows up when the line is reached. So this script
# pairs the syntax check with a pattern scan, and self-tests both before it
# trusts either - it proves the scanner still matches a fixture containing
# every banned construct, and, when /bin/bash really is 3.2, that /bin/bash
# really does reject them at run time.
#
# The construct table lives in scripts/bash32-constructs.txt so that the
# scanner cannot match its own patterns.
#
# Usage: scripts/check-bash32.sh <file>...

set -euo pipefail

SYSTEM_BASH="${SYSTEM_BASH:-/bin/bash}"
CONSTRUCTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/bash32-constructs.txt"

constructs() {
  grep -vE '^[[:space:]]*(#|$)' "${CONSTRUCTS}"
}

tmpfile() {
  mktemp "${TMPDIR:-/tmp}/cwtch-bash32.XXXXXX"
}

# Scan one file, reporting every hit as `file:line: id: sample`.
scan_file() {
  local file="$1"
  local rc=0 stripped id regex runtime sample hits hit
  stripped="$(tmpfile)"
  # Whole-line comments would otherwise trip the scanner on prose about the
  # very constructs it is looking for.
  sed 's/^[[:space:]]*#.*$//' "${file}" >"${stripped}"
  while read -r id regex runtime sample; do
    : "${runtime}"
    hits="$(grep -nE "${regex}" "${stripped}" || true)"
    if [[ -n "${hits}" ]]; then
      while IFS= read -r hit; do
        printf '%s:%s: %s: not available in Bash 3.2 (e.g. %s)\n' \
          "${file}" "${hit%%:*}" "${id}" "${sample}" >&2
      done <<<"${hits}"
      rc=1
    fi
  done < <(constructs)
  rm -f "${stripped}"
  return "${rc}"
}

# Prove the scanner matches its own fixture, and that a clean file is quiet.
self_test_scanner() {
  local rc=0 id regex runtime sample fixture found
  fixture="$(tmpfile)"
  printf 'true\n' >"${fixture}"
  if ! scan_file "${fixture}" 2>/dev/null; then
    printf 'self-test: scanner reported a hit on a clean file\n' >&2
    rc=1
  fi
  while read -r id regex runtime sample; do
    : "${regex}" "${runtime}"
    printf '%s\n' "${sample}" >"${fixture}"
    # Not a pipeline: `pipefail` plus scan_file's non-zero "found something"
    # status would swallow the grep result.
    found="$(scan_file "${fixture}" 2>&1 >/dev/null || true)"
    case "${found}" in
      *": ${id}: "*) ;;
      *)
        printf 'self-test: scanner no longer detects %s (%s)\n' "${id}" "${sample}" >&2
        rc=1
        ;;
    esac
  done < <(constructs)
  rm -f "${fixture}"
  return "${rc}"
}

# Prove /bin/bash really rejects the constructs, so the table stays grounded in
# observed behaviour rather than memory.
self_test_runtime() {
  local rc=0 id regex runtime sample
  while read -r id regex runtime sample; do
    : "${regex}"
    if [[ "${runtime}" != "yes" ]]; then
      continue
    fi
    if "${SYSTEM_BASH}" -c "${sample}" >/dev/null 2>&1; then
      printf 'self-test: %s ran successfully under %s; it is no longer a 3.2 marker\n' \
        "${id}" "${SYSTEM_BASH}" >&2
      rc=1
    fi
  done < <(constructs)
  return "${rc}"
}

main() {
  local rc=0 file version

  if [[ ! -x "${SYSTEM_BASH}" ]]; then
    printf 'no executable %s; cannot check Bash 3.2 compatibility\n' "${SYSTEM_BASH}" >&2
    return 1
  fi
  if [[ ! -f "${CONSTRUCTS}" ]]; then
    printf '%s is missing\n' "${CONSTRUCTS}" >&2
    return 1
  fi
  version="$("${SYSTEM_BASH}" --version | sed -n '1s/.*version \([0-9.]*\).*/\1/p')"
  printf '%s is %s\n' "${SYSTEM_BASH}" "${version}"

  self_test_scanner || rc=1
  case "${version}" in
    3.2*)
      self_test_runtime || rc=1
      ;;
    *)
      printf 'note: %s is %s, not 3.2, so the run-time probe is skipped here; the macOS test jobs cover it\n' \
        "${SYSTEM_BASH}" "${version}"
      ;;
  esac

  for file in "$@"; do
    "${SYSTEM_BASH}" -n "${file}" || rc=1
    scan_file "${file}" || rc=1
  done

  if [[ "${rc}" -ne 0 ]]; then
    printf 'FAIL: Bash 3.2 compatibility check\n' >&2
    return 1
  fi
  printf 'OK: %s file(s) are Bash 3.2 compatible\n' "$#"
}

main "$@"
