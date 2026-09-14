# Implementation Checklist

## Installer

- [x] PowerShell 7 entry point
- [x] Client, Server, and Full modes
- [x] Install, Repair, Verify, Uninstall, and ExportReport actions
- [x] elevation and WhatIf handling
- [x] state backup before managed changes
- [x] OpenSSH Client and Server capability management
- [x] Windows PowerShell 5.1 servicing bridge
- [x] DISM executable fallback
- [x] post-servicing state verification

## Server configuration

- [x] sshd automatic startup and running state
- [x] validated sshd_config before activation
- [x] blank-line-safe configuration editing
- [x] conservative authentication defaults

## Network

- [x] managed inbound TCP port 22 rule
- [x] Domain and Private profiles by default
- [x] LocalSubnet source scope by default
- [x] explicit Any scope option
- [x] compatible NetSecurity query/update flow

## Client integration

- [x] managed SSH config block
- [x] ZeaZ prod, core, ha-a, and ha-b presets
- [x] per-host Ed25519 key generation
- [x] existing keys preserved on rerun
- [x] optional public-key deployment

## Verification

- [x] capability, service, configuration, and firewall health checks
- [x] ZeaZ DNS and TCP probes
- [x] JSON health report
- [x] live Windows validation completed with Healthy = True
- [x] regression contract tests
- [ ] disposable Windows integration-test environment
- [ ] signed release artifacts and provenance
