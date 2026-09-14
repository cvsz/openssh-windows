# Contributing

Thanks for contributing to `cvsz/openssh-windows`.

## Development workflow

1. Branch from `main`.
2. Keep changes focused and reviewable.
3. Add or update regression tests for behavior changes.
4. Run `python -m pytest -q`.
5. Parse both PowerShell entry points before opening a pull request.
6. For machine-mutating behavior, validate on a disposable Windows 11 VM or test host.
7. Update documentation and `CHANGELOG.md` when behavior, compatibility, or security defaults change.

## Branch naming

Use concise prefixes such as `feat/`, `fix/`, `docs/`, `chore/`, `refactor/`, `test/`, or `security/`.

## Commit guidance

Prefer Conventional Commits, for example:

- `feat: add offline capability source option`
- `fix: preserve blank lines in sshd config`
- `security: tighten managed firewall scope`
- `docs: update Windows compatibility notes`

## Pull requests

Explain the problem, implementation, tests, Windows/PowerShell compatibility impact, security impact, and rollback considerations where applicable. Do not bypass quality or security checks to obtain a green build.

## Security

Do not report exploitable vulnerabilities in public issues. Follow `SECURITY.md`.
