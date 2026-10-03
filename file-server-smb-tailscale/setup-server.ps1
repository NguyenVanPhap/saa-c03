#Requires -Version 5.1
<#
.SYNOPSIS
    Configure this Windows 11 PC as a read-only SMB file server reachable over Tailscale.

.DESCRIPTION
    Creates D:\SharedFiles, a local account (shareuser) with no admin rights,
    NTFS + SMB share permissions that allow Read/Open/Copy only, and a Windows
    Firewall rule that allows TCP 445 from the Tailscale CGNAT range only.

    Compatible with Windows PowerShell 5.1. Does not require PowerShell 7.

    This script is idempotent. It will not format disks, delete share data,
    disable Windows Firewall / Defender / UAC, enable SMB1, or log in to Tailscale.

.NOTES
    Run from an elevated 64-bit Windows PowerShell session:
      powershell -ExecutionPolicy Bypass -File .\setup-server.ps1

    Exit codes:
      0  Success
      1  Unexpected error
      2  Not running as Administrator
      3  Tailscale not installed / not connected
      4  Share drive (D:\) is missing
      5  Validation failed
      6  User cancelled
#>

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ConfirmPreference     = 'None'

# ---------------------------------------------------------------------------
# D. Configuration (edit these if needed; never put a password here)
# ---------------------------------------------------------------------------
$SharePath = 'D:\SharedFiles'
$ShareName = 'SharedFiles'
$ShareUser = 'shareuser'

$FirewallRuleName = 'SMB-Tailscale-SharedFiles-In'
$TailscaleCgnat   = '100.64.0.0/10'
$TailscaleCgnatV6 = 'fd7a:115c:a1e0::/48'

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

function Test-SecureStringEqual {
    param(
        [Security.SecureString]$A,
        [Security.SecureString]$B
    )
    $p1 = ConvertFrom-SecureStringPlain -Secure $A
    $p2 = ConvertFrom-SecureStringPlain -Secure $B
    try {
        return ($p1 -ceq $p2)
    }
    finally {
        $p1 = $null
        $p2 = $null
    }
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

function Get-TailscaleAdapter {
    Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match 'Tailscale' -or $_.InterfaceDescription -match 'Tailscale'
    } | Select-Object -First 1
}

function Get-TailscaleState {
    $exe = Get-TailscaleExe
    if (-not $exe) { return $null }

    $state = [pscustomobject]@{
        Exe          = $exe
        BackendState = $null
        IPv4         = $null
        Connected    = $false
        Raw          = $null
    }

    try {
        $raw = & $exe status --json 2>$null | Out-String
        if ($raw) {
            $state.Raw = $raw | ConvertFrom-Json
            $state.BackendState = [string]$state.Raw.BackendState
        }
    }
    catch {
        Write-Log "Could not parse 'tailscale status --json': $($_.Exception.Message)" 'WARN'
    }

    try {
        $ipOut = & $exe ip -4 2>$null | Out-String
        $ipv4 = ($ipOut -split '\r?\n' | Where-Object { $_ -match '^\s*100\.\d{1,3}\.\d{1,3}\.\d{1,3}\s*$' } | Select-Object -First 1)
        if ($ipv4) { $state.IPv4 = $ipv4.Trim() }
    }
    catch { }

    if (-not $state.IPv4 -and $state.Raw -and $state.Raw.Self -and $state.Raw.Self.TailscaleIPs) {
        $state.IPv4 = @($state.Raw.Self.TailscaleIPs | Where-Object { $_ -match '^100\.' } | Select-Object -First 1)
    }

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

    Write-Log "Installing Tailscale via winget (Tailscale.Tailscale)..." 'INFO'
    $wingetArgs = @(
        'install',
        '--id', 'Tailscale.Tailscale',
        '-e',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity'
    )
    & winget @wingetArgs
    $code = $LASTEXITCODE
    Write-Log "winget exit code: $code" 'INFO'

    $exe = Get-TailscaleExe
    if (-not $exe) {
        throw "winget finished but tailscale.exe was not found. Open the Tailscale installer from Start if winget queued it, then re-run this script."
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
    Write-Host '  2. Complete login in the browser.'
    Write-Host '  3. Wait until Tailscale shows Connected.'
    Write-Host 'This script does not store Tailscale credentials and will not run "tailscale login" for you.'
    Write-Host ''

    $attempt = 0
    while ($attempt -lt 3) {
        $attempt++
        $null = Read-Host 'Press Enter after Tailscale is Connected (or press Enter to re-check)'
        $state = Get-TailscaleState
        if ($state -and $state.Connected) {
            Write-Log "Tailscale connected. IPv4 = $($state.IPv4)" 'OK'
            return $state
        }

        $backend = if ($state -and $state.BackendState) { $state.BackendState } else { 'Unknown' }
        Write-Log "Tailscale is not connected yet (BackendState=$backend)." 'WARN'

        if ($attempt -lt 3) {
            $retry = Read-Host 'Retry login check? [Y/N]'
            if ($retry -notmatch '^[Yy]') { break }
        }
    }

    throw "Tailscale is installed but not authenticated/connected. Log in from the Tailscale app, then re-run this script."
}

function Test-ShareDriveReady {
    $root = [IO.Path]::GetPathRoot($SharePath)
    $letter = $root.TrimEnd('\').TrimEnd(':')
    $deviceId = "${letter}:"

    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$deviceId'" -ErrorAction SilentlyContinue
    if ($null -eq $disk) {
        $script:exitCode = 4
        throw "ERROR: Drive $deviceId does not exist. This script will NOT format, partition, initialize, or erase any disk. Attach the volume and assign it letter ${deviceId}, then re-run."
    }

    # 2 = Removable, 3 = Local disk. Reject network / CD / RAM.
    if (@(2, 3) -notcontains [int]$disk.DriveType) {
        $script:exitCode = 4
        throw "ERROR: $deviceId exists but is not a local/removable disk (DriveType=$($disk.DriveType)). This script will not use a network or CD/DVD path as the share root."
    }

    Write-Log "Drive $deviceId is present (DriveType=$($disk.DriveType)). Data will be kept." 'OK'
}

function Ensure-ShareFolder {
    if (Test-Path -LiteralPath $SharePath) {
        $item = Get-Item -LiteralPath $SharePath -Force
        if (-not $item.PSIsContainer) {
            throw "$SharePath exists but is a file, not a folder. Move/rename that file, then re-run. No data was deleted."
        }
        Write-Log "Folder already exists (keeping all files): $SharePath" 'OK'
        return
    }

    New-Item -ItemType Directory -Path $SharePath -Force | Out-Null
    Write-Log "Created folder $SharePath" 'OK'
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

function Ensure-ShareUser {
    $existing = Get-LocalUser -Name $ShareUser -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Log "Local user '$ShareUser' already exists. It will not be deleted and the password will not be reset." 'WARN'
        $use = Confirm-YesNo "Use the existing '$ShareUser' account? [Y/N]"
        if (-not $use) {
            $script:exitCode = 6
            throw "User cancelled. Existing account '$ShareUser' was left unchanged."
        }

        $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        $isAdmin = $false
        foreach ($a in $admins) {
            if ($a -like "*\$ShareUser" -or $a -eq $ShareUser) { $isAdmin = $true }
        }
        if ($isAdmin) {
            throw "Existing account '$ShareUser' is in Administrators. Refusing to use an admin account as the SMB identity. Create/use a non-admin account."
        }

        Write-Log "Using existing non-admin account '$ShareUser'." 'OK'
        return
    }

    Write-Host ''
    Write-Host "Create local user '$ShareUser' (SMB-only, not an administrator)." -ForegroundColor Cyan
    Write-Host 'Password is read securely and is never written to disk by this script.'
    Write-Host ''

    $pass1 = Read-Host "Enter password for $ShareUser" -AsSecureString
    $pass2 = Read-Host 'Confirm password' -AsSecureString
    if (-not (Test-SecureStringEqual -A $pass1 -B $pass2)) {
        throw 'Passwords do not match. Nothing was changed.'
    }

    $params = @{
        Name                     = $ShareUser
        Password                 = $pass1
        FullName                 = 'SMB Share Read-Only User'
        Description              = 'SMB read-only SharedFiles'
        AccountNeverExpires      = $true
        PasswordNeverExpires     = $true
        UserMayNotChangePassword = $true
    }
    New-LocalUser @params | Out-Null
    $pass1 = $null
    $pass2 = $null

    # Local users are in Users by default. NEVER add to Administrators.
    $inAdmins = Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*\$ShareUser" }
    if ($inAdmins) {
        throw "Refusing to continue: '$ShareUser' ended up in Administrators."
    }

    Write-Log "Created local user '$ShareUser' (not in Administrators)." 'OK'
}

function Get-WriteRightsMask {
    # Only bits that allow changing data. Do NOT include Modify or FullControl:
    # those flags contain ReadAndExecute, so -band would false-positive on a
    # correct RX ACE (Windows reports "ReadAndExecute, Synchronize").
    $names = @(
        'Write', 'Delete', 'DeleteSubdirectoriesAndFiles',
        'ChangePermissions', 'TakeOwnership',
        'CreateFiles', 'CreateDirectories', 'AppendData',
        'WriteData', 'WriteAttributes', 'WriteExtendedAttributes'
    )
    $mask = 0
    foreach ($n in $names) {
        $mask = $mask -bor [int][System.Security.AccessControl.FileSystemRights]::$n
    }
    # GenericWrite / GenericAll sometimes appear on Get-Acl even if not named.
    $mask = $mask -bor 1073741824 -bor 268435456
    return $mask
}

function Set-ShareNtfsReadOnly {
    <#
        Break inheritance on D:\SharedFiles ONLY.

        Why we do not "just add Read for shareuser":
        - Local accounts belong to BUILTIN\Users.
        - D:\ often grants Users Modify via inheritance.
        - Effective NTFS access would then be writable even if the share is Read.

        Combined access over SMB = most restrictive of (Share ACL, NTFS ACL).
        Both layers are set to Read / RX so create/edit/rename/delete/upload fail.
        Copy still works: the client reads bytes and writes them to a local disk.
    #>
    Write-Log "Setting NTFS ACL on $SharePath only (D:\ and other folders are not modified)." 'INFO'

    $acl = Get-Acl -Path $SharePath
    # Protect + do NOT copy inherited ACEs from D:\ (those often include Users=Modify).
    $acl.SetAccessRuleProtection($true, $false)

    foreach ($rule in @($acl.Access)) {
        try { $null = $acl.RemoveAccessRule($rule) } catch { }
    }

    $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $prop    = [System.Security.AccessControl.PropagationFlags]::None
    $allow   = [System.Security.AccessControl.AccessControlType]::Allow
    $full    = [System.Security.AccessControl.FileSystemRights]::FullControl
    # Read + ReadAndExecute + List folder contents. No Write / Modify / Delete / Change permissions / Take ownership.
    $rx      = [System.Security.AccessControl.FileSystemRights]'ReadAndExecute, ListDirectory, Read'

    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $shareId     = "$env:COMPUTERNAME\$ShareUser"

    $identities = @(
        @{ Id = 'NT AUTHORITY\SYSTEM';     Rights = $full; Required = $true  },
        @{ Id = 'BUILTIN\Administrators';  Rights = $full; Required = $true  },
        @{ Id = $currentUser;              Rights = $full; Required = $false },
        @{ Id = $shareId;                  Rights = $rx;   Required = $true  }
    )

    foreach ($i in $identities) {
        if ([string]::IsNullOrWhiteSpace($i.Id)) { continue }
        try {
            $ace = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $i.Id, $i.Rights, $inherit, $prop, $allow
            )
            $acl.AddAccessRule($ace) | Out-Null
        }
        catch {
            if ($i.Required) { throw }
            Write-Log "Skipped NTFS ACE for '$($i.Id)': $($_.Exception.Message)" 'WARN'
        }
    }

    Set-Acl -Path $SharePath -AclObject $acl
    Write-Log 'NTFS ACL applied on the share folder (inheritance blocked from D:\).' 'OK'

    # Children inherit from SharedFiles. /reset does not delete files.
    $children = @(Get-ChildItem -LiteralPath $SharePath -Force -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        try {
            & icacls.exe $child.FullName /reset /T /C /Q 2>$null | Out-Null
        }
        catch {
            Write-Log "Could not reset ACL on $($child.FullName): $($_.Exception.Message)" 'WARN'
        }
    }
    if ($children.Count -gt 0) {
        Write-Log "Reset NTFS inheritance on $($children.Count) existing item(s) under $SharePath (file contents unchanged)." 'OK'
    }
}

function Test-NtfsReadOnly {
    $acl = Get-Acl -Path $SharePath
    $writeMask = Get-WriteRightsMask
    $errors = New-Object System.Collections.Generic.List[string]

    $shareHits = 0
    foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -ne 'Allow') { continue }

        $id = [string]$rule.IdentityReference
        $rights = [int]$rule.FileSystemRights
        $hasWrite = (($rights -band $writeMask) -ne 0)

        $isShareUser = ($id -like "*\$ShareUser" -or $id -eq $ShareUser)
        $isUsers     = ($id -eq 'BUILTIN\Users' -or $id -like '*\Users' -or $id -eq 'Users')
        $isEveryone  = ($id -eq 'Everyone')
        $isAuth      = ($id -eq 'NT AUTHORITY\Authenticated Users' -or $id -eq 'Authenticated Users')

        if ($isShareUser) {
            $shareHits++
            if ($hasWrite) {
                [void]$errors.Add("shareuser has write-related NTFS rights ($($rule.FileSystemRights)).")
            }
        }

        if (($isUsers -or $isEveryone -or $isAuth) -and $hasWrite) {
            [void]$errors.Add("$id has write-related NTFS rights on the share folder.")
        }
    }

    if ($shareHits -eq 0) {
        [void]$errors.Add("No NTFS Allow ACE found for $ShareUser.")
    }

    return [pscustomobject]@{
        Ok     = ($errors.Count -eq 0)
        Errors = $errors
    }
}

function Ensure-SmbServer {
    $cfg = Get-SmbServerConfiguration

    if ($cfg.EnableSMB1Protocol) {
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
        Write-Log 'SMB1 was enabled; it is now disabled. SMB1 was not turned on by this script.' 'OK'
    }
    else {
        Write-Log 'SMB1 protocol is disabled.' 'OK'
    }

    if (-not $cfg.EnableSMB2Protocol) {
        Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force
        Write-Log 'Enabled SMB2/SMB3 (same stack).' 'OK'
    }
    else {
        Write-Log 'SMB2/SMB3 protocol is enabled.' 'OK'
    }

    $setSmb = Get-Command -Name Set-SmbServerConfiguration -ErrorAction SilentlyContinue
    if ($setSmb -and $setSmb.Parameters.ContainsKey('EnableInsecureGuestAuth')) {
        try {
            Set-SmbServerConfiguration -EnableInsecureGuestAuth $false -Force
        }
        catch {
            Write-Log "Could not set EnableInsecureGuestAuth: $($_.Exception.Message)" 'WARN'
        }
    }

    $svc = Get-Service -Name 'LanmanServer' -ErrorAction Stop
    if ($svc.StartType -eq 'Disabled') {
        Set-Service -Name 'LanmanServer' -StartupType Automatic
    }
    if ($svc.Status -ne 'Running') {
        Start-Service -Name 'LanmanServer'
    }
    Write-Log 'SMB server service (LanmanServer) is running.' 'OK'
}

function Set-ShareSmbReadOnly {
    $existing = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
    if ($existing) {
        if ([string]$existing.Path -ne $SharePath) {
            throw "SMB share '$ShareName' already exists but points to '$($existing.Path)', not '$SharePath'. This script will not delete that share. Remove it manually only if you intend to replace it: Remove-SmbShare -Name $ShareName"
        }
        Write-Log "SMB share '$ShareName' already exists at $SharePath. Updating configuration (no duplicate)." 'INFO'
        try {
            Set-SmbShare -Name $ShareName -CachingMode None -FolderEnumerationMode AccessBased -EncryptData $true -Force
        }
        catch {
            Write-Log "Set-SmbShare optional properties failed: $($_.Exception.Message). Share will still be permission-hardened." 'WARN'
        }
    }
    else {
        try {
            New-SmbShare -Name $ShareName -Path $SharePath -ReadAccess $ShareUser -Description 'Read-only files over Tailscale' -CachingMode None -FolderEnumerationMode AccessBased -EncryptData $true | Out-Null
        }
        catch {
            Write-Log "New-SmbShare with encryption failed ($($_.Exception.Message)). Retrying without EncryptData." 'WARN'
            New-SmbShare -Name $ShareName -Path $SharePath -ReadAccess $ShareUser -Description 'Read-only files over Tailscale' -CachingMode None | Out-Null
        }
        Write-Log "Created SMB share '$ShareName'." 'OK'
    }

    Grant-SmbShareAccess -Name $ShareName -AccountName $ShareUser -AccessRight Read -Force | Out-Null

    $access = @(Get-SmbShareAccess -Name $ShareName)
    foreach ($ace in $access) {
        $isShareUser = ($ace.AccountName -like "*\$ShareUser" -or $ace.AccountName -eq $ShareUser)
        if ($isShareUser) {
            if ($ace.AccessControlType -eq 'Allow' -and $ace.AccessRight -ne 'Read') {
                Revoke-SmbShareAccess -Name $ShareName -AccountName $ace.AccountName -Force | Out-Null
                Grant-SmbShareAccess -Name $ShareName -AccountName $ShareUser -AccessRight Read -Force | Out-Null
                Write-Log "Corrected share permission for $ShareUser to Read." 'OK'
            }
            continue
        }

        # Remove Everyone / Users / Authenticated Users / leftover Change+Full entries.
        try {
            Revoke-SmbShareAccess -Name $ShareName -AccountName $ace.AccountName -Force | Out-Null
            Write-Log "Removed share ACE $($ace.AccountName) = $($ace.AccessRight)." 'INFO'
        }
        catch {
            Write-Log "Could not revoke share ACE $($ace.AccountName): $($_.Exception.Message)" 'WARN'
        }
    }

    Grant-SmbShareAccess -Name $ShareName -AccountName $ShareUser -AccessRight Read -Force | Out-Null
    Write-Log "SMB share permission: $ShareUser = Read (no Change / Full Control)." 'OK'
}

function Test-SharePermissionRead {
    $access = @(Get-SmbShareAccess -Name $ShareName -ErrorAction SilentlyContinue)
    if ($access.Count -eq 0) { return $false }

    $userOk = $false
    $broadWrite = @('Everyone', 'BUILTIN\Users', 'NT AUTHORITY\Authenticated Users', 'Guests', 'BUILTIN\Guests')
    foreach ($ace in $access) {
        $isShareUser = ($ace.AccountName -like "*\$ShareUser" -or $ace.AccountName -eq $ShareUser)
        if ($isShareUser) {
            if ($ace.AccessControlType -eq 'Allow' -and $ace.AccessRight -eq 'Read') { $userOk = $true }
            if ($ace.AccessRight -in @('Change', 'Full')) { return $false }
            continue
        }

        $isBroad = $false
        foreach ($b in $broadWrite) {
            if ($ace.AccountName -eq $b -or $ace.AccountName -like "*\$b") { $isBroad = $true }
        }
        if ($isBroad -and $ace.AccessControlType -eq 'Allow' -and $ace.AccessRight -in @('Change', 'Full')) {
            return $false
        }
    }
    return $userOk
}

function Disable-BroadSmbFirewallRules {
    $inbound = @(Get-NetFirewallRule -Direction Inbound -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq 'True' -and $_.Action -eq 'Allow' })

    foreach ($rule in $inbound) {
        if ($rule.DisplayName -eq $FirewallRuleName -or $rule.Name -eq $FirewallRuleName) { continue }

        try { $pf = $rule | Get-NetFirewallPortFilter } catch { continue }
        if ($pf.Protocol -ne 'TCP') { continue }

        $ports = @($pf.LocalPort)
        $hits445 = $false
        foreach ($p in $ports) {
            # Only TCP/445 rules. Do not treat LocalPort=Any (Tailscale/VPN allow-all) as SMB.
            if ([string]$p -eq '445') { $hits445 = $true }
        }
        if (-not $hits445) { continue }

        try { $af = $rule | Get-NetFirewallAddressFilter } catch { continue }
        $remote = @($af.RemoteAddress)
        $isAny = ($remote.Count -eq 0)
        foreach ($r in $remote) {
            if ([string]$r -eq 'Any' -or [string]$r -eq '*') { $isAny = $true }
        }
        if (-not $isAny) { continue }

        $name = [string]$rule.Name
        $isFps = ($name -like 'FPS-SMB*' -or $name -like '*SMB-In*' -or [string]$rule.DisplayName -like '*SMB-In*')
        if ($isFps) {
            Disable-NetFirewallRule -Name $rule.Name
            Write-Log "Disabled built-in unrestricted SMB-In rule: $($rule.DisplayName) ($name)" 'OK'
        }
        else {
            Write-Log "WARN: Another inbound TCP 445 allow-from-Any rule exists: '$($rule.DisplayName)'. It was NOT disabled automatically (may be third-party). Review it in Windows Defender Firewall." 'WARN'
        }
    }
}

function Set-TailscaleSmbFirewall {
    Write-Log 'Windows Firewall will stay enabled. TCP 445 will not be opened to the Internet.' 'INFO'

    $profiles = @(Get-NetFirewallProfile)
    foreach ($p in $profiles) {
        if (-not $p.Enabled) {
            Write-Log "Firewall profile '$($p.Name)' is OFF. This script will not turn the firewall off, and it will not silently turn it on. Enable it in Windows Security." 'WARN'
        }
    }

    Disable-BroadSmbFirewallRules

    $adapter = Get-TailscaleAdapter
    $alias   = $null
    if ($adapter) { $alias = [string]$adapter.Name }

    $existing = Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($existing) {
        Remove-NetFirewallRule -Name $existing.Name -ErrorAction SilentlyContinue
        Write-Log "Replaced previous firewall rule '$FirewallRuleName' (idempotent update)." 'INFO'
    }

    # IPv4 CGNAT first: Windows often stores mixed v4/v6 as a range string that
    # failed a strict "100.64.0.0/10" validation on some Windows 11 builds.
    $attempts = @(
        @{ Remote = @($TailscaleCgnat);                     Alias = $alias },
        @{ Remote = @($TailscaleCgnat, $TailscaleCgnatV6); Alias = $alias },
        @{ Remote = @($TailscaleCgnat);                     Alias = $null  },
        @{ Remote = @($TailscaleCgnat, $TailscaleCgnatV6); Alias = $null  }
    )

    $created       = $false
    $boundToAdapter = $false
    $lastError     = $null

    foreach ($attempt in $attempts) {
        if ($attempt.Alias -and -not $alias) { continue }
        $ruleParams = @{
            DisplayName   = $FirewallRuleName
            Name          = $FirewallRuleName
            Direction     = 'Inbound'
            Action        = 'Allow'
            Protocol      = 'TCP'
            LocalPort     = 445
            RemoteAddress = $attempt.Remote
            Profile       = 'Any'
            Enabled       = 'True'
            Description   = 'Allow SMB (TCP 445) only from Tailscale CGNAT / ULA. Not from the Internet.'
        }
        if ($attempt.Alias) {
            $ruleParams['InterfaceAlias'] = $attempt.Alias
        }
        try {
            New-NetFirewallRule @ruleParams | Out-Null
            $created = $true
            $boundToAdapter = [bool]$attempt.Alias
            break
        }
        catch {
            $lastError = $_.Exception.Message
            $leftover = Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue
            if ($leftover) {
                Remove-NetFirewallRule -Name $leftover.Name -ErrorAction SilentlyContinue
            }
        }
    }

    if (-not $created) {
        throw "Could not create a scoped SMB firewall rule (TCP 445 is still not opened globally). Last error: $lastError"
    }

    if ($boundToAdapter) {
        Write-Log "Firewall: allow TCP 445 from $TailscaleCgnat on interface '$alias'." 'OK'
    }
    else {
        Write-Log "Firewall: allow TCP 445 from $TailscaleCgnat (could not bind to a Tailscale adapter name)." 'WARN'
        Write-Log 'Re-run this script after Tailscale is Connected to bind the rule to the Tailscale interface.' 'WARN'
        Write-Log 'TCP 445 is still NOT allowed from 0.0.0.0/0.' 'WARN'
    }
}

function Test-IsTailscaleRemoteAddress {
    param($Address)
    $s = ([string]$Address).Trim()
    if ([string]::IsNullOrWhiteSpace($s) -or $s -eq 'Any') { return $false }
    if ($s -eq $TailscaleCgnat) { return $true }
    if ($s -eq '100.64.0.0-100.127.255.255') { return $true }
    if ($s -match '100\.64\.0\.0') { return $true }
    if ($s -match 'fd7a:115c:a1e0') { return $true }
    return $false
}

function Test-FirewallConfigured {
    $rule = Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $rule) {
        $rule = Get-NetFirewallRule -Name $FirewallRuleName -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    if (-not $rule) { return $false }

    $enabled = [string]$rule.Enabled
    if ($enabled -ne 'True' -and $rule.Enabled -ne $true) { return $false }
    if ([string]$rule.Action -ne 'Allow') { return $false }

    $pf = $rule | Get-NetFirewallPortFilter
    if ([string]$pf.Protocol -ne 'TCP') { return $false }
    $ports = @($pf.LocalPort)
    $has445 = $false
    foreach ($p in $ports) {
        if ([string]$p -eq '445') { $has445 = $true }
    }
    if (-not $has445) { return $false }

    $af = $rule | Get-NetFirewallAddressFilter
    $remote = @($af.RemoteAddress)
    $hasCgnat = $false
    $isAny    = $false
    foreach ($r in $remote) {
        $s = [string]$r
        if ($s -eq 'Any' -or $s -eq '*') { $isAny = $true }
        if (Test-IsTailscaleRemoteAddress -Address $s) { $hasCgnat = $true }
    }

    $ifFilter = $null
    try { $ifFilter = $rule | Get-NetFirewallInterfaceFilter } catch { }
    $onTailscaleNic = $false
    if ($ifFilter -and $ifFilter.InterfaceAlias -and [string]$ifFilter.InterfaceAlias -ne 'Any') {
        $aliases = @($ifFilter.InterfaceAlias)
        foreach ($a in $aliases) {
            if ([string]$a -match 'Tailscale') { $onTailscaleNic = $true }
        }
    }

    # Pass if scoped to CGNAT, or bound to the Tailscale adapter (not Internet-wide).
    if ($hasCgnat) { return $true }
    if ($onTailscaleNic) { return $true }
    if ($isAny) { return $false }
    return $false
}

function Write-Check {
    param(
        [bool]$Ok,
        [string]$Name,
        [string]$Fix
    )
    if ($Ok) {
        Write-Host "[OK] $Name" -ForegroundColor Green
        return $true
    }
    Write-Host "[ERROR] $Name" -ForegroundColor Red
    if ($Fix) {
        Write-Host "       $Fix" -ForegroundColor Yellow
    }
    return $false
}

function Invoke-ServerValidation {
    param(
        [bool]$AdminOk,
        [bool]$Win11Ok,
        $TailscaleState
    )

    Write-Host ''
    Write-Host '========================================'
    Write-Host ' SERVER VALIDATION'
    Write-Host '========================================'

    $allOk = $true

    $allOk = (Write-Check -Ok $AdminOk -Name 'Administrator' -Fix 'Right-click PowerShell -> Run as administrator.') -and $allOk
    $allOk = (Write-Check -Ok $Win11Ok -Name 'Windows 11' -Fix 'This script targets Windows 11 (build 22000+).') -and $allOk

    $tsInstalled = [bool](Get-TailscaleExe)
    $allOk = (Write-Check -Ok $tsInstalled -Name 'Tailscale installed' -Fix 'Re-run this script so winget can install Tailscale.Tailscale.') -and $allOk

    $tsConnected = [bool]($TailscaleState -and $TailscaleState.Connected)
    $allOk = (Write-Check -Ok $tsConnected -Name 'Tailscale connected' -Fix 'Open Tailscale, log in, wait until Connected, then re-run.') -and $allOk

    $folderOk = Test-Path -LiteralPath $SharePath
    $allOk = (Write-Check -Ok $folderOk -Name 'Shared folder exists' -Fix "Create $SharePath or fix `$SharePath at the top of the script.") -and $allOk

    $svc = Get-Service -Name 'LanmanServer' -ErrorAction SilentlyContinue
    $smbRunning = ($svc -and $svc.Status -eq 'Running')
    $allOk = (Write-Check -Ok $smbRunning -Name 'SMB service running' -Fix 'Start-Service LanmanServer; Set-Service LanmanServer -StartupType Automatic') -and $allOk

    $share = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
    $shareExists = ($null -ne $share -and [string]$share.Path -eq $SharePath)
    $allOk = (Write-Check -Ok $shareExists -Name 'SMB share exists' -Fix "New-SmbShare -Name $ShareName -Path $SharePath") -and $allOk

    $shareRead = Test-SharePermissionRead
    $allOk = (Write-Check -Ok $shareRead -Name 'Share permission = Read' -Fix "Grant-SmbShareAccess -Name $ShareName -AccountName $ShareUser -AccessRight Read -Force; revoke Change/Full/Everyone.") -and $allOk

    $ntfs = Test-NtfsReadOnly
    $ntfsFix = 'Re-run this script. shareuser must be RX only; Users/Everyone must not have Write on D:\SharedFiles (inheritance from D:\ must be blocked).'
    if (-not $ntfs.Ok) { $ntfsFix = ($ntfs.Errors -join ' ') }
    $allOk = (Write-Check -Ok $ntfs.Ok -Name 'NTFS permission = Read-only' -Fix $ntfsFix) -and $allOk

    $fwOk = Test-FirewallConfigured
    $allOk = (Write-Check -Ok $fwOk -Name 'Firewall configured' -Fix "Ensure rule '$FirewallRuleName' allows TCP 445 only from $TailscaleCgnat. Do not create a rule for Any/Internet.") -and $allOk

    $cfg = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
    if ($cfg -and $cfg.EnableSMB1Protocol) {
        $allOk = (Write-Check -Ok $false -Name 'SMB1 disabled' -Fix 'Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force') -and $allOk
    }

    return $allOk
}

function Show-ReadyBanner {
    param([string]$IPv4)

    Write-Host ''
    Write-Host '========================================'
    Write-Host ' FILE SERVER READY'
    Write-Host '========================================'
    Write-Host ''
    Write-Host 'Tailscale IP:'
    Write-Host $IPv4
    Write-Host ''
    Write-Host 'SMB Share:'
    Write-Host "\\$IPv4\$ShareName"
    Write-Host ''
    Write-Host 'Username:'
    Write-Host $ShareUser
    Write-Host ''
    Write-Host 'Client connection:'
    Write-Host "\\$IPv4\$ShareName"
    Write-Host ''
    Write-Host 'Password is not displayed.'
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$exitCode = 0
$tsState  = $null
$adminOk  = $false
$win11Ok  = $false

try {
    Write-Log 'setup-server.ps1 starting (Windows 11 / PowerShell 5.1).' 'INFO'

    # A. Administrator
    $adminOk = Test-IsAdministrator
    if (-not $adminOk) {
        Write-Host 'ERROR: Please run this script as Administrator.' -ForegroundColor Red
        $exitCode = 2
        throw 'ERROR: Please run this script as Administrator.'
    }
    Write-Log 'Running as Administrator.' 'OK'

    if (-not [Environment]::Is64BitProcess) {
        Write-Log 'Please use 64-bit Windows PowerShell (System32), not SysWOW64.' 'WARN'
    }

    # B. Windows 11
    $win11Ok = Test-IsWindows11
    if (-not $win11Ok) {
        $os = Get-CimInstance Win32_OperatingSystem
        throw "This script is for Windows 11. Detected: $($os.Caption) (build $($os.BuildNumber))."
    }
    Write-Log 'Windows 11 detected.' 'OK'
    Write-Log "PowerShell $($PSVersionTable.PSVersion)" 'INFO'

    # C. Tailscale
    Install-TailscaleIfNeeded
    $tsState = Get-TailscaleState
    if (-not $tsState -or -not $tsState.Connected) {
        $tsState = Wait-TailscaleLogin
    }
    else {
        Write-Log "Tailscale already connected. IPv4 = $($tsState.IPv4)" 'OK'
    }

    # D. Folder
    Test-ShareDriveReady
    Ensure-ShareFolder

    # E. Local user
    Ensure-ShareUser

    # F. NTFS
    Set-ShareNtfsReadOnly

    # G. SMB
    Ensure-SmbServer
    Set-ShareSmbReadOnly

    # H. Firewall
    Set-TailscaleSmbFirewall

    # I / J. Banner + validation
    $valid = Invoke-ServerValidation -AdminOk $adminOk -Win11Ok $win11Ok -TailscaleState $tsState
    if (-not $valid) {
        Write-Log 'One or more validation checks failed. See [ERROR] lines above.' 'ERROR'
        $exitCode = 5
    }
    else {
        Show-ReadyBanner -IPv4 $tsState.IPv4
        Write-Log 'Server setup completed.' 'OK'
        $exitCode = 0
    }
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        Write-Log $_.InvocationInfo.PositionMessage 'ERROR'
    }
    if ($exitCode -eq 0) { $exitCode = 1 }
    if ($exitCode -eq 1 -and $_.Exception.Message -match 'Tailscale') { $exitCode = 3 }
}
finally {
    Write-Log "Exit code: $exitCode" 'INFO'
}

exit $exitCode
