# =====================================================================
# PARAMETERS (please insert your values)
# =====================================================================
param(
    [string]$SITE = "https://my-url.sentinelone.net",
    [string]$TOKEN = "YOUR_API_KEY_TOKEN",
    [string]$PROXY_ADDRESS = "http://proxy.example.com:8080",
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
    if ($LASTEXITCODE -ne 0) {
        throw "SentinelCtl.exe agent_id failed with exit code $LASTEXITCODE."
    }

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

# 5. Run a SentinelCtl command and verify it actually succeeded
function Invoke-SentinelCtl {
    param (
        [string]$ctlPath,
        [string[]]$ArgList,
        [string]$StepDescription
    )

    & $ctlPath @ArgList
    if ($LASTEXITCODE -ne 0) {
        throw "$StepDescription failed (SentinelCtl.exe exit code $LASTEXITCODE)."
    }
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
        Write-Host "[*] Proxy address: $PROXY_ADDRESS" -ForegroundColor Yellow
        Write-Host "[*] Passphrase: $('*' * $passphrase.Length)" -ForegroundColor Yellow
    } else {
        # Step 1: Set proxy for Console communication
        Write-Host "[*] Setting proxy for Console communication..." -ForegroundColor Cyan
        Invoke-SentinelCtl -ctlPath $sentinelctl -ArgList @("config", "-p", "server.proxy", "-v", $PROXY_ADDRESS, "-k", $passphrase) -StepDescription "Setting server.proxy"

        # Step 2: Prevent fallback to direct communication
        Write-Host "[*] Enforcing proxy (no direct fallback)..." -ForegroundColor Cyan
        Invoke-SentinelCtl -ctlPath $sentinelctl -ArgList @("config", "-p", "communicatorConfig.forceProxy", "-v", "true", "-k", $passphrase) -StepDescription "Setting communicatorConfig.forceProxy"

        # Step 3: Restart the agent to apply the proxy configuration
        Write-Host "[*] Reloading agent to apply changes..." -ForegroundColor Cyan
        Invoke-SentinelCtl -ctlPath $sentinelctl -ArgList @("reload", "-a", "-k", $passphrase) -StepDescription "Reloading agent"

        Write-Host "[+] Script completed successfully!" -ForegroundColor Green
    }
}
catch {
    $errorMsg = $_.Exception.Message

    Write-Host "[-] FATAL ERROR: $errorMsg" -ForegroundColor Red
    try {
        Write-EventLog -LogName Application -Source "Application Error" -EventId 1000 -EntryType Error -Message "SentinelOne Proxy Update Failed: $errorMsg"
    } catch {
        Write-Host "[!] Failed to write to Event Log: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    [Console]::Error.WriteLine($errorMsg)
    exit 1
}
