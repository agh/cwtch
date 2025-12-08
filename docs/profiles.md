# Profiles

Profiles store Claude credentials, enabling you to switch between accounts without re-authenticating.

## Profile Types

### OAuth Profiles (Claude Max)

For users with Claude Max subscriptions who authenticate via OAuth:

```bash
# After logging in via 'claude login', save the session
cwtch profile save work

# Switch profiles (restores credential to Keychain)
cwtch profile use personal

# View current profile and usage
cwtch status
```

### API Key Profiles

For users with Anthropic API keys:

```bash
# Save an API key (prompts for input)
cwtch profile save-key ci-bot

# Or pipe it in
echo "sk-ant-..." | cwtch profile save-key ci-bot

# Output current API key
cwtch profile api-key
```

To use API key profiles with Claude Code, configure `apiKeyHelper` in your settings:

```json
{
  "apiKeyHelper": "cwtch profile api-key"
}
```

## Commands

| Command | Description |
|---------|-------------|
| `cwtch profile list` | List all saved profiles |
| `cwtch profile current` | Show current profile name |
| `cwtch profile save <name>` | Save current OAuth credential |
| `cwtch profile save-key <name>` | Save an API key |
| `cwtch profile use <name>` | Switch to a profile |
| `cwtch profile delete <name>` | Delete a profile |
| `cwtch profile api-key` | Output current profile's API key |

## Storage

Profiles are stored in `~/.cwtch/profiles/`:

```
~/.cwtch/profiles/
├── work/
│   └── .credential      # OAuth token (chmod 600)
├── personal/
│   └── .credential
└── ci-bot/
    └── .apikey          # API key (chmod 600)
```

Profiles contain **only credentials**, not configuration. Configuration is managed separately via [sync](configuration.md).

## Status

The `cwtch status` command shows your current profile and usage:

```bash
$ cwtch status
Profile: work (oauth)
  5h: 23% (resets 2025-01-15 14:00 UTC)
  7d: 45% (resets 2025-01-18 00:00 UTC)

Sources: 2 configured
  myuser/claude-agents → personal [abc1234]
  mycompany/tools → work [def5678]

Config: ~/.cwtch/Cwtchfile
```

Usage data is only available for OAuth profiles. API key profiles show:

```bash
$ cwtch status
Profile: ci-bot (api-key)
  (API key profiles have no usage data)
```
