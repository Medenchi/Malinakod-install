# MalinaKod — установщик клиента для Windows 10/11.
#
# Запуск (открой PowerShell ОТ ИМЕНИ АДМИНИСТРАТОРА):
#   iwr -useb https://raw.githubusercontent.com/Medenchi/Malinacode-Deploy-system/main/scripts/install_client.ps1 | iex
#
# Делает:
#   1. Проверяет права администратора
#   2. Ставит Python 3 через winget (если ещё нет)
#   3. Ставит Tailscale через winget (если ещё нет) — это бесплатная mesh-сеть для безопасного SSH-доступа без открытия портов
#   4. Подключает Tailscale к твоему аккаунту (откроется браузер)
#   5. Ставит пакет malinakod через pip
#   6. Запрашивает лицензионный ключ и активирует клиента
#   7. Создаёт Scheduled Task для автозапуска при включении компьютера
#   8. Запускает клиент

$ErrorActionPreference = "Stop"

# --- Цвета и заголовок ---
function Write-Step($msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Magenta }
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "  [X] $msg" -ForegroundColor Red }

Clear-Host
Write-Host @"

  __  __       _ _              _  __         _
 |  \/  | __ _| (_)_ __   __ _| |/ /___   __| |
 | |\/| |/ _\` | | | '_ \ / _\` | ' // _ \ / _\` |
 | |  | | (_| | | | | | | (_| | . \ (_) | (_| |
 |_|  |_|\__,_|_|_|_| |_|\__,_|_|\_\___/ \__,_|

  Установщик клиента для Windows
  Сейчас этот скрипт автоматически:
    - поставит Python (если нет)
    - поставит Tailscale (бесплатная mesh-сеть для безопасного удалённого доступа)
    - поставит сам пакет malinakod
    - попросит у тебя лицензионный ключ
    - настроит автозапуск при включении компьютера

  Все вопросы — внизу. Просто следуй инструкциям.

"@ -ForegroundColor Cyan

# --- 1. Проверка прав админа ---
Write-Step "Проверяю права администратора"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
    Write-Err "Скрипт нужно запускать от администратора!"
    Write-Host ""
    Write-Host "  Что сделать:" -ForegroundColor Yellow
    Write-Host "    1. Закрой это окно PowerShell"
    Write-Host "    2. Нажми Win + X"
    Write-Host '    3. Выбери "Терминал (администратор)" или "PowerShell (администратор)"'
    Write-Host "    4. Скопируй и вставь ту же команду что присылал админ"
    Write-Host ""
    Read-Host "Нажми Enter чтобы выйти"
    exit 1
}
Write-Ok "Права администратора есть"

# --- 2. winget доступен? ---
Write-Step "Проверяю winget (менеджер пакетов Windows)"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Err "winget не найден. Это стандартный Windows-инструмент."
    Write-Host ""
    Write-Host "  Включи его так:" -ForegroundColor Yellow
    Write-Host "    1. Открой Microsoft Store"
    Write-Host '    2. Найди "App Installer" (Установщик приложений)'
    Write-Host "    3. Нажми Update / Обновить"
    Write-Host "    4. Перезапусти этот скрипт"
    Write-Host ""
    Read-Host "Нажми Enter чтобы выйти"
    exit 1
}
Write-Ok "winget найден"

# --- 3. Python ---
Write-Step "Проверяю Python"
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
$needPython = $true
if ($pythonCmd) {
    $pyVer = & python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
    if ($pyVer -and ([version]$pyVer) -ge ([version]"3.10")) {
        Write-Ok "Python $pyVer уже установлен"
        $needPython = $false
    } else {
        Write-Warn "Python $pyVer слишком старый — нужен 3.10+. Поставлю свежий."
    }
}

if ($needPython) {
    Write-Host "  Устанавливаю Python 3.12 (это займёт пару минут)..." -ForegroundColor Cyan
    winget install --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
    Write-Ok "Python установлен"
    Write-Host "  Обновляю PATH в текущей сессии..." -ForegroundColor Cyan
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Err "Python поставился, но не появился в PATH. Закрой PowerShell, открой заново от админа, и запусти скрипт ещё раз."
        Read-Host "Нажми Enter чтобы выйти"
        exit 1
    }
}

# --- 4. Tailscale ---
Write-Step "Проверяю Tailscale"
$tailscaleExe = "C:\Program Files\Tailscale\tailscale.exe"
if (-not (Test-Path $tailscaleExe)) {
    Write-Host @"
  Tailscale — это бесплатная программа, которая создаёт защищённую сеть
  между твоим компьютером и компьютером админа. Это нужно чтобы админ
  мог подключаться к твоему серверу удалённо БЕЗ открытия портов наружу
  (то есть полностью безопасно). Аккаунт бесплатный.

  Сейчас я её установлю...
"@ -ForegroundColor Cyan
    winget install --id tailscale.tailscale --silent --accept-package-agreements --accept-source-agreements
    Write-Ok "Tailscale установлен"
} else {
    Write-Ok "Tailscale уже установлен"
}

# --- 5. Tailscale login ---
Write-Step "Подключаю Tailscale"
$tsStatus = & $tailscaleExe status 2>&1
if ($tsStatus -match "Logged out" -or $tsStatus -match "NeedsLogin" -or $LASTEXITCODE -ne 0) {
    Write-Host @"
  Сейчас откроется браузер с предложением войти в Tailscale.
  Используй ТОТ ЖЕ аккаунт что и у твоего админа (он скажет какой).
  Если у тебя ещё нет аккаунта — на странице будет кнопка
  "Sign up" (зарегистрироваться через Google/Microsoft за 10 секунд).

  После того как залогинишься — закрой вкладку и вернись сюда.
"@ -ForegroundColor Cyan
    Write-Host "  Запускаю tailscale up..." -ForegroundColor Cyan
    Start-Process -FilePath $tailscaleExe -ArgumentList "up" -Wait
    Write-Ok "Tailscale подключён"
} else {
    Write-Ok "Tailscale уже подключён"
}

$tsIp = & $tailscaleExe ip -4 2>&1 | Select-Object -First 1
if ($tsIp) {
    Write-Ok "Твой Tailscale IP: $tsIp"
} else {
    Write-Warn "Не удалось получить Tailscale IP — продолжаю, но проверь позже."
}

# --- 6. malinakod ---
Write-Step "Устанавливаю пакет malinakod"
& python -m pip install --upgrade --quiet malinakod
if ($LASTEXITCODE -ne 0) {
    Write-Err "Не удалось установить malinakod. Проверь интернет и запусти скрипт ещё раз."
    Read-Host "Нажми Enter чтобы выйти"
    exit 1
}
$mlkVer = & python -m pip show malinakod 2>$null | Select-String "^Version: " | ForEach-Object { $_.ToString().Split(" ")[1] }
Write-Ok "malinakod установлен (версия $mlkVer)"

# --- 7. Активация лицензии ---
Write-Step "Активация лицензии"
$licensePath = Join-Path $env:USERPROFILE ".malinakod\license.json"
if (Test-Path $licensePath) {
    Write-Ok "Лицензия уже активирована"
} else {
    Write-Host @"
  Сейчас введи лицензионный ключ который тебе прислал админ.
  Это ОДНА длинная строка вида: MLNK-S-XXXXX-XXXXX-...

  Скопируй её из сообщения от админа и вставь сюда.
  (Чтобы вставить в PowerShell — правый клик мышкой)
"@ -ForegroundColor Cyan

    $key = ""
    while ([string]::IsNullOrWhiteSpace($key)) {
        $key = Read-Host "  Лицензионный ключ"
        $key = $key.Trim()
        if ([string]::IsNullOrWhiteSpace($key)) {
            Write-Warn "Ключ пустой, попробуй ещё раз"
        }
    }

    Write-Host "  Активирую..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path (Split-Path $licensePath) | Out-Null

    # Запоминаем уже запущенные python.exe чтобы не задеть чужие после активации.
    $existingPyPids = @(Get-Process -Name python -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })

    # Запускаем TUI с готовым ключом через stdin, ждём появления license.json, прибиваем
    # ИМЕННО спавненный нами процесс (не все python.exe — у клиента могут быть другие).
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
        # Если процесс упал сам — нет смысла ждать дольше
        if ($activationProc.HasExited) { break }
    }

    if (-not $activationProc.HasExited) {
        Stop-Process -Id $activationProc.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $tempInput -ErrorAction SilentlyContinue

    # Подчищаем дочерние/осиротевшие python.exe, которые появились ИМЕННО за время активации.
    # Берём процессы запущенные после $activationProc.StartTime и которых не было в $existingPyPids.
    $startedAt = $activationProc.StartTime
    Get-Process -Name python -ErrorAction SilentlyContinue | Where-Object {
        $existingPyPids -notcontains $_.Id -and $_.StartTime -ge $startedAt
    } | Stop-Process -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $licensePath)) {
        Write-Err "Не удалось активировать. Возможно ключ неверный."
        Write-Host "  Попробуй вручную: " -ForegroundColor Yellow -NoNewline
        Write-Host "python -m malinakod" -ForegroundColor White
        Read-Host "Нажми Enter чтобы выйти"
        exit 1
    }
    Write-Ok "Лицензия активирована: $licensePath"
}

# --- 8. Scheduled Task ---
Write-Step "Настраиваю автозапуск при включении компьютера"
$taskName = "MalinaKod"

# Удаляем старую если есть
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$pythonExe = (Get-Command python).Source
$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start `"MalinaKod`" /MIN `"$pythonExe`" -m malinakod"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "MalinaKod Client (auto-sync + heartbeat)" | Out-Null
Write-Ok "Автозапуск настроен (Scheduled Task: $taskName)"

# --- 9. Запуск ---
Write-Step "Запускаю клиента"
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 2
$task = Get-ScheduledTask -TaskName $taskName
$state = (Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult
if ((Get-Process -Name python -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match "MalinaKod" -or $_.CommandLine -match "malinakod" })) {
    Write-Ok "Клиент запущен (свернутое окно в трее)"
} else {
    Write-Warn "Не вижу запущенного процесса. Проверь ручным запуском задачи в Планировщике."
}

# --- 10. Финал ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  ГОТОВО!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Что дальше:" -ForegroundColor Cyan
Write-Host "    - Клиент работает в фоне (свернутое окно)"
Write-Host "    - При перезагрузке компьютера он автоматически стартанёт"
Write-Host "    - Твой Tailscale IP: $tsIp"
Write-Host ""
Write-Host "  Полезные команды (в обычном PowerShell):" -ForegroundColor Cyan
Write-Host "    Перезапустить:    Stop-ScheduledTask MalinaKod; Start-ScheduledTask MalinaKod"
Write-Host "    Открыть TUI:      python -m malinakod"
Write-Host "    Обновить:         python -m pip install -U malinakod"
Write-Host ""
Write-Host "  Скажи админу что установка завершена — он подключится сам." -ForegroundColor Yellow
Write-Host ""
Read-Host "Нажми Enter чтобы закрыть это окно"
