#!/bin/bash
# Print the toolchain the test suite depends on, and fail if anything is older
# than the minimum cwtch supports.
#
# CI takes git, jq and yq from the runner image rather than a pinned download,
# so an image change has to be both visible in the log and unable to silently
# degrade the suite. yq must be Mike Farah's Go implementation: the Python
# `yq` wrapper takes different expressions and would misparse every Cwtchfile.

set -euo pipefail

# tool  minimum version
requirements() {
  cat <<'REQS'
git 2.30.0
jq 1.7
yq 4.30.0
bats 1.5.0
REQS
}

version_of() {
  "$1" --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
}

version_ge() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]
}

main() {
  local rc=0 tool minimum found banner

  printf 'bash (this shell): %s\n' "${BASH_VERSION}"
  if [[ -x /bin/bash ]]; then
    printf '/bin/bash:         %s\n' "$(/bin/bash --version | head -1)"
  fi

  while read -r tool minimum; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      printf '%s: not installed (need >= %s)\n' "${tool}" "${minimum}" >&2
      rc=1
      continue
    fi
    banner="$("${tool}" --version 2>&1 | head -1)"
    found="$(version_of "${tool}")"
    printf '%-18s %s\n' "${tool}:" "${banner}"
    if [[ -z "${found}" ]]; then
      printf '%s: could not parse a version from %s\n' "${tool}" "${banner}" >&2
      rc=1
      continue
    fi
    if ! version_ge "${found}" "${minimum}"; then
      printf '%s %s is older than the required %s\n' "${tool}" "${found}" "${minimum}" >&2
      rc=1
    fi
  done < <(requirements)

  if command -v yq >/dev/null 2>&1; then
    case "$(yq --version 2>&1)" in
      *mikefarah*) ;;
      *)
        printf 'yq is not the mikefarah/yq Go implementation; cwtch cannot use it\n' >&2
        rc=1
        ;;
    esac
  fi

  if [[ "${rc}" -ne 0 ]]; then
    printf 'FAIL: toolchain check\n' >&2
    return 1
  fi
  printf 'OK: toolchain meets the minimum versions\n'
}

main "$@"
