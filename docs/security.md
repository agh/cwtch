# Security model

cwtch handles authentication material, invokes macOS Keychain, and writes to Claude Code's user
configuration. Use profiles and sync sources with those trust boundaries in mind.

## Credential storage

| Profile type | Primary storage | Mode | Activation |
|---|---|---|---|
| Setup token | `~/.cwtch/profiles/<name>/.token` | `600` | Exported as `CLAUDE_CODE_OAUTH_TOKEN` |
| OAuth snapshot | `~/.cwtch/profiles/<name>/.credential` | `600` | Restored to the default `Claude Code-credentials` Keychain item |
| API key | `~/.cwtch/profiles/<name>/.apikey` | `600` | Exported as `ANTHROPIC_API_KEY` |

All profile files contain plaintext secrets readable by the owning user. A saved OAuth snapshot is
not protected solely by Keychain.

Secret files are created through a mode-`600` temporary file and atomically moved into place.
Replacing different content writes one mode-`600` `.bak` file first. Protect both the primary
credential and its backup. Do not commit, upload, or broadly synchronise
`~/.cwtch/profiles/`.

## Keychain and configuration directories

OAuth profiles use the macOS Keychain service `Claude Code-credentials` and the current account
name. cwtch updates the item in place and leaves `.current` unchanged if Keychain reports a
failure.

Claude Code uses a differently keyed Keychain item when `CLAUDE_CONFIG_DIR` is set. cwtch still
uses the default entry and warns before OAuth operations. Configuration sync does honour the
custom directory for `settings.json`, `CLAUDE.md`, skills, agents, and `.claude.json`.

## Commands that print secrets

`cwtch profile env` prints this unset command before the selected export or OAuth comment:

```sh
unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
```

For token and API-key profiles, the following export contains the raw secret. `profile token` and
`profile api-key` print the raw selected credential directly. Avoid shell tracing, shared terminal
logs, scrollback capture, and redirection to unprotected files.

`profile setup` does not repeat the raw `claude setup-token` output. It captures that output in a
mode-`600` temporary file, validates exactly one token, and removes the temporary file.

Environment credentials are inherited by child processes. OAuth restoration also passes the
credential to macOS `security` through its `-w` command-line argument; same-user process inspection
may expose that argument briefly. Do not run profile operations on an untrusted multi-user system.

## Authentication precedence

Claude Code checks cloud-provider credentials before `ANTHROPIC_AUTH_TOKEN`, then
`ANTHROPIC_API_KEY`, `apiKeyHelper`, `CLAUDE_CODE_OAUTH_TOKEN`, federation profiles, and `/login`
OAuth. A higher-precedence variable can cause Claude Code to ignore the active cwtch profile.

`profile env` warns when `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_USE_BEDROCK`,
`CLAUDE_CODE_USE_VERTEX`, or `CLAUDE_CODE_USE_FOUNDRY` is set. Treat any helper or provider
credentials as secrets too.

## Git source trust

`cwtch sync` can:

- clone and reset repositories below `~/.cwtch/sources/`;
- merge repository settings into Claude Code user settings;
- link a repository file as the user `CLAUDE.md`;
- expose repository skills and agents to Claude Code;
- merge repository-provided MCP servers into the user `.claude.json`.

Only sync repositories and refs you trust. A mutable branch can change without a cwtch update.
Managed source checkouts are disposable and local edits are discarded.

Existing settings, `CLAUDE.md`, and `.claude.json` may produce `.bak` files. Those backups can
contain private paths, commands, MCP credentials, or other sensitive configuration; protect them
accordingly.

## Filesystem safety

Profile names and Cwtchfile namespaces are validated before use in paths. Profile deletion checks
the resolved target before removing it.

Sync link targets are replaced only when they are symlinks. A regular target causes a source error;
the sole opt-in exception is user `CLAUDE.md`, which `--force` copies to `CLAUDE.md.bak` before
linking. Manifest pruning removes only managed links that still point inside cwtch's source
directory. cwtch does not recursively delete link targets.

Git refs are validated, and Git commands place `--` before untrusted refs and URLs.

## Reporting vulnerabilities

Use GitHub's
[private vulnerability reporting](https://github.com/agh/cwtch/security/advisories/new) or email
alex@howells.me. Never include a live token, API key, OAuth credential, or private repository
content in a report. See the repository [security policy](../SECURITY.md).
