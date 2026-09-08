# Troubleshooting

## Claude Code still uses the previous token or API key

Selecting a profile cannot change its parent shell. Apply the generated environment after every
token or API-key switch:

```bash
cwtch profile use personal
eval "$(cwtch profile env)"
```

`profile env` unsets both cwtch-managed variables before exporting the selected one.

If the output warns about `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_USE_BEDROCK`,
`CLAUDE_CODE_USE_VERTEX`, or `CLAUDE_CODE_USE_FOUNDRY`, clear or correct that higher-precedence
configuration first. An `apiKeyHelper` can also take precedence over a setup token.

## `profile env` says no profile is active

Inspect and select a saved profile:

```bash
cwtch profile current
cwtch profile list
cwtch profile use personal
```

An invalid value in `~/.cwtch/.current` is ignored with a warning. Profile names may contain up to
64 letters, digits, dots, underscores, or hyphens, and must begin with a letter or digit.

## A profile is shown as `(mixed!)`

The profile directory contains more than one of `.credential`, `.token`, and `.apikey`. Save the
intended type again; a successful save removes the other two credential files. Check any `.bak`
before deleting it because backups contain secrets.

## Switching OAuth profiles captured the wrong account

Before an OAuth-to-OAuth switch, cwtch snapshots the current Keychain credential into the outgoing
profile. If you used `/login` for a different account while that profile was active, save the new
login under its own name before switching:

```bash
cwtch profile save new-account
```

## OAuth commands warn about `CLAUDE_CONFIG_DIR`

Claude Code keys Keychain entries differently for custom configuration directories. cwtch honours
`CLAUDE_CONFIG_DIR` for synced files but still reads and writes the default Keychain item. Use
Claude Code's separate configuration directories directly when you need Keychain-isolated
accounts.

## `profile setup` cannot find a token

Run `claude setup-token` directly and save the resulting token:

```bash
cwtch profile save-token personal
```

If cwtch reports several candidates, paste the intended token into `save-token`. Tokens must begin
with `sk-ant-oat01-` and use the expected format.

## `refresh` appears to do nothing

That is the 6.0.0 behaviour. `refresh` is a deprecated no-op retained for one major release.
Claude Code refreshes its own login; run `/login` inside Claude Code when a login has expired.
`-q` and `--quiet` suppress the deprecation warning.

## A new Cwtchfile has nothing to sync

This is expected. `sync init` writes a valid example with the entire source block commented out.
Edit it and uncomment a real source:

```bash
cwtch edit
cwtch sync check
```

An absent, null, or empty `sources` value is also valid.

## The `owner/repo` placeholder is rejected

The example value is deliberately invalid once uncommented. Replace it with a GitHub
`owner/repo`, an HTTPS or SSH Git URL, or an absolute local path.

## A repository does not use `main`

With no `ref`, cwtch uses the branch advertised by the remote's `HEAD`. If discovery fails, it
falls back to `main`. Set a branch or tag explicitly when required:

```yaml
sources:
  - repo: owner/repo
    ref: trunk
```

## Sync refuses to replace a target

cwtch replaces only symlinks for skills, converted commands, and agents. Move or rename a regular
file or directory at the reported path, then run sync again. It never recursively deletes the
target.

A regular user `CLAUDE.md` can be handled explicitly:

```bash
cwtch sync --force
```

The original is copied to `CLAUDE.md.bak` before the symlink is created.

## Preview a sync safely

Validate, then inspect the plan:

```bash
cwtch sync check
cwtch sync --dry-run
```

Dry-run mode prints clone, update, merge, link, and prune operations without changing files.

## MCP servers are not in `settings.json`

User-scope MCP servers belong in `~/.claude.json`. With `CLAUDE_CONFIG_DIR` set, cwtch writes
`$CLAUDE_CONFIG_DIR/.claude.json`. Existing servers are retained, and a newly configured server
wins when names collide.

## A converted command has a different slash name

`commands/review.md` under a source with `as: team` becomes a skill at `/team-review`. Native
skills use the same `/<as>-<skill>` naming rule. The old `/team/review` namespace layout is not
used.

## Configuration commands cannot find `yq`

cwtch requires the Mike Farah implementation of `yq` v4:

```bash
brew install yq
yq --version
```

There is no grep or awk fallback.

## Disable colour

Set `NO_COLOR`:

```bash
NO_COLOR=1 cwtch status
```

Colour is also disabled when output is not a terminal or `TERM=dumb`.
