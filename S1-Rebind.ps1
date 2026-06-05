# =====================================================================
# PARAMETERS (please insert your values)
# =====================================================================
param(
    [string]$SITE = "https://my-url.sentinelone.net",
    [string]$TOKEN = "YOUR_API_KEY_TOKEN",
    [string]$SITE_TOKEN = "YOUR_SITE_TOKEN",
    [switch]$DryRun
)
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

# 2. Find SentinelCtl.exe
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

# 3. Get UUID
function Get-UUID {
    param ($ctlPath)

    $output = & $ctlPath agent_id
    $id = $output | Where-Object { $_ -match '\S' } | Select-Object -Last 1

    if (-not $id) { throw "Failed to retrieve agent UUID." }

    return $id.Trim()
}

# 4. Get passphrase
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

    $sentinelctl = Find-SentinelCtl

    $uuid = Get-UUID -ctlPath $sentinelctl
    Write-Host "[*] Agent UUID: $uuid" -ForegroundColor Cyan

    $passphrase = Get-Passphrase -uuid $uuid -Site $SITE -Token $TOKEN

    if ([string]::IsNullOrWhiteSpace($passphrase)) {
        throw "Passphrase is empty. Aborting."
    }

    if ($DryRun) {
        Write-Host "[*] DryRun mode: no changes will be made." -ForegroundColor Yellow
        Write-Host "[*] Passphrase: $('*' * $passphrase.Length)" -ForegroundColor Yellow
        Write-Host "[*] Site Token: $('*' * $SITE_TOKEN.Length)" -ForegroundColor Yellow
    } else {
        # Step 1: Unload agent
        Write-Host "[*] Unloading agent..." -ForegroundColor Cyan
        & $sentinelctl unload -a -k $passphrase

        # Step 2: Wait for agent to unload
        Write-Host "[*] Waiting 30 seconds for agent to unload..." -ForegroundColor Cyan
        Start-Sleep -Seconds 30

        # Step 3: Bind to new site
        Write-Host "[*] Binding to new site..." -ForegroundColor Cyan
        & $sentinelctl bind $SITE_TOKEN -k $passphrase

        # Step 4: Load agent
        Write-Host "[*] Loading agent..." -ForegroundColor Cyan
        & $sentinelctl load -a

        Write-Host "[+] Script completed successfully!" -ForegroundColor Green
    }
}
catch {
    $errorMsg = $_.Exception.Message

    Write-Host "[-] FATAL ERROR: $errorMsg" -ForegroundColor Red
    try {
        Write-EventLog -LogName Application -Source "Application Error" -EventId 1000 -EntryType Error -Message "SentinelOne Rebind Failed: $errorMsg"
    } catch {
        Write-Host "[!] Failed to write to Event Log: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    [Console]::Error.WriteLine($errorMsg)
    exit 1
}

# Load agent:
& $sentinelctl load -a

# Generate logs:
& $sentinelctl log_generate
#>
