# MalinaKod -- installer for Windows 10/11 clients.
#
# Run (open PowerShell AS ADMINISTRATOR first):
#   iwr -useb https://raw.githubusercontent.com/Medenchi/Malinakod-install/main/install_client.ps1 | iex
#
# Vsya nadpisi sdelany na latinitse chtoby ne bylo problem s kodirovkoy
# v staroy Windows PowerShell 5.1 (kotoraya ploho rabotaet s UTF-8).
#
# What it does:
#   1. Checks admin rights
#   2. Installs Python 3 via winget (if needed)
#   3. Installs Tailscale via winget (if needed)
#   4. Connects Tailscale to your account (browser opens)
#   5. Installs the malinakod package via pip
#   6. Installs OpenSSH Server + opens port 22
#   7. Asks you to set a Windows password for SSH (or keep existing)
#   8. Asks for license key and activates the client
#   9. Creates a Scheduled Task to autostart on logon
#  10. Starts the client

$ErrorActionPreference = "Stop"

# Try to make console UTF-8 (best-effort, may not fully work on PS5.1 + iwr | iex
# pipeline, which is why all script text below is plain ASCII anyway).
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    chcp 65001 > $null 2>&1
} catch {}

function Write-Step($msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Magenta }
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "  [X] $msg" -ForegroundColor Red }

Clear-Host
Write-Host @"

  __  __       _ _              _  __         _
 |  \/  | __ _| (_)_ __   __ _| |/ /___   __| |
 | |\/| |/ _\` | | | '_ \ / _\` | ' // _ \ / _\` |
 | |  | | (_| | | | | | | (_| | . \ (_) | (_| |
 |_|  |_|\__,_|_|_|_| |_|\__,_|_|\_\___/ \__,_|

  MalinaKod -- Client Installer for Windows
  Etot skript avtomaticheski:
    - postavit Python (esli net)
    - postavit Tailscale (besplatnaya mesh-set dlya bezopasnogo dostupa)
    - postavit paket malinakod
    - vklyuchit OpenSSH Server i otkroet port 22
    - poprosit zadat parol dlya tvoego Windows-akkaunta (dlya SSH)
    - poprosit litsenzionnyy klyuch
    - nastroit avtozapusk

  Prosto sleduy instruktsiyam nizhe.

"@ -ForegroundColor Cyan

# --- 1. Admin check ---
Write-Step "Step 1/9: Checking admin rights"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
    Write-Err "Skript nuzhno zapuskat OT IMENI ADMINISTRATORA!"
    Write-Host ""
    Write-Host "  Chto sdelat:" -ForegroundColor Yellow
    Write-Host "    1. Zakroy etot PowerShell"
    Write-Host "    2. Nazhmi Win + X"
    Write-Host '    3. Vyberi "Terminal (administrator)" ili "PowerShell (administrator)"'
    Write-Host "    4. Vstav tu zhe komandu chto prislal admin"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Ok "Admin rights OK"

# --- 2. winget ---
Write-Step "Step 2/9: Checking winget (Windows package manager)"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Err "winget ne nayden. Eto standartnyy Windows-instrument."
    Write-Host ""
    Write-Host "  Vklyuchi ego tak:" -ForegroundColor Yellow
    Write-Host "    1. Otkroy Microsoft Store"
    Write-Host '    2. Naydi "App Installer" (Ustanovshchik prilozheniy)'
    Write-Host "    3. Nazhmi Update / Obnovit"
    Write-Host "    4. Perezapusti etot skript"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Ok "winget found"

# --- 3. Python ---
Write-Step "Step 3/9: Checking Python"
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
$needPython = $true
if ($pythonCmd) {
    $pyVer = & python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
    if ($pyVer -and ([version]$pyVer) -ge ([version]"3.10")) {
        Write-Ok "Python $pyVer already installed"
        $needPython = $false
    } else {
        Write-Warn "Python $pyVer too old (need 3.10+). Installing fresh one."
    }
}

if ($needPython) {
    Write-Host "  Installing Python 3.12 (takes a couple of minutes)..." -ForegroundColor Cyan
    winget install --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
    Write-Ok "Python installed"
    Write-Host "  Refreshing PATH in current session..." -ForegroundColor Cyan
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Err "Python installed but not in PATH. Close PowerShell, open as admin again, and rerun the script."
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# --- 4. Tailscale install ---
Write-Step "Step 4/9: Checking Tailscale"
$tailscaleExe = "C:\Program Files\Tailscale\tailscale.exe"
if (-not (Test-Path $tailscaleExe)) {
    Write-Host @"
  Tailscale -- besplatnaya programma kotoraya sozdaet zashchischennuyu set
  mezhdu tvoim kompyuterom i kompyuterom admina. Nuzhna chtoby admin mog
  podklyuchatsya k tebe BEZ otkrytiya portov v internet (polnostyu bezopasno).
  Akkaunt besplatnyy.

  Sejchas ya ee ustanovlyu...
"@ -ForegroundColor Cyan
    winget install --id tailscale.tailscale --silent --accept-package-agreements --accept-source-agreements
    Write-Ok "Tailscale installed"
} else {
    Write-Ok "Tailscale already installed"
}

# --- 5. Tailscale login ---
Write-Step "Step 5/9: Connecting Tailscale"
$tsStatus = & $tailscaleExe status 2>&1
if ($tsStatus -match "Logged out" -or $tsStatus -match "NeedsLogin" -or $LASTEXITCODE -ne 0) {
    Write-Host @"
  Sejchas otkroetsya brauzer s predlozheniem voyti v Tailscale.
  Ispolzuy TOT ZHE akkaunt chto i u tvoego admina (on skazhet kakoy).
  Esli akkaunta net -- na stranitse budet knopka "Sign up"
  (zaregistrirovatsya cherez Google/Microsoft, 10 sekund).

  Posle togo kak zaloginishsya -- zakroy vkladku i vernis syuda.
"@ -ForegroundColor Cyan
    Write-Host "  Running tailscale up..." -ForegroundColor Cyan
    Start-Process -FilePath $tailscaleExe -ArgumentList "up" -Wait
    Write-Ok "Tailscale connected"
} else {
    Write-Ok "Tailscale already connected"
}

$tsIp = & $tailscaleExe ip -4 2>&1 | Select-Object -First 1
if ($tsIp) {
    Write-Ok "Your Tailscale IP: $tsIp"
} else {
    Write-Warn "Could not get Tailscale IP -- continuing, check later."
}

# --- 6. OpenSSH Server ---
Write-Step "Step 6/9: Setting up OpenSSH Server"
Write-Host @"
  V otlichie ot Linux, Windows ne imeet vstroennogo SSH-servera u Tailscale.
  Stavlyu standartnyy OpenSSH Server ot Microsoft i otkryvayu port 22 dlya
  Tailscale-seti (nikakih portov v internet).
"@ -ForegroundColor Cyan

try {
    $sshCap = Get-WindowsCapability -Online -Name "OpenSSH.Server*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sshCap -and $sshCap.State -ne "Installed") {
        Write-Host "  Installing OpenSSH.Server..." -ForegroundColor Cyan
        Add-WindowsCapability -Online -Name $sshCap.Name | Out-Null
        Write-Ok "OpenSSH Server installed"
    } else {
        Write-Ok "OpenSSH Server already installed"
    }

    Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name sshd -ErrorAction SilentlyContinue
    if ((Get-Service sshd -ErrorAction SilentlyContinue).Status -eq "Running") {
        Write-Ok "sshd service running"
    } else {
        Write-Warn "sshd did not start -- check logs"
    }

    if (-not (Get-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name "sshd" -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow `
            -LocalPort 22 | Out-Null
        Write-Ok "Firewall: port 22 allowed"
    } else {
        Write-Ok "Firewall: rule already exists"
    }
} catch {
    Write-Warn "Could not fully configure OpenSSH: $_"
    Write-Warn "Admin can configure manually -- continuing."
}

# --- 7. Windows password for SSH ---
Write-Step "Step 7/9: Setting Windows password for SSH access"
Write-Host @"
  Sejchas pridumay parol pod kotorym admin budet zahodit k tebe po SSH.
  Eto parol tvoego Windows-akkaunta '$env:USERNAME' (tot zhe chto
  ispolzuetsya dlya vhoda v Windows).

  Esli u tebya UZHE EST svoy parol i ty ego pomnish -- nazhmi Enter
  chtoby propustit etot shag, i soobschi adminu svoy sushchestvuyuschiy parol.

  Esli parolya ne bylo ili ne pomnish -- vvedi novyy nizhe, on srazu primenitsya.

  VAZHNO: parol nuzhno vvodit OBYCHNYMI BUKVAMI, ne kommentariyami!
  Naprimer: MalinaPass2026
"@ -ForegroundColor Cyan

$newPass = Read-Host "  New password (or Enter to skip)" -AsSecureString
$plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($newPass)
)

if ([string]::IsNullOrWhiteSpace($plainPass)) {
    Write-Warn "Password not changed. Tell admin your existing Windows password."
} else {
    try {
        Set-LocalUser -Name $env:USERNAME -Password $newPass -ErrorAction Stop
        Write-Ok "Password set for account '$env:USERNAME'"
        Write-Host ""
        Write-Host "  *** VAZHNO ***" -ForegroundColor Yellow
        Write-Host "  Soobschi etot parol ADMINU (tomu kto prislal ustanovshchik)." -ForegroundColor Yellow
        Write-Host "  Bez nego on ne smozhet podklyuchitsya po SSH." -ForegroundColor Yellow
        Write-Host ""
    } catch {
        Write-Warn "Could not set password via Set-LocalUser: $_"
        Write-Warn "Backup: run in admin cmd: net user $env:USERNAME <password>"
    }
}

# --- 8. malinakod ---
Write-Step "Step 8/9: Installing malinakod package"
& python -m pip install --upgrade --quiet malinakod
if ($LASTEXITCODE -ne 0) {
    Write-Err "Could not install malinakod. Check internet and retry."
    Read-Host "Press Enter to exit"
    exit 1
}
$mlkVer = & python -m pip show malinakod 2>$null | Select-String "^Version: " | ForEach-Object { $_.ToString().Split(" ")[1] }
Write-Ok "malinakod installed (version $mlkVer)"

# --- 9. License activation ---
Write-Step "Step 9/9: License activation"
$licensePath = Join-Path $env:USERPROFILE ".malinakod\license.json"
if (Test-Path $licensePath) {
    Write-Ok "License already activated"
} else {
    Write-Host @"
  Sejchas vvedi litsenzionnyy klyuch kotoryy prislal admin.
  Eto ODNA dlinnaya stroka vida: MLNK-S-XXXXX-XXXXX-...

  Skopiruy iz soobscheniya admina i vstav syuda.
  (Chtoby vstavit v PowerShell -- KLIK PRAVOY KNOPKOY MYSHI)
"@ -ForegroundColor Cyan

    $key = ""
    while ([string]::IsNullOrWhiteSpace($key)) {
        $key = Read-Host "  License key"
        $key = $key.Trim()
        if ([string]::IsNullOrWhiteSpace($key)) {
            Write-Warn "Empty key, try again"
        }
    }

    Write-Host "  Activating..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path (Split-Path $licensePath) | Out-Null

    $existingPyPids = @(Get-Process -Name python -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })

    $tempInput = New-TemporaryFile
    Set-Content -Path $tempInput -Value $key -NoNewline
    $pyExe = (Get-Command python).Source
    $activationProc = Start-Process -FilePath $pyExe -ArgumentList "-m","malinakod" `
        -RedirectStandardInput $tempInput `
        -RedirectStandardOutput "$env:TEMP\malinakod-activate.log" `
        -RedirectStandardError "$env:TEMP\malinakod-activate.err" `
        -WindowStyle Hidden -PassThru

    $waited = 0
    while ($waited -lt 30 -and -not (Test-Path $licensePath)) {
        Start-Sleep -Seconds 1
        $waited++
        if ($activationProc.HasExited) { break }
    }

    if (-not $activationProc.HasExited) {
        Stop-Process -Id $activationProc.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $tempInput -ErrorAction SilentlyContinue

    $startedAt = $activationProc.StartTime
    Get-Process -Name python -ErrorAction SilentlyContinue | Where-Object {
        $existingPyPids -notcontains $_.Id -and $_.StartTime -ge $startedAt
    } | Stop-Process -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $licensePath)) {
        Write-Err "Activation failed. Maybe key is wrong."
        Write-Host "  Try manually: " -ForegroundColor Yellow -NoNewline
        Write-Host "python -m malinakod" -ForegroundColor White
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Ok "License activated: $licensePath"
}

# --- Scheduled Task ---
Write-Step "Setting up autostart (Scheduled Task)"
$taskName = "MalinaKod"

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$pythonExe = (Get-Command python).Source
$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start `"MalinaKod`" /MIN `"$pythonExe`" -m malinakod"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "MalinaKod Client (auto-sync + heartbeat)" | Out-Null
Write-Ok "Scheduled Task '$taskName' created"

# --- Start ---
Write-Step "Starting client"
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 2
Write-Ok "Client started (look for minimized window in taskbar)"

# --- Final ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  GOTOVO! / DONE!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Chto dalshe:" -ForegroundColor Cyan
Write-Host "    - Klient rabotaet v fone (svernutoe okno)"
Write-Host "    - Pri perezagruzke kompyutera on stantet sam"
Write-Host "    - Tvoy Tailscale IP: $tsIp"
Write-Host ""
Write-Host "  Poleznye komandy (v obychnom PowerShell):" -ForegroundColor Cyan
Write-Host "    Restart:    Stop-ScheduledTask MalinaKod; Start-ScheduledTask MalinaKod"
Write-Host "    Open TUI:   python -m malinakod"
Write-Host "    Update:     python -m pip install -U malinakod"
Write-Host ""
Write-Host "  *** SOOBSCHI ADMINU ***" -ForegroundColor Yellow
Write-Host "  1) Tvoy Tailscale IP: $tsIp" -ForegroundColor Yellow
Write-Host "  2) Parol Windows-akkaunta '$env:USERNAME' (kotoryy zadal vyshe)" -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter to close"
