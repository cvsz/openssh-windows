# Windows PowerShell 5.1-compatible bootstrap for the PowerShell 7 OpenSSH installer.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$RemoteUser = $env:USERNAME,
    [switch]$DeployPublicKeys,
    [switch]$SkipPowerShell7Install
)

$ErrorActionPreference = 'Stop'

function Resolve-Pwsh {
    $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $known = @(
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe')
    )
    foreach ($path in $known) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Install-PowerShell7 {
    if ($SkipPowerShell7Install) {
        throw 'PowerShell 7 is required but was not found. Install Microsoft.PowerShell with WinGet, then rerun this launcher.'
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'PowerShell 7 is required and winget.exe is unavailable. Install PowerShell 7 from Microsoft, then rerun this launcher.'
    }

    Write-Host '[Bootstrap] PowerShell 7 was not found. Installing Microsoft.PowerShell with WinGet...' -ForegroundColor Cyan
    $wingetArgs = @(
        'install',
        '--id','Microsoft.PowerShell',
        '--exact',
        '--source','winget',
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--silent',
        '--disable-interactivity'
    )

    $p = Start-Process -FilePath $winget.Source -ArgumentList $wingetArgs -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        throw "WinGet failed to install PowerShell 7. Exit code: $($p.ExitCode)"
    }

    # Refresh PATH for this process after WinGet installation.
    $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = "$machinePath;$userPath"

    $pwsh = Resolve-Pwsh
    if (-not $pwsh) {
        throw 'PowerShell 7 installation completed but pwsh.exe could not be located. Open a new terminal and rerun this launcher.'
    }
    return $pwsh
}

function Invoke-UnderPowerShell7 {
    param([Parameter(Mandatory=$true)][string]$PwshPath)

    $forward = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy','Bypass',
        '-File', $PSCommandPath,
        '-RemoteUser', $RemoteUser
    )
    if ($DeployPublicKeys) { $forward += '-DeployPublicKeys' }
    if ($SkipPowerShell7Install) { $forward += '-SkipPowerShell7Install' }
    if ($WhatIfPreference) { $forward += '-WhatIf' }

    Write-Host "[Bootstrap] Relaunching with PowerShell 7: $PwshPath" -ForegroundColor Cyan
    & $PwshPath @forward
    exit $LASTEXITCODE
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "[Bootstrap] Current host: Windows PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    $pwsh = Resolve-Pwsh
    if (-not $pwsh) { $pwsh = Install-PowerShell7 }
    Invoke-UnderPowerShell7 -PwshPath $pwsh
}

$installer = Join-Path $PSScriptRoot 'install-openssh.ps1'
if (-not (Test-Path -LiteralPath $installer)) {
    throw "Installer not found: $installer"
}

$args = @(
    '-Mode','Full',
    '-Action','Install',
    '-ConfigureZeaZ',
    '-GenerateKeys',
    '-EnableAgent',
    '-RemoteUser',$RemoteUser
)
if ($DeployPublicKeys) { $args += '-DeployPublicKeys' }
if ($WhatIfPreference) { $args += '-WhatIf' }

& $installer @args
exit $LASTEXITCODE
