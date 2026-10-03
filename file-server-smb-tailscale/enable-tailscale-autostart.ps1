#Requires -Version 5.1
<#
.SYNOPSIS
    Make Tailscale start automatically when Windows boots / the user signs in.

.NOTES
    Run as Administrator on BOTH the server and every client:
      powershell -ExecutionPolicy Bypass -File .\enable-tailscale-autostart.ps1

    Does not log in to Tailscale and does not store credentials.
#>

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    switch ($Level) {
        'OK'    { Write-Host $line -ForegroundColor Green }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        default { Write-Host $line }
    }
}

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TailscaleGuiExe {
    $dirs = @(
        (Join-Path $env:ProgramFiles 'Tailscale'),
        (Join-Path ${env:ProgramFiles(x86)} 'Tailscale')
    )
    $names = @('tailscale-ipn.exe', 'Tailscale.exe')
    foreach ($dir in $dirs) {
        if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($n in $names) {
            $p = Join-Path $dir $n
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    return $null
}

function Enable-StartupApproved {
    param([string]$KeyPath, [string]$ValueName)
    if (-not (Test-Path -LiteralPath $KeyPath)) {
        New-Item -Path $KeyPath -Force | Out-Null
    }
    # 0x02 = enabled in Windows 11 Startup apps
    $enabled = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    New-ItemProperty -Path $KeyPath -Name $ValueName -PropertyType Binary -Value $enabled -Force | Out-Null
}

$exitCode = 0
try {
    if (-not (Test-IsAdministrator)) {
        Write-Host 'ERROR: Please run this script as Administrator.' -ForegroundColor Red
        $exitCode = 2
        throw 'ERROR: Please run this script as Administrator.'
    }

    $svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
    if (-not $svc) {
        throw 'Tailscale is not installed. Run setup-server.ps1 or setup-client.ps1 first.'
    }

    Set-Service -Name 'Tailscale' -StartupType Automatic
    if ($svc.Status -ne 'Running') {
        Start-Service -Name 'Tailscale'
    }
    Write-Log 'Tailscale service: Automatic, running.' 'OK'

    $gui = Get-TailscaleGuiExe
    if (-not $gui) {
        Write-Log 'Tailscale tray app not found. VPN service will still start in the background after reboot.' 'WARN'
    }
    else {
        $cmd = '"' + $gui + '"'
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'Tailscale' -PropertyType String -Value $cmd -Force | Out-Null
        New-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'Tailscale' -PropertyType String -Value $cmd -Force | Out-Null
        Enable-StartupApproved -KeyPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' -ValueName 'Tailscale'
        Enable-StartupApproved -KeyPath 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' -ValueName 'Tailscale'

        $startupDir = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'
        if (Test-Path -LiteralPath $startupDir) {
            $lnk = Join-Path $startupDir 'Tailscale.lnk'
            $w = New-Object -ComObject WScript.Shell
            $s = $w.CreateShortcut($lnk)
            $s.TargetPath = $gui
            $s.WorkingDirectory = Split-Path $gui
            $s.WindowStyle = 7
            $s.Save()
            Write-Log "Startup shortcut: $lnk" 'OK'
        }

        Write-Log "Tailscale app will start at logon: $gui" 'OK'
    }

    Write-Host ''
    Write-Host 'After reboot: Tailscale service starts, then the tray icon at sign-in.'
    Write-Host 'Log in to Tailscale once (if not already). After that it reconnects by itself.'
    Write-Host 'This script does not store Tailscale credentials.'
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    if ($exitCode -eq 0) { $exitCode = 1 }
}
finally {
    Write-Log "Exit code: $exitCode" 'INFO'
}

exit $exitCode
