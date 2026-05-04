# MalinaKod — установщик клиента

Этот публичный репо содержит only-installer-скрипты для системы [MalinaKod](https://pypi.org/project/malinakod/) — приватная клиент-серверная система управления сервисами через GitHub.

## Установка клиента

### Linux (Ubuntu, Debian, Fedora, Arch):

```bash
curl -fsSL https://raw.githubusercontent.com/Medenchi/Malinakod-install/main/install_client.sh | bash
```

С готовым лицензионным ключом (без интерактивного ввода):

```bash
curl -fsSL https://raw.githubusercontent.com/Medenchi/Malinakod-install/main/install_client.sh | MALINAKOD_KEY="MLNK-S-..." bash
```

### Windows 10/11:

Открой PowerShell **от имени администратора** и выполни:

```powershell
iwr -useb https://raw.githubusercontent.com/Medenchi/Malinakod-install/main/install_client.ps1 | iex
```

## Что делают скрипты

Оба скрипта симметричны и делают одно и то же:

1. Проверяют права (root/admin при необходимости)
2. Ставят Python 3.10+ (если ещё нет)
3. Ставят [Tailscale](https://tailscale.com) — бесплатную mesh-сеть для безопасного удалённого SSH без открытия портов
4. Запускают `tailscale up` для логина клиента в свой Tailscale-аккаунт
5. Ставят пакет `malinakod` через pip
6. Запрашивают лицензионный ключ (или берут из переменной `MALINAKOD_KEY`)
7. Активируют клиент
8. Создают автозапуск:
   - Linux: systemd-юнит `malinakod.service` с tmux-обёрткой (TUI работает в фоне)
   - Windows: Scheduled Task `MalinaKod` с триггером At-Logon
9. Запускают сервис

## Безопасность

- Скрипты публичные и открытые — посмотри что они делают перед запуском
- Лицензия сохраняется с правами 0600 (Linux) / в `%USERPROFILE%\.malinakod\` (Windows)
- Никаких портов наружу — SSH идёт только через Tailscale-mesh между устройствами с одним аккаунтом

## Поддержка

Если что-то не работает — пиши автору, прислали ссылку на установщик.

## Исходники

Сами скрипты живут в этом репо. Сам пакет `malinakod` (Python TUI клиент) — на PyPI: https://pypi.org/project/malinakod/
