#!/usr/bin/env bash
# MalinaKod — установщик клиента в одну команду.
#
# Использование:
#   curl -fsSL https://raw.githubusercontent.com/Medenchi/Malinacode-Deploy-system/main/scripts/install_client.sh | bash
#
# Или с готовым ключом:
#   curl -fsSL https://raw.githubusercontent.com/Medenchi/Malinacode-Deploy-system/main/scripts/install_client.sh | MALINAKOD_KEY="MLNK-S-..." bash
#
# Делает:
#   1. Ставит Tailscale (mesh-сеть для SSH без открытых портов)
#   2. Ставит Python 3 + pip + tmux
#   3. Ставит пакет `malinakod` через pip
#   4. Запрашивает лицензионный ключ
#   5. Активирует клиент (запускает TUI один раз чтобы сохранить лицензию)
#   6. Создаёт systemd-юнит для автозапуска при ребуте
#   7. Запускает сервис

set -euo pipefail

# --- цвета ---
if [ -t 1 ]; then
    BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
    BLUE=$'\033[34m'; PINK=$'\033[35m'; RESET=$'\033[0m'
else
    BOLD=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; PINK=""; RESET=""
fi

step() { echo; echo "${BOLD}${PINK}➜ $1${RESET}"; }
ok() { echo "  ${GREEN}✓${RESET} $1"; }
warn() { echo "  ${YELLOW}!${RESET} $1"; }
fail() { echo "  ${RED}✗${RESET} $1" >&2; exit 1; }

# --- root check ---
if [ "$(id -u)" -eq 0 ]; then
    fail "Не запускай скрипт от root. Запусти от обычного юзера, sudo попросится автоматически."
fi

if ! sudo -n true 2>/dev/null; then
    echo "${YELLOW}Скрипту понадобится sudo для установки пакетов.${RESET}"
    sudo -v || fail "Нужен sudo-доступ"
fi

# --- определяем пакетный менеджер ---
step "Определяю систему"
if command -v apt-get >/dev/null 2>&1; then
    PM="apt"
elif command -v dnf >/dev/null 2>&1; then
    PM="dnf"
elif command -v pacman >/dev/null 2>&1; then
    PM="pacman"
else
    fail "Не нашёл apt/dnf/pacman. Поддерживаются Ubuntu/Debian/Fedora/Arch."
fi
ok "Пакетный менеджер: $PM"

# --- Базовые пакеты ---
step "Устанавливаю базовые пакеты (Python, pip, curl, tmux)"
case "$PM" in
    apt)
        sudo apt-get update -qq
        sudo apt-get install -y python3 python3-pip python3-venv curl tmux ca-certificates
        ;;
    dnf)
        sudo dnf install -y python3 python3-pip curl tmux ca-certificates
        ;;
    pacman)
        sudo pacman -Sy --noconfirm python python-pip curl tmux ca-certificates
        ;;
esac
ok "Базовые пакеты установлены"

PYTHON=$(command -v python3 || command -v python)
[ -z "$PYTHON" ] && fail "Python не нашёлся"
PYVER=$($PYTHON -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
ok "Python: $PYVER"

# --- Tailscale ---
step "Устанавливаю Tailscale"
if command -v tailscale >/dev/null 2>&1; then
    ok "Tailscale уже установлен"
else
    curl -fsSL https://tailscale.com/install.sh | sh
    ok "Tailscale установлен"
fi

# Подключаемся к mesh
if sudo tailscale status >/dev/null 2>&1 && sudo tailscale ip -4 >/dev/null 2>&1; then
    ok "Tailscale уже подключён: $(sudo tailscale ip -4 | head -1)"
else
    step "Подключаю Tailscale к твоему аккаунту"
    echo "  ${BOLD}Сейчас появится ссылка — открой её в браузере на любом устройстве${RESET}"
    echo "  ${BOLD}и залогинься тем же Tailscale-аккаунтом что у твоего админа.${RESET}"
    echo
    sudo tailscale up --ssh || fail "Не удалось подключить Tailscale"
    ok "Tailscale подключён: $(sudo tailscale ip -4 | head -1)"
fi

# --- malinakod ---
step "Устанавливаю пакет malinakod"
sudo $PYTHON -m pip install --upgrade malinakod 2>&1 | tail -3
ok "malinakod установлен ($(sudo $PYTHON -m pip show malinakod | grep ^Version | awk '{print $2}'))"

# --- Активация лицензией ---
step "Активация лицензией"
LICENSE_FILE="$HOME/.malinakod/license.json"

if [ -f "$LICENSE_FILE" ]; then
    ok "Лицензия уже активирована: $LICENSE_FILE"
else
    KEY="${MALINAKOD_KEY:-}"
    if [ -z "$KEY" ]; then
        # Когда скрипт запущен через `curl ... | bash`, stdin занят пайпом
        # и обычный `read` сразу получит EOF. Читаем напрямую из терминала.
        if [ ! -e /dev/tty ]; then
            fail "Терминал недоступен и MALINAKOD_KEY не задан. Скачай скрипт файлом и запусти его явно: bash install_client.sh"
        fi
        echo
        echo "  ${BOLD}Вставь лицензионный ключ который тебе выдал админ${RESET}"
        echo "  ${BOLD}(одной строкой, начинается с MLNK-S-...)${RESET}"
        echo
        read -r -p "  Ключ: " KEY < /dev/tty
    fi
    [ -z "$KEY" ] && fail "Ключ не введён"

    # Активация: запускаем TUI с готовым ключом через stdin
    # TUI спрашивает ключ через Prompt.ask, поэтому просто пишем его в stdin
    mkdir -p "$HOME/.malinakod"
    echo "$KEY" | $PYTHON -m malinakod >/tmp/malinakod-activate.log 2>&1 &
    ACTPID=$!
    # Ждём появления license.json (или таймаут)
    for i in {1..30}; do
        if [ -f "$LICENSE_FILE" ]; then
            break
        fi
        sleep 1
    done
    # Прибиваем TUI
    kill $ACTPID 2>/dev/null || true
    wait $ACTPID 2>/dev/null || true

    if [ ! -f "$LICENSE_FILE" ]; then
        echo
        warn "Не удалось активировать автоматически. Лог:"
        cat /tmp/malinakod-activate.log | tail -20
        fail "Запусти вручную: $PYTHON -m malinakod"
    fi
    chmod 600 "$LICENSE_FILE"
    ok "Лицензия активирована и сохранена в $LICENSE_FILE"
fi

# --- systemd-юнит ---
step "Создаю systemd-юнит для автозапуска"
SERVICE_FILE="/etc/systemd/system/malinakod.service"
TMUX_BIN=$(command -v tmux)

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=MalinaKod Client (TUI in tmux)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=forking
User=$USER
Group=$(id -gn)
WorkingDirectory=$HOME
Environment=TERM=xterm-256color
Environment=HOME=$HOME
ExecStart=$TMUX_BIN new-session -d -s malinakod '$PYTHON -m malinakod'
ExecStop=$TMUX_BIN kill-session -t malinakod
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable malinakod >/dev/null 2>&1
sudo systemctl restart malinakod
sleep 2

if sudo systemctl is-active malinakod >/dev/null 2>&1; then
    ok "Сервис malinakod запущен и в автозапуске"
else
    warn "Сервис не стартовал, смотри: sudo journalctl -u malinakod -n 50"
fi

# --- Финал ---
echo
echo "${BOLD}${GREEN}════════════════════════════════════════════════════════════${RESET}"
echo "${BOLD}${GREEN}  Готово!${RESET}"
echo "${BOLD}${GREEN}════════════════════════════════════════════════════════════${RESET}"
echo
echo "  ${BOLD}Клиент работает в фоне.${RESET}"
echo "  Tailscale IP: ${BOLD}$(sudo tailscale ip -4 | head -1)${RESET}"
echo
echo "  ${BOLD}Полезные команды:${RESET}"
echo "    Подключиться к TUI:        ${BLUE}tmux attach -t malinakod${RESET}"
echo "      (выйти не убивая:        Ctrl+B, потом D)"
echo "    Перезапустить:             ${BLUE}sudo systemctl restart malinakod${RESET}"
echo "    Логи:                      ${BLUE}sudo journalctl -u malinakod -f${RESET}"
echo "    Обновить:                  ${BLUE}sudo $PYTHON -m pip install -U malinakod && sudo systemctl restart malinakod${RESET}"
echo
echo "  ${BOLD}Админ теперь сможет ходить к тебе по SSH через Tailscale.${RESET}"
echo
