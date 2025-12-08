#!/bin/bash
# Shared test helpers for cwtch tests.

setup_test_env() {
  export TEST_DIR="$(mktemp -d)"
  export HOME="${TEST_DIR}"
  export MOCK_BIN="${TEST_DIR}/bin"
  mkdir -p "${MOCK_BIN}"

  # Mock security command for keychain
  cat > "${MOCK_BIN}/security" << 'MOCK'
#!/bin/bash
MOCK_CRED="${HOME}/.mock-keychain-cred"
case "$1" in
  find-generic-password) [[ -f "${MOCK_CRED}" ]] && cat "${MOCK_CRED}" ;;
  delete-generic-password) rm -f "${MOCK_CRED}" ;;
  add-generic-password) shift; while [[ $# -gt 0 ]]; do [[ "$1" == "-w" ]] && { echo "$2" > "${MOCK_CRED}"; break; }; shift; done ;;
esac
MOCK
  chmod +x "${MOCK_BIN}/security"

  # Use real yq if available, otherwise use a more robust mock
  if command -v yq >/dev/null 2>&1; then
    # Link to real yq
    ln -sf "$(command -v yq)" "${MOCK_BIN}/yq"
  else
    # Create a Python-based mock that handles YAML properly
    cat > "${MOCK_BIN}/yq" << 'MOCK'
#!/bin/bash
# Fallback yq mock using grep/awk for simple YAML parsing
file=""
query=""
raw_mode=false

for arg in "$@"; do
  case "${arg}" in
    -r) raw_mode=true ;;
    -*) ;;
    *)
      if [[ -z "${query}" ]]; then
        query="${arg}"
      else
        file="${arg}"
      fi
      ;;
  esac
done

[[ -z "${file}" ]] && file="/dev/stdin"
[[ ! -f "${file}" ]] && exit 1

case "${query}" in
  ".")
    cat "${file}"
    ;;
  ".sources | length")
    # Count source entries (lines starting with "  - ")
    count=$(grep -c "^  - " "${file}" 2>/dev/null || echo 0)
    echo "${count}"
    ;;
  ".sources | type")
    if grep -q "^sources:" "${file}" 2>/dev/null; then
      echo "!!seq"
    else
      echo "null"
    fi
    ;;
  ".settings // empty")
    val=$(grep "^settings:" "${file}" 2>/dev/null | sed 's/^settings: *//')
    echo "${val}"
    ;;
  ".claude_md // empty")
    val=$(grep "^claude_md:" "${file}" 2>/dev/null | sed 's/^claude_md: *//')
    echo "${val}"
    ;;
  ".sources[].as // empty")
    grep "^    as:" "${file}" 2>/dev/null | sed 's/^    as: *//' || true
    ;;
  .sources\[*\].repo*)
    idx=$(echo "${query}" | sed 's/.*\[\([0-9]*\)\].*/\1/')
    # Find the nth source block and extract repo
    awk -v idx="${idx}" '
      /^  - / { count++; in_block = (count == idx + 1) }
      in_block && /^  - repo:/ { gsub(/^  - repo: */, ""); print; exit }
      in_block && /^    repo:/ { gsub(/^    repo: */, ""); print; exit }
      /^  - / && count > idx + 1 { exit }
    ' "${file}"
    ;;
  .sources\[*\].ref*)
    idx=$(echo "${query}" | sed 's/.*\[\([0-9]*\)\].*/\1/')
    awk -v idx="${idx}" '
      /^  - / { count++; in_block = (count == idx + 1) }
      in_block && /^    ref:/ { gsub(/^    ref: */, ""); print; exit }
      /^  - / && count > idx + 1 { exit }
    ' "${file}"
    ;;
  .sources\[*\].as*)
    idx=$(echo "${query}" | sed 's/.*\[\([0-9]*\)\].*/\1/')
    awk -v idx="${idx}" '
      /^  - / { count++; in_block = (count == idx + 1) }
      in_block && /^    as:/ { gsub(/^    as: */, ""); print; exit }
      /^  - / && count > idx + 1 { exit }
    ' "${file}"
    ;;
  .sources\[*\].commands*)
    idx=$(echo "${query}" | sed 's/.*\[\([0-9]*\)\].*/\1/')
    awk -v idx="${idx}" '
      /^  - / { count++; in_block = (count == idx + 1) }
      in_block && /^    commands:/ { gsub(/^    commands: */, ""); print; exit }
      /^  - / && count > idx + 1 { exit }
    ' "${file}"
    ;;
  .sources\[*\].agents*)
    idx=$(echo "${query}" | sed 's/.*\[\([0-9]*\)\].*/\1/')
    awk -v idx="${idx}" '
      /^  - / { count++; in_block = (count == idx + 1) }
      in_block && /^    agents:/ { gsub(/^    agents: */, ""); print; exit }
      /^  - / && count > idx + 1 { exit }
    ' "${file}"
    ;;
  .sources\[*\].hooks*)
    idx=$(echo "${query}" | sed 's/.*\[\([0-9]*\)\].*/\1/')
    awk -v idx="${idx}" '
      /^  - / { count++; in_block = (count == idx + 1) }
      in_block && /^    hooks:/ { gsub(/^    hooks: */, ""); print; exit }
      /^  - / && count > idx + 1 { exit }
    ' "${file}"
    ;;
  .sources\[*\].mcp*)
    idx=$(echo "${query}" | sed 's/.*\[\([0-9]*\)\].*/\1/')
    awk -v idx="${idx}" '
      /^  - / { count++; in_block = (count == idx + 1) }
      in_block && /^    mcp:/ { gsub(/^    mcp: */, ""); print; exit }
      /^  - / && count > idx + 1 { exit }
    ' "${file}"
    ;;
  *)
    # Default empty
    echo ""
    ;;
esac
MOCK
    chmod +x "${MOCK_BIN}/yq"
  fi

  export PATH="${MOCK_BIN}:${BATS_TEST_DIRNAME}/../bin:${PATH}"
}

teardown_test_env() {
  rm -rf "${TEST_DIR}"
}

# Create a mock git repo for testing sync
create_mock_repo() {
  local name="$1"
  local repo_dir="${TEST_DIR}/repos/${name}.git"
  local src_dir="${TEST_DIR}/repos/${name}-src"

  mkdir -p "${src_dir}/commands" "${src_dir}/agents"
  echo "# Test command" > "${src_dir}/commands/test.md"
  echo "# Test agent" > "${src_dir}/agents/helper.md"

  git -C "${src_dir}" init --quiet
  git -C "${src_dir}" add .
  git -C "${src_dir}" commit -m "init" --quiet

  git clone --bare --quiet "${src_dir}" "${repo_dir}"
  echo "${repo_dir}"
}

# Create a valid Cwtchfile
create_cwtchfile() {
  mkdir -p "${HOME}/.cwtch"
  cat > "${HOME}/.cwtch/Cwtchfile" << EOF
$1
EOF
}
