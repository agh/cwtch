# cwtch

Cwtch: Helpful utilities for Claude Code. Manage multiple profiles, check your usage, deploy your army of agents. 🤖

> **Note:** This project is not affiliated with, sponsored by, or endorsed by Anthropic PBC.

**Platform:** macOS only (uses Keychain for credential storage). Tested on macOS Tahoe.

## Installation

### Homebrew (recommended)

```bash
brew tap agh/cask
brew install cwtch
```

### Manual

```bash
./scripts/install.sh
```

Add to your shell rc file if needed:

```bash
export PATH="${HOME}/.local/bin:${PATH}"
```

## Usage

### OAuth Profiles (Claude Max subscription)

```bash
# Save current Claude session as a profile
cwtch profile save work

# Switch to another profile
cwtch profile use personal

# Show current profile and usage
cwtch status

# Show usage for all profiles
cwtch usage
```

### API Key Profiles

API key profiles store an Anthropic API key. Note: usage data is only available for OAuth profiles.

```bash
# Save an API key as a profile (prompts for key)
cwtch profile save-key myapikey

# Switch to API key profile
cwtch profile use myapikey

# Output current API key (for use with apiKeyHelper)
cwtch profile api-key
```

To use API key profiles with Claude Code, configure `apiKeyHelper` in your settings:

```json
{
  "apiKeyHelper": "cwtch profile api-key"
}
```

### Common Commands

```bash
# List all profiles
cwtch profile list

# Show current profile name
cwtch profile current

# Delete a profile
cwtch profile delete old
```

## Dependencies

- `jq` - for JSON parsing (installed automatically via Homebrew)

## License

[MIT](LICENSE)
