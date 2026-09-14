# Roadmap

## Current state

The core Windows OpenSSH installation, repair, hardening, ZeaZ client configuration, and health-report flow is implemented and has completed successfully in live Windows validation.

## Next bounded improvements

- add a disposable Windows integration-test harness so CI can validate service/firewall behavior without mutating developer machines
- test additional Windows 11 patch levels and PowerShell 7 releases
- add regression coverage for network profile transitions (`Public` vs `Private` / `Domain`)
- allow host inventory overrides without editing source
- package release ZIPs and SHA-256 checksums in GitHub Actions
- add signed-release guidance without requiring signing for local development
- document offline Features on Demand installation using matching Windows media

## Non-goals

- embedding passwords or private keys
- disabling Windows security controls globally
- permanently changing PowerShell execution policy
- opening SSH to unrestricted network scope by default
