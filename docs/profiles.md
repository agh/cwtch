# Profile management

Profiles are named Claude Code credentials stored below `~/.cwtch/profiles/`. Exactly one
credential type belongs in each profile.

## Choose a profile type

| Type | File | Activation | Limits |
|---|---|---|---|
| Setup token | `.token` | `profile env` exports `CLAUDE_CODE_OAUTH_TOKEN`; apply it with the checked recipe below | Created by `claude setup-token`; one-year and non-refreshing. It can only make model requests, so it can't establish Remote Control sessions or fetch claude.ai connectors. MCP servers you configure locally still work. Bare mode ignores it. |
| OAuth snapshot | `.credential` | `cwtch profile use` updates the default macOS Keychain entry | A point-in-time copy of a Claude Code login. Claude Code can refresh the active Keychain value, and cwtch snapshots that value before the next OAuth switch. |
| API key | `.apikey` | `profile env` exports `ANTHROPIC_API_KEY`; apply it with the checked recipe below | Intended for API-key authentication. It has higher precedence than setup-token and OAuth credentials. |

`profile list` reports `(mixed!)` if a profile directory contains more than one credential file.
Saving any profile type removes the other two credential files after the new value is safely
written.

## Names and credential validation

Profile names must match `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$` and cannot be `.` or `..`. This rule
also applies to the names stored in `~/.cwtch/.current` and `~/.cwtch/.keychain-owner`.

Tokens must match:

```text
^sk-ant-oat01-[A-Za-z0-9_-]{20,}$
```

API keys must match:

```text
^[A-Za-z0-9_-]{20,}$
```

Invalid values are rejected without being printed. An invalid `.current` file is ignored with an
`Ignoring invalid .current` warning.

## Setup-token profiles

Create and activate a token interactively:

```bash
cwtch profile setup personal
cwtch_env="$(cwtch profile env)" && eval "${cwtch_env}"
```

`profile setup` captures the combined `claude setup-token` output in a mode-`600` temporary file,
removes terminal escape sequences and carriage returns, and rejoins token-only continuation
lines. Blank lines and prose end a candidate; the whole transcript is never flattened. It requires
exactly one distinct candidate of at most 256 characters and does not repeat the captured output.
If no token is found, it reports the failure; if several are found, use `profile save-token` and
paste the intended value. Repeated copies of the same token are accepted.

Save an existing token from a hidden prompt or standard input:

```bash
cwtch profile save-token personal
printf '%s\n' "$CLAUDE_CODE_OAUTH_TOKEN" | cwtch profile save-token personal
```

Selecting a token profile changes `~/.cwtch/.current`, but a child process cannot alter its parent
shell:

```bash
cwtch profile use work
cwtch_env="$(cwtch profile env)" && eval "${cwtch_env}"
```

## OAuth snapshot profiles

Authenticate Claude Code, then save the current Keychain credential:

```bash
claude auth login
cwtch profile save work
```

Saving or restoring an OAuth snapshot requires a JSON object with a non-empty string at
`.claudeAiOauth.accessToken`. Invalid snapshots cannot overwrite a working Keychain login.

Switching to an OAuth profile performs these operations in order:

1. cwtch validates the selected snapshot before changing anything.
2. If the Keychain owner is an OAuth profile and the live Keychain value is valid OAuth JSON,
   cwtch writes it back to that profile. If the snapshot write fails, the switch aborts before
   changing Keychain or the selected name.
3. cwtch stages the new name for `~/.cwtch/.keychain-owner`; if it cannot, nothing changes.
4. cwtch updates the `Claude Code-credentials` item for the current macOS account in place. If the
   update fails, the selected profile is not changed. If the staged owner record then cannot be
   moved into place, cwtch restores the previous Keychain value and reports the failure.
5. cwtch records the new name in `~/.cwtch/.current`.

An unreadable or invalid `.keychain-owner` stops OAuth switches until it is fixed or removed,
because cwtch could not tell which profile owns the refreshed login.

`profile save` also records Keychain ownership. Token and API-key selections leave that ownership
unchanged, so an OAuth login refreshed while either is selected is still preserved at the next
OAuth switch. When `.keychain-owner` is absent, cwtch uses `.current` if it names an OAuth profile,
providing migration from 6.0.0. That fallback is recorded before selecting a token or API-key
profile, so the first switch after upgrading does not lose ownership.

If `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` is set when switching to OAuth, cwtch warns that
the environment overrides Keychain and prints the checked `profile env` recipe to clear it.

There is an important snapshot-before-switch caveat: if you run `/login` for a different account
while an OAuth profile is active, then switch profiles, the new login is captured into the
outgoing profile. Use `cwtch profile save <newname>` immediately after `/login` instead.

### `CLAUDE_CONFIG_DIR`

Claude Code supports `CLAUDE_CONFIG_DIR` for separate configuration directories. cwtch honours it
for configuration sync:

- `CLAUDE_DIR` becomes `$CLAUDE_CONFIG_DIR`;
- the user MCP file becomes `$CLAUDE_CONFIG_DIR/.claude.json`.

Claude Code also keys its Keychain entry to a custom configuration directory. cwtch OAuth
operations still use the default `Claude Code-credentials` entry, so they print a warning when
`CLAUDE_CONFIG_DIR` is set. Use separate Claude Code configuration directories directly when
Keychain-isolated accounts are required.

## API-key profiles

Save, select, and apply an API key:

```bash
cwtch profile save-key ci-bot
cwtch profile use ci-bot
cwtch_env="$(cwtch profile env)" && eval "${cwtch_env}"
```

An API key can also be supplied on standard input:

```bash
printf '%s\n' "$ANTHROPIC_API_KEY" | cwtch profile save-key ci-bot
```

Claude Code supports the `apiKeyHelper` setting. If you use it with cwtch storage, point the helper
at one fixed, named API-key profile such as `~/.cwtch/profiles/ci-bot/.apikey`. Do not configure
`apiKeyHelper` as `cwtch profile api-key`: that command follows the mutable current profile and
therefore does not provide a stable credential identity.

## Applying a profile to the shell

Capture the output successfully before evaluating it:

```bash
cwtch_env="$(cwtch profile env)" && eval "${cwtch_env}"
```

This leaves errors visible and preserves the failing exit status. A bare
`eval "$(cwtch profile env)"` can instead evaluate an empty string and report success after
`profile env` fails. The short hints printed by `profile use`, `profile setup`, and `status`
retain that compact form for
readability; use the checked recipe in scripts and shell configuration.

For bash or zsh, a small function can select and apply a profile together:

```bash
cwtch_use() {
  local cwtch_env
  cwtch profile use "$1" || return
  cwtch_env="$(cwtch profile env)" || return
  eval "${cwtch_env}"
}
```

For a token profile, `cwtch profile env` writes:

```sh
unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
export CLAUDE_CODE_OAUTH_TOKEN='<token>'
```

For an API-key profile:

```sh
unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
export ANTHROPIC_API_KEY='<key>'
```

For an OAuth snapshot:

```sh
unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
```

The credential is validated again before it is printed. If `ANTHROPIC_AUTH_TOKEN`,
`CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, or `CLAUDE_CODE_USE_FOUNDRY` is already set,
`profile env` warns on standard error that the variable takes precedence. The OAuth explanation
also goes to standard error; standard output contains only evaluable shell statements.

Claude Code authentication precedence is: cloud-provider credentials, `ANTHROPIC_AUTH_TOKEN`,
`ANTHROPIC_API_KEY`, `apiKeyHelper`, `CLAUDE_CODE_OAUTH_TOKEN`, federation profiles, then `/login`
OAuth. Clear or correct higher-precedence configuration when the selected cwtch profile is not
being used.

`profile token` and `profile api-key` print the active raw credential. They fail if the selected
profile has the wrong type.

## Listing, selecting, and deleting

```bash
cwtch profile list
cwtch profile current
cwtch profile use personal
cwtch profile delete personal
```

`profile current` prints the selected name or `(none)`. Deleting the active profile also removes
`.current`. Deleting the Keychain owner also removes `.keychain-owner`, without deleting the
Keychain login itself. All name-bearing commands validate the name first, and deletion refuses any
resolved path outside the named profile directory.

## Status and usage

`cwtch status` is offline. It shows the cwtch version, active profile and type, the shell activation
hint for token and API-key profiles, configured source revisions or `not synced`, and the
Cwtchfile path. It does not fetch usage.

`cwtch usage` is best effort and always continues through individual failures:

- token and API-key profiles are labelled by type;
- malformed OAuth snapshots are shown as `(unreadable credential)`;
- failed usage requests and invalid responses are shown as `(usage unavailable)`;
- successful requests show the 5-hour and 7-day percentages plus active limit entries.

Requests have a ten-second timeout. Claude Code's `/usage` display remains authoritative.
Responses must contain one JSON object with non-negative numeric `five_hour.utilization` and
`seven_day.utilization` values. Missing, null, and non-numeric values are unavailable, not zero
usage; genuine numeric zero is displayed as `0%`.

## Deprecated refresh command

`cwtch refresh` is retained as a no-op for one major release. Without a quiet flag it writes:

```text
cwtch refresh is deprecated and does nothing: Claude Code refreshes its own login. If a login has expired, run /login inside Claude Code.
```

`-q` or `--quiet` anywhere in the arguments suppresses the warning. The command always exits
successfully.

## Storage, backups, and permissions

```text
~/.cwtch/
├── .current
├── .keychain-owner
└── profiles/
    ├── personal/
    │   └── .token
    ├── work/
    │   └── .credential
    └── ci-bot/
        └── .apikey
```

Credential files are created with mode `600`. Replacing a credential with different content first
copies the old value to the same path plus `.bak`, also mode `600`; only one backup is retained.
These files and their backups contain plaintext secrets readable by the owning user.

Commands return `0` on success and `1` for user errors such as an invalid name, missing profile, or
wrong credential type. See [Security model](security.md) before backing up or synchronising
`~/.cwtch/`.
