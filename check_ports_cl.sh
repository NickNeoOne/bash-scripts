#!/bin/bash
# ссылка на github https://github.com/NickNeoOne/bash-scripts
# для выполнения запустить команду:
# curl -fsSL "https://raw.githubusercontent.com/NickNeoOne/bash-scripts/main/check_ports_cl.sh" | bash -s -- --hosts  host1 host2 -p port1 port2 
# или
# wget -qO- "https://raw.githubusercontent.com/NickNeoOne/bash-scripts/main/check_ports_cl.sh" | bash -s -- --hosts  host1 host2 -p port1 port2 

# Цветовые коды
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # Сброс цвета

cur_host=$(hostnamectl --static)

# Инициализация массивов
hosts=()
ports=()

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--hosts)
            shift
            while [[ $# -gt 0 && $1 != -* ]]; do
                hosts+=("$1")
                shift
            done
            ;;
        -p|--ports)
            shift
            while [[ $# -gt 0 && $1 != -* ]]; do
                ports+=("$1")
                shift
            done
            ;;
        *)
            echo "Неизвестный параметр: $1"
            exit 1
            ;;
    esac
done

# Проверка наличия параметров
if [ ${#hosts[@]} -eq 0 ]; then
    echo -e "${RED}Ошибка: Не указаны хосты!${NC}"
    echo "Использование: $0 -h HOST1 HOST2... -p PORT1 PORT2..."
    exit 1
fi

if [ ${#ports[@]} -eq 0 ]; then
    echo -e "${RED}Ошибка: Не указаны порты!${NC}"
    echo "Использование: $0 -h HOST1 HOST2... -p PORT1 PORT2..."
    exit 1
fi


resolve_fqdn() {
    local host=$1
    if [[ "$host" != *.* ]]; then
        local fqdn=$(dig +short "$host" | grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]+\.?$' | head -1)
        [ -z "$fqdn" ] && echo "$host" || echo "$fqdn"
    else
        echo "$host"
    fi
}

check_ping() {
    local host=$1
    if ping -c 1 -W 1 "$host" &> /dev/null; then
        echo -e "     ${GREEN}✅${NC}       "
    else
        echo -e "     ${RED}❌${NC}       "
    fi
}

check_port() {
    local host=$1
    local port=$2
    if nc -zv -w 2 "$host" "$port" &> /dev/null; then
        echo -e "     ${GREEN}✅${NC}       "
    else
        echo -e "     ${RED}❌${NC}       "
    fi
}

# Остальная часть оригинального скрипта
command -v nc >/dev/null 2>&1 || { echo -e "${RED}Ошибка: Утилита 'nc' не установлена!${NC}"; exit 1; }
command -v dig >/dev/null 2>&1 || { echo -e "${RED}Ошибка: Утилита 'dig' не установлена!${NC}"; exit 1; }

declare -A status
declare -a hosts_resolved

for i in "${!hosts[@]}"; do
    original_host="${hosts[i]}"
    resolved_host=$(resolve_fqdn "$original_host")
    hosts_resolved[i]="$resolved_host"
    status["$original_host,Ping"]=$(check_ping "$resolved_host")
    for port in "${ports[@]}"; do
        status["$original_host,Port$port"]=$(check_port "$resolved_host" "$port")
    done
done

echo "# Отчет проверки сети"
echo "**Время проверки:** $(date '+%Y-%m-%d %H:%M:%S') from ${cur_host}"
echo ""

printf "| %-14s |" "Проверка      "
for host in "${hosts[@]}"; do
    printf " %-14s |" "$host"
done
echo

printf "|%-12s|" "----------------"
for host in "${hosts[@]}"; do
    printf "%-14s|" "----------------"
done
echo

printf "| %-14s |" "Ping"
for host in "${hosts[@]}"; do
    printf " %-14s |" "${status["$host,Ping"]}"
done
echo

for port in "${ports[@]}"; do
    printf "| %-18s |" "Порт $port"
    for host in "${hosts[@]}"; do
        printf " %-18s |" "${status["$host,Port$port"]}"
    done
    echo
done

