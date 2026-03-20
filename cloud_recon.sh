#!/bin/bash
###############################################################################
#                                                                             #
#  Скрипт: cloud_recon.sh                                                     #
#  Описание: Инструмент для сетевой разведки (reconnaissance)                 #
#                                                                             #
#  Основные этапы работы:                                                     #
#                                                                             #
#  1. Определение целевого IP-адреса:                                         #
#     • Принимает на вход доменное имя или IP-адрес.                          #
#     • Если передан домен, скрипт разрешает его в IPv4-адрес                 #
#       (используя dig или getent).                                           #
#     • Можно указать конкретный DNS-сервер для разрешения имен.              #
#                                                                             #
#  2. Поиск владельца и ASN (Autonomous System Number):                       #
#     • Использует whois для получения информации об IP-адресе.               #
#     • Пытается извлечь номер Автономной Системы (ASN) из данных WHOIS.      #
#     • Если WHOIS не вернул ASN, скрипт использует сервис Team Cymru         #
#       (через DNS-запрос к origin.asn.cymru.com) для определения ASN         #
#       по обратному IP.                                                      #
#     • Определяет название организации и страну владельца                    #
#       (фильтруя записи регистраторов вроде RIPE или ARIN).                  #
#                                                                             #
#  3. Выгрузка диапазонов подсетей:                                           #
#     • Обращается к базе данных RADB (Routing Assets Database)               #
#       через сервер whois.radb.net.                                          #
#     • Запрашивает все маршруты (route), исходящие от найденного             #
#       номера AS (-i origin AS$ASN).                                         #
#     • Извлекает списки подсетей, сортирует их и сохраняет                   #
#       в указанный файл (или выводит в консоль).                             #
# Лицензия: MIT                                                               #
#                                                                             #
###############################################################################

#  Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Сброс цвета (No Color)

# Функция вывода справки
usage() {
    echo -e "\n========================================================================================${NC}"
    echo -e "${GREEN} Использование: $0 -t <target> [-f <output_file>] [-d <dns_server>]${NC}"
    echo -e "========================================================================================${NC}"
    echo " Параметры:"
    echo "  -t : Цель (IP-адрес или доменное имя). (Обязательно)"
    echo "  -f : (Опционально) Файл для сохранения всех подсетей найденной AS."
    echo "       Если не указан, результат выводится в консоль."
    echo "  -d : (Опционально) IP DNS-сервера (например, 1.1.1.1)."
    echo ""
    echo " Примеры:"
    echo "  $0 -t mail.ru -d 8.8.8.8              # Вывод в консоль"
    echo "  $0 -t mail.ru -f subnets.txt -d 8.8.8.8 # Сохранение в файл"
    echo -e "$=======================================================================================${NC}"
    exit 1
}

# Функция проверки IPv4 адреса
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if ((octet < 0 || octet > 255)); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Обработка параметров
while getopts "t:f:d:h" opt; do
    case ${opt} in
        t ) TARGET=$OPTARG ;;
        f ) OUT_FILE=$OPTARG ;;
        d ) DNS_SERVER=$OPTARG ;;
        h ) usage ;;
        * ) usage ;;
    esac
done
echo -e "\n"
#  Проверки с красным выводом ошибок
if [[ -z "$TARGET" ]]; then 
    echo -e "${RED}[-] Ошибка: Параметр -t (цель) обязателен.${NC}"
    usage
fi

# Проверка имени файла (если указан)
if [[ -n "$OUT_FILE" ]]; then
    if [[ -z "$OUT_FILE" ]]; then
        echo -e "${RED}[-] Ошибка: Параметр -f требует указания имени файла.${NC}"
        usage
    fi
    if [[ "$OUT_FILE" =~ ^- ]]; then
        echo -e "${RED}[-] Ошибка: Неверное имя файла '$OUT_FILE'. Имя файла не должно начинаться с '-'.${NC}"
        usage
    fi
fi

# Проверка DNS-сервера (если указан)
if [[ -n "$DNS_SERVER" ]]; then
    if ! validate_ip "$DNS_SERVER"; then
        echo -e "${RED}[-] Ошибка: Неверный формат DNS-сервера '$DNS_SERVER'. Ожидался IPv4 адрес.${NC}"
        usage
    fi
fi

# Проверка утилит
for tool in whois dig awk grep; do
    if ! command -v "$tool" &> /dev/null; then
        echo -e "${RED}[-] Ошибка: утилита $tool не установлена. (apt install dnsutils whois)${NC}"
        exit 1
    fi
done

# Создание временного файла для промежуточного хранения результатов
TEMP_FILE=$(mktemp)
trap "rm -f '$TEMP_FILE'" EXIT

echo -e "${BLUE}[*] Этап 1: Определение IPv4 для $TARGET...${NC}"
if [[ ! "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    if [[ -n "$DNS_SERVER" ]]; then
        IP_ADDR=$(dig @"$DNS_SERVER" +short "$TARGET" A | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    else
        IP_ADDR=$(dig +short "$TARGET" A | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    fi
else
    IP_ADDR="$TARGET"
fi

if [[ -z "$IP_ADDR" ]]; then
    echo -e "${RED}[-] Ошибка: не удалось разрешить $TARGET.${NC}"
    exit 1
fi
echo -e "${GREEN}[+] Целевой IP: $IP_ADDR${NC}"

echo -e "${BLUE}[*] Этап 2: Поиск владельца и номера Автономной Системы (ASN)...${NC}"
WHOIS_DATA=$(whois "$IP_ADDR")

# Используем grep -oE вместо -oP для совместимости
ASN=$(echo "$WHOIS_DATA" | grep -iE "origin:|originas:|OriginAS:|aut-num:" | head -n 1 | grep -oE 'AS[0-9]+' | grep -oE '[0-9]+')

if [[ -z "$ASN" ]]; then
    echo -e "${YELLOW}[i] WHOIS пуст, запрашиваю данные BGP через Cymru...${NC}"
    REV_IP=$(echo "$IP_ADDR" | awk -F. '{print $4"."$3"."$2"."$1}')
    ASN=$(dig +short "${REV_IP}.origin.asn.cymru.com" TXT | tr -d '"' | cut -d'|' -f1 | xargs)
fi

ORG_NAME=$(echo "$WHOIS_DATA" | grep -iE "descr:|org-name:|organization:|OrgName:" | \
    grep -ivE "RIPE|ARIN|IANA|NCC|Coordination|Regional|Internet" | head -n 1 | cut -d: -f2- | xargs)

COUNTRY=$(echo "$WHOIS_DATA" | grep -iE "country:" | head -n 1 | awk '{print $2}' | tr '[:lower:]' '[:upper:]')

if [[ -z "$ASN" ]]; then
    echo -e "${RED}[-] КРИТИЧЕСКАЯ ОШИБКА: Не удалось определить AS.${NC}"
    exit 1
fi

echo -e "${GREEN}[+] Организация: ${ORG_NAME:-Определена через BGP}${NC}"
echo -e "${GREEN}[+] Страна: ${COUNTRY:-Неизвестна}${NC}"
echo -e "${GREEN}[+] Номер системы: AS$ASN${NC}"

echo -e "${BLUE}[*] Этап 3: Выгрузка всех диапазонов для AS$ASN из RADB...${NC}"

whois -h whois.radb.net -- "-i origin AS$ASN" | \
    grep -E '^route:' | \
    awk '{print $2}' | \
    grep -v ':' | \
    sort -V | uniq > "$TEMP_FILE"

if [[ -s "$TEMP_FILE" ]]; then
    COUNT=$(wc -l < "$TEMP_FILE")
    
    echo -e "${GREEN}-----------------------------------------------------------------${NC}"
    echo -e "${GREEN}[УСПЕХ] Найдено подсетей: $COUNT${NC}"
    echo -e "${GREEN}[УСПЕХ] Владелец: $ORG_NAME ($COUNTRY)${NC}"
    
    if [[ -n "$OUT_FILE" ]]; then
        mv "$TEMP_FILE" "$OUT_FILE"
        trap - EXIT
        echo -e "${GREEN}[УСПЕХ] Данные сохранены в: $OUT_FILE${NC}"
    else
        cat "$TEMP_FILE"
        echo -e "${GREEN}[УСПЕХ] Данные выведены в консоль${NC}"
    fi
    echo -e "${GREEN}-----------------------------------------------------------------${NC}"
else
    echo -e "${RED}[-] Ошибка: RADB не вернула данных. Попробуйте сменить сервер на whois.ripe.net в коде.${NC}"
    exit 1
fi
