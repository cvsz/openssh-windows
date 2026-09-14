# Architecture

## System context

`openssh-windows` is a host-local Windows automation tool. It manages Microsoft OpenSSH optional capabilities, SSH services, server configuration, firewall policy, optional client keys/configuration, and health evidence.

## Components

### `install-openssh.ps1`

PowerShell 7 is the primary runtime. The script owns install, repair, verify, uninstall, backup, hardening, ZeaZ client configuration, and health reporting.

### `install-zeaz-openssh.ps1`

Windows PowerShell 5.1-compatible bootstrap. It locates PowerShell 7 and can install stable `Microsoft.PowerShell` with WinGet before relaunching the main installer.

### `install-zeaz-openssh.cmd`

Minimal CMD entry point that invokes the bootstrap script.

## Capability-servicing boundary

The main process remains on PowerShell 7, but Windows capability servicing is delegated to inbox Windows PowerShell 5.1 because the inbox DISM PowerShell module can fail under PowerShell 7 on some Windows builds. If that bridge fails, the installer falls back to `dism.exe`.

Every capability mutation is followed by a state query; the installer does not treat process completion alone as proof of installation.

## Server-configuration boundary

Before changing the active server configuration the installer:

1. backs up the current state;
2. edits a temporary `sshd_config` representation;
3. validates the temporary file using `sshd.exe -t`;
4. copies the validated file into place;
5. restarts `sshd`.

This prevents an invalid generated configuration from replacing the active configuration.

## Firewall boundary

The project creates a managed inbound rule named `OpenSSH-Server-In-TCP-ZeaZ`. Defaults are TCP/22, Domain and Private profiles, and `LocalSubnet`. `Any` source scope is explicit opt-in.

The Microsoft-created OpenSSH firewall rule can coexist with the managed rule; operators should review both when diagnosing network reachability.

## Client configuration

Optional ZeaZ integration creates a delimited managed block in the user's SSH config and optional per-host Ed25519 keys. Existing keys are reused. Public-key deployment sends only `.pub` content to remote hosts.

## Observability

- transcript logs: `C:\ProgramData\OpenSSH-Installer\logs`
- backups: `C:\ProgramData\OpenSSH-Installer\backups`
- default health report: `C:\ProgramData\OpenSSH-Installer\reports\openssh-health.json`

Formatting output is routed to the host stream so report formatting cannot contaminate the success pipeline or change the type of the returned health object.

## Trust boundaries

The installer requires administrator privileges for machine-level changes. User SSH keys and client configuration remain under the invoking user's profile. Remote public-key deployment depends on the authentication and host-verification policy of the local OpenSSH client.
