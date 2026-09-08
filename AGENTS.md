# AGENTS.md - cwtch

## Overview

cwtch (Welsh: "cuddle/cosy nook") manages Claude Code profiles and syncs selected configuration
from Git.

> **Note:** This project is not affiliated with, sponsored by, or endorsed by Anthropic PBC.

## Platforms and dependencies

The product runs on macOS because OAuth profile switching uses `security` and macOS Keychain.
Ubuntu is a supported test environment through mocks, not a product runtime.

Runtime dependencies:

- macOS `/bin/bash` 3.2.57-compatible shell code
- Git, `curl`, and `shasum`
- `jq`
- Mike Farah's real `yq` v4; there is no test or runtime fallback
- Claude Code for `profile setup`
- macOS `security` for OAuth snapshot profiles

Development dependencies include bats 1.5 or later, shellcheck, shfmt, and Make.

## Repository structure

```text
cwtch/
├── .devcontainer/          # Linux editing and test environment
├── .github/
│   ├── ISSUE_TEMPLATE/
│   ├── workflows/          # CI, release, scanning, and Scorecard workflows
│   └── PULL_REQUEST_TEMPLATE.md
├── assets/                 # README and release artwork
├── bin/
│   └── cwtch               # Argument dispatch and output rendering
├── docs/
│   ├── configuration.md
│   ├── profiles.md
│   ├── security.md
│   └── troubleshooting.md
├── lib/
│   ├── common.sh           # Shared output, validation, profiles, Keychain, usage
│   ├── config.sh           # Cwtchfile parsing and validation
│   └── sync.sh             # Repositories, merges, links, manifest, pruning
├── scripts/
│   └── install.sh
├── tests/
│   ├── helpers.bash        # Sandboxed HOME, strict security/claude/curl mocks, fixtures
│   ├── cli.bats            # Dispatch, help, aliases, exit codes, deprecated refresh
│   ├── names.bats          # validate_name, .current handling, path safety
│   ├── profile.bats        # Save, use, delete, setup, credential storage
│   ├── env.bats            # profile env output and precedence warnings
│   ├── status.bats         # Offline status rendering
│   ├── usage.bats          # Best-effort usage rendering with a mocked curl
│   ├── version.bats        # -v, --version and the update check
│   ├── config.bats         # Cwtchfile validation
│   ├── sync.bats           # Repositories, refs, outputs, manifest
│   ├── sync-safety.bats    # Symlink-only replacement, backups, ref injection
│   └── e2e.bats            # Real-output checks; network clone gated on CWTCH_E2E=1
├── CHANGELOG.md
├── CONTRIBUTING.md
├── Makefile
├── SECURITY.md
└── VERSION
```

## Architecture

### Profiles

Profiles contain exactly one credential:

- `.token` — setup token exported as `CLAUDE_CODE_OAUTH_TOKEN`
- `.credential` — OAuth JSON copied from and restored to macOS Keychain
- `.apikey` — API key exported as `ANTHROPIC_API_KEY`

The selected name is stored in `~/.cwtch/.current`. `validate_name()` protects profile and
namespace paths, `current_profile()` validates `.current`, and `write_secret()` creates mode-`600`
files and their single `.bak` backup.

### Configuration

`~/.cwtch/Cwtchfile` declares optional base settings, user `CLAUDE.md`, and Git sources.
Repositories live below `~/.cwtch/sources/`. cwtch merges JSON and creates symlinks in
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, while user MCP servers are merged into
`${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json`.

```text
Cwtchfile -> config_validate()
          -> sync_repo() -> sources/
          -> settings merge / CLAUDE.md link
          -> skill conversion / agent links / MCP merge
          -> state/links manifest and conservative pruning
```

Only symlinks are replaced for linked outputs. Managed source checkouts are disposable; local edits
are discarded.

## Key functions

### `bin/cwtch`

- `main()` — top-level dispatch and standard exit behaviour
- `usage_help()` — complete command and alias help
- `cmd_profile()` — profile subcommand dispatch
- `cmd_setup()` — capture, extract, validate, and save one setup token
- `cmd_refresh()` — deprecated quiet-aware no-op
- `cmd_status()` — offline profile and source rendering
- `cmd_usage()` — best-effort per-profile usage rendering
- `cmd_version()` — offline version output or the explicit update-check path

### `lib/common.sh`

- `validate_name()` / `current_profile()` — safe names and active-profile lookup
- `write_secret()` — atomic mode-`600` writes and one-file backups
- `get_cred()` / `get_token()` — Keychain and OAuth access-token reads
- `profile_save()` / `profile_save_token()` / `profile_save_key()` — typed credential storage
- `profile_use()` / `profile_list()` — safe switching and type rendering
- `fetch_usage()` — bounded usage request

### `lib/config.sh`

- `config_get()` / `config_source_get()` — yq-backed Cwtchfile access
- `config_validate()` — schema, name, ref, placeholder, and duplicate validation

### `lib/sync.sh`

- `repo_to_url()` / `repo_local_path()` — canonical source URL and collision-resistant checkout path
- `sync_repo()` — shallow clone or fetched-ref checkout
- settings, MCP, skill, command, agent, and `CLAUDE.md` helpers — safe output application
- `do_sync()` — dry-run planning, per-source error collection, manifest update, and pruning

## Make targets

Use Make targets rather than duplicating tool arguments:

| Target | Purpose |
|---|---|
| `make check` | Run the complete local check set used by CI |
| `make lint` | Run shellcheck with the repository `.shellcheckrc` |
| `make fmt` | Rewrite shell sources with `shfmt -i 2 -ci` |
| `make fmt-check` | Fail when shfmt would change a file |
| `make test` | Run the bats suite |
| `make test-hermetic` | Run tests with isolated Git configuration and `USER` unset |
| `make bash32-check` | Parse shell files with macOS `/bin/bash` 3.2 |
| `make e2e` | Run macOS end-to-end checks against real platform facilities |

CI runs linting and portable tests on Ubuntu 24.04, tests on macOS 15 and macOS 26, hermetic tests,
Bash 3.2 parsing, and macOS end-to-end coverage.

## Shell style

- Executable scripts use `set -euo pipefail`; sourced libraries inherit it from `bin/cwtch`.
- Keep Bash 3.2 compatibility: no `${var,,}`, `mapfile`, `readarray`, `declare -A`, `|&`, `&>>`,
  negative substring indices, or other Bash 4 features.
- Use `[[ ... ]]` for tests, `$()` for command substitution, and two-space indentation.
- Print user-controlled strings with `printf '%s\n'`; reserve `%b` for cwtch's own colour codes.
- Honour `NO_COLOR`, `TERM=dumb`, and non-terminal output.
- Send progress messages to standard error when a function's standard output is captured.
- Each file has one responsibility. Split responsibilities when necessary; do not impose an
  arbitrary line-count limit.
- Never compress statements to satisfy a length budget.
- Run `make lint` and `make fmt-check`.
- Write user-facing text in British English.

## Test conventions

Tests use bats 1.5 or later and the real `jq`, `yq`, and Git executables.

`tests/helpers.bash` provides:

- a sandboxed `HOME`;
- isolated author, committer, and global Git configuration;
- `GIT_CONFIG_NOSYSTEM=1` and `init.defaultBranch=main`;
- strict `security`, `claude`, and `curl` mocks with scriptable results;
- real-shape credential and usage fixtures;
- mock Git repository builders;
- portable permission inspection.

Every behaviour change needs a focused bats test. Run related tests first, then `make check`.
Platform-independent tests must pass on macOS and Ubuntu, both normally and with `USER` unset.
Real Keychain integration belongs in macOS end-to-end coverage.

## Release procedure

1. Set `VERSION` to `X.Y.Z`.
2. Add the dated release and migration notes to `CHANGELOG.md`.
3. Run `make check` and `make e2e`.
4. Commit the release changes.
5. Create a signed tag: `git tag -s vX.Y.Z -m "vX.Y.Z"`.
6. Push the commit and tag.
7. Replace the Homebrew formula checksum and bump the formula in
   [agh/homebrew-cask](https://github.com/agh/homebrew-cask).

The release workflow requires the tag and `VERSION` to match.
