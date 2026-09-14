# About openssh-windows

`cvsz/openssh-windows` provides a production-oriented, idempotent Windows OpenSSH installer and operator workflow.

The project covers the full lifecycle: install Windows OpenSSH capabilities, configure services, apply a conservative firewall policy, harden and validate `sshd_config`, manage optional SSH client aliases/keys, verify health, and retain backup state for repair or rollback.

## Design goals

- secure defaults instead of convenience defaults
- idempotent reruns
- PowerShell 7 as the primary runtime
- Windows PowerShell 5.1 only as the servicing/bootstrap compatibility boundary
- explicit validation before replacing active SSH server configuration
- clear transcript logging and machine-readable health reporting
- no embedded credentials or private-key export
- no permanent PowerShell execution-policy changes

## Optional ZeaZ integration

The installer can manage SSH aliases for:

- `prod.zeaz.dev`
- `core.zeaz.dev`
- `ha-a.zeaz.dev`
- `ha-b.zeaz.dev`

ZeaZ integration is optional. The Windows OpenSSH lifecycle works without it.

## Supported workflow

The primary target is Windows 11 with PowerShell 7. Windows PowerShell 5.1 is supported as a bootstrap and capability-servicing bridge rather than as the main installer runtime.
