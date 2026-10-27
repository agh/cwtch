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

For independent shells, use `profile env work` instead of `profile use work`; see
[Applying a profile to the shell](#applying-a-profile-to-the-shell).

## Token expiry metadata

Every successful save writes a non-secret `meta.json` beside the credential, at mode `600`:

```json
{
  "type": "token",
  "created": "2026-10-27T12:00:00Z",
  "source": "setup",
  "expires": "2027-10-27",
  "expires_basis": "estimated"
}
```

`created` is the UTC time cwtch saved the profile. `profile setup` records source `setup` and
estimates expiry at creation plus 365 days because setup tokens are one-year credentials. This
is an estimate, not a server-provided expiry. `save-token`, `save-key`, and OAuth `save` record
source `import`; imported tokens have unknown expiry unless specified, and API-key and OAuth
metadata always have null `expires` and `expires_basis`.

Supply a known token expiry when importing, or set it later without re-entering the token:

```bash
cwtch profile save-token work --expires 2027-07-12
cwtch profile expires work 2027-07-12
```

Both commands require a real calendar date in `YYYY-MM-DD` form. `profile expires` works only
on an existing token profile and preserves its token, creation time, source, and global selection.
For a profile saved before 6.1, which has no metadata, it records `created` as `null`: cwtch does
not know when that token was issued and does not guess from file times.

Metadata is advisory. If `meta.json` cannot be written, the credential is still saved and cwtch
warns that the expiry will show as unknown.

`profile list` and `status` show `expires 2027-07-12`,
`expires ~2027-07-12 (estimated)`, or `expiry unknown` for token profiles. Existing profiles
without metadata remain unknown; cwtch never infers expiry from file modification times.
`profile env`, `profile use`, and `run` warn on standard error when a token expires within 30
UTC calendar days, including today, or has already expired. Warnings include
`cwtch profile setup <name>` as the remedy and never block activation.

Re-saving a profile replaces its metadata, including creation time and expiry. Setting an explicit
expiry preserves existing provenance and changes `expires_basis` to `explicit`. Deleting a profile
removes its metadata and backups with it. Invalid metadata produces an `expiry unknown` warning
on activation or display; re-save the token before changing malformed metadata.

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

To select a token or API-key profile for just this shell, name it explicitly:

```bash
cwtch_env="$(cwtch profile env work)" && eval "${cwtch_env}"
```

Named activation validates the profile without reading or changing `.current` or
`.keychain-owner`. Omitting the name retains the current-profile behaviour. Named OAuth
activation is refused because the Keychain login is global: use `cwtch profile use <name>`,
then apply the unnamed `profile env` output to clear shell credentials.

For bash or zsh, add this checked per-shell helper to your shell configuration:

```bash
cwtch_use() {
  local cwtch_env
  cwtch_env="$(cwtch profile env "$1")" || return
  eval "${cwtch_env}"
}

cwtch_use work
```

This helper does not change the default that another shell will activate.
For a token profile named `work`, `cwtch profile env work` writes:

```sh
unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY CWTCH_PROFILE
export CLAUDE_CODE_OAUTH_TOKEN='<token>'
export CWTCH_PROFILE='work'
```

For an API-key profile named `ci-bot`:

```sh
unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY CWTCH_PROFILE
export ANTHROPIC_API_KEY='<key>'
export CWTCH_PROFILE='ci-bot'
```

For a current OAuth snapshot named `personal`:

```sh
unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY CWTCH_PROFILE
export CWTCH_PROFILE='personal'
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

### Launch labels in prompts and statuslines

Every successful `profile env` exports `CWTCH_PROFILE`. It is an inherited launch label for
prompts and statuslines, not proof of effective authentication: higher-precedence configuration
can override the credential, and a later global selection or Keychain switch does not update
already-running environments.

For a zsh prompt:

```zsh
setopt PROMPT_SUBST
PROMPT='[${CWTCH_PROFILE:-}] %~ %# '
```

For a Claude Code statusline, merge this setting into `settings.json`. Statusline commands receive
JSON on standard input; this minimal command ignores it and prints only the inherited label:

```json
{
  "statusLine": {
    "type": "command",
    "command": "printf '%s\\n' \"${CWTCH_PROFILE:-}\""
  }
}
```

### Opt-in direnv activation

After saving a `work` token or API-key profile, an opt-in project `.envrc` can contain:

```bash
eval "$(cwtch profile env work)"
```

Review the file before running `direnv allow`: that approval is the trust boundary for executing
`.envrc`. The file must name the profile and never contain a token. The compact recipe does not
preserve a failing `profile env` exit status; use the checked capture-then-eval form above when
activation must report failure.

## Launching a command with a profile

`cwtch run` builds the child environment directly, without evaluating shell output or changing
`.current` or `.keychain-owner`:

```bash
cwtch run work
cwtch run work -- claude --resume
cwtch run ci-bot sh -c 'printf "%s\n" "${CWTCH_PROFILE}"'
```

The default command is `claude`. A single leading `--` is optional; remaining command arguments
retain their boundaries, including spaces, empty strings, and quoted globs. cwtch clears both
credential variables, exports only the selected token or API key plus `CWTCH_PROFILE`, and
replaces itself with the command using `exec`. Credentials are never placed in the command's
argument list. Exit status and signals propagate directly; a missing command exits `127`.
Precedence and expiry warnings go to standard error before the command starts.

Only token and API-key profiles support `run`. OAuth profiles are refused because Keychain
activation is global; use `cwtch profile use <name>` instead.

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

`cwtch status` is offline. It shows the cwtch version, globally selected profile and type, token
expiry, the shell activation hint for token and API-key profiles, configured source revisions or
`not synced`, and the Cwtchfile path. It does not fetch usage or identify a running shell's
effective authentication; use `CWTCH_PROFILE` only as a launch label.

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
    │   ├── .token
    │   └── meta.json
    ├── work/
    │   ├── .credential
    │   └── meta.json
    └── ci-bot/
        ├── .apikey
        └── meta.json
```

Credential files are created with mode `600`. Replacing a credential with different content first
copies the old value to the same path plus `.bak`, also mode `600`; only one backup is retained.
These files and their backups contain plaintext secrets readable by the owning user.
`meta.json` contains no credential and uses the same atomic mode-`600` write and single-backup
pattern. It does not count as a credential when determining the profile type.

Commands return `0` on success and `1` for user errors such as an invalid name, missing profile, or
wrong credential type. `run` instead propagates the launched command's status, including `127`
when the command cannot be found. See [Security model](security.md) before backing up or synchronising
`~/.cwtch/`.
