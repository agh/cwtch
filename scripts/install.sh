#!/bin/bash
# Install cwtch by symlinking to ~/.local/bin

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR
readonly BIN_DIR="${HOME}/.local/bin"

log() { echo "[install] $*"; }

main() {
  mkdir -p "${BIN_DIR}"

  local target="${BIN_DIR}/cwtch"
  ln -sf "${REPO_DIR}/bin/cwtch" "${target}"
  log "Linked cwtch -> ${target}"

  if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
    local rc_file
    case "${SHELL}" in
      */zsh)  rc_file="${HOME}/.zshrc" ;;
      */bash) rc_file="${HOME}/.bashrc" ;;
      *)      rc_file="your shell rc file" ;;
    esac
    echo ""
    echo "WARNING: ${BIN_DIR} is not in PATH"
    echo "Add to ${rc_file}:"
    echo "  export PATH=\"\${HOME}/.local/bin:\${PATH}\""
  else
    log "PATH already includes ${BIN_DIR}"
  fi
}

main "$@"
