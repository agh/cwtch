# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/agh/claude-utils/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/agh/claude-utils/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/agh/claude-utils/releases/tag/v1.0.0
