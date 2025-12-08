# CLAUDE.md - cwtch

## Overview

cwtch (Welsh: "cuddle/cozy nook") — Manage Claude Code profiles and sync configuration from Git.

> **Note:** This project is not affiliated with, sponsored by, or endorsed by Anthropic PBC.

**Platform:** macOS only (tested on macOS Tahoe). Uses macOS Keychain for credential storage.

## Tech Stack

- **Language**: Bash
- **Platform**: macOS (requires `security` command for Keychain access)
- **Dependencies**: `jq` for JSON parsing, `yq` for YAML parsing
- **Standards**: [Doctrine Shell Guide](https://github.com/agh/doctrine/blob/main/guides/languages/shell.md)

## Repository Structure

```
cwtch/
├── .github/
│   └── workflows/ci.yml    # GitHub Actions CI (lint, test, e2e)
├── bin/
│   └── cwtch               # Main CLI entry point
├── lib/
│   ├── common.sh           # Shared functions, profile management
│   ├── config.sh           # Cwtchfile parsing and validation
│   └── sync.sh             # Git sync and namespace linking
├── scripts/
│   └── install.sh          # Manual installer
├── tests/
│   ├── helpers.bash        # Shared test utilities
│   ├── cwtch.bats          # Top-level CLI tests
│   ├── profile.bats        # Profile management tests
│   ├── config.bats         # Cwtchfile validation tests
│   └── sync.bats           # Sync functionality tests
└── docs/
    ├── profiles.md         # Profile management reference
    └── configuration.md    # Cwtchfile and sync reference
```

## Architecture

### Core Concepts

1. **Profiles are thin** — Store only credentials (`.credential` or `.apikey`)
2. **Configuration is declarative** — Defined in `~/.cwtch/Cwtchfile`
3. **Sources merge via namespaces** — Multiple repos coexist as `/namespace/command`
4. **Symlinks for instant updates** — No copying, just linking

### Directory Layout

```
~/.cwtch/
├── Cwtchfile              # Configuration (YAML)
├── .current               # Current profile name
├── profiles/{name}/       # Credentials only
│   └── .credential        # OAuth token (chmod 600)
└── sources/{repo}/        # Cloned repositories

~/.claude/                 # Built by cwtch sync
├── settings.json          # Merged settings
├── CLAUDE.md              # Symlink → source
├── commands/{namespace}/  # Symlink → source
├── agents/{namespace}/    # Symlink → source
└── hooks/{namespace}/     # Symlink → source
```

### Data Flow

```
Cwtchfile → sync_repo() → sources/ → link_namespace() → ~/.claude/
                                   → merge_mcp() → settings.json
```

## Common Commands

| Task | Command |
|------|---------|
| Install | `brew install agh/cask/cwtch` |
| Test | `bats tests/` |
| Lint | `shellcheck bin/cwtch lib/*.sh` |
| Format check | `shfmt -d -i 2 -ci bin/ lib/ scripts/` |

## Code Style

- Scripts **MUST NOT** exceed 100 lines per file
- **MUST** use `set -euo pipefail`
- **MUST** use `[[ ]]` for tests, `$()` for substitution
- **MUST** use 2-space indentation
- **MUST** pass shellcheck
- Log messages go to stderr via `log "..." >&2` when output is captured

## Key Functions

### lib/common.sh
- `profile_save()` — Save current credential to profile
- `profile_use()` — Restore credential from profile
- `get_cred()` / `restore_cred()` — Keychain operations

### lib/config.sh
- `config_get()` — Read top-level Cwtchfile key
- `config_source_get()` — Read source field by index
- `config_validate()` — Validate Cwtchfile structure

### lib/sync.sh
- `sync_repo()` — Clone or update a Git repository
- `link_namespace()` — Create symlink for commands/agents/hooks
- `merge_mcp()` — Deep-merge MCP servers into settings.json
- `do_sync()` — Main sync orchestration

## Testing

Tests use [bats](https://bats-core.readthedocs.io/) with mock utilities:

- **Mock yq** — Tests work without real yq installed (uses grep/awk fallback)
- **Mock security** — Simulates Keychain operations
- **Mock git repos** — Created via `create_mock_repo()` helper

Run tests:
```bash
bats tests/           # All tests
bats tests/sync.bats  # Just sync tests
```

## Related Projects

- [agh/homebrew-cask](https://github.com/agh/homebrew-cask) — Homebrew tap
