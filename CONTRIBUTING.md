# Contributing to cwtch

Thank you for considering contributing! This document explains how to contribute.

## Code of Conduct

This project follows the [Contributor Covenant](https://www.contributor-covenant.org/). Be respectful and constructive.

## Getting Started

1. Fork the repository
2. Clone your fork
3. Set up the development environment (see README.md)
4. Create a branch for your changes

## Development Workflow

### Before You Start

- Check existing issues and PRs to avoid duplicates
- For significant changes, open an issue first to discuss

### Making Changes

1. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following our style guide (see CLAUDE.md)

3. Write or update tests

4. Run the test suite:
   ```bash
   bats tests/
   ```

5. Run linting:
   ```bash
   shellcheck bin/cwtch lib/common.sh tests/*.bats
   ```

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

Examples:
- `feat(profile): add export command`
- `fix(status): handle missing credential gracefully`
- `docs: update installation instructions`

### Pull Requests

1. Push your branch to your fork
2. Open a PR against the `main` branch
3. Fill out the PR template completely
4. Wait for CI to pass
5. Address review feedback

## Reporting Issues

### Bug Reports

Use the bug report template. Include:
- Steps to reproduce
- Expected vs actual behavior
- macOS version
- Logs or error messages

### Feature Requests

Use the feature request template. Include:
- Problem you're trying to solve
- Proposed solution
- Alternatives you've considered

## Questions?

- Check existing documentation
- Search closed issues
- Open an issue
