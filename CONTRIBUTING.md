# Contributing to cwtch

Contributions must preserve credential safety, macOS behaviour, Bash 3.2 compatibility, and the
documented Cwtchfile contract.

## Conduct

Be respectful and constructive. The project follows the
[Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

## Before starting

Search existing issues and pull requests. Open an issue before a significant command,
authentication, storage, or configuration-format change so compatibility and migration can be
agreed first.

## Development environment

cwtch runs on macOS because OAuth switching uses Keychain. The Ubuntu CI job and development
container exercise portable logic through mocks, but they cannot replace real macOS end-to-end
coverage.

On macOS:

```bash
brew install bats-core shellcheck shfmt jq yq
make check
```

Required development tools are Bash, Git, Make, bats 1.5 or later, shellcheck, shfmt, `jq`, and Mike
Farah's real `yq` v4. Tool versions used by CI are pinned in the workflow and development
environment. Update a version and its checksum together.

Read [AGENTS.md](AGENTS.md) for architecture, functions, shell constraints, and test conventions.

## Make a change

1. Create a branch from `main`.
2. Make the smallest coherent change.
3. Add or update focused tests for changed behaviour.
4. Update user documentation and `CHANGELOG.md` when commands, output, storage, or the Cwtchfile
   changes.
5. Run the relevant checks, then `make check`.

Use the repository targets:

| Command | Purpose |
|---|---|
| `make check` | Complete local CI check set |
| `make lint` | shellcheck using `.shellcheckrc` |
| `make fmt` | Apply `shfmt -i 2 -ci` |
| `make fmt-check` | Check formatting without rewriting |
| `make test` | Run all bats tests |
| `make test-hermetic` | Run with isolated Git state and `USER` unset |
| `make bash32-check` | Check macOS Bash 3.2 syntax |
| `make e2e` | Run macOS platform integration checks |

The CI matrix includes Ubuntu 24.04 and macOS 15 and 26. Portable tests must pass on both operating
systems. Never run profile tests against real credentials, the maintainer's home directory, or an
unmocked Keychain.

## Shell changes

- Keep `/bin/bash` 3.2 compatibility.
- Use `[[ ... ]]`, `$()`, and two-space indentation.
- Use `printf '%s\n'` for user-controlled values.
- Keep each file to one responsibility; never compress statements to satisfy a length budget.
- Run `make fmt` rather than hand-formatting.
- Use the real `yq` v4 in tests and runtime code.
- Preserve standard-output contracts; send progress output to standard error where necessary.
- Write user-facing text in British English.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```text
type(scope): imperative description
```

Common types are `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, and `chore`.

## Pull requests

Describe the problem, the root cause for a fix, and exactly what changed. Name the relevant files,
functions, commands, and data flow. Include the commands run and their results, and state related
behaviour deliberately left outside the change.

## Releases

Release preparation updates `VERSION` and `CHANGELOG.md`, runs the complete checks, creates a
signed `vX.Y.Z` tag, pushes the commit and tag, then updates the Homebrew formula checksum. See the
full procedure in [AGENTS.md](AGENTS.md#release-procedure).

## Reporting issues

Bug reports should contain reproducible steps, expected and actual behaviour, `cwtch --version`,
the macOS and shell versions, and redacted output. Use [SECURITY.md](SECURITY.md) rather than a
public issue for vulnerabilities.
