# Security Policy

Security is part of the delivery baseline for `cvsz/openssh-windows` because this project changes authentication, service, firewall, and SSH configuration on Windows hosts.

## Reporting a vulnerability

Do not disclose exploitable vulnerabilities in public issues, pull requests, discussions, or commit messages. Use GitHub private vulnerability reporting/security advisories for this repository when available.

Include the affected installer version or commit, Windows build, PowerShell version, reproduction steps, impact, prerequisites, and suggested remediation when known.

## Supported versions

Security fixes are supported on the current `main` branch and the latest published release. Older installer snapshots may be superseded by later Windows compatibility fixes.

## Security expectations

- never commit credentials, tokens, private keys, generated host keys, or machine-specific secrets;
- do not permanently weaken PowerShell execution policy;
- validate generated `sshd_config` before activation;
- keep password-based SSH access opt-in rather than default;
- default inbound firewall scope to trusted profiles and the local subnet;
- preserve backups before managed configuration changes;
- treat remote public-key deployment as public-key-only transfer;
- keep GitHub Actions permissions least-privilege;
- fix CI/security failures rather than disabling the gates.

## Incident handling

For an installer security regression, stop distributing the affected release, identify the last known-good commit, review host backups and health reports, publish a corrective release, and document any operator action required to restore the intended SSH/firewall policy.
