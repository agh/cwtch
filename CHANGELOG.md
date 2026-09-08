# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [6.0.0] - 2026-09-07

### Breaking

- Profile names, the active profile name, and Cwtchfile `as` values must now use letters, digits,
  dots, underscores, or hyphens, begin with a letter or digit, and be no longer than 64 characters
- Removed profile-specific Cwtchfile overlays
- Removed `hooks:` from the Cwtchfile; hooks must be registered in Claude Code settings with an
  event and matcher
- Changed `commands:` outputs from namespaced command directories to skills named
  `/<as>-<name>`
- Moved user-scope MCP server output from `settings.json` to `~/.claude.json`, or
  `$CLAUDE_CONFIG_DIR/.claude.json`
- Changed `settings:` from wholesale replacement to a deep merge where existing user values win

### Added

- Native `skills:` sources, linked as `/<as>-<skill>`
- `cwtch sync --force` to back up and replace a regular user `CLAUDE.md`
- `cwtch sync --dry-run` to print the sync plan without changing files
- A managed-link manifest at `~/.cwtch/state/links` for conservative stale-link pruning
- Validation for profile names, setup tokens, API keys, namespaces, Git refs, and `repo:path`
  values
- Safe mode-`600` secret writes with a single `.bak` backup
- Outgoing OAuth snapshots before OAuth-to-OAuth switches
- Support for `CLAUDE_CONFIG_DIR` in synced Claude Code paths, with a warning about custom
  Keychain identities
- Remote default-branch discovery before the `main` fallback
- Settings, `CLAUDE.md`, and `.claude.json` backups when sync changes existing content
- Security and troubleshooting documentation

### Changed

- `profile env` now unsets `CLAUDE_CODE_OAUTH_TOKEN` and `ANTHROPIC_API_KEY` before printing the
  selected export or OAuth comment
- `profile env` warns when `ANTHROPIC_AUTH_TOKEN` or a supported cloud-provider flag takes
  precedence
- OAuth Keychain updates now occur in place, and `.current` is written only after a successful
  update
- `status` is fully offline and no longer includes usage data
- `usage` handles unreadable credentials and unavailable requests per profile, includes active
  limit entries, and keeps Claude Code's `/usage` as the authoritative source
- `-v` and `--version` now print only `cwtch <version>` without a network request or Git revision
- `version` keeps the update check but never fails when GitHub is unavailable
- Source checkout directories are collision-resistant, including hashed absolute local paths
- Source updates check out the fetched ref directly and report every Git failure
- `sync init` now writes a valid no-op Cwtchfile with its source example commented out
- Renamed the repository guidance file to `AGENTS.md`, retaining `CLAUDE.md` as an `@AGENTS.md`
  compatibility pointer

### Fixed

- Strip ANSI escape sequences and join wrapped output before extracting a setup token
- Reject missing, malformed, or multiple setup-token candidates without printing captured output
- Accept absent, null, and empty `sources` values
- Reject the uncommented `owner/repo` placeholder
- Prevent failed Keychain writes from changing the active profile
- Preserve user settings while applying repository defaults
- Preserve existing MCP servers while allowing newly configured servers to replace duplicate names
- Prevent sync from replacing regular skill, command, or agent targets
- Prevent manifest pruning from removing links outside cwtch-managed sources
- Ensure invalid profile paths cannot escape the profiles directory during deletion

### Removed

- OAuth refresh internals and the network or Claude Code calls previously made by `refresh`
- Profile-overlay status output
- Legacy command namespace links after their conversion to skills
- Git SHA output from every version command
- Dead refresh and token-expiry helpers

### Security

- Create secret and setup-token temporary files with mode `600` from the start
- Validate credential formats again before printing shell exports
- Pass `--` before untrusted Git refs and URLs
- Replace link targets only when they are symlinks; never recursively delete a conflicting target
- Back up sensitive configuration before an intentional replacement

### Migrating from 5.x

Remove `hooks:` and profile overlays, review the new `/<as>-<name>` skill names, and expect MCP
servers in `.claude.json`. Existing user settings now override repository defaults. Run
`cwtch sync check` and `cwtch sync --dry-run` before the first 6.0.0 sync. `refresh` remains as a
deprecated no-op for one major release.

## [5.3.0] - 2026-02-07

### Added

- Long-lived token profiles stored in `.token` files
- `cwtch profile setup <name>` to run `claude setup-token` and save its token
- `cwtch profile save-token <name>` to save an existing long-lived token
- `cwtch profile token` to print the selected profile's token
- `cwtch profile env` to print `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` exports

### Changed

- Long-lived token profiles are shown as the recommended setup path in help and empty status output
- `profile list`, `profile use`, `usage`, `status`, and `refresh` recognise token profiles

## [5.2.0] - 2026-01-03

### Added

- `cwtch refresh` command to automatically refresh expiring OAuth tokens
- Quiet mode (`-q`) for shell startup integration
- Token expiry checking with a 30-minute threshold

### Usage

Add to `~/.zshrc` for automatic token refresh on terminal startup:

```bash
cwtch refresh -q 2>/dev/null
```

## [5.1.0] - 2025-12-07

### Added

- `cwtch version` command with a GitHub release update check
- Version output in help and status
- Banner and icon assets
- Exit-code tests

### Changed

- Styled help, status, usage, profile-list, and sync output with Unicode symbols
- Colour-coded usage percentages and support for `NO_COLOR` and non-terminal output
- Removed the README's ASCII-art banner

## [5.0.2] - 2025-12-07

### Fixed

- Ensure `cwtch usage` exits successfully

## [5.0.1] - 2025-12-07

### Fixed

- Use `yq` v4-compatible empty-value expressions
- Restore the `cwtch usage` command

## [5.0.0] - 2025-12-07

### Added

- **Configuration sync from Git repositories** — New `cwtch sync` command pulls commands, agents,
  hooks, and MCP servers from remote repositories
- **Cwtchfile** — Declarative YAML configuration at `~/.cwtch/Cwtchfile`
- **Namespace-based merging** — Multiple sources coexist via the `as:` field
- **MCP server merging** — MCP configurations are deep-merged into `settings.json`
- **Base settings and CLAUDE.md** — Sync global settings and CLAUDE.md from repositories
- `cwtch sync init` — Create an example Cwtchfile
- `cwtch sync check` — Validate a Cwtchfile without syncing
- `cwtch edit` — Open the Cwtchfile in an editor
- `yq` dependency for YAML parsing

### Changed

- **BREAKING**: Profiles now store only credentials, not the entire `~/.claude/` directory
- **BREAKING**: `cwtch profile use` no longer modifies `~/.claude/`; use `cwtch sync` for
  configuration
- `cwtch status` now shows sync state alongside profile and usage
- Architecture refactored to separate identity from configuration

## [4.0.4] - 2025-12-07

### Added

- macOS end-to-end CI job
- GitHub release workflow for version tags

### Fixed

- Replaced a non-existent shfmt action in CI

## [4.0.3] - 2025-12-07

### Fixed

- Fixed symlink resolution to follow a chain to its real path

## [4.0.2] - 2025-12-07

### Fixed

- Fixed symlink resolution for relative symlink targets

## [4.0.1] - 2025-12-07

### Fixed

- Fixed symlink resolution for Homebrew installation

## [4.0.0] - 2025-12-07

### Changed

- **BREAKING**: Profile storage moved from `~/.claude-accounts/` to `~/.cwtch/profiles/`

## [3.0.0] - 2025-12-07

### Added

- New CLI structure with subcommands (`cwtch profile`, `cwtch status`, `cwtch usage`)
- `cwtch status` command shows the current profile and its usage
- `cwtch usage` command shows usage for all profiles
- API-key profile support
- CONTRIBUTING.md with contribution guidelines
- SECURITY.md with vulnerability reporting procedures
- GitHub issue and pull request templates

### Changed

- **BREAKING**: Renamed the project from `claude-utils` to `cwtch`
- **BREAKING**: Renamed the CLI from `claude-switch` to `cwtch`
- **BREAKING**: Changed the command structure
- Moved the main script from `scripts/` to `bin/`
- Changed terminology from accounts to profiles

### Removed

- Old `claude-switch` CLI entry point

## [2.1.0] - 2025-12-07

### Added

- `status` command to show 5-hour and 7-day utilisation for all saved accounts
- `lib/common.sh` for shared functions
- `jq` dependency for JSON parsing

### Changed

- Refactored the script to source a shared library

## [2.0.0] - 2025-12-07

### Added

- Keychain credential storage and restoration on account switch
- Devcontainer support for a consistent development environment
- macOS platform documentation

### Fixed

- Account switching now changes Keychain credentials
- Added a check for running Claude processes before switching

### Changed

- **BREAKING**: Accounts saved with v1.0.0 must be saved again to include credentials

## [1.0.0] - 2025-12-07

### Added

- `claude-switch` script for switching between Claude Code accounts
- `install.sh` script for symlinking utilities to `~/.local/bin`
- shellcheck and EditorConfig configuration
- `CLAUDE.md` project context file
- MIT licence
- bats test suite
- GitHub Actions CI

[Unreleased]: https://github.com/agh/cwtch/compare/v6.0.0...HEAD
[6.0.0]: https://github.com/agh/cwtch/compare/v5.3.0...v6.0.0
[5.3.0]: https://github.com/agh/cwtch/compare/v5.2.0...v5.3.0
[5.2.0]: https://github.com/agh/cwtch/compare/v5.1.0...v5.2.0
[5.1.0]: https://github.com/agh/cwtch/compare/v5.0.2...v5.1.0
[5.0.2]: https://github.com/agh/cwtch/compare/v5.0.1...v5.0.2
[5.0.1]: https://github.com/agh/cwtch/compare/v5.0.0...v5.0.1
[5.0.0]: https://github.com/agh/cwtch/compare/v4.0.4...v5.0.0
[4.0.4]: https://github.com/agh/cwtch/compare/v4.0.3...v4.0.4
[4.0.3]: https://github.com/agh/cwtch/compare/v4.0.2...v4.0.3
[4.0.2]: https://github.com/agh/cwtch/compare/v4.0.1...v4.0.2
[4.0.1]: https://github.com/agh/cwtch/compare/v4.0.0...v4.0.1
[4.0.0]: https://github.com/agh/cwtch/compare/v3.0.0...v4.0.0
[3.0.0]: https://github.com/agh/cwtch/compare/v2.1.0...v3.0.0
[2.1.0]: https://github.com/agh/cwtch/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/agh/cwtch/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/agh/cwtch/releases/tag/v1.0.0
