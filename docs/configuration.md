# Configuration Sync

Cwtch syncs Claude Code configuration (commands, agents, hooks, MCP servers) from Git repositories.

## The Cwtchfile

Configuration is defined in `~/.cwtch/Cwtchfile`:

```yaml
# Base settings.json (optional)
settings: owner/repo:path/to/settings.json

# Global CLAUDE.md (optional)
claude_md: owner/repo:path/to/CLAUDE.md

# Sources to sync
sources:
  # Personal agents and commands
  - repo: myuser/claude-agents
    ref: main
    commands: commands/
    agents: agents/
    hooks: hooks/
    as: personal

  # Work tools
  - repo: mycompany/claude-tools
    commands: commands/
    agents: agents/
    mcp: mcp-servers.json
    as: work

  # Just MCP servers (no namespace needed)
  - repo: myuser/mcp-configs
    mcp: servers.json
```

## Commands

| Command | Description |
|---------|-------------|
| `cwtch sync` | Pull all sources and build `~/.claude/` |
| `cwtch sync init` | Create an example Cwtchfile |
| `cwtch sync check` | Validate Cwtchfile without syncing |
| `cwtch edit` | Open Cwtchfile in your editor |

## How Syncing Works

When you run `cwtch sync`:

1. **Clone/update repositories** — Sources are cloned to `~/.cwtch/sources/`
2. **Link commands/agents** — Symlinked to `~/.claude/{commands,agents}/{namespace}/`
3. **Merge settings** — MCP servers are deep-merged into `~/.claude/settings.json`
4. **Link CLAUDE.md** — Symlinked to `~/.claude/CLAUDE.md`

The result:

```
~/.claude/
├── settings.json          # Merged from all sources
├── CLAUDE.md              # Symlink → source
├── commands/
│   ├── personal/          # Symlink → myuser/claude-agents/commands/
│   └── work/              # Symlink → mycompany/claude-tools/commands/
└── agents/
    ├── personal/          # Symlink → myuser/claude-agents/agents/
    └── work/              # Symlink → mycompany/claude-tools/agents/
```

Commands and agents are invoked with their namespace: `/personal/review`, `/work/deploy`.

## Cwtchfile Reference

### Top-Level Keys

| Key | Format | Description |
|-----|--------|-------------|
| `settings` | `owner/repo:path` | Base settings.json to copy |
| `claude_md` | `owner/repo:path` | CLAUDE.md to symlink |
| `sources` | list | Sources to sync (see below) |

### Source Object

| Key | Required | Description |
|-----|----------|-------------|
| `repo` | Yes | GitHub `owner/repo`, full URL, or local path |
| `ref` | No | Branch or tag (default: `main`) |
| `as` | When using commands/agents/hooks | Namespace for this source |
| `commands` | No | Path to commands directory in repo |
| `agents` | No | Path to agents directory in repo |
| `hooks` | No | Path to hooks directory in repo |
| `mcp` | No | Path to MCP servers JSON file |

### Repo Formats

```yaml
# GitHub shorthand (recommended)
repo: owner/repo

# Full HTTPS URL
repo: https://github.com/owner/repo.git

# SSH URL
repo: git@github.com:owner/repo.git

# Local path (for development)
repo: /path/to/local/repo
```

## Validation

The Cwtchfile is validated before syncing:

```bash
$ cwtch sync check
Checking ~/.cwtch/Cwtchfile...
  settings:  agh/claude-base:settings.json
  claude_md: (none)
  sources:   2
    [0] myuser/claude-agents → personal
    [1] mycompany/tools → work
[cwtch] Cwtchfile is valid
```

Validation rules:
- Valid YAML syntax
- `sources` must be a list
- `settings` and `claude_md` must be `repo:path` format
- Each source must have `repo`
- `as` is required when `commands`, `agents`, or `hooks` are specified
- No duplicate namespaces

## New Machine Setup

```bash
# 1. Install cwtch
brew tap agh/cask && brew install cwtch

# 2. Link Cwtchfile from your dotfiles
mkdir -p ~/.cwtch
ln -s ~/dotfiles/Cwtchfile ~/.cwtch/Cwtchfile

# 3. Sync configuration
cwtch sync

# 4. Authenticate with Claude
claude login

# 5. Save as a profile
cwtch profile save work
```
