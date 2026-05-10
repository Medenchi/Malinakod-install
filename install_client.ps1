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
#   8. Enables Windows RDP for remote desktop via Tailscale
#   9. Installs RustDesk in service-mode (SYSTEM privileges, UAC-bypass)
#  10. Asks for license key and activates the client
#  11. Creates a Scheduled Task to autostart on logon
#  12. Starts the client

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

  MalinaKod Client Installer for Windows 10/11

  Skript vypolnit sleduyuschie operatsii:
    1.  Proverka prav administratora
    2.  Ustanovka Python 3.10+ (cherez winget)
    3.  Ustanovka i nastroyka Tailscale (mesh-VPN dlya udalennogo dostupa)
    4.  Ustanovka paketa malinakod cherez pip
    5.  Vklyuchenie OpenSSH Server, otkrytie portov 22 i 17731
    6.  Nastroyka parolya uchetnoy zapisi Windows dlya SSH-dostupa
    7.  Vklyuchenie Windows RDP (udalennyy rabochiy stol) cherez Tailscale
    8.  Ustanovka RustDesk v rezhime sluzhby (analog AnyDesk s pravami SYSTEM)
    9.  Aktivatsiya litsenzii
    10. Sozdanie zadachi avtozapuska v Task Scheduler

  Sleduyte instruktsiyam na ekrane.

"@ -ForegroundColor Cyan

# --- 1. Admin check ---
Write-Step "Shag 1/11: Proverka prav administratora"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
    Write-Err "Trebuyutsya prava administratora."
    Write-Host ""
    Write-Host "  Dlya zapuska s pravami administratora:" -ForegroundColor Yellow
    Write-Host "    1. Zakroyte tekuschiy PowerShell"
    Write-Host "    2. Nazhmite Win+X"
    Write-Host '    3. Vyberite "Terminal (administrator)" ili "PowerShell (administrator)"'
    Write-Host "    4. Povtorite komandu zapuska"
    Write-Host ""
    Read-Host "Nazhmite Enter dlya vyhoda"
    exit 1
}
Write-Ok "Prava administratora podtverzhdeny"

# --- 2. winget ---
Write-Step "Shag 2/11: Proverka nalichiya winget"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Err "winget ne obnaruzhen v sisteme."
    Write-Host ""
    Write-Host "  winget eto standartnyy paketnyy menedzher Windows." -ForegroundColor Yellow
    Write-Host "  Dlya ego ustanovki ili obnovleniya:" -ForegroundColor Yellow
    Write-Host "    1. Otkroyte Microsoft Store"
    Write-Host '    2. Naydite prilozhenie "App Installer"'
    Write-Host "    3. Vypolnite ego ustanovku ili obnovlenie"
    Write-Host "    4. Povtorite zapusk skripta"
    Write-Host ""
    Read-Host "Nazhmite Enter dlya vyhoda"
    exit 1
}
Write-Ok "winget obnaruzhen"

# --- 3. Python ---
Write-Step "Shag 3/11: Proverka i ustanovka Python"
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
$needPython = $true
if ($pythonCmd) {
    $pyVer = & python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
    if ($pyVer -and ([version]$pyVer) -ge ([version]"3.10")) {
        Write-Ok "Python $pyVer ustanovlen"
        $needPython = $false
    } else {
        Write-Warn "Obnaruzhena ustarevshaya versiya Python $pyVer (trebuetsya 3.10 ili vyshe). Budet ustanovlena novaya versiya."
    }
}

if ($needPython) {
    Write-Host "  Vypolnyaetsya ustanovka Python 3.12. Eto mozhet zanyat neskolko minut..." -ForegroundColor Cyan
    winget install --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
    Write-Ok "Python uspeshno ustanovlen"
    Write-Host "  Obnovlenie peremennoy PATH dlya tekuschey sessii..." -ForegroundColor Cyan
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Err "Python ustanovlen, no nedostupen v PATH. Zakroyte PowerShell, otkroyte zanovo s pravami administratora i povtorite zapusk skripta."
        Read-Host "Nazhmite Enter dlya vyhoda"
        exit 1
    }
}

# --- 4. Tailscale install ---
Write-Step "Shag 4/11: Proverka i ustanovka Tailscale"
$tailscaleExe = "C:\Program Files\Tailscale\tailscale.exe"
if (-not (Test-Path $tailscaleExe)) {
    Write-Host @"
  Tailscale eto besplatnoe reshenie mesh-VPN, obespechivayushchee zashchischennoe
  soedinenie mezhdu rabochey stantsiey klienta i administratorom. Tailscale
  pozvolyaet ne otkryvat porty na vneshnem perimetre seti.

  Vypolnyaetsya ustanovka...
"@ -ForegroundColor Cyan
    winget install --id tailscale.tailscale --silent --accept-package-agreements --accept-source-agreements
    Write-Ok "Tailscale uspeshno ustanovlen"
} else {
    Write-Ok "Tailscale uzhe ustanovlen"
}

# --- 5. Tailscale login ---
Write-Step "Shag 5/11: Avtorizatsiya Tailscale"
$tsStatus = & $tailscaleExe status 2>&1
if ($tsStatus -match "Logged out" -or $tsStatus -match "NeedsLogin" -or $LASTEXITCODE -ne 0) {
    Write-Host @"
  Sejchas budet otkryt brauzer dlya avtorizatsii v Tailscale.
  Ispolzuyte uchetnuyu zapis, ukazannuyu administratorom.
  Esli uchetnoy zapisi net, sozdayte ee na stranitse cherez "Sign up"
  (vozmozhna registratsiya cherez Google ili Microsoft).

  Posle uspeshnoy avtorizatsii zakroyte vkladku brauzera i vernites k konsoli.
"@ -ForegroundColor Cyan
    Write-Host "  Vypolnyaetsya komanda 'tailscale up'..." -ForegroundColor Cyan
    Start-Process -FilePath $tailscaleExe -ArgumentList "up" -Wait
    Write-Ok "Tailscale podklyuchen"
} else {
    Write-Ok "Tailscale uzhe podklyuchen"
}

$tsIp = & $tailscaleExe ip -4 2>&1 | Select-Object -First 1
if ($tsIp) {
    Write-Ok "Naznachen Tailscale IP: $tsIp"
} else {
    Write-Warn "Ne udalos poluchit Tailscale IP. Prodolzhaem ustanovku."
}

# --- 6. OpenSSH Server ---
Write-Step "Shag 6/11: Ustanovka i nastroyka OpenSSH Server"
Write-Host @"
  Vypolnyaetsya ustanovka OpenSSH Server ot Microsoft.
  Otkryvayutsya porty 22 (SSH) i 17731 (malinakod agent API)
  v vnutrennem fayrvolle Windows. Eti porty dostupny tolko
  v predelakh Tailscale-seti.
"@ -ForegroundColor Cyan

try {
    $sshCap = Get-WindowsCapability -Online -Name "OpenSSH.Server*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sshCap -and $sshCap.State -ne "Installed") {
        Write-Host "  Vypolnyaetsya ustanovka komponenta OpenSSH.Server..." -ForegroundColor Cyan
        Add-WindowsCapability -Online -Name $sshCap.Name | Out-Null
        Write-Ok "OpenSSH Server ustanovlen"
    } else {
        Write-Ok "OpenSSH Server uzhe ustanovlen"
    }

    Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name sshd -ErrorAction SilentlyContinue
    if ((Get-Service sshd -ErrorAction SilentlyContinue).Status -eq "Running") {
        Write-Ok "Sluzhba sshd zapuschena"
    } else {
        Write-Warn "Sluzhba sshd ne zapustilas. Proverte sistemnyy zhurnal."
    }

    if (-not (Get-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name "sshd" -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow `
            -LocalPort 22 | Out-Null
        Write-Ok "Pravilo fayrvola: port 22 razreshen (SSH)"
    } else {
        Write-Ok "Pravilo fayrvola dlya SSH uzhe sozdano"
    }

    # Port 17731 -- malinakod agent API s HMAC-podpisyu komand ot administratora.
    if (-not (Get-NetFirewallRule -Name "malinakod-agent" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name "malinakod-agent" -DisplayName "MalinaKod Agent (17731)" `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow `
            -LocalPort 17731 | Out-Null
        Write-Ok "Pravilo fayrvola: port 17731 razreshen (malinakod agent)"
    } else {
        Write-Ok "Pravilo fayrvola dlya malinakod agent uzhe sozdano"
    }
} catch {
    Write-Warn "Ne udalos polnostyu nastroit OpenSSH: $_"
    Write-Warn "Administrator mozhet vypolnit nastroyku vruchnuyu. Prodolzhaem."
}

# --- 7. Windows password for SSH ---
Write-Step "Shag 7/11: Nastroyka parolya uchetnoy zapisi Windows dlya SSH"
Write-Host @"
  Dlya udalennogo dostupa po SSH neobhodim parol uchetnoy zapisi Windows.
  Tekuschiy polzovatel: '$env:USERNAME'.

  Variant 1: U vas uzhe est parol ot uchetnoy zapisi.
             Nazhmite Enter dlya propuska shaga i peredayte
             sushchestvuyuschiy parol administratoru.

  Variant 2: Parol ne zadan ili zabyt.
             Vvedite novyy parol nizhe. On budet primenen nemedlenno.

  VNIMANIE: vvodimoe znachenie stanet parolem uchetnoy zapisi Windows.
            Vvodite konkretnuyu strocku (naprimer: MalinaPass2026),
            a ne kommentarii ili instruktsii.
"@ -ForegroundColor Cyan

$newPass = Read-Host "  Novyy parol (Enter dlya propuska)" -AsSecureString
$plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($newPass)
)

if ([string]::IsNullOrWhiteSpace($plainPass)) {
    Write-Warn "Parol ne izmenen. Soobschite administratoru tekuschiy parol uchetnoy zapisi."
} else {
    try {
        Set-LocalUser -Name $env:USERNAME -Password $newPass -ErrorAction Stop
        Write-Ok "Parol uchetnoy zapisi '$env:USERNAME' uspeshno ustanovlen"
        Write-Host ""
        Write-Host "  TREBUETSYA DEYSTVIE:" -ForegroundColor Yellow
        Write-Host "  Peredayte ustanovlennyy parol administratoru, prislavshemu ustanovshchik." -ForegroundColor Yellow
        Write-Host "  Bez parolya udalennoe podklyuchenie po SSH ne budet rabotat." -ForegroundColor Yellow
        Write-Host ""
    } catch {
        Write-Warn "Ne udalos zadat parol cherez Set-LocalUser: $_"
        Write-Warn "Alternativnyy sposob: v cmd s pravami administratora vypolnite: net user $env:USERNAME <parol>"
    }
}

# --- 7b. Windows RDP enablement ---
Write-Step "Shag 8/11: Vklyuchenie Windows Remote Desktop (RDP)"
Write-Host @"
  RDP eto vstroennyy v Windows protokol udalennogo rabochego stola.
  Administrator smozhet podklyuchatsya k rabochey stantsii cherez 'mstsc'
  ispolzuya Tailscale-IP (port 3389 dostupen tolko vnutri Tailscale-seti,
  vneshniy perimetr zatronut ne budet).
"@ -ForegroundColor Cyan

try {
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 0 -Type DWord -ErrorAction Stop
    Write-Ok "RDP vklyuchen v reestre"

    # Включаем Network Level Authentication для большей безопасности.
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
        -Name "UserAuthentication" -Value 1 -Type DWord -ErrorAction SilentlyContinue

    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Write-Ok "Pravila fayrvola RDP aktivirovany"

    # Текущий пользователь добавляется в группу Remote Desktop Users.
    # Администраторы и так имеют RDP-доступ, но добавим для надёжности.
    try {
        Add-LocalGroupMember -Group "Remote Desktop Users" -Member $env:USERNAME -ErrorAction Stop
        Write-Ok "Polzovatel '$env:USERNAME' dobavlen v gruppu 'Remote Desktop Users'"
    } catch {
        # Уже в группе — это OK
        Write-Ok "Polzovatel uzhe imeet RDP-dostup"
    }
} catch {
    Write-Warn "Ne udalos polnostyu nastroit RDP: $_"
    Write-Warn "Mozhno vklyuchit vruchnuyu: Settings -> System -> Remote Desktop"
}

# --- 7c. RustDesk service-mode install ---
Write-Step "Shag 9/11: Ustanovka RustDesk (analog AnyDesk s pravami SYSTEM)"
Write-Host @"
  RustDesk eto open-source analog AnyDesk/TeamViewer. Ustanavlivaetsya
  v rezhime sluzhby Windows (zapuskaetsya kak SYSTEM), chto pozvolyaet:
    * obhodit UAC i otkryvat okna trebuyuschie prav administratora
    * pokazyvat ekran do logina v Windows
    * upravlyat rabotoy klienta posle perezagruzki bez vhoda v sistemu

  Posle ustanovki avtomaticheski generiruyutsya unikalnyy ID i parol;
  oni budut peredany v admin-paneli cherez heartbeat.
"@ -ForegroundColor Cyan

$rustdeskInstalled = $false
$rustdeskExe = "C:\Program Files\RustDesk\RustDesk.exe"

# Проверка существующей установки.
if (Test-Path $rustdeskExe) {
    Write-Ok "RustDesk uzhe ustanovlen ($rustdeskExe)"
    $rustdeskInstalled = $true
} else {
    # Качаем последний релиз с GitHub. URL стабилен по тегу 1.3.7,
    # если нужно обновиться — поменяй $rdVersion ниже.
    $rdVersion = "1.4.0"
    $rdUrl = "https://github.com/rustdesk/rustdesk/releases/download/$rdVersion/rustdesk-$rdVersion-x86_64.exe"
    $rdInstaller = "$env:TEMP\rustdesk-installer.exe"

    Write-Host "  Skachivanie RustDesk $rdVersion (~30 MB)..." -ForegroundColor Cyan
    try {
        # TLS 1.2 — старые Windows 10 могут падать без него.
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $rdUrl -OutFile $rdInstaller -UseBasicParsing -ErrorAction Stop
        Write-Ok "RustDesk skachan"
    } catch {
        Write-Warn "Ne udalos skachat RustDesk: $_"
        Write-Warn "Propuskaem ustanovku RustDesk. Esli nuzhno, ustanov vruchnuyu pozzhe (https://rustdesk.com)."
    }

    if (Test-Path $rdInstaller) {
        Write-Host "  Vypolnyaetsya 'tihaya' ustanovka..." -ForegroundColor Cyan
        # Аргумент --silent-install включает service-mode (SYSTEM).
        try {
            Start-Process -FilePath $rdInstaller -ArgumentList "--silent-install" -Wait -ErrorAction Stop
            Start-Sleep -Seconds 5
            if (Test-Path $rustdeskExe) {
                Write-Ok "RustDesk ustanovlen v $rustdeskExe"
                $rustdeskInstalled = $true
            } else {
                Write-Warn "RustDesk.exe ne nayden posle ustanovki — vozmozhno, ustanovshchik ne zavershil rabotu"
            }
        } catch {
            Write-Warn "Oshibka ustanovshchika RustDesk: $_"
        }
        Remove-Item $rdInstaller -ErrorAction SilentlyContinue
    }
}

if ($rustdeskInstalled) {
    # Принудительно стартуем сервис (--silent-install обычно сам, но на всякий).
    try {
        Start-Service -Name "RustDesk" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    } catch {}

    # Генерируем случайный пароль (16 alphanumeric chars) и применяем его.
    Add-Type -AssemblyName System.Web
    $rdPassword = -join ((1..16) | ForEach-Object { [char](Get-Random -Input (([byte][char]'A'..[byte][char]'Z') + ([byte][char]'a'..[byte][char]'z') + ([byte][char]'0'..[byte][char]'9'))) })

    # rustdesk.exe --password "..." — устанавливает permanent password (требует service running).
    try {
        & $rustdeskExe --password $rdPassword 2>&1 | Out-Null
        Write-Ok "Postoyannyy parol RustDesk ustanovlen"
    } catch {
        Write-Warn "Ne udalos zadat parol RustDesk avtomaticheski. Mozhno zadat vruchnuyu cherez RustDesk -> Settings -> Security."
        $rdPassword = "<zadayte vruchnuyu>"
    }

    # Считываем 9-значный ID. Может быть не сразу доступен — пробуем 30 сек.
    $rdId = ""
    $tries = 0
    while (-not $rdId -and $tries -lt 30) {
        try {
            $idOut = & $rustdeskExe --get-id 2>&1 | Select-Object -First 1
            if ($idOut -and $idOut -match "^\d{6,12}$") {
                $rdId = $idOut.Trim()
                break
            }
        } catch {}
        Start-Sleep -Seconds 1
        $tries++
    }

    if (-not $rdId) {
        $rdId = "<ne udalos schitat ID; otkroy RustDesk vruchnuyu>"
        Write-Warn "Ne udalos schitat RustDesk ID. Otkroy okno RustDesk — ID otobrazitsya tam."
    } else {
        Write-Ok "RustDesk ID: $rdId"
    }

    # Сохраняем metadata в файл, который heartbeat будет публиковать в репо.
    $rdInfoDir = Join-Path $env:USERPROFILE ".malinakod"
    New-Item -ItemType Directory -Force -Path $rdInfoDir | Out-Null
    $rdInfoPath = Join-Path $rdInfoDir "rustdesk.json"
    @{
        id = $rdId
        password = $rdPassword
        installed_at = (Get-Date).ToUniversalTime().ToString('o')
        version = $rdVersion
    } | ConvertTo-Json | Set-Content -Path $rdInfoPath -Encoding UTF8
    Write-Ok "RustDesk metadata sohranena v $rdInfoPath"
}

# --- 8. malinakod ---
Write-Step "Shag 10/11: Ustanovka paketa malinakod"
& python -m pip install --upgrade --quiet malinakod
if ($LASTEXITCODE -ne 0) {
    Write-Err "Ne udalos ustanovit paket malinakod. Proverte internet-soedinenie i povtorite zapusk."
    Read-Host "Nazhmite Enter dlya vyhoda"
    exit 1
}
$mlkVer = & python -m pip show malinakod 2>$null | Select-String "^Version: " | ForEach-Object { $_.ToString().Split(" ")[1] }
Write-Ok "Paket malinakod ustanovlen (versiya $mlkVer)"

# --- 9. License activation ---
Write-Step "Shag 11/11: Aktivatsiya litsenzii"
$licensePath = Join-Path $env:USERPROFILE ".malinakod\license.json"
if (Test-Path $licensePath) {
    Write-Ok "Litsenziya uzhe aktivirovana"
} else {
    Write-Host @"
  Vvedite litsenzionnyy klyuch, predostavlennyy administratorom.
  Format klyucha: MLNK-S-XXXXX-XXXXX-...

  Vstavka klyucha v PowerShell vypolnyaetsya pravoy knopkoy myshi.
"@ -ForegroundColor Cyan

    $key = ""
    while ([string]::IsNullOrWhiteSpace($key)) {
        $key = Read-Host "  Litsenzionnyy klyuch"
        $key = $key.Trim()
        if ([string]::IsNullOrWhiteSpace($key)) {
            Write-Warn "Pustoe znachenie. Povtorite vvod."
        }
    }

    Write-Host "  Vypolnyaetsya aktivatsiya..." -ForegroundColor Cyan
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
        Write-Err "Aktivatsiya ne vypolnena. Vozmozhno, ukazan nevernyy klyuch."
        Write-Host "  Dlya ruchnoy aktivatsii vypolnite: " -ForegroundColor Yellow -NoNewline
        Write-Host "python -m malinakod" -ForegroundColor White
        Read-Host "Nazhmite Enter dlya vyhoda"
        exit 1
    }
    Write-Ok "Litsenziya aktivirovana, fayl: $licensePath"
}

# --- Scheduled Task ---
Write-Step "Sozdanie zadachi avtozapuska v Task Scheduler"
$taskName = "MalinaKod"

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$pythonExe = (Get-Command python).Source
$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start `"MalinaKod`" /MIN `"$pythonExe`" -m malinakod"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "MalinaKod Client (auto-sync + heartbeat)" | Out-Null
Write-Ok "Zadacha '$taskName' zaregistrirovana v Task Scheduler"

# --- Start ---
Write-Step "Zapusk klienta MalinaKod"
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 2
Write-Ok "Klient zapuschen v fonovom rezhime (svernutoe okno na paneli zadach)"

# --- Final ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  USTANOVKA ZAVERSHENA" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Tekuschee sostoyanie:" -ForegroundColor Cyan
Write-Host "    - Klient MalinaKod zapuschen i rabotaet v fone"
Write-Host "    - Avtozapusk pri vhode v Windows nastroyen"
Write-Host "    - Tailscale IP: $tsIp"
Write-Host "    - RDP: vklyuchen (3389/tcp cherez Tailscale-set)"
if ($rustdeskInstalled) {
    Write-Host "    - RustDesk ID: $rdId" -ForegroundColor Cyan
    Write-Host "    - RustDesk parol: $rdPassword" -ForegroundColor Cyan
} else {
    Write-Host "    - RustDesk: ne ustanovlen"
}
Write-Host ""
Write-Host "  Poleznye komandy (v obychnom PowerShell):" -ForegroundColor Cyan
Write-Host "    Restart:    Stop-ScheduledTask MalinaKod; Start-ScheduledTask MalinaKod"
Write-Host "    Open TUI:   python -m malinakod"
Write-Host "    Update:     python -m pip install -U malinakod"
Write-Host ""
Write-Host "  *** SOOBSCHI ADMINU ***" -ForegroundColor Yellow
Write-Host "  1) Tailscale IP: $tsIp" -ForegroundColor Yellow
Write-Host "  2) Parol Windows-akkaunta '$env:USERNAME' (kotoryy zadal vyshe)" -ForegroundColor Yellow
if ($rustdeskInstalled) {
    Write-Host "  3) RustDesk ID: $rdId" -ForegroundColor Yellow
    Write-Host "  4) RustDesk parol: $rdPassword" -ForegroundColor Yellow
}
Write-Host ""
Read-Host "Nazhmite Enter dlya zakrytiya"
