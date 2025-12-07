# Claude Utilities

Utilities for managing Claude Code workflows.

**Platform:** macOS only (uses Keychain for credential storage). Tested on macOS Tahoe.

## Installation

### Homebrew (recommended)

```bash
brew tap agh/cask
brew install claude-switch
```

### Manual

```bash
./scripts/install.sh
```

Add to your shell rc file:

```bash
export PATH="${HOME}/.local/bin:${PATH}"
```

## Usage

```bash
# Save current Claude session
claude-switch save work

# Switch between accounts
claude-switch use personal

# List all accounts
claude-switch list

# Show current account
claude-switch current

# Delete an account
claude-switch delete old
```

## License

[MIT](LICENSE)
