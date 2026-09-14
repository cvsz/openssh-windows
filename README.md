# OpenSSH Windows Automated Installer

Production-oriented PowerShell automation for installing, repairing, hardening, verifying, and uninstalling Microsoft OpenSSH on Windows 11.

## Production validation

The current installer has been live-validated on Windows build `10.0.26100` with PowerShell `7.6.6` and OpenSSH for Windows `9.5p2`. The validated run completed with:

- OpenSSH Client: `Installed`
- OpenSSH Server: `Installed`
- `sshd`: `Running`, `Automatic`
- `ssh-agent`: `Running`, `Automatic`
- `sshd_config`: valid
- TCP/22 listening on IPv4 and IPv6
- managed firewall rule enabled for `Domain,Private` and `LocalSubnet`
- health result: `Healthy = True`

This is evidence from one validated environment, not a claim that every Windows configuration is identical.

## Features

- Modes: `Client`, `Server`, `Full`
- Actions: `Install`, `Repair`, `Verify`, `Uninstall`, `ExportReport`
- Windows OpenSSH Client/Server Features on Demand management
- PowerShell 7 runtime with Windows PowerShell 5.1 compatibility bridge for DISM capability servicing
- `dism.exe` fallback when PowerShell servicing fails
- self-elevation for mutating actions
- idempotent `sshd` and optional `ssh-agent` configuration
- backup before managed changes
- safe `sshd_config` editing and `sshd.exe -t` validation before activation
- public-key authentication by default
- password authentication disabled unless explicitly requested
- inbound TCP/22 firewall rule scoped to `Domain,Private` + `LocalSubnet` by default
- `-WhatIf` support
- JSON health reports
- optional ZeaZ aliases for `prod`, `core`, `ha-a`, and `ha-b`
- per-host Ed25519 key generation
- optional public-key deployment to Linux hosts; private keys never leave Windows
- uninstall path that preserves user SSH keys/configuration/backups

## Repository files

```text
install-openssh.ps1          Main PowerShell 7 installer
install-zeaz-openssh.ps1     Windows PowerShell 5.1-compatible bootstrap
install-zeaz-openssh.cmd     CMD bootstrap
tests/                       Regression contract tests
docs/                        Architecture, development, and release guidance
```

## Recommended install

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\install-openssh.ps1 `
  -Mode Full `
  -Action Install `
  -ConfigureZeaZ `
  -GenerateKeys `
  -EnableAgent `
  -RemoteUser cvsz
```

`-ExecutionPolicy Bypass` above is process-scoped for that invocation. The installer never calls `Set-ExecutionPolicy` and does not permanently weaken execution policy.

## Windows PowerShell 5.1 bootstrap

```powershell
.\install-zeaz-openssh.ps1 -RemoteUser cvsz
```

or:

```cmd
install-zeaz-openssh.cmd -RemoteUser cvsz
```

The bootstrap locates PowerShell 7. If it is missing, it can install stable `Microsoft.PowerShell` through WinGet and relaunch under `pwsh.exe`. Add `-SkipPowerShell7Install` to forbid automatic installation.

## Verify only

```powershell
pwsh.exe -NoLogo -NoProfile -File .\install-openssh.ps1 `
  -Mode Full `
  -Action Verify `
  -ConfigureZeaZ
```

Default health report:

```text
C:\ProgramData\OpenSSH-Installer\reports\openssh-health.json
```

## ZeaZ public-key deployment

```powershell
pwsh.exe -NoLogo -NoProfile -File .\install-openssh.ps1 `
  -Mode Client `
  -Action Repair `
  -ConfigureZeaZ `
  -GenerateKeys `
  -DeployPublicKeys `
  -RemoteUser cvsz
```

Interactive remote authentication may be requested. Only public key material is sent.

## Temporary password bootstrap

Password authentication is disabled by default. To explicitly allow it temporarily:

```powershell
.\install-openssh.ps1 -Mode Server -Action Repair -AllowPasswordAuthentication
```

After public-key login is verified, rerun without `-AllowPasswordAuthentication`.

## Uninstall

```powershell
.\install-openssh.ps1 -Mode Full -Action Uninstall
```

User SSH keys, client configuration, and installer backups are intentionally preserved.

## Security model

- no embedded passwords, tokens, or private keys
- no permanent execution-policy weakening
- invalid `sshd_config` is rejected before activation
- firewall defaults to trusted Windows profiles and local subnet
- password authentication is opt-in
- private keys remain local
- state is backed up before managed changes

See `SECURITY.md` for vulnerability reporting.

## Testing

```bash
python -m pytest -q
```

CI also parses both PowerShell entry points on `windows-latest`.

## License

MIT. See `LICENSE`.
