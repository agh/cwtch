# Security policy

## Supported versions

| Version | Supported |
|---|---|
| Latest minor release | Yes |
| Older releases | No |

Update to the latest minor release before reporting a defect that may already be fixed.

## Reporting a vulnerability

Do not report security vulnerabilities through public GitHub issues.

Use
[GitHub private vulnerability reporting](https://github.com/agh/cwtch/security/advisories/new) or
email alex@howells.me. Include a description, reproduction steps, affected versions, potential
impact, and a suggested fix when available. Never include a live token, API key, OAuth credential,
private repository content, or unredacted personal path.

## Credential and sync risks

cwtch stores plaintext, mode-`600` credentials and one-file backups below
`~/.cwtch/profiles/`. OAuth snapshots are also restored to the default macOS Keychain entry.
Commands that print environment exports, tokens, or API keys must be handled as secret-producing
commands.

Configuration sync can merge settings, link skills and agents, replace `CLAUDE.md` when explicitly
forced, and merge MCP server definitions. Only sync repositories and refs you trust.

See [docs/security.md](docs/security.md) for storage paths, authentication precedence, backup
behaviour, process-argument exposure, and filesystem safeguards.
