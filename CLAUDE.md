# CLAUDE.md - Claude Utilities

## Overview

Utilities for managing Claude Code workflows, including account switching for Max 20x subscriptions.

**Platform:** macOS only (tested on macOS Tahoe). Uses macOS Keychain for credential storage.

## Tech Stack

- **Language**: Bash (POSIX-compatible where possible)
- **Platform**: macOS (requires `security` command for Keychain access)
- **Standards**: [Doctrine Shell Guide](https://github.com/agh/doctrine/blob/main/guides/languages/shell.md)

## Repository Structure

```
claude/
├── .github/workflows/
│   └── ci.yml              # GitHub Actions CI
├── scripts/
│   ├── claude-switch.sh    # Switch between Claude accounts
│   └── install.sh          # Install scripts to PATH
├── tests/
│   └── claude-switch.bats  # bats test suite
├── CLAUDE.md               # This file
├── .shellcheckrc           # shellcheck configuration
└── .editorconfig           # Editor settings
```

## Quick Start

```bash
# Install utilities to ~/.local/bin
./scripts/install.sh

# Save current Claude session
claude-switch save work

# Switch to another account
claude-switch use personal

# List all accounts
claude-switch list
```

## Common Commands

| Task | Command |
|------|---------|
| Install | `./scripts/install.sh` |
| Test | `bats tests/` |
| Lint | `shellcheck scripts/*.sh` |
| Format | `shfmt -i 2 -ci -bn -w scripts/*.sh` |

## Code Style

This project follows the [Shell Style Guide](https://github.com/agh/doctrine/blob/main/guides/languages/shell.md).

Key conventions:
- Scripts **MUST NOT** exceed 100 lines
- **MUST** use `set -euo pipefail`
- **MUST** use `[[ ]]` for tests, `$()` for substitution
- **MUST** use 2-space indentation
- **MUST** pass shellcheck and shfmt

## Account Storage

Accounts are stored in `~/.claude-accounts/`:

```
~/.claude-accounts/
├── .current          # Name of active account
├── work/             # Account 1 (includes .credential)
├── personal/         # Account 2 (includes .credential)
└── ...               # Unlimited accounts
```

Each account directory includes:
- Copy of `~/.claude/` session data
- `.credential` file containing the Keychain credential (chmod 600)

Switching accounts restores both session data and Keychain credential.

## Related Projects

- [agh/doctrine](https://github.com/agh/doctrine) - Style guides
- [agh/homebrew-cask](https://github.com/agh/homebrew-cask) - Homebrew tap (`brew tap agh/cask`)
