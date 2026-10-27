<div align="center">

<picture>
  <img alt="cwtch banner" src="assets/banner.svg" width="600">
</picture>

**Manage Claude Code profiles and sync configuration from Git.**

[![CI](https://github.com/agh/cwtch/actions/workflows/ci.yml/badge.svg)](https://github.com/agh/cwtch/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/agh/cwtch/badge)](https://scorecard.dev/viewer/?uri=github.com/agh/cwtch)
[![GitHub release](https://img.shields.io/github/v/release/agh/cwtch)](https://github.com/agh/cwtch/releases/latest)
[![Homebrew](https://img.shields.io/badge/Homebrew-agh%2Ftap%2Fcwtch-FBB040?logo=homebrew&logoColor=black)](https://github.com/agh/homebrew-tap)

*cwtch (Welsh): a cuddle or cosy nook*

</div>

> **Note:** This project is not affiliated with, sponsored by, or endorsed by Anthropic PBC.

cwtch is a macOS command-line tool. It stores named Claude Code credentials and builds selected
parts of Claude Code's user configuration from Git repositories.

## Requirements

- macOS
- Claude Code
- Git and `curl`
- `jq`
- Mike Farah's `yq` v4

The Homebrew formula installs `jq` and `yq`.

## Install

```bash
brew install agh/tap/cwtch
```

## Quick start

Create a setup-token profile, then apply it to the current shell:

```bash
cwtch profile setup personal
cwtch_env="$(cwtch profile env)" && eval "${cwtch_env}"
```

`claude setup-token` creates a one-year, non-refreshing credential. It can only make model
requests, so it can't establish Remote Control sessions or fetch claude.ai connectors. MCP servers
you configure locally still work. Claude Code's bare mode ignores it.

Create another profile in the same way. Selecting a token or API-key profile does not alter the
parent shell, so apply the environment after every switch:

```bash
cwtch profile use work
cwtch_env="$(cwtch profile env)" && eval "${cwtch_env}"
```

To sync configuration from Git:

```bash
cwtch sync init
cwtch edit
cwtch sync check
cwtch sync --dry-run
cwtch sync
```

The generated Cwtchfile is a valid no-op example. Uncomment and edit a source before syncing.

## Per-shell profiles

Activate a named token or API-key profile without changing other shells' next activation:

```bash
cwtch_env="$(cwtch profile env work)" && eval "${cwtch_env}"
cwtch run personal -- claude
```

`CWTCH_PROFILE` labels the launched environment; it does not prove which credential Claude Code
uses. See [Per-shell activation](docs/profiles.md#applying-a-profile-to-the-shell) for a helper,
prompts, statuslines, and direnv.

## Profile types

| Type | Create with | Storage | Activation and limits |
|---|---|---|---|
| Setup token | `cwtch profile setup` or `profile save-token` | `~/.cwtch/profiles/<name>/.token` | `profile env` exports `CLAUDE_CODE_OAUTH_TOKEN`. The token is one-year and non-refreshing, with the Remote Control, claude.ai connector, and bare-mode limits described above. |
| OAuth snapshot | `cwtch profile save` | `~/.cwtch/profiles/<name>/.credential` | `profile use` restores the snapshot to the default macOS Keychain entry. Claude Code can refresh the active login; cwtch snapshots it before the next OAuth switch. |
| API key | `cwtch profile save-key` | `~/.cwtch/profiles/<name>/.apikey` | `profile env` exports `ANTHROPIC_API_KEY`. It takes precedence over setup-token and OAuth credentials. |

Only OAuth snapshots have usage data. Usage is best effort; Claude Code's `/usage` display is
authoritative. See [Profile management](docs/profiles.md) for switching, precedence, Keychain, and
`CLAUDE_CONFIG_DIR` details.

## Commands

| Command | Description |
|---|---|
| `cwtch status` | Show the active profile and local source state without making network requests |
| `cwtch usage` | Show best-effort usage for all saved profiles |
| `cwtch run <name> [--] [command [args...]]` | Launch with a named token or API-key profile; default command is `claude` |
| `cwtch sync` | Validate the Cwtchfile, update sources, apply configuration, and prune stale managed links |
| `cwtch sync --force` | Back up and replace a regular `CLAUDE.md` that would otherwise block sync |
| `cwtch sync --dry-run` | Print the planned clone, update, link, merge, and prune operations without changing files |
| `cwtch sync init` | Create a valid example `~/.cwtch/Cwtchfile` |
| `cwtch sync check` | Print and validate the Cwtchfile, including warnings for existing settings or `CLAUDE.md` targets |
| `cwtch profile list` | List saved profiles, their types, token expiry, and the active profile |
| `cwtch profile current` | Print the active profile name, or `(none)` |
| `cwtch profile setup <name>` | Run `claude setup-token`, validate the result, and save a token profile |
| `cwtch profile save-token <name> [--expires YYYY-MM-DD]` | Read and save an existing setup token, optionally with an explicit expiry |
| `cwtch profile expires <name> <YYYY-MM-DD>` | Set an existing token profile's expiry without re-entering the token |
| `cwtch profile save-key <name>` | Read and save an API key |
| `cwtch profile save <name>` | Save the current default Keychain OAuth credential |
| `cwtch profile use <name>` | Select a profile; OAuth profiles are also restored to Keychain |
| `cwtch profile delete <name>` | Delete a profile and clear the selection when it was active |
| `cwtch profile env [name]` | Print shell statements for the named or current profile; send warnings and OAuth information to standard error |
| `cwtch profile token` | Print the active setup token |
| `cwtch profile api-key` | Print the active API key |
| `cwtch refresh [args...]` | Deprecated no-op; `-q` or `--quiet` suppresses its warning |
| `cwtch edit` | Open the Cwtchfile with `$EDITOR`, or `vi` when `$EDITOR` is unset |
| `cwtch version` | Print the version and make a short GitHub release update check |
| `cwtch -v`, `cwtch --version` | Print `cwtch <version>` offline |
| `cwtch -h`, `cwtch --help` | Show command help; no command also shows help |

Set `NO_COLOR`, set `TERM=dumb`, or redirect output to disable colour.

## Documentation

- [Profile management](docs/profiles.md) — profile types, switching, precedence, and usage
- [Configuration sync](docs/configuration.md) — Cwtchfile schema, outputs, safety, and 5.x migration
- [Security model](docs/security.md) — secrets, backups, output, and trust boundaries
- [Troubleshooting](docs/troubleshooting.md) — common profile and sync failures
- [Contributing](CONTRIBUTING.md) — development and review workflow
- [Security policy](SECURITY.md) — supported releases and private vulnerability reporting

## Uninstall

```bash
brew uninstall cwtch
```

Homebrew removes the executable but not user data. Profiles, source clones, state, and the
Cwtchfile remain under `~/.cwtch/`. Files and links already written to the Claude Code
configuration paths also remain. Review those paths before removing them, particularly if they
contain configuration not created by cwtch.

## Licence

[MIT](LICENSE)
