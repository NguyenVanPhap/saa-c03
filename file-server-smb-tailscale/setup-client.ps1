#Requires -Version 5.1
<#
.SYNOPSIS
    Connect this Windows 11 PC to the read-only SMB share over Tailscale.

.DESCRIPTION
    Installs Tailscale if needed (winget), checks the server is reachable on
    TCP 445 (not just ping), maps \\<TailscaleIP>\SharedFiles to Z:, and
    verifies the share is read-only.

    Compatible with Windows PowerShell 5.1. Does not require PowerShell 7.

    This script will not hard-code or print passwords, disconnect unrelated
    network drives, disable Firewall / Defender / UAC, or log in to Tailscale.

.NOTES
    Run from an elevated 64-bit Windows PowerShell session:
      powershell -ExecutionPolicy Bypass -File .\setup-client.ps1

    Exit codes:
      0  Success
      1  Unexpected error
      2  Not running as Administrator
      3  Tailscale not installed / not connected
      5  Validation / read-only test failed
      6  Drive letter conflict or user cancelled
      7  Network / SMB reachability failed
#>

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ConfirmPreference     = 'None'

# ---------------------------------------------------------------------------
# C. Configuration
# ---------------------------------------------------------------------------
$ServerTailscaleIP = ''
$ShareName         = 'SharedFiles'
$DriveLetter       = 'Z:'
$ShareUser         = 'shareuser'

$WriteTestFileName = '__write_test__.tmp'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
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

function Test-IsWindows11 {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    $caption = [string]$os.Caption
    if ($build -ge 22000) { return $true }
    if ($caption -match 'Windows 11') { return $true }
    return $false
}

function Confirm-YesNo {
    param([string]$Prompt)
    while ($true) {
        $r = Read-Host $Prompt
        if ($r -match '^[Yy]') { return $true }
        if ($r -match '^[Nn]') { return $false }
        Write-Host 'Please answer Y or N.'
    }
}

function Test-IPv4Address {
    param([string]$Ip)
    if ([string]::IsNullOrWhiteSpace($Ip)) { return $false }
    $octets = $Ip.Trim() -split '\.'
    if ($octets.Count -ne 4) { return $false }
    foreach ($o in $octets) {
        if ($o -notmatch '^\d{1,3}$') { return $false }
        $n = [int]$o
        if ($n -lt 0 -or $n -gt 255) { return $false }
        if ($o.Length -gt 1 -and $o.StartsWith('0')) { return $false }
    }
    return $true
}

function Test-TailscaleCgnatIPv4 {
    param([string]$Ip)
    if (-not (Test-IPv4Address -Ip $Ip)) { return $false }
    $p = $Ip.Trim() -split '\.' | ForEach-Object { [int]$_ }
    return ($p[0] -eq 100 -and $p[1] -ge 64 -and $p[1] -le 127)
}

function Get-TailscaleExe {
    $cmd = Get-Command -Name tailscale -ErrorAction SilentlyContinue
    if ($null -ne $cmd -and $cmd.Source) { return [string]$cmd.Source }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Tailscale\tailscale.exe')
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function Get-TailscaleState {
    $exe = Get-TailscaleExe
    if (-not $exe) { return $null }

    $state = [pscustomobject]@{
        Exe          = $exe
        BackendState = $null
        IPv4         = $null
        Connected    = $false
    }

    try {
        $raw = & $exe status --json 2>$null | Out-String
        if ($raw) {
            $json = $raw | ConvertFrom-Json
            $state.BackendState = [string]$json.BackendState
        }
    }
    catch { }

    try {
        $ipOut = & $exe ip -4 2>$null | Out-String
        $ipv4 = ($ipOut -split '\r?\n' | Where-Object { $_ -match '^\s*100\.\d{1,3}\.\d{1,3}\.\d{1,3}\s*$' } | Select-Object -First 1)
        if ($ipv4) { $state.IPv4 = $ipv4.Trim() }
    }
    catch { }

    $state.Connected = ($state.BackendState -eq 'Running' -and $state.IPv4)
    return $state
}

function Install-TailscaleIfNeeded {
    $exe = Get-TailscaleExe
    if ($exe) {
        Write-Log "Tailscale already installed: $exe" 'OK'
        try { & $exe version | ForEach-Object { Write-Log $_ 'INFO' } } catch { }
        return
    }

    $winget = Get-Command -Name winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "Tailscale is not installed and winget was not found. Install 'App Installer' from the Microsoft Store, then re-run this script. The script will not download Tailscale from an unknown URL."
    }

    Write-Log 'Installing Tailscale via winget (Tailscale.Tailscale)...' 'INFO'
    & winget install --id Tailscale.Tailscale -e --accept-package-agreements --accept-source-agreements --disable-interactivity
    Write-Log "winget exit code: $LASTEXITCODE" 'INFO'

    $exe = Get-TailscaleExe
    if (-not $exe) {
        throw 'winget finished but tailscale.exe was not found. Finish the Tailscale install from Start, then re-run this script.'
    }

    $svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
        try { Start-Service -Name 'Tailscale' } catch {
            Write-Log "Could not start Tailscale service: $($_.Exception.Message)" 'WARN'
        }
    }
    Write-Log "Tailscale installed: $exe" 'OK'
}

function Wait-TailscaleLogin {
    Write-Host ''
    Write-Host 'Please login to Tailscale first.' -ForegroundColor Cyan
    Write-Host '  1. Open Tailscale from the system tray / Start menu.'
    Write-Host '  2. Complete login in the browser (same tailnet as the server).'
    Write-Host '  3. Wait until Tailscale shows Connected.'
    Write-Host 'This script does not store Tailscale credentials and will not run "tailscale login" for you.'
    Write-Host ''

    $attempt = 0
    while ($attempt -lt 3) {
        $attempt++
        $null = Read-Host 'Press Enter after Tailscale is Connected (or press Enter to re-check)'
        $state = Get-TailscaleState
        if ($state -and $state.Connected) {
            Write-Log "Tailscale connected. This PC IPv4 = $($state.IPv4)" 'OK'
            return $state
        }
        $backend = if ($state -and $state.BackendState) { $state.BackendState } else { 'Unknown' }
        Write-Log "Tailscale is not connected yet (BackendState=$backend)." 'WARN'
        if ($attempt -lt 3) {
            $retry = Read-Host 'Retry login check? [Y/N]'
            if ($retry -notmatch '^[Yy]') { break }
        }
    }

    throw 'Tailscale is installed but not authenticated/connected. Log in from the Tailscale app, then re-run this script.'
}

function Read-ServerIp {
    param([string]$Configured)

    $ip = [string]$Configured
    if ([string]::IsNullOrWhiteSpace($ip)) {
        $ip = Read-Host 'Enter Tailscale IP of server'
    }
    $ip = $ip.Trim()

    if (-not (Test-IPv4Address -Ip $ip)) {
        throw "Invalid IPv4 address: '$ip'. Example: 100.101.102.103"
    }

    if (-not (Test-TailscaleCgnatIPv4 -Ip $ip)) {
        Write-Log "$ip is valid IPv4 but not in Tailscale CGNAT range 100.64.0.0/10." 'WARN'
        $cont = Confirm-YesNo 'Continue with this IP anyway? [Y/N]'
        if (-not $cont) {
            throw 'User cancelled because the IP is not a Tailscale address.'
        }
    }

    return $ip
}

function Get-DriveLetterColon {
    param([string]$Value)
    $d = $Value.Trim().ToUpperInvariant()
    if ($d.Length -eq 1) { $d = "${d}:" }
    if ($d -notmatch '^[A-Z]:$') {
        throw "DriveLetter must look like Z: (got '$Value')."
    }
    return $d
}

function ConvertFrom-SecureStringPlain {
    param([Security.SecureString]$Secure)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Get-MappedPath {
    param([string]$LetterColon)
    $map = Get-CimInstance -ClassName Win32_MappedLogicalDisk -Filter "DeviceID='$LetterColon'" -ErrorAction SilentlyContinue
    if ($map -and $map.ProviderName) { return [string]$map.ProviderName }

    $logical = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$LetterColon'" -ErrorAction SilentlyContinue
    if ($logical) {
        if ([int]$logical.DriveType -eq 4 -and $logical.ProviderName) { return [string]$logical.ProviderName }
        return 'LOCAL'
    }
    return $null
}

function Normalize-Unc {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return $Path.Trim().TrimEnd('\').ToLowerInvariant()
}

function Enable-LinkedConnections {
    # Makes mapped drives visible in both elevated and Explorer sessions.
    # This does not disable UAC.
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    try {
        $current = (Get-ItemProperty -Path $key -Name 'EnableLinkedConnections' -ErrorAction SilentlyContinue).EnableLinkedConnections
        if ($current -ne 1) {
            New-ItemProperty -Path $key -Name 'EnableLinkedConnections' -PropertyType DWord -Value 1 -Force | Out-Null
            Write-Log 'Set EnableLinkedConnections=1 so Z: is visible in File Explorer (UAC remains enabled). Sign out/in if Explorer still hides Z:.' 'OK'
        }
        else {
            Write-Log 'EnableLinkedConnections is already set.' 'INFO'
        }
    }
    catch {
        Write-Log "Could not set EnableLinkedConnections: $($_.Exception.Message). If Z: is missing in Explorer, map it from a non-admin PowerShell window." 'WARN'
    }
}

function Show-ReachabilityHints {
    param(
        [bool]$TailscaleConnected,
        [bool]$TcpOk,
        [string]$ServerIp
    )

    Write-Host ''
    Write-Host 'Possible causes:' -ForegroundColor Yellow
    if (-not $TailscaleConnected) {
        Write-Host '- Tailscale is not connected'
    }
    else {
        Write-Host '- Tailscale is not connected  (checked: connected on this PC)'
    }
    Write-Host '- Server is offline'
    Write-Host '- Wrong Tailscale IP'
    Write-Host '- Windows Firewall'
    Write-Host '- SMB service is not running'
    Write-Host '- SMB share does not exist'
    Write-Host ''
    Write-Host 'On the SERVER, confirm:'
    Write-Host "  tailscale ip -4          (should be $ServerIp)"
    Write-Host '  Get-Service LanmanServer'
    Write-Host '  Get-SmbShare -Name SharedFiles'
    Write-Host '  setup-server.ps1 validation checklist'
}

function Test-ServerNetwork {
    param(
        [string]$ServerIp,
        [bool]$TailscaleConnected
    )

    Write-Log 'Network test: Tailscale connected -> server reachable -> TCP 445 -> SMB share' 'INFO'

    if (-not $TailscaleConnected) {
        Write-Log 'FAIL: Tailscale is not connected on this client.' 'ERROR'
        Show-ReachabilityHints -TailscaleConnected $false -TcpOk $false -ServerIp $ServerIp
        return $false
    }
    Write-Log 'Tailscale connected on this PC.' 'OK'

    Write-Log "Test-NetConnection $ServerIp -Port 445 (ICMP/ping is not used as the pass/fail signal)." 'INFO'
    $tnc = $null
    try {
        $tnc = Test-NetConnection -ComputerName $ServerIp -Port 445 -WarningAction SilentlyContinue
    }
    catch {
        Write-Log "Test-NetConnection failed: $($_.Exception.Message)" 'ERROR'
        Show-ReachabilityHints -TailscaleConnected $true -TcpOk $false -ServerIp $ServerIp
        return $false
    }

    if ($tnc.PingSucceeded) {
        Write-Log 'ICMP echo succeeded (informational only).' 'INFO'
    }
    else {
        Write-Log 'ICMP echo failed or was filtered. That is OK; SMB uses TCP 445, not ping.' 'INFO'
    }

    if (-not $tnc.TcpTestSucceeded) {
        Write-Log "FAIL: TCP 445 is not reachable on $ServerIp." 'ERROR'
        Show-ReachabilityHints -TailscaleConnected $true -TcpOk $false -ServerIp $ServerIp
        return $false
    }

    Write-Log "TCP 445 reachable on $ServerIp." 'OK'
    return $true
}

function Save-CredentialIfRequested {
    param(
        [string]$Target,
        [string]$UserName,
        [string]$Password
    )

    $save = Confirm-YesNo 'Save credentials in Windows Credential Manager? [Y/N]'
    if (-not $save) { return $false }

    $p = Start-Process -FilePath 'cmdkey.exe' -ArgumentList @("/add:$Target", "/user:$UserName", "/pass:$Password") -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -eq 0) {
        Write-Log "Saved credential for $Target in Windows Credential Manager." 'OK'
        return $true
    }

    Write-Log "cmdkey failed (exit $($p.ExitCode)). Mapping will still use the password for this session." 'WARN'
    return $false
}

function Connect-ShareDrive {
    param(
        [string]$ServerIp,
        [string]$Share,
        [string]$LetterColon,
        [string]$User
    )

    $unc = "\\$ServerIp\$Share"
    $existing = Get-MappedPath -LetterColon $LetterColon

    if ($existing) {
        $want = Normalize-Unc -Path $unc
        $have = Normalize-Unc -Path $existing
        if ($have -eq $want) {
            Write-Log "$LetterColon is already mapped to $unc. Reusing it (other drives were not changed)." 'OK'
            return $unc
        }
        if ($existing -eq 'LOCAL') {
            throw "$LetterColon is a local disk. This script will not overwrite it. Change `$DriveLetter at the top of the script."
        }
        throw "$LetterColon is already mapped to '$existing', not '$unc'. This script will not disconnect it. Choose another `$DriveLetter or disconnect it yourself: net use $LetterColon /delete"
    }

    Write-Log "Windows will prompt for the '$User' password. It is not stored in this script." 'INFO'
    $cred = Get-Credential -UserName $User -Message "SMB login for $unc (user $User). If this fails, try SERVERNAME\$User."
    if ($null -eq $cred) {
        throw 'Credential prompt was cancelled.'
    }

    $plain = ConvertFrom-SecureStringPlain -Secure $cred.Password
    $userName = $cred.UserName
    $mapped = $false

    try {
        Save-CredentialIfRequested -Target $ServerIp -UserName $userName -Password $plain | Out-Null

        $p = Start-Process -FilePath 'net.exe' -ArgumentList @(
            'use', $LetterColon, $unc, "/user:$userName", $plain, '/persistent:yes'
        ) -Wait -PassThru -NoNewWindow

        if ($p.ExitCode -ne 0) {
            throw "net use failed with exit code $($p.ExitCode). Wrong password, wrong username (try COMPUTERNAME\$User), or the share name does not exist."
        }
        $mapped = $true
    }
    finally {
        $plain = $null
    }

    if (-not $mapped) {
        throw "Failed to map $unc to $LetterColon."
    }

    if (-not (Test-Path -LiteralPath $LetterColon)) {
        throw "net use reported success but $LetterColon is not accessible yet. Sign out/in if UAC is hiding the mapped drive, then re-run."
    }

    Write-Log "Mapped $unc -> $LetterColon" 'OK'
    return $unc
}

function Test-ReadOnlyShare {
    param([string]$LetterColon)

    $root = "$LetterColon\"
    Write-Host ''
    Write-Host 'Verifying READ ONLY access...' -ForegroundColor Cyan

    # Test 1: read directory. Never modify real files.
    try {
        $null = Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop
        Write-Host 'Test 1 (read directory): PASS' -ForegroundColor Green
    }
    catch {
        Write-Host 'Test 1 (read directory): FAIL' -ForegroundColor Red
        throw "Could not list $root : $($_.Exception.Message)"
    }

    # Optional copy check using a small existing file, to a local temp path only.
    $sample = Get-ChildItem -LiteralPath $root -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -lt 10MB -and $_.Name -ne $WriteTestFileName } |
        Select-Object -First 1
    if ($sample) {
        $copyDest = Join-Path $env:TEMP '__smb_client_copy_test__.tmp'
        try {
            Copy-Item -LiteralPath $sample.FullName -Destination $copyDest -Force
            if (Test-Path -LiteralPath $copyDest) {
                Write-Log "Copy-to-local succeeded for sample file '$($sample.Name)'." 'OK'
            }
        }
        catch {
            Write-Log "Copy-to-local failed: $($_.Exception.Message)" 'WARN'
        }
        finally {
            if (Test-Path -LiteralPath $copyDest) {
                Remove-Item -LiteralPath $copyDest -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        Write-Log 'Share has no small file to sample-copy. Directory listing still proves Read.' 'INFO'
    }

    # Test 2: write probe. Create ONLY __write_test__.tmp. Never touch real files.
    $probe = Join-Path $root $WriteTestFileName
    if (Test-Path -LiteralPath $probe) {
        Write-Log 'Leftover __write_test__.tmp found; attempting to remove it (test file only).' 'WARN'
        try { Remove-Item -LiteralPath $probe -Force -ErrorAction Stop } catch { }
    }

    $created = $false
    $denied  = $false
    try {
        [IO.File]::WriteAllText($probe, 'write-test')
        $created = Test-Path -LiteralPath $probe
    }
    catch {
        $denied = $true
        Write-Log "Write probe result: $($_.Exception.Message)" 'INFO'
    }

    if ($created) {
        try { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue } catch { }
        Write-Host 'Test 2 (write blocked): FAIL' -ForegroundColor Red
        Write-Host ''
        Write-Host 'SECURITY ERROR:' -ForegroundColor Red
        Write-Host 'SMB share is writable.' -ForegroundColor Red
        Write-Host 'Re-run setup-server.ps1 on the server. Share permission and NTFS must both be Read-only for shareuser.' -ForegroundColor Yellow
        return $false
    }

    if ($denied -or -not $created) {
        Write-Host 'Test 2 (write blocked / Access Denied): PASS' -ForegroundColor Green
        return $true
    }

    Write-Host 'Test 2 (write blocked): FAIL' -ForegroundColor Red
    return $false
}

function Show-ClientBanner {
    param(
        [string]$ServerIp,
        [string]$Unc,
        [string]$LetterColon
    )

    Write-Host ''
    Write-Host '========================================'
    Write-Host ' CLIENT SETUP SUCCESS'
    Write-Host '========================================'
    Write-Host ''
    Write-Host 'Server:'
    Write-Host $ServerIp
    Write-Host ''
    Write-Host 'Network path:'
    Write-Host $Unc
    Write-Host ''
    Write-Host 'Mapped drive:'
    Write-Host $LetterColon
    Write-Host ''
    Write-Host 'Permissions:'
    Write-Host 'READ ONLY'
    Write-Host ''
    Write-Host 'Read files:       YES'
    Write-Host 'Copy files:       YES'
    Write-Host 'Create files:     NO'
    Write-Host 'Edit files:       NO'
    Write-Host 'Rename files:     NO'
    Write-Host 'Delete files:     NO'
    Write-Host 'Upload files:     NO'
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$exitCode = 0

try {
    Write-Log 'setup-client.ps1 starting (Windows 11 / PowerShell 5.1).' 'INFO'

    # A. Administrator
    if (-not (Test-IsAdministrator)) {
        Write-Host 'ERROR: Please run this script as Administrator.' -ForegroundColor Red
        $exitCode = 2
        throw 'ERROR: Please run this script as Administrator.'
    }
    Write-Log 'Running as Administrator.' 'OK'

    if (-not (Test-IsWindows11)) {
        $os = Get-CimInstance Win32_OperatingSystem
        Write-Log "This script targets Windows 11. Detected: $($os.Caption) (build $($os.BuildNumber))." 'WARN'
    }
    else {
        Write-Log 'Windows 11 detected.' 'OK'
    }

    # B. Tailscale
    Install-TailscaleIfNeeded
    $tsState = Get-TailscaleState
    if (-not $tsState -or -not $tsState.Connected) {
        $tsState = Wait-TailscaleLogin
    }
    else {
        Write-Log "Tailscale already connected. This PC IPv4 = $($tsState.IPv4)" 'OK'
    }

    Enable-LinkedConnections

    $serverIp     = Read-ServerIp -Configured $ServerTailscaleIP
    $letterColon  = Get-DriveLetterColon -Value $DriveLetter
    $uncExpected  = "\\$serverIp\$ShareName"

    # D. Network test
    $netOk = Test-ServerNetwork -ServerIp $serverIp -TailscaleConnected ([bool]$tsState.Connected)
    if (-not $netOk) {
        $exitCode = 7
        throw "Cannot reach TCP 445 on $serverIp."
    }

    # E / F. Map + authenticate
    $unc = Connect-ShareDrive -ServerIp $serverIp -Share $ShareName -LetterColon $letterColon -User $ShareUser

    # G. Verify read-only
    $ro = Test-ReadOnlyShare -LetterColon $letterColon
    if (-not $ro) {
        $exitCode = 5
        throw 'Read-only verification failed.'
    }

    # H. Result
    Show-ClientBanner -ServerIp $serverIp -Unc $uncExpected -LetterColon $letterColon
    Write-Log 'Client setup completed.' 'OK'
    $exitCode = 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        Write-Log $_.InvocationInfo.PositionMessage 'ERROR'
    }
    if ($exitCode -eq 0) { $exitCode = 1 }
    if ($exitCode -eq 1 -and $_.Exception.Message -match 'Tailscale') { $exitCode = 3 }
    if ($exitCode -eq 1 -and $_.Exception.Message -match 'already mapped|local disk|DriveLetter') { $exitCode = 6 }
}
finally {
    Write-Log "Exit code: $exitCode" 'INFO'
}

exit $exitCode
