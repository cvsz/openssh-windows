from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "install-openssh.ps1"

def text():
    return SCRIPT.read_text(encoding="utf-8")

def test_installer_exists():
    assert SCRIPT.exists()

def test_modes_and_actions_are_declared():
    t = text()
    for token in ["Client", "Server", "Full", "Install", "Repair", "Verify", "Uninstall", "ExportReport"]:
        assert token in t

def test_installer_has_backup_and_restore_safety():
    t = text()
    assert "Backup-OpenSshState" in t
    assert "sshd_config" in t
    assert "Copy-Item" in t

def test_installer_manages_services_and_firewall():
    t = text()
    for token in ["sshd", "ssh-agent", "New-NetFirewallRule", "Set-Service"]:
        assert token in t

def test_installer_hardens_server():
    t = text()
    for token in ["PasswordAuthentication", "PubkeyAuthentication", "PermitEmptyPasswords", "MaxAuthTries"]:
        assert token in t

def test_installer_has_zeaz_presets():
    t = text()
    for host in ["prod.zeaz.dev", "core.zeaz.dev", "ha-a.zeaz.dev", "ha-b.zeaz.dev"]:
        assert host in t

def test_installer_supports_verification_and_whatif():
    t = text()
    assert "SupportsShouldProcess" in t
    assert "Test-OpenSshHealth" in t

def test_no_execution_policy_bypass():
    t = text().lower()
    assert "set-executionpolicy unrestricted" not in t
    assert "set-executionpolicy bypass" not in t

def test_capability_servicing_avoids_ps7_dism_cmdlets_directly():
    t = text()
    assert "Invoke-WindowsPowerShellCapability" in t
    assert "powershell.exe" in t
    assert "dism.exe" in t
    start = t.index("function Get-CapabilityState")
    end = t.index("function Backup-OpenSshState")
    block = t[start:end]
    assert "Get-WindowsCapability -Online" not in block
    assert "Add-WindowsCapability -Online" not in block
    assert "Remove-WindowsCapability -Online" not in block

def test_sshd_directive_editor_accepts_blank_lines():
    t = text()
    start = t.index('function Set-GlobalSshdDirective')
    end = t.index('function Test-SshdConfigFile')
    block = t[start:end]
    assert '[Parameter(Mandatory)][System.Collections.Generic.List[string]]$Lines' not in block

def test_firewall_update_uses_supported_set_netfirewallrule_parameters():
    t = text()
    start = t.index('function Ensure-FirewallRule')
    end = t.index('function Remove-ManagedFirewallRule')
    block = t[start:end]
    assert 'Set-NetFirewallAddressFilter -AssociatedNetFirewallRule' not in block
    assert 'Set-NetFirewallPortFilter -AssociatedNetFirewallRule' not in block
    assert 'Set-NetFirewallRule -Name $Script:FirewallRuleName' in block
    assert '-RemoteAddress $remote' in block
    assert '-Protocol TCP' in block
    assert '-LocalPort $SshPort' in block

def test_firewall_health_query_uses_pipeline_compatibility_form():
    t = text()
    start = t.index('function Test-OpenSshHealth')
    end = t.index('function Export-HealthReport')
    block = t[start:end]
    assert 'Get-NetFirewallPortFilter -AssociatedNetFirewallRule' not in block
    assert 'Get-NetFirewallAddressFilter -AssociatedNetFirewallRule' not in block
    assert '$fw | Get-NetFirewallPortFilter' in block
    assert '$fw | Get-NetFirewallAddressFilter' in block

def test_health_report_does_not_pollute_success_pipeline():
    t = text()
    assert "$health | Format-List | Out-Host" in t
    assert "$health | Format-List" in t
