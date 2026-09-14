# Release

## Release gate

Before publishing an installer release:

1. run `python -m pytest -q` and require zero failures;
2. parse both PowerShell entry points with the PowerShell parser;
3. verify that no credentials or private-key files are tracked;
4. verify the main installer can produce a healthy report on a disposable Windows 11 host;
5. confirm `sshd_config` validation succeeds before activation;
6. update `CHANGELOG.md` and compatibility notes;
7. calculate SHA-256 checksums for packaged artifacts.

## Package contents

A release ZIP should contain at least:

- `install-openssh.ps1`
- `install-zeaz-openssh.ps1`
- `install-zeaz-openssh.cmd`
- `README.md`
- license and release notes

Do not include generated SSH keys, transcripts, backups, or host-specific health reports.

## Versioning

Use Semantic Versioning for released installer packages. A behavior-changing security/default change should be called out explicitly in the changelog even when command-line compatibility is retained.

## Rollback

The installer stores backup state beneath:

```text
C:\ProgramData\OpenSSH-Installer\backups
```

For a bad release, stop distributing the affected artifact, restore the last known-good installer, review the backup made before the failed mutation, and validate `sshd_config` before restoring or restarting the SSH service.

Capability removal is not an automatic rollback mechanism; use it only when OpenSSH itself is intentionally being uninstalled.
