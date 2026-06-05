# =====================================================================
# PARAMETERS (please insert your values)
# =====================================================================
param(
    [string]$SITE = "https://my-url.sentinelone.net",
    [string]$TOKEN = "YOUR_API_KEY_TOKEN",
    [string]$INSTALLER_VERSION = "24_1_5_277",
    [string]$CUSTOM_INSTALLER_PATH = "C:\Temp",
    [switch]$DryRun
)
# =====================================================================

# =====================================================================
# VARIABLES
# =====================================================================
$INSTALLER_NAME = "SentinelOneInstaller_windows_64bit_v$INSTALLER_VERSION.exe"
# =====================================================================


# 1. Check Administrator
function Test-IfAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw "This script must be executed as Administrator."
    }

    Write-Host "[+] Running as Administrator." -ForegroundColor Green
}

# 2. Find installer
function Find-Installer {
    param (
        [string]$FileName,
        [string]$CustomPath
    )

    $searchPaths = @($CustomPath, "C:\Temp", "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop") |
                   Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                   Select-Object -Unique

    foreach ($dir in $searchPaths) {
        $fullPath = Join-Path $dir $FileName
        if (Test-Path $fullPath -PathType Leaf) {
            Write-Host "[+] Installer found: $fullPath" -ForegroundColor Green
            return $fullPath
        }
    }

    throw "Installer $FileName not found. Checked: $($searchPaths -join ', ')"
}

# 3. Find SentinelCtl.exe
function Find-SentinelCtl {
    $basePath = "$env:ProgramFiles\SentinelOne"

    if (-not (Test-Path $basePath)) {
        throw "SentinelOne directory not found: $basePath"
    }

    $agentDir = Get-ChildItem -Path $basePath -Directory -Filter "Sentinel Agent*" |
                Where-Object { Test-Path (Join-Path $_.FullName "SentinelCtl.exe") } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1

    if (-not $agentDir) {
        throw "Sentinel Agent directory with SentinelCtl.exe not found."
    }

    return (Join-Path $agentDir.FullName "SentinelCtl.exe")
}

# 4. Get UUID
function Get-UUID {
    param ($ctlPath)

    $output = & $ctlPath agent_id
    $id = $output | Where-Object { $_ -match '\S' } | Select-Object -Last 1

    if (-not $id) { throw "Failed to retrieve agent UUID." }

    return $id.Trim()
}

# 5. Get passphrase
function Get-Passphrase {
    param (
        [string]$uuid,
        [string]$Site,
        [string]$Token
    )

    $headers = @{ "Authorization" = "ApiToken $Token" }

    $urls = @(
        "$Site/web/api/v2.1/agents/passphrases?uuid=$uuid",
        "$Site/web/api/v2.1/agents/passphrases?uuid=$uuid&isDecommissioned=True"
    )

    foreach ($url in $urls) {
        try {
            $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ContentType "application/json" -ErrorAction Stop

            if ($response.data -and $response.data.Count -gt 0) {
                $pass = $response.data[0].passphrase

                if ($pass) {
                    Write-Host "[+] Passphrase retrieved." -ForegroundColor Green
                    return $pass
                }
            }
        } catch {
            Write-Host "[!] Request failed for $url : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    throw "Couldn't retrieve passphrase for UUID: $uuid"
}

# =====================================================================
# MAIN
# =====================================================================

$sentinelctl = $null
$passphrase = $null

try {
    Test-IfAdministrator

    $installerPath = Find-Installer -FileName $INSTALLER_NAME -CustomPath $CUSTOM_INSTALLER_PATH
    $sentinelctl = Find-SentinelCtl

    $uuid = Get-UUID -ctlPath $sentinelctl
    Write-Host "[*] Agent UUID: $uuid" -ForegroundColor Cyan

    $passphrase = Get-Passphrase -uuid $uuid -Site $SITE -Token $TOKEN

    if ([string]::IsNullOrWhiteSpace($passphrase)) {
        throw "Passphrase is empty. Aborting installation."
    }

    if ($DryRun) {
        Write-Host "[*] DryRun mode: installer will NOT be executed." -ForegroundColor Yellow
        Write-Host "[*] Installer path: $installerPath" -ForegroundColor Yellow
        Write-Host "[*] Passphrase: $('*' * $passphrase.Length)" -ForegroundColor Yellow
    } else {
        Write-Host "[*] Processing..." -ForegroundColor Cyan

        $process = Start-Process -FilePath $installerPath -ArgumentList @("-c", "-k", $passphrase) -Wait -PassThru

        if ($process.ExitCode -notin @(0, 3010)) {
            throw "Process failed with exit code: $($process.ExitCode)"
        }

        if ($process.ExitCode -eq 3010) {
            Write-Host "[+] Script completed successfully! (REBOOT REQUIRED)" -ForegroundColor Yellow
        } else {
            Write-Host "[+] Script completed successfully!" -ForegroundColor Green
        }
    }
}
catch {
    $errorMsg = $_.Exception.Message

    Write-Host "[-] FATAL ERROR: $errorMsg" -ForegroundColor Red
    try {
        Write-EventLog -LogName Application -Source "Application Error" -EventId 1000 -EntryType Error -Message "SentinelOne Install Failed: $errorMsg"
    } catch {
        Write-Host "[!] Failed to write to Event Log: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    [Console]::Error.WriteLine($errorMsg)
    exit 1
}
# Generate logs:
& $sentinelctl log_generate
#>
