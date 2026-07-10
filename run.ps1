# Quick launch (Windows) — creates the venv and installs deps on first run, then
# starts the server (which serves BOTH dashboards) and opens one in your browser.
# Usage: .\run.ps1          # opens the lab dashboard (/lab)
#        .\run.ps1 pi       # opens the Pi dashboard (/)
#        .\run.ps1 kiosk    # fullscreen Chrome/Edge kiosk on /lab, server detached
#        .\run.ps1 stop     # stop a running/detached server
#        .\run.ps1 none     # server only, no browser
param(
    [ValidateSet("lab", "pi", "kiosk", "none", "stop")]
    [string]$Open = "lab"
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

if ($Open -eq "stop") {
    $stopped = $false
    $pids = Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($procId in $pids) {
        $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -eq "python") {
            Stop-Process -Id $procId -Force
            Write-Host "[poolman] Stopped server (PID $procId)."
            $stopped = $true
        }
    }
    if (-not $stopped) { Write-Host "[poolman] No poolman server found on port 5000." }
    exit 0
}

if (-not (Test-Path "venv")) {
    Write-Host "[poolman] Creating virtual environment..."
    if (Get-Command python -ErrorAction SilentlyContinue) {
        python -m venv venv
    } else {
        py -3 -m venv venv
    }
}

$py = Join-Path $PSScriptRoot "venv\Scripts\python.exe"

& $py -c "import importlib.util, sys; sys.exit(0 if all(importlib.util.find_spec(m) for m in ('flask', 'dotenv', 'requests')) else 1)"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[poolman] Installing dependencies..."
    & $py -m pip install -r requirements.txt
}

if (-not (Test-Path ".env")) {
    Write-Host "[poolman] WARNING: no .env file found. Create one with BTC_ADDRESS=<your address>." -ForegroundColor Yellow
}

# Raw TCP readiness probe — Invoke-WebRequest can stall for seconds on Windows
# proxy auto-detection, silently eating the whole wait.
function Wait-ForServer {
    for ($i = 0; $i -lt 60; $i++) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $tcp.Connect("127.0.0.1", 5000)
            return $true
        } catch {
            Start-Sleep -Milliseconds 500
        } finally {
            $tcp.Close()
        }
    }
    return $false
}

if ($Open -eq "kiosk") {
    # Detached server + fullscreen browser: the script exits, the dashboard stays.
    $browser = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

    Start-Process -FilePath $py -ArgumentList "app.py" -WindowStyle Minimized
    if (-not (Wait-ForServer)) {
        Write-Host "[poolman] Server did not come up on port 5000." -ForegroundColor Red
        exit 1
    }
    $url = "http://localhost:5000/lab"
    if ($browser) {
        Start-Process -FilePath $browser -ArgumentList "--kiosk", $url
    } else {
        Write-Host "[poolman] Chrome/Edge not found - opening default browser instead."
        Start-Process $url
    }
    Write-Host "[poolman] Kiosk running. Server is detached - stop it with: .\run.ps1 stop"
    exit 0
}

if ($Open -ne "none") {
    $url = if ($Open -eq "lab") { "http://localhost:5000/lab" } else { "http://localhost:5000/" }
    # From a background job: wait until the port accepts connections, then open
    # the browser (same TCP-probe rationale as Wait-ForServer, job-local copy)
    Start-Job -ScriptBlock {
        param($u)
        $up = $false
        for ($i = 0; $i -lt 60; $i++) {
            $tcp = New-Object System.Net.Sockets.TcpClient
            try {
                $tcp.Connect("127.0.0.1", 5000)
                $up = $true
            } catch {
                Start-Sleep -Milliseconds 500
            } finally {
                $tcp.Close()
            }
            if ($up) { break }
        }
        if ($up) { Start-Process $u }
    } -ArgumentList $url | Out-Null
    Write-Host "[poolman] Will open $url when the server is ready."
}

Write-Host "[poolman] Pi dashboard:  http://localhost:5000"
Write-Host "[poolman] Lab dashboard: http://localhost:5000/lab"
Write-Host "[poolman] Starting server... Ctrl+C to stop."
& $py app.py
