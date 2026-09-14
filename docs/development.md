# Development

## Requirements

- PowerShell 7 for the main installer
- Windows 11 for end-to-end service/firewall integration testing
- Python 3 with pytest for repository contract tests

## Contract tests

Run from the repository root:

```bash
python -m pytest -q
```

The contract suite guards the behaviors that failed during live Windows validation, including Windows capability servicing, normal blank lines in `sshd_config`, NetSecurity cmdlet compatibility, and health-report pipeline behavior.

## PowerShell syntax validation

On Windows:

```powershell
$files = @('install-openssh.ps1', 'install-zeaz-openssh.ps1')
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path $file),
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null
    if ($errors.Count) { $errors; throw "Parse failed: $file" }
}
```

## Integration testing

Use a disposable Windows 11 VM or test host for mutating integration work. Exercise at least:

1. Client capability absent/present paths.
2. Server capability absent/present paths.
3. `sshd` service start and restart.
4. firewall creation and rerun normalization.
5. `sshd_config` backup, edit, validation, and activation.
6. repeat install to prove idempotency.
7. verify/report-only flow.

Avoid using production hosts as the first execution environment for new mutating behavior.

## Development rules

- add a regression test for each discovered failure;
- keep capability servicing isolated from the rest of the PowerShell 7 runtime;
- validate generated SSH server configuration before activation;
- never commit credentials, generated private keys, or local health/log files;
- do not weaken security gates merely to make CI pass.
