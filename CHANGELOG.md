# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [4.0.1] - 2025-12-07

### Fixed

- Fixed symlink resolution for Homebrew installation

## [4.0.0] - 2025-12-07

### Changed

- **BREAKING**: Profile storage moved from `~/.claude-accounts/` to `~/.cwtch/profiles/`

## [3.0.0] - 2025-12-07

### Added

- New CLI structure with subcommands (`cwtch profile`, `cwtch status`, `cwtch usage`)
- `cwtch status` command shows current profile and its usage
- `cwtch usage` command shows usage for all profiles
- API key profile support (`cwtch profile save-key`, `cwtch api-key`)
- CONTRIBUTING.md with contribution guidelines
- SECURITY.md with vulnerability reporting procedures
- GitHub issue and PR templates

### Changed

- **BREAKING**: Renamed project from `claude-utils` to `cwtch`
- **BREAKING**: Renamed CLI from `claude-switch` to `cwtch`
- **BREAKING**: Changed command structure (e.g., `claude-switch save` → `cwtch profile save`)
- Moved main script from `scripts/` to `bin/`
- Terminology changed from "accounts" to "profiles"

### Removed

- Old `claude-switch` CLI entry point

## [2.1.0] - 2025-12-07

### Added

- `status` command to show usage (5h/7d utilization) for all saved accounts
- `lib/common.sh` for shared functions (enables future utilities)
- `jq` dependency for JSON parsing

### Changed

- Refactored script to source shared library

## [2.0.0] - 2025-12-07

### Added

- Keychain credential storage and restoration on account switch
- Devcontainer support for consistent development environment
- Platform documentation (macOS only, tested on Tahoe)

### Fixed

- Account switching now properly switches accounts (previously only copied directories, not Keychain credentials)
- Check for running Claude processes before switching (prevents "Directory not empty" error)

### Changed

- **BREAKING**: Accounts saved with v1.0.0 need to be re-saved to include credentials

## [1.0.0] - 2025-12-07

### Added

- `claude-switch` script for switching between Claude Code accounts
- `install.sh` script for symlinking utilities to `~/.local/bin`
- shellcheck and editorconfig configuration
- CLAUDE.md project context file
- MIT license
- bats test suite
- GitHub Actions CI (shellcheck, shfmt, tests)

[Unreleased]: https://github.com/agh/cwtch/compare/v4.0.1...HEAD
[4.0.1]: https://github.com/agh/cwtch/compare/v4.0.0...v4.0.1
[4.0.0]: https://github.com/agh/cwtch/compare/v3.0.0...v4.0.0
[3.0.0]: https://github.com/agh/cwtch/compare/v2.1.0...v3.0.0
[2.1.0]: https://github.com/agh/cwtch/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/agh/cwtch/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/agh/cwtch/releases/tag/v1.0.0
