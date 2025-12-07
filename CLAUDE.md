# CLAUDE.md - cwtch

## Overview

cwtch (Welsh: "cuddle/cozy nook") - Manage Claude Code profiles and usage.

> **Note:** This project is not affiliated with, sponsored by, or endorsed by Anthropic PBC.

**Platform:** macOS only (tested on macOS Tahoe). Uses macOS Keychain for credential storage.

## Tech Stack

- **Language**: Bash
- **Platform**: macOS (requires `security` command for Keychain access)
- **Dependencies**: `jq` for JSON parsing
- **Standards**: [Doctrine Shell Guide](https://github.com/agh/doctrine/blob/main/guides/languages/shell.md)

## Repository Structure

```
cwtch/
├── .github/
│   └── workflows/ci.yml    # GitHub Actions CI
├── bin/
│   └── cwtch               # Main CLI
├── lib/
│   └── common.sh           # Shared functions
├── scripts/
│   └── install.sh          # Manual installer
├── tests/
│   └── cwtch.bats          # bats test suite
└── CLAUDE.md               # This file
```

## Quick Start

```bash
# Install via Homebrew
brew tap agh/cask && brew install cwtch

# Save current Claude session
cwtch profile save work

# Switch profiles
cwtch profile use personal

# Check usage across all profiles
cwtch usage

# Check current profile status
cwtch status
```

## Common Commands

| Task | Command |
|------|---------|
| Install | `brew install agh/cask/cwtch` |
| Test | `bats tests/` |
| Lint | `shellcheck bin/cwtch lib/common.sh` |

## Code Style

- Scripts **MUST NOT** exceed 100 lines
- **MUST** use `set -euo pipefail`
- **MUST** use `[[ ]]` for tests, `$()` for substitution
- **MUST** use 2-space indentation
- **MUST** pass shellcheck

## Profile Storage

Profiles are stored in `~/.cwtch/`:

```
~/.cwtch/
├── .current          # Name of active profile
└── profiles/
    ├── work/         # OAuth profile
    ├── personal/     # OAuth profile
    ├── myapi/        # API key profile
    └── ...
```

**OAuth profiles** (from Claude Max subscription):
- Copy of `~/.claude/` session data
- `.credential` file (chmod 600)

**API key profiles**:
- `.apikey` file only (chmod 600)

## Related Projects

- [agh/homebrew-cask](https://github.com/agh/homebrew-cask) - Homebrew tap (`brew tap agh/cask`)
