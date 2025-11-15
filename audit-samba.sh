#!/bin/bash
# audit-samba.sh — ОПТИМИЗИРОВАННАЯ ВЕРСИЯ С ДИНАМИЧЕСКОЙ ПОДСЕТЬЮ

# Проверяет ТОЛЬКО АКТИВНЫЕ строки
set -euo pipefail

# === Цвета ===
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

# === Пути ===
CONFIG="/etc/samba/smb.conf"
LOG_DIR="/var/log/samba"
REPORT="/tmp/samba-audit-report-$(date +%Y%m%d-%H%M%S).txt"

# === Функции ===
log() { echo -e "$1" | tee -a "$REPORT"; }
title() { log "${BLUE}=== $1 ===${NC}"; }
ok() { log "${GREEN}[OK] $1${NC}"; }
warn() { log "${YELLOW}[!] $1${NC}"; }
crit() { log "${RED}[!!] $1${NC}"; }

# === Проверка root ===
if [ "$EUID" -ne 0 ]; then
    echo "Запустите от root: sudo $0"
    exit 1
fi

# === ОПРЕДЕЛЕНИЕ ПОДСЕТИ ДЛЯ hosts allow ===
# Ищем подсеть в таблице маршрутизации, исключая loopback и default-маршрут.
NETWORK_CIDR=$(ip route | awk '/dev/ && !/default/ && !/127.0.0.0/ {print $1; exit}' 2>/dev/null)

# Санитарная проверка и установка окончательной строки рекомендаций.
if [[ -z "$NETWORK_CIDR" || "$NETWORK_CIDR" =~ ^(0\.0\.0\.0) ]]; then
    # Если подсеть не определена, используем безопасное значение по умолчанию.
    HOSTS_ALLOW_REC="192.168.1.0/24 127.0.0.1 # Внимание: использована подсеть по умолчанию, проверьте!"
else
    HOSTS_ALLOW_REC="$NETWORK_CIDR 127.0.0.1"
fi
# ============================================

# === Отчёт ===
: > "$REPORT"
log "=== АУДИТ БЕЗОПАСНОСТИ SAMBA ==="
log "Дата: $(date)"
log "Хост: $(hostname)"
log "ОС: $(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d'"' -f2 || echo 'Unknown')"
log "Локальная подсеть: $NETWORK_CIDR"
log ""

# === 1. Версия Samba ===
title "1. ВЕРСИЯ SAMBA"
if command -v smbd >/dev/null 2>&1; then
    VERSION=$(smbd --version 2>/dev/null | head -1)
    log "Версия: $VERSION"
    # Проверка на современные ветки (4.14+ как минимум)
    if echo "$VERSION" | grep -qE "Version 4\.(1[4-9]|[2-9][0-9])"; then
        ok "Версия актуальна (4.14+)"
    else
        crit "Устаревшая! Обновите: apt upgrade samba"
    fi
else
    warn "smbd не найден"
fi

# === 2. Службы ===
title "2. СЛУЖБЫ"
for svc in smbd nmbd winbind; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        if [ "$svc" = "nmbd" ]; then
            crit "nmbd активен → отключите NetBIOS!"
        else
            ok "$svc активна"
        fi
    else
        [ "$svc" = "nmbd" ] && ok "nmbd отключён" || warn "$svc неактивна"
    fi
done

# === 3. Порты ===
title "3. ПОРТЫ"
PORTS=$(ss -tuln | awk '$5 ~ /:137|:139|:445/ {print $5}' 2>/dev/null || true)
[ -z "$PORTS" ] && ok "Порты 137,139,445 закрыты" || { log "Открыты:\n$PORTS"; crit "Ограничьте firewall!"; }

# === 4. АНАЛИЗ smb.conf (ОДИН ПРОХОД) ===
title "4. АНАЛИЗ $CONFIG"
if [ ! -f "$CONFIG" ]; then
    warn "Конфиг не найден"
else
    # === ОДНОКРАТНАЯ ОБРАБОТКА КОНФИГА ===
    CFG=$(sed -e 's/[ \t]*[;#].*//' -e '/^[ \t]*[;#]/d' -e '/^\s*$/d' "$CONFIG" | tr '[:upper:]' '[:lower:]')

    # === Проверки (используем grep на переменную $CFG) ===

    # 4.1. min protocol (SMBv1)
    if echo "$CFG" | grep -q "min protocol.*\<smb1\|nt1"; then
        crit "SMBv1 активен! Установите: server min protocol = SMB2_10"
    elif echo "$CFG" | grep -q "min protocol.*smb[2-3].*[1-9]"; then
        ok "min protocol установлен (SMB2_10+)"
    else
        warn "min protocol не задан или установлен неоптимально"
    fi

    # 4.2. disable netbios
    if echo "$CFG" | grep -q "disable netbios.*yes"; then
        ok "NetBIOS отключён"
    else
        crit "NetBIOS включён → добавьте: disable netbios = yes"
    fi

    # 4.3. smb encrypt
    if echo "$CFG" | grep -q "smb encrypt.*required\|mandatory"; then
        ok "Шифрование включено"
    else
        warn "Шифрование не требуется → добавьте: smb encrypt = required"
    fi

    # 4.4. ntlm auth
    if echo "$CFG" | grep -q "ntlm auth.*ntlmv2-only"; then
        ok "NTLMv2-only включён"
    elif echo "$CFG" | grep -q "ntlm auth"; then
        crit "ntlm auth задан, но небезопасен (не ntlmv2-only)"
    else
        warn "ntlm auth не задан (рекомендуется ntlmv2-only)"
    fi

    # 4.5. guest ok / map to guest
    if echo "$CFG" | grep -q -E "guest ok.*yes"; then
        crit "Обнаружен 'guest ok = yes'! Отключите анонимный доступ."
    elif echo "$CFG" | grep -q -E "map to guest.*(bad user|guest|root|nobody)"; then
        crit "Обнаружен 'map to guest' с небезопасным значением. Отключите анонимный доступ."
    else
        ok "Анонимный доступ отключён (нет 'guest ok=yes' и безопасный 'map to guest')"
    fi

    # 4.6. hosts allow
    if echo "$CFG" | grep -q "hosts allow"; then
        ALLOW=$(echo "$CFG" | grep "hosts allow" | head -1 | sed 's/.*hosts allow *= *//')
        log "hosts allow: $ALLOW"
        ok "Ограничение по IP активно"
    else
        warn "hosts allow не задан"
    fi
fi

# === 5. Логи ===
title "5. ЛОГИ"
if [ -d "$LOG_DIR" ] && ls "$LOG_DIR"/log.* 1>/dev/null 2>&1; then
    SIZE=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
    ok "Логи пишутся ($SIZE)"
else
    warn "Логи не найдены"
fi


# === 6. Уязвимости (nmap) ===
title "6. УЯЗВИМОСТИ"
if command -v nmap >/dev/null 2>&1 && ss -tuln | grep -q ":445"; then
    IP=$(hostname -I | awk '{print $1}')
    VULNS=$(nmap -p445 --script "smb-vuln-*" "$IP" 2>/dev/null | grep -i "VULNERABLE" || true)
    [ -z "$VULNS" ] && ok "Уязвимостей не найдено" || crit "ОБНАРУЖЕНЫ:\n$VULNS"
else
    ss -tuln | grep -q ":445" || ok "Порт 445 закрыт"
    command -v nmap >/dev/null || warn "nmap не установлен"
fi

# === 7. Рекомендации ===
title "7. РЕКОМЕНДАЦИИ"
cat << EOF | tee -a "$REPORT"

# В [global] добавьте/проверьте:
server min protocol = SMB2_10
disable netbios = yes
smb encrypt = required
ntlm auth = ntlmv2-only
hosts allow = $HOSTS_ALLOW_REC

# Убедитесь, что НЕТ активных:
; guest ok = yes
; map to guest = ...

systemctl restart smbd
systemctl disable --now nmbd
EOF

# === Финал ===
log "${GREEN}Аудит завершён! Отчёт: $REPORT${NC}"
echo "Отчёт сохранён: $REPORT"
