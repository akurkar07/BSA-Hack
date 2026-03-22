$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$logsDir = Join-Path $projectRoot "logs"
$runtimeDir = Join-Path $projectRoot "runtime"
$sessionFile = Join-Path $runtimeDir "enspay-session.json"
$manifestFile = Join-Path $projectRoot "tonconnect-manifest.json"

New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null

function Require-File([string]$Path, [string]$Message) {
    if (-not (Test-Path $Path)) {
        throw $Message
    }
}

function Wait-ForUrl([string]$Url, [int]$Attempts = 20, [int]$DelayMs = 500) {
    for ($i = 0; $i -lt $Attempts; $i++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing $Url
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
                return $true
            }
        } catch {}
        Start-Sleep -Milliseconds $DelayMs
    }
    return $false
}

function Get-NgrokPublicUrl([int]$Attempts = 30, [int]$DelayMs = 1000) {
    for ($i = 0; $i -lt $Attempts; $i++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:4040/api/tunnels"
            $payload = $response.Content | ConvertFrom-Json
            $httpsTunnel = $payload.tunnels | Where-Object { $_.public_url -like "https://*" } | Select-Object -First 1
            if ($httpsTunnel) {
                return $httpsTunnel.public_url
            }
        } catch {}
        Start-Sleep -Milliseconds $DelayMs
    }
    return $null
}

Require-File (Join-Path $projectRoot ".env") "Missing .env file. Add BOT_TOKEN before launching."
Require-File (Join-Path $projectRoot "main.py") "Missing main.py."
Require-File (Join-Path $projectRoot "index.html") "Missing index.html."
Require-File $manifestFile "Missing tonconnect-manifest.json."

$envFile = Get-Content (Join-Path $projectRoot ".env") -Raw
if ($envFile -notmatch "(?m)^\s*BOT_TOKEN\s*=") {
    throw "BOT_TOKEN is missing from .env."
}

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCommand) {
    throw "Python is not available on PATH."
}

$ngrokCommand = Get-Command ngrok -ErrorAction SilentlyContinue
if (-not $ngrokCommand) {
    $ngrokCommand = Get-Command ngrok.exe -ErrorAction SilentlyContinue
}
if (-not $ngrokCommand) {
    $candidatePaths = @(
        (Join-Path $HOME "ngrok.exe"),
        (Join-Path $projectRoot "ngrok.exe"),
        "C:\Users\al3xk\ngrok.exe"
    ) | Select-Object -Unique

    foreach ($candidate in $candidatePaths) {
        if (Test-Path $candidate) {
            $ngrokCommand = @{ Source = $candidate }
            break
        }
    }
}
if (-not $ngrokCommand) {
    throw "ngrok is not available on PATH. Install it or place ngrok.exe in your home folder or project folder."
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$botOutLog = Join-Path $logsDir "bot-$timestamp.out.log"
$botErrLog = Join-Path $logsDir "bot-$timestamp.err.log"
$serverOutLog = Join-Path $logsDir "server-$timestamp.out.log"
$serverErrLog = Join-Path $logsDir "server-$timestamp.err.log"
$ngrokOutLog = Join-Path $logsDir "ngrok-$timestamp.out.log"
$ngrokErrLog = Join-Path $logsDir "ngrok-$timestamp.err.log"

Write-Host "Starting Telegram bot..." -ForegroundColor Cyan
$botProcess = Start-Process -FilePath $pythonCommand.Source `
    -ArgumentList "main.py" `
    -WorkingDirectory $projectRoot `
    -RedirectStandardOutput $botOutLog `
    -RedirectStandardError $botErrLog `
    -PassThru

Write-Host "Starting Mini App static server on port 8000..." -ForegroundColor Cyan
$serverProcess = Start-Process -FilePath $pythonCommand.Source `
    -ArgumentList "-m", "http.server", "8000" `
    -WorkingDirectory $projectRoot `
    -RedirectStandardOutput $serverOutLog `
    -RedirectStandardError $serverErrLog `
    -PassThru

if (-not (Wait-ForUrl "http://127.0.0.1:8000/index.html")) {
    throw "Local web server did not come up on http://127.0.0.1:8000/index.html"
}

Write-Host "Starting ngrok tunnel..." -ForegroundColor Cyan
$ngrokProcess = Start-Process -FilePath $ngrokCommand.Source `
    -ArgumentList "http", "8000" `
    -WorkingDirectory $projectRoot `
    -RedirectStandardOutput $ngrokOutLog `
    -RedirectStandardError $ngrokErrLog `
    -PassThru

$publicUrl = Get-NgrokPublicUrl
if (-not $publicUrl) {
    throw "ngrok started but no HTTPS tunnel was detected on http://127.0.0.1:4040/api/tunnels"
}

$manifest = @{
    url = $publicUrl
    name = "ENS Pay"
    iconUrl = "https://telegram.org/img/t_logo.png"
}
$manifest | ConvertTo-Json | Set-Content $manifestFile

$miniAppUrl = "$publicUrl/index.html"
$session = @{
    started_at = (Get-Date).ToString("o")
    bot_pid = $botProcess.Id
    server_pid = $serverProcess.Id
    ngrok_pid = $ngrokProcess.Id
    local_url = "http://127.0.0.1:8000/index.html"
    public_url = $publicUrl
    mini_app_url = $miniAppUrl
    bot_out_log = $botOutLog
    bot_err_log = $botErrLog
    server_out_log = $serverOutLog
    server_err_log = $serverErrLog
    ngrok_out_log = $ngrokOutLog
    ngrok_err_log = $ngrokErrLog
}
$session | ConvertTo-Json | Set-Content $sessionFile

Write-Host ""
Write-Host "ENS Pay is running." -ForegroundColor Green
Write-Host "Bot PID: $($botProcess.Id)"
Write-Host "Server PID: $($serverProcess.Id)"
Write-Host "ngrok PID: $($ngrokProcess.Id)"
Write-Host ""
Write-Host "Local Mini App URL:"
Write-Host "  http://127.0.0.1:8000/index.html" -ForegroundColor Yellow
Write-Host ""
Write-Host "Public Mini App URL for BotFather:"
Write-Host "  $miniAppUrl" -ForegroundColor Yellow
Write-Host ""
Write-Host "BotFather setup:"
Write-Host "  /mybots -> choose your bot -> Bot Settings -> Menu Button -> Configure menu button"
Write-Host "  Button text: Open ENS Pay"
Write-Host "  URL: $miniAppUrl"
Write-Host ""
Write-Host "Logs:"
Write-Host "  $botOutLog"
Write-Host "  $botErrLog"
Write-Host "  $serverOutLog"
Write-Host "  $serverErrLog"
Write-Host "  $ngrokOutLog"
Write-Host "  $ngrokErrLog"
Write-Host ""
Write-Host "Session file:"
Write-Host "  $sessionFile"
