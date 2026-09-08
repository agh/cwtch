# Configuration sync

cwtch reads `~/.cwtch/Cwtchfile`, manages source checkouts below `~/.cwtch/sources/`, and applies
selected configuration to Claude Code's user paths.

## Create a Cwtchfile

```bash
cwtch sync init
cwtch edit
```

The generated file has a fully commented `sources:` example. It is valid immediately, and
`cwtch sync` reports:

```text
Nothing to sync (edit ~/.cwtch/Cwtchfile)
```

`sources:` may be absent, `null`, or an empty sequence.

## Schema

```yaml
# Optional base settings and CLAUDE.md. Both use repo:path.
settings: owner/repo:path/settings.json
claude_md: owner/repo:path/CLAUDE.md

# Optional: may be omitted, null, or [].
sources:
  - repo: owner/repo
    ref: main
    as: personal
    skills: skills/
    commands: commands/
    agents: agents/
    mcp: mcp.json
```

### Top-level keys

| Key | Required | Meaning |
|---|---|---|
| `settings` | No | `repo:path` JSON file deep-merged into the Claude Code user settings |
| `claude_md` | No | `repo:path` file linked as the user `CLAUDE.md` |
| `sources` | No | Sequence of source definitions; absent, null, and empty are valid |

Both sides of a `repo:path` value must be non-empty. For example, `settings: ":"` is invalid.

### Source keys

| Key | Required | Meaning |
|---|---|---|
| `repo` | Yes | GitHub `owner/repo`, HTTPS URL, SSH URL, or absolute local path |
| `ref` | No | Branch or tag; defaults to the remote's advertised HEAD, then `main` if discovery fails |
| `as` | With `skills`, `commands`, or `agents` | Validated namespace used in destination path names |
| `skills` | No | Directory whose child skill directories contain `SKILL.md` |
| `commands` | No | Directory of legacy `*.md` commands converted into skills |
| `agents` | No | Directory of agent Markdown files linked as one recursive source |
| `mcp` | No | JSON file containing `{"mcpServers": {...}}` or a bare server map |

The `as` value follows the same rule as profile names:
`^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`, excluding `.` and `..`. Duplicate `as` values are invalid.

`hooks:` is not supported. Register hooks in `settings.json`, where Claude Code requires an event
and matcher. A hooks directory on its own has no effect.

The literal `repo: owner/repo` placeholder is rejected. Replace it with a real source before
uncommenting the example.

## Repository handling

Supported repository forms are:

```yaml
repo: owner/repo
repo: https://github.com/owner/repo.git
repo: git@github.com:owner/repo.git
repo: /absolute/path/to/local/repo
```

Managed checkout directories use a sanitised repository string. Absolute local paths also receive
the first eight hexadecimal characters of the path's SHA-256 digest, preventing different paths
from sharing a checkout directory.

When `ref` is absent, cwtch asks the remote which branch `HEAD` names. It falls back to `main` only
when that lookup fails. Explicit refs must pass Git's ref-format validation and cannot begin with
`-`.

Clones are shallow. Existing managed checkouts fetch the selected ref and reset a local branch to
`FETCH_HEAD`. Local edits below `~/.cwtch/sources/` are discarded by design; do not use those
directories as working copies. Clone, fetch, or checkout failures are source errors and make the
overall sync exit with status `1`.

## Outputs and merge rules

Claude Code's configuration directory is `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`.

### Settings

`settings:` deep-merges the repository JSON into the existing user `settings.json`. Existing user
values win when the same key exists; the repository file supplies defaults. When existing content
changes, cwtch writes `settings.json.bak` before replacing it. If no target exists, cwtch creates
one.

### CLAUDE.md

`claude_md:` creates a symlink at
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md`.

An absent target or existing symlink can be replaced. A regular file blocks sync:

```text
CLAUDE.md exists and is not a symlink; move it or run 'cwtch sync --force'
```

With `--force`, cwtch copies the regular file to `CLAUDE.md.bak` before replacing it with the
symlink.

### Skills

For each child directory containing `SKILL.md`, this source:

```yaml
sources:
  - repo: myuser/claude-skills
    as: team
    skills: skills/
```

creates links such as:

```text
~/.claude/skills/team-review -> <source>/skills/review
~/.claude/skills/team-deploy -> <source>/skills/deploy
```

The resulting skill names are `/team-review` and `/team-deploy`.

### Legacy commands

Claude Code now uses skills for new workflows. Each legacy command file is converted into a skill.
For example:

```text
<source>/commands/review.md
```

with `as: team` becomes:

```text
~/.claude/skills/team-review/
└── SKILL.md -> <source>/commands/review.md
```

The command is therefore invoked as `/team-review`, not `/team/review`. Symlinks from older cwtch
versions at `~/.claude/commands/<as>` are removed when they point into cwtch's source directory.

### Agents

`agents:` creates one directory symlink:

```text
~/.claude/agents/team -> <source>/agents
```

Claude Code discovers agents recursively. The `name` in each agent file's frontmatter is its
identity; the `as` directory does not rename the agent.

### MCP servers

User-scope MCP servers belong in `~/.claude.json`, not `settings.json`. When
`CLAUDE_CONFIG_DIR` is set, cwtch uses `$CLAUDE_CONFIG_DIR/.claude.json`.

For each source, cwtch normalises a wrapped `mcpServers` object or bare server map, then merges it
into `.mcpServers`. Existing servers are retained; newly configured servers win on a duplicate
name. Changes back up the previous file to `.claude.json.bak`. If the file is absent, cwtch creates
it with a top-level `mcpServers` object.

## Link safety and pruning

cwtch only creates or replaces symlinks for linked outputs. If a skill, command, agent, or other
link target already exists and is not a symlink, that source fails with:

```text
target exists and is not a symlink: <path>
```

cwtch never recursively removes such a target.

`~/.cwtch/state/links` records every symlink created by the last successful run. On a later
successful sync, a path no longer configured is removed only when it is still:

- a symlink whose target is inside `~/.cwtch/sources/`; or
- a converted command's `SKILL.md` symlink inside a directory cwtch created.

Empty converted-command directories are removed afterwards. User files and links to other
locations are not pruned.

## Commands and flags

| Command | Behaviour |
|---|---|
| `cwtch sync init` | Create a valid commented example; refuses to overwrite an existing Cwtchfile |
| `cwtch edit` | Open the Cwtchfile with `$EDITOR`, or `vi` |
| `cwtch sync check` | Print and validate the schema; warn when settings or `CLAUDE.md` would touch existing files |
| `cwtch sync --dry-run` | Print planned clone, update, merge, link, and prune operations; change nothing and exit successfully |
| `cwtch sync --force` | Permit a regular user `CLAUDE.md` to be backed up and replaced |
| `cwtch sync` | Apply the configuration and report per-source summaries plus skill and agent counts |

A complete run ends with `Sync complete`. Source failures are printed as they happen, followed by
`Sync finished with N error(s)`, and the command exits with status `1`.

## Migrating from 5.x

Review the Cwtchfile before the first 6.0.0 sync:

1. Remove every `hooks:` key and register hooks in `settings.json`.
2. Expect `commands:` files to become skills named `/<as>-<name>`.
3. Add `skills:` for native skill directories.
4. Check for user files at intended link targets; cwtch will not replace regular files, except
   `CLAUDE.md` when `--force` is supplied.
5. Expect repository settings to be defaults merged beneath existing user values, rather than a
   wholesale replacement.
6. Move user-scope MCP expectations from `settings.json` to `~/.claude.json` or
   `$CLAUDE_CONFIG_DIR/.claude.json`.
7. Remove any profile-specific `profiles/<name>/Cwtchfile`; profile overlays no longer exist.
8. Check every profile name and `as` value against the new validation rule.

Run `cwtch sync check`, inspect `cwtch sync --dry-run`, then run `cwtch sync`. The manifest prunes
obsolete managed links only when their targets remain inside cwtch's source directory.
