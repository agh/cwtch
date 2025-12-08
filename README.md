# cwtch

Manage Claude Code profiles and sync configuration from Git.

> **Note:** This project is not affiliated with, sponsored by, or endorsed by Anthropic PBC.

**Platform:** macOS only. Tested on macOS Tahoe.

## Installation

```bash
brew tap agh/cask
brew install cwtch
```

## Quick Start

### Switch Between Accounts

```bash
# Save your current Claude session
cwtch profile save work

# Switch profiles
cwtch profile use personal

# Check status
cwtch status
```

### Sync Configuration from Git

```bash
# Create a Cwtchfile
cwtch sync init

# Edit it to add your sources
cwtch edit

# Pull and build ~/.claude/
cwtch sync
```

Example Cwtchfile:

```yaml
sources:
  - repo: myuser/claude-agents
    commands: commands/
    agents: agents/
    as: personal
```

## Documentation

- [Profiles](docs/profiles.md) — OAuth and API key management
- [Configuration](docs/configuration.md) — Cwtchfile reference and sync details

## Commands

```
cwtch status              Show profile, usage, and sync state

cwtch sync                Pull sources and build ~/.claude/
cwtch sync init           Create example Cwtchfile
cwtch sync check          Validate Cwtchfile
cwtch edit                Edit Cwtchfile

cwtch profile list        List saved profiles
cwtch profile save <n>    Save current OAuth credential
cwtch profile save-key <n> Save API key as profile
cwtch profile use <n>     Switch to profile
cwtch profile delete <n>  Delete a profile
cwtch profile api-key     Output current API key
```

## License

[MIT](LICENSE)
