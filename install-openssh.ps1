#requires -Version 7.0
<#
.SYNOPSIS
  Production-oriented OpenSSH installer/repair/verification utility for Windows 11.

.DESCRIPTION
  Installs and configures Microsoft OpenSSH Client/Server optional capabilities,
  manages sshd and ssh-agent, creates a LAN-scoped firewall rule, backs up and
  hardens sshd_config, optionally generates per-host Ed25519 keys, writes a
  managed SSH client config block for ZeaZ hosts, optionally deploys public keys
  to Linux targets, and emits a JSON health report.

  The script does not weaken PowerShell execution policy and never embeds or
  transmits private keys.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Client','Server','Full')]
    [string]$Mode = 'Full',

    [ValidateSet('Install','Repair','Verify','Uninstall','ExportReport')]
    [string]$Action = 'Install',

    [switch]$ConfigureZeaZ,
    [switch]$GenerateKeys,
    [switch]$DeployPublicKeys,

    [string]$RemoteUser = $env:USERNAME,
    [int]$SshPort = 22,

    [ValidateSet('LocalSubnet','Any')]
    [string]$FirewallScope = 'LocalSubnet',

    [switch]$AllowPasswordAuthentication,
    [switch]$EnableAgent,
    [switch]$Force,

    [string]$BackupRoot = "$env:ProgramData\OpenSSH-Installer\backups",
    [string]$ReportPath = "$env:ProgramData\OpenSSH-Installer\reports\openssh-health.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Script:ClientCapability = 'OpenSSH.Client~~~~0.0.1.0'
$Script:ServerCapability = 'OpenSSH.Server~~~~0.0.1.0'
$Script:SshDir = Join-Path $env:USERPROFILE '.ssh'
$Script:ProgramDataSsh = Join-Path $env:ProgramData 'ssh'
$Script:SshdConfig = Join-Path $Script:ProgramDataSsh 'sshd_config'
$Script:OpenSshBin = Join-Path $env:WINDIR 'System32\OpenSSH'
$Script:FirewallRuleName = 'OpenSSH-Server-In-TCP-ZeaZ'
$Script:LogRoot = Join-Path $env:ProgramData 'OpenSSH-Installer\logs'
$Script:TranscriptStarted = $false
$Script:ZeaZHosts = [ordered]@{
    'prod' = 'prod.zeaz.dev'
    'core' = 'core.zeaz.dev'
    'ha-a' = 'ha-a.zeaz.dev'
    'ha-b' = 'ha-b.zeaz.dev'
}

function Write-Step {
    param([string]$Message)
    Write-Host "[OpenSSH] $Message" -ForegroundColor Cyan
}

function Test-IsAdministrator {
    if (-not $IsWindows) { return $false }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Windows11 {
    if (-not $IsWindows) { throw 'This installer requires Windows.' }
    $os = Get-CimInstance Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    if ($build -lt 22000) {
        throw "Windows 11 is required. Detected build $build."
    }
}

function Get-OriginalArgumentList {
    $argsOut = @('-NoProfile','-File',"`"$PSCommandPath`"",'-Mode',$Mode,'-Action',$Action,'-SshPort',"$SshPort",'-FirewallScope',$FirewallScope,'-RemoteUser',"`"$RemoteUser`"",'-BackupRoot',"`"$BackupRoot`"",'-ReportPath',"`"$ReportPath`"")
    foreach ($switchName in 'ConfigureZeaZ','GenerateKeys','DeployPublicKeys','AllowPasswordAuthentication','EnableAgent','Force','WhatIf') {
        $value = switch ($switchName) {
            'ConfigureZeaZ' { $ConfigureZeaZ }
            'GenerateKeys' { $GenerateKeys }
            'DeployPublicKeys' { $DeployPublicKeys }
            'AllowPasswordAuthentication' { $AllowPasswordAuthentication }
            'EnableAgent' { $EnableAgent }
            'Force' { $Force }
            'WhatIf' { $WhatIfPreference }
        }
        if ($value) { $argsOut += "-$switchName" }
    }
    return $argsOut
}

function Ensure-Elevated {
    if ($Action -in @('Verify','ExportReport')) { return }
    if (Test-IsAdministrator) { return }
    Write-Step 'Administrator rights are required; requesting elevation.'
    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwsh) { $pwsh = (Get-Command powershell.exe).Source }
    if (-not $pwsh) { throw 'Unable to locate PowerShell for elevation.' }
    Start-Process -FilePath $pwsh -Verb RunAs -ArgumentList (Get-OriginalArgumentList)
    exit
}

function Start-InstallerTranscript {
    if (-not (Test-IsAdministrator)) { return }
    New-Item -ItemType Directory -Force -Path $Script:LogRoot | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $Script:LogRoot "openssh-installer-$stamp.log"
    try {
        Start-Transcript -Path $path -Force | Out-Null
        $Script:TranscriptStarted = $true
        Write-Step "Log: $path"
    } catch {
        Write-Warning "Unable to start transcript: $($_.Exception.Message)"
    }
}

function Stop-InstallerTranscript {
    if ($Script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}

function Invoke-DismExeCapability {
    param(
        [Parameter(Mandatory)][ValidateSet('State','Add','Remove')][string]$Operation,
        [Parameter(Mandatory)][string]$Name
    )

    $dism = Join-Path $env:WINDIR 'System32\dism.exe'
    if (-not (Test-Path $dism)) { throw "DISM executable not found: $dism" }

    switch ($Operation) {
        'State' {
            Write-Step "Fallback: querying $Name with dism.exe"
            $output = & $dism /English /Online /Get-CapabilityInfo "/CapabilityName:$Name" 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "dism.exe capability query failed for $Name (exit $LASTEXITCODE): $($output -join ' ')"
            }
            $line = $output | Where-Object { $_ -match '^\s*State\s*:\s*(\S+)' } | Select-Object -First 1
            if (-not $line) { throw "Unable to parse capability state for $Name from dism.exe output." }
            [void]($line -match '^\s*State\s*:\s*(\S+)')
            return $Matches[1]
        }
        'Add' {
            Write-Step "Fallback: installing $Name with dism.exe"
            $output = & $dism /English /Online /Add-Capability "/CapabilityName:$Name" /NoRestart 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "dism.exe capability install failed for $Name (exit $LASTEXITCODE): $($output -join ' ')"
            }
            return 'Installed'
        }
        'Remove' {
            Write-Step "Fallback: removing $Name with dism.exe"
            $output = & $dism /English /Online /Remove-Capability "/CapabilityName:$Name" /NoRestart 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "dism.exe capability removal failed for $Name (exit $LASTEXITCODE): $($output -join ' ')"
            }
            return 'NotPresent'
        }
    }
}

function Invoke-WindowsPowerShellCapability {
    param(
        [Parameter(Mandatory)][ValidateSet('State','Add','Remove')][string]$Operation,
        [Parameter(Mandatory)][string]$Name
    )

    # The inbox DISM PowerShell module is a Windows PowerShell component. On
    # some Windows 11 builds it can fail under PowerShell 7 with
    # "Class not registered". Run only the servicing call in Windows
    # PowerShell 5.1 and keep the rest of this installer on PowerShell 7.
    $winPs = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $winPs)) {
        return Invoke-DismExeCapability -Operation $Operation -Name $Name
    }

    $escapedName = $Name.Replace("'", "''")
    $command = switch ($Operation) {
        'State'  { "`$ErrorActionPreference='Stop'; `$ProgressPreference='SilentlyContinue'; Import-Module Dism -ErrorAction Stop; (Get-WindowsCapability -Online -Name '$escapedName' -ErrorAction Stop).State.ToString()" }
        'Add'    { "`$ErrorActionPreference='Stop'; `$ProgressPreference='SilentlyContinue'; Import-Module Dism -ErrorAction Stop; Add-WindowsCapability -Online -Name '$escapedName' -ErrorAction Stop | Out-Null; 'Installed'" }
        'Remove' { "`$ErrorActionPreference='Stop'; `$ProgressPreference='SilentlyContinue'; Import-Module Dism -ErrorAction Stop; Remove-WindowsCapability -Online -Name '$escapedName' -ErrorAction Stop | Out-Null; 'NotPresent'" }
    }

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    Write-Step "Servicing $Name via inbox Windows PowerShell 5.1 ($Operation)..."
    $output = & $winPs -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        $result = @($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }) | Select-Object -Last 1
        if ($result) { return $result }
    }

    Write-Warning "Windows PowerShell capability servicing failed for $Name (exit $exitCode). Falling back to dism.exe."
    return Invoke-DismExeCapability -Operation $Operation -Name $Name
}

function Get-CapabilityState {
    param([Parameter(Mandatory)][string]$Name)
    Write-Step "Checking Windows capability: $Name"
    $state = Invoke-WindowsPowerShellCapability -Operation State -Name $Name
    Write-Step "$Name state: $state"
    return $state
}

function Ensure-Capability {
    param([Parameter(Mandatory)][string]$Name)
    $state = Get-CapabilityState -Name $Name
    if ($state -eq 'Installed') {
        Write-Step "$Name already installed."
        return
    }
    if ($PSCmdlet.ShouldProcess($Name, 'Install Windows capability')) {
        Write-Step "Installing $Name"
        [void](Invoke-WindowsPowerShellCapability -Operation Add -Name $Name)
        $verified = Get-CapabilityState -Name $Name
        if ($verified -ne 'Installed') { throw "$Name installation did not reach Installed state (state=$verified)." }
    }
}

function Remove-CapabilitySafe {
    param([Parameter(Mandatory)][string]$Name)
    $state = Get-CapabilityState -Name $Name
    if ($state -ne 'Installed') { return }
    if ($PSCmdlet.ShouldProcess($Name, 'Remove Windows capability')) {
        [void](Invoke-WindowsPowerShellCapability -Operation Remove -Name $Name)
    }
}

function Backup-OpenSshState {
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dest = Join-Path $BackupRoot $stamp
    New-Item -ItemType Directory -Force -Path $dest | Out-Null

    if (Test-Path $Script:SshdConfig) {
        Copy-Item -LiteralPath $Script:SshdConfig -Destination (Join-Path $dest 'sshd_config') -Force
    }
    if (Test-Path $Script:SshDir) {
        $clientConfig = Join-Path $Script:SshDir 'config'
        if (Test-Path $clientConfig) {
            Copy-Item -LiteralPath $clientConfig -Destination (Join-Path $dest 'client_config') -Force
        }
    }

    $serviceInfo = @()
    foreach ($name in 'sshd','ssh-agent') {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) {
            $cim = Get-CimInstance Win32_Service -Filter "Name='$name'"
            $serviceInfo += [pscustomobject]@{ Name=$name; Status=$svc.Status.ToString(); StartMode=$cim.StartMode }
        }
    }
    $serviceInfo | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dest 'services.json') -Encoding UTF8
    Write-Step "Backup created: $dest"
    return $dest
}

function Set-ServiceSafe {
    param(
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet('Automatic','Manual','Disabled')][string]$StartupType,
        [switch]$Start
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { throw "Service '$Name' was not found." }
    if ($PSCmdlet.ShouldProcess($Name, "Set-Service StartupType=$StartupType")) {
        Set-Service -Name $Name -StartupType $StartupType
    }
    if ($Start -and $svc.Status -ne 'Running') {
        if ($PSCmdlet.ShouldProcess($Name, 'Start service')) { Start-Service -Name $Name }
    }
}

function Ensure-FirewallRule {
    $remote = if ($FirewallScope -eq 'Any') { 'Any' } else { 'LocalSubnet' }
    $existing = Get-NetFirewallRule -Name $Script:FirewallRuleName -ErrorAction SilentlyContinue
    if ($existing) {
        if ($PSCmdlet.ShouldProcess($Script:FirewallRuleName, 'Normalize managed SSH firewall rule')) {
            Set-NetFirewallRule -Name $Script:FirewallRuleName -Enabled True -Direction Inbound -Action Allow -Profile Domain,Private -RemoteAddress $remote -Protocol TCP -LocalPort $SshPort
        }
    } else {
        if ($PSCmdlet.ShouldProcess($Script:FirewallRuleName, "Create TCP/$SshPort firewall rule scoped to $remote")) {
            New-NetFirewallRule -Name $Script:FirewallRuleName -DisplayName 'OpenSSH Server (ZeaZ managed)' -Enabled True -Direction Inbound -Action Allow -Protocol TCP -LocalPort $SshPort -Profile Domain,Private -RemoteAddress $remote | Out-Null
        }
    }
}

function Remove-ManagedFirewallRule {
    $rule = Get-NetFirewallRule -Name $Script:FirewallRuleName -ErrorAction SilentlyContinue
    if ($rule -and $PSCmdlet.ShouldProcess($Script:FirewallRuleName, 'Remove managed firewall rule')) {
        Remove-NetFirewallRule -Name $Script:FirewallRuleName
    }
}

function Set-GlobalSshdDirective {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )
    $matchIndex = $Lines.Count
    for ($i=0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*Match\s+') { $matchIndex = $i; break }
    }

    $found = $false
    for ($i=0; $i -lt $matchIndex; $i++) {
        if ($Lines[$i] -match "^\s*#?\s*$([regex]::Escape($Name))\s+") {
            $Lines[$i] = "$Name $Value"
            $found = $true
            break
        }
    }
    if (-not $found) {
        $Lines.Insert($matchIndex, "$Name $Value")
    }
}

function Test-SshdConfigFile {
    param([Parameter(Mandatory)][string]$Path)
    $sshd = Join-Path $Script:OpenSshBin 'sshd.exe'
    if (-not (Test-Path $sshd)) { throw "sshd.exe not found at $sshd" }
    & $sshd -t -f $Path
    if ($LASTEXITCODE -ne 0) { throw "sshd_config validation failed with exit code $LASTEXITCODE" }
}

function Harden-SshdConfig {
    if (-not (Test-Path $Script:SshdConfig)) {
        throw "sshd_config not found at $Script:SshdConfig"
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $Script:SshdConfig) { $lines.Add($line) }

    Set-GlobalSshdDirective -Lines $lines -Name 'Port' -Value "$SshPort"
    Set-GlobalSshdDirective -Lines $lines -Name 'PubkeyAuthentication' -Value 'yes'
    Set-GlobalSshdDirective -Lines $lines -Name 'PasswordAuthentication' -Value $(if ($AllowPasswordAuthentication) { 'yes' } else { 'no' })
    Set-GlobalSshdDirective -Lines $lines -Name 'PermitEmptyPasswords' -Value 'no'
    Set-GlobalSshdDirective -Lines $lines -Name 'MaxAuthTries' -Value '4'
    Set-GlobalSshdDirective -Lines $lines -Name 'MaxSessions' -Value '10'
    Set-GlobalSshdDirective -Lines $lines -Name 'ClientAliveInterval' -Value '300'
    Set-GlobalSshdDirective -Lines $lines -Name 'ClientAliveCountMax' -Value '2'
    Set-GlobalSshdDirective -Lines $lines -Name 'AllowTcpForwarding' -Value 'yes'
    Set-GlobalSshdDirective -Lines $lines -Name 'GatewayPorts' -Value 'no'
    Set-GlobalSshdDirective -Lines $lines -Name 'X11Forwarding' -Value 'no'
    Set-GlobalSshdDirective -Lines $lines -Name 'LogLevel' -Value 'VERBOSE'

    $temp = Join-Path $env:TEMP "sshd_config.$PID.tmp"
    try {
        $lines | Set-Content -LiteralPath $temp -Encoding ascii
        Test-SshdConfigFile -Path $temp
        if ($PSCmdlet.ShouldProcess($Script:SshdConfig, 'Install validated hardened sshd_config')) {
            Copy-Item -LiteralPath $temp -Destination $Script:SshdConfig -Force
        }
    } finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-SshDirectory {
    if (-not (Test-Path $Script:SshDir)) {
        New-Item -ItemType Directory -Path $Script:SshDir -Force | Out-Null
    }
}

function Ensure-Ed25519Key {
    param([Parameter(Mandatory)][string]$Alias)
    Ensure-SshDirectory
    $safeAlias = $Alias -replace '[^A-Za-z0-9_.-]','_'
    $path = Join-Path $Script:SshDir "id_ed25519_$safeAlias"
    if (Test-Path $path) {
        Write-Step "Key exists: $path"
        return $path
    }
    $sshKeygen = Get-Command ssh-keygen.exe -ErrorAction Stop
    if ($PSCmdlet.ShouldProcess($path, 'Generate Ed25519 keypair')) {
        & $sshKeygen.Source -t ed25519 -a 64 -f $path -N '' -C "$env:USERNAME@$env:COMPUTERNAME:$Alias"
        if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed for $Alias" }
    }
    return $path
}

function Set-ZeaZSshConfig {
    Ensure-SshDirectory
    $configPath = Join-Path $Script:SshDir 'config'
    $begin = '# BEGIN OMEGA-ZEAZ-MANAGED'
    $end = '# END OMEGA-ZEAZ-MANAGED'
    $old = if (Test-Path $configPath) { Get-Content -Raw -LiteralPath $configPath } else { '' }
    $escapedBegin = [regex]::Escape($begin)
    $escapedEnd = [regex]::Escape($end)
    $clean = [regex]::Replace($old, "(?ms)^$escapedBegin.*?^$escapedEnd\s*", '').TrimEnd()

    $block = [System.Collections.Generic.List[string]]::new()
    $block.Add($begin)
    $block.Add('# Generated by install-openssh.ps1. Edit outside this block only.')
    foreach ($entry in $Script:ZeaZHosts.GetEnumerator()) {
        $alias = $entry.Key
        $hostName = $entry.Value
        $keyPath = Join-Path $Script:SshDir "id_ed25519_$alias"
        $block.Add("Host $alias $hostName")
        $block.Add("    HostName $hostName")
        $block.Add("    User $RemoteUser")
        $block.Add("    Port $SshPort")
        if (Test-Path $keyPath) { $block.Add("    IdentityFile $keyPath") }
        $block.Add('    IdentitiesOnly yes')
        $block.Add('    ServerAliveInterval 20')
        $block.Add('    ServerAliveCountMax 3')
        $block.Add('    TCPKeepAlive yes')
        $block.Add('    HashKnownHosts yes')
        $block.Add('')
    }
    $block.Add($end)

    $newContent = if ([string]::IsNullOrWhiteSpace($clean)) { $block -join "`r`n" } else { "$clean`r`n`r`n$($block -join "`r`n")" }
    if ($PSCmdlet.ShouldProcess($configPath, 'Write ZeaZ managed SSH client block')) {
        Set-Content -LiteralPath $configPath -Value $newContent -Encoding utf8NoBOM
    }
}

function Deploy-PublicKey {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][string]$KeyPath
    )
    $pub = "$KeyPath.pub"
    if (-not (Test-Path $pub)) { throw "Public key missing: $pub" }
    $target = "$RemoteUser@$HostName"
    $remote = "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys; key=`$(cat); grep -qxF `"`$key`" ~/.ssh/authorized_keys || printf '%s\n' `"`$key`" >> ~/.ssh/authorized_keys"
    if ($PSCmdlet.ShouldProcess($target, 'Deploy public key (interactive authentication may be requested)')) {
        Get-Content -Raw -LiteralPath $pub | & ssh.exe -p $SshPort $target $remote
        if ($LASTEXITCODE -ne 0) { throw "Public-key deployment failed for $target" }
    }
}

function Configure-ZeaZClient {
    if ($GenerateKeys) {
        foreach ($alias in $Script:ZeaZHosts.Keys) { [void](Ensure-Ed25519Key -Alias $alias) }
    }
    Set-ZeaZSshConfig
    if ($DeployPublicKeys) {
        foreach ($entry in $Script:ZeaZHosts.GetEnumerator()) {
            $key = Join-Path $Script:SshDir "id_ed25519_$($entry.Key)"
            if (-not (Test-Path $key)) {
                throw "Cannot deploy key for $($entry.Key): $key is missing. Use -GenerateKeys first."
            }
            Deploy-PublicKey -HostName $entry.Value -KeyPath $key
        }
    }
}

function Get-CommandVersionText {
    param([string]$Command,[string[]]$Arguments)
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    try { return ((& $cmd.Source @Arguments 2>&1 | Select-Object -First 1) -join '').Trim() } catch { return $null }
}

function Test-OpenSshHealth {
    $result = [ordered]@{
        Timestamp = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        User = $env:USERNAME
        Mode = $Mode
        ClientCapability = $null
        ServerCapability = $null
        SshVersion = Get-CommandVersionText -Command 'ssh.exe' -Arguments @('-V')
        SshdConfig = [ordered]@{ Path=$Script:SshdConfig; Exists=(Test-Path $Script:SshdConfig); Valid=$false }
        Services = @()
        Firewall = $null
        ZeaZ = @()
        Healthy = $true
    }

    try { $result.ClientCapability = Get-CapabilityState -Name $Script:ClientCapability } catch { $result.ClientCapability = 'Unknown' }
    try { $result.ServerCapability = Get-CapabilityState -Name $Script:ServerCapability } catch { $result.ServerCapability = 'Unknown' }

    foreach ($name in 'sshd','ssh-agent') {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) { $result.Services += [pscustomobject]@{ Name=$name; Status=$svc.Status.ToString() } }
    }

    if (Test-Path $Script:SshdConfig) {
        try { Test-SshdConfigFile -Path $Script:SshdConfig; $result.SshdConfig.Valid = $true } catch { $result.SshdConfig.Valid = $false }
    }

    $fw = Get-NetFirewallRule -Name $Script:FirewallRuleName -ErrorAction SilentlyContinue
    if ($fw) {
        $pf = $fw | Get-NetFirewallPortFilter
        $af = $fw | Get-NetFirewallAddressFilter
        $result.Firewall = [pscustomobject]@{ Enabled=$fw.Enabled.ToString(); Port=$pf.LocalPort; RemoteAddress=($af.RemoteAddress -join ',') }
    }

    if ($ConfigureZeaZ -or (Test-Path (Join-Path $Script:SshDir 'config'))) {
        foreach ($entry in $Script:ZeaZHosts.GetEnumerator()) {
            $dnsOk = $false
            try { $dnsOk = [bool](Resolve-DnsName $entry.Value -ErrorAction Stop | Where-Object Type -in 'A','AAAA' | Select-Object -First 1) } catch { }
            $tcp = $false
            try { $tcp = (Test-NetConnection -ComputerName $entry.Value -Port $SshPort -InformationLevel Quiet -WarningAction SilentlyContinue) } catch { }
            $result.ZeaZ += [pscustomobject]@{ Alias=$entry.Key; Host=$entry.Value; Dns=$dnsOk; Tcp22=$tcp }
        }
    }

    if ($Mode -in @('Client','Full') -and $result.ClientCapability -ne 'Installed') { $result.Healthy = $false }
    if ($Mode -in @('Server','Full')) {
        if ($result.ServerCapability -ne 'Installed') { $result.Healthy = $false }
        if (-not $result.SshdConfig.Valid) { $result.Healthy = $false }
        $sshd = $result.Services | Where-Object Name -eq 'sshd'
        if (-not $sshd -or $sshd.Status -ne 'Running') { $result.Healthy = $false }
    }
    return [pscustomobject]$result
}

function Export-HealthReport {
    $health = Test-OpenSshHealth
    $dir = Split-Path -Parent $ReportPath
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $health | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-Step "Health report: $ReportPath"
    $health | Format-List | Out-Host
    return $health
}

function Install-OrRepair {
    [void](Backup-OpenSshState)

    if ($Mode -in @('Client','Full')) { Ensure-Capability -Name $Script:ClientCapability }
    if ($Mode -in @('Server','Full')) { Ensure-Capability -Name $Script:ServerCapability }

    if ($Mode -in @('Server','Full')) {
        Set-ServiceSafe -Name 'sshd' -StartupType Automatic -Start
        Ensure-FirewallRule
        Harden-SshdConfig
        if ($PSCmdlet.ShouldProcess('sshd', 'Restart after validated configuration update')) {
            Restart-Service sshd -Force
        }
    }

    if ($Mode -in @('Client','Full')) {
        if ($EnableAgent) { Set-ServiceSafe -Name 'ssh-agent' -StartupType Automatic -Start }
        if ($ConfigureZeaZ) { Configure-ZeaZClient }
    }
}

function Uninstall-OpenSsh {
    [void](Backup-OpenSshState)
    if ($Mode -in @('Server','Full')) {
        $svc = Get-Service sshd -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Stopped' -and $PSCmdlet.ShouldProcess('sshd','Stop service')) { Stop-Service sshd -Force }
        Remove-ManagedFirewallRule
        Remove-CapabilitySafe -Name $Script:ServerCapability
    }
    if ($Mode -in @('Client','Full')) {
        $svc = Get-Service ssh-agent -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Stopped' -and $PSCmdlet.ShouldProcess('ssh-agent','Stop service')) { Stop-Service ssh-agent -Force }
        Remove-CapabilitySafe -Name $Script:ClientCapability
    }
    Write-Warning 'User keys, authorized_keys, and SSH client configuration were preserved. Backups were preserved.'
}

try {
    Assert-Windows11
    Ensure-Elevated
    Start-InstallerTranscript
    Write-Step "Action=$Action Mode=$Mode PowerShell=$($PSVersionTable.PSVersion)"

    switch ($Action) {
        'Install' { Install-OrRepair }
        'Repair' { Install-OrRepair }
        'Verify' { }
        'Uninstall' { Uninstall-OpenSsh }
        'ExportReport' { }
    }

    $health = Export-HealthReport
    if ($Action -in @('Install','Repair','Verify') -and -not $health.Healthy) {
        throw "OpenSSH health verification failed. Inspect $ReportPath and transcript logs."
    }
    Write-Step 'Completed successfully.'
} catch {
    Write-Error $_
    exit 1
} finally {
    Stop-InstallerTranscript
}
