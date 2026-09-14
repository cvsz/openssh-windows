# Changelog

## 2026-09-14

### Added

- Windows OpenSSH Client/Server install, repair, verify, uninstall, and report actions
- `sshd` and `ssh-agent` service management
- Windows Firewall handling for SSH
- validated `sshd_config` updates
- optional ZeaZ SSH aliases and Ed25519 key generation
- JSON health reports
- PowerShell 7 bootstrap support
- regression contract tests

### Fixed

- Windows capability servicing compatibility between PowerShell 7 and inbox Windows PowerShell 5.1
- capability state verification after servicing
- blank-line handling in `sshd_config`
- Windows Firewall cmdlet compatibility
- final health-report object handling

### Validation

A live Windows 11 run completed successfully with both OpenSSH capabilities installed, valid server configuration, running SSH services, TCP/22 listening, an enabled inbound firewall rule, and `Healthy = True`.
