#!/bin/bash
# Install cwtch by symlinking bin/cwtch into ~/.local/bin.
#
# Usage: scripts/install.sh [--force]
#
# The installer refuses to overwrite anything it did not create. ~/.local/bin
# is shared with every other tool a user installs by hand, and `ln -sf` there
# would silently destroy an unrelated `cwtch` - a Homebrew shim, a different
# checkout, or a script of the user's own. --force moves the existing entry to
# cwtch.bak instead of deleting it.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly REPO_DIR
readonly BIN_DIR="${HOME}/.local/bin"
readonly SOURCE="${REPO_DIR}/bin/cwtch"

log() { printf '[install] %s\n' "$*"; }
err() { printf '[install] %s\n' "$*" >&2; }

# Absolute, symlink-free path of an existing symlink's target.
link_target() {
  local link="$1" dest
  dest="$(readlink "${link}")"
  case "${dest}" in
    /*) ;;
    *) dest="$(dirname "${link}")/${dest}" ;;
  esac
  printf '%s/%s\n' "$(cd "$(dirname "${dest}")" && pwd -P)" "$(basename "${dest}")"
}

# Decide what to do about an existing ~/.local/bin/cwtch. Returns 1 to abort.
inspect_target() {
  local target="$1" force="$2"

  if [[ -L "${target}" ]]; then
    if [[ "$(link_target "${target}")" == "${SOURCE}" ]]; then
      return 0
    fi
    if [[ "${force}" == "1" ]]; then
      log "Moving the existing symlink aside: ${target} -> ${target}.bak"
      mv -f "${target}" "${target}.bak"
      return 0
    fi
    err "${target} is a symlink to $(link_target "${target}")"
    err "Refusing to replace it. Remove it, or re-run with --force."
    return 1
  fi

  if [[ -e "${target}" ]]; then
    if [[ "${force}" == "1" ]]; then
      log "Moving the existing file aside: ${target} -> ${target}.bak"
      mv -f "${target}" "${target}.bak"
      return 0
    fi
    err "${target} already exists and was not created by this installer."
    err "Refusing to replace it. Remove it, or re-run with --force."
    return 1
  fi

  return 0
}

path_hint() {
  local rc_file
  case "${SHELL:-}" in
    */zsh) rc_file="${HOME}/.zshrc" ;;
    */bash) rc_file="${HOME}/.bashrc" ;;
    *) rc_file="your shell rc file" ;;
  esac
  printf '\n'
  err "WARNING: ${BIN_DIR} is not in PATH"
  err "Add to ${rc_file}:"
  # shellcheck disable=SC2016 # the line is printed for the user to copy verbatim
  err '  export PATH="${HOME}/.local/bin:${PATH}"'
}

main() {
  local force=0 arg
  for arg in "$@"; do
    case "${arg}" in
      --force) force=1 ;;
      -h | --help)
        printf 'Usage: scripts/install.sh [--force]\n'
        return 0
        ;;
      *)
        err "Unknown option: ${arg}"
        return 1
        ;;
    esac
  done

  if [[ ! -x "${SOURCE}" ]]; then
    err "${SOURCE} is missing or not executable"
    return 1
  fi

  mkdir -p "${BIN_DIR}"
  local target="${BIN_DIR}/cwtch"
  inspect_target "${target}" "${force}" || return 1

  ln -sfn "${SOURCE}" "${target}"
  log "Linked ${target} -> ${SOURCE}"

  if [[ ":${PATH}:" == *":${BIN_DIR}:"* ]]; then
    log "PATH already includes ${BIN_DIR}"
  else
    path_hint
  fi
}

main "$@"
