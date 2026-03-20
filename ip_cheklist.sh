#!/bin/bash
################################################################################
# Скрипт: ip_cheklist.sh
# Описание: Массовая проверка IP-адресов и доменов на принадлежность к заданным
#           сетевым подсетям (CIDR).
#
# Функционал:
#   1. Принимает базу подсетей (файл с CIDR или доменами) через параметр -w
#   2. Принимает цели для проверки (IP, домены, CIDR, JSON) через -r или -j
#   3. Автоматически резолвит доменные имена в IPv4-адреса
#   4. Использует grepcidr для быстрой сверки IP с диапазоном подсетей
#   5. Ведёт лог доменов, которые не удалось резолвить
#   6. Поддерживает кэширование результатов (ускоряет повторные запуски)
#   7. Автоматически очищает устаревший кэш (защита от замусоривания)
#
# Хранение данных:
#   - Кэш: ./ip_cheklist_cache/ (подкаталог в текущей директории)
#   - Логи: ./ip_cheklist_logs/failed.log (подкаталог в текущей директории)
#
# Зависимости:
#   - grepcidr (утилита для сравнения IP с CIDR)
#   - jq (для парсинга JSON-файлов, опционально)
#   - getent (для DNS-резолвинга, обычно в составе libc)
#   - dig (запасной вариант для DNS, опционально)
#   - bash 4.0+
#
# Примеры использования:
#   ./ip_cheklist.sh -w rkn.txt -r ips.txt
#   ./ip_cheklist.sh -w whitelist.txt -j microsoft.json
#   ./ip_cheklist.sh -w domains.txt -r targets.txt
#
# Лицензия: MIT
################################################################################

# Цвета для терминала
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
R='\033[0;31m'
NC='\033[0m'

# Директория для кэша и логов (подкаталоги в текущей директории!)
CACHE_DIR="./ip_cheklist_cache"
LOG_DIR="./ip_cheklist_logs"
FAILED_LOG="${LOG_DIR}/failed.log"

# Настройки очистки (в днях)
CACHE_MAX_AGE=7      # Кэш старше 7 дней удаляется
LOG_MAX_AGE=30       # Логи старше 30 дней удаляются

# Создаём каталоги
mkdir -p "$CACHE_DIR"
mkdir -p "$LOG_DIR"
> "$FAILED_LOG"

# --- Функция очистки устаревших файлов ---
cleanup_old_files() {
    local dir=$1
    local max_age_days=$2
    local count=0
    
    if [[ -d "$dir" ]]; then
        # Находим и удаляем файлы старше указанного возраста
        while IFS= read -r -d '' file; do
            rm -f "$file"
            ((count++))
        done < <(find "$dir" -type f -mtime +$max_age_days -print0 2>/dev/null)
        
        if [[ $count -gt 0 ]]; then
            echo -e "${Y}[i] Очищено устаревших файлов в $dir: $count${NC}"
        fi
    fi
}

# Очистка при старте скрипта
cleanup_old_files "$CACHE_DIR" "$CACHE_MAX_AGE"
cleanup_old_files "$LOG_DIR" "$LOG_MAX_AGE"

usage() {
    echo -e "${Y}Использование:${NC} $0 -w <subnets_file> [-r <ips_file>] [-j <json_file>]"
    echo "  -w : Файл с подсетями/CIDR (база)."
    echo "  -r : Файл с вашими IP для проверки (цели)."
    echo "  -j : Файл с диапазонами в формате JSON (цели)."
    echo -e "\nПример: $0 -w rkn.txt -j microsoft.json"
    exit 1
}

while getopts "w:r:j:h" opt; do
    case ${opt} in
        w ) MY_WHITELIST=$OPTARG ;;
        r ) TXT_RANGES=$OPTARG ;;
        j ) JSON_RANGES=$OPTARG ;;
        * ) usage ;;
    esac
done

# 1. Проверяем наличие базы (-w)
if [[ ! -f "$MY_WHITELIST" ]]; then
    echo -e "${R}[-] Ошибка: Файл базы подсетей (-w) не найден.${NC}"
    usage
fi

# 2. Проверяем, что указан ХОТЯ БЫ ОДИН файл с целями (-r или -j)
if [[ ! -f "$TXT_RANGES" && ! -f "$JSON_RANGES" ]]; then
    echo -e "${R}[-] Ошибка: Укажите файл с IP для проверки через -r или -j.${NC}"
    usage
fi

# Временные файлы
CLEAN_DB="/tmp/ranges_$$.txt"
INPUT_STREAM="/tmp/input_$$.txt"
> "$CLEAN_DB"
> "$INPUT_STREAM"

# --- Функции кэширования ---

# Получить хеш файла
get_file_hash() {
    md5sum "$1" 2>/dev/null | awk '{print $1}'
}

# Получить имя файла кэша
get_cache_file() {
    local source_file=$1
    local file_hash=$(get_file_hash "$source_file")
    local base_name=$(basename "$source_file" | sed 's/[^a-zA-Z0-9]/_/g')
    echo "${CACHE_DIR}/${base_name}.${file_hash}.cache"
}

# --- Функция DNS-резолвинга (множественные методы) ---
resolve_domain() {
    local domain=$1
    local ip=""
    
    # Способ 1: getent ahosts (основной)
    ip=$(getent ahosts "$domain" 2>/dev/null | grep -v ':' | head -n 1 | awk '{print $1}')
    
    # Способ 2: getent hosts (запасной)
    if [[ -z "$ip" ]]; then
        ip=$(getent hosts "$domain" 2>/dev/null | awk '{print $1; exit}')
    fi
    
    # Способ 3: dig (если установлен)
    if [[ -z "$ip" ]] && command -v dig &> /dev/null; then
        ip=$(dig +short "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)
    fi
    
    # Способ 4: host (если установлен)
    if [[ -z "$ip" ]] && command -v host &> /dev/null; then
        ip=$(host -A "$domain" 2>/dev/null | grep 'has address' | awk '{print $NF}' | head -n 1)
    fi
    
    # Финальная проверка что это IPv4
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "$ip"
        return 0
    fi
    return 1
}

# --- Шаг 1: Подготовка базы подсетей (из -w) с кэшированием ---
echo -e "${B}[*] Шаг 1: Подготовка базы подсетей...${NC}"

process_whitelist() {
    local source_file=$1
    local cache_file=$(get_cache_file "$source_file")
    
    # Проверяем кэш
    if [[ -f "$cache_file" ]]; then
        echo -e "${G}[i] Используем кэш для: $source_file${NC}"
        cat "$cache_file" >> "$CLEAN_DB"
        return
    fi
    
    echo -e "[i] Обрабатываем файл: $source_file"
    local total_lines=$(grep -cve '^\s*$' "$source_file" 2>/dev/null || echo 1)
    local current=0
    local resolved=0
    local failed=0
    
    [[ "$total_lines" -eq 0 ]] && total_lines=1
    > "$cache_file"
    
    while read -r line; do
        resource=$(echo "$line" | tr -d '\r' | sed 's/[[:space:]]//g')
        [[ -z "$resource" || "$resource" =~ ^# ]] && continue
        
        # Проверяем: это IP или подсеть (с маской или без)
        if [[ "$resource" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/([0-9]|[1-2][0-9]|3[0-2]))?$ ]]; then
            echo "$resource" >> "$CLEAN_DB"
            echo "$resource" >> "$cache_file"
            ((resolved++))
        else
            # Это домен — резолвим
            ip=$(resolve_domain "$resource")
            if [[ -n "$ip" ]]; then
                echo "$ip/32" >> "$CLEAN_DB"
                echo "$ip/32" >> "$cache_file"
                ((resolved++))
            else
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] $source_file (BASE) : $resource" >> "$FAILED_LOG"
                ((failed++))
            fi
        fi
        
        ((current++))
        percent=$(( current * 100 / total_lines ))
        printf "\r    Прогресс: [%-50s] %d%% (%d/%d)" "$(printf '#%.0s' $(seq 1 $((percent/2))))" "$percent" "$current" "$total_lines"
    done < "$source_file"
    echo -e "\n"
    
    echo -e "[i] База: обработано=${resolved}, не резолвилось=${failed}"
}

process_whitelist "$MY_WHITELIST"

if [[ ! -s "$CLEAN_DB" ]]; then
    echo -e "${R}[-] Ошибка: База подсетей пуста после обработки.${NC}"
    exit 1
fi

# --- Шаг 2: Сбор целей (IP/Домены) с кэшированием ---
echo -e "${B}[*] Шаг 2: Сбор целей и DNS-резолв...${NC}"

# Счётчики статистики
resolve_ok=0
resolve_failed=0

process_targets() {
    local source_file=$1
    local cache_file=$(get_cache_file "$source_file")
    
    # Проверяем кэш
    if [[ -f "$cache_file" ]]; then
        echo -e "${G}[i] Используем кэш для: $source_file${NC}"
        cat "$cache_file" >> "$INPUT_STREAM"
        return
    fi
    
    local total_lines=$(grep -cve '^\s*$' "$source_file" 2>/dev/null || echo 1)
    local current=0
    local file_failed=0
    
    [[ "$total_lines" -eq 0 ]] && total_lines=1
    echo -e "[i] Обработка файла: $source_file"
    
    > "$cache_file"
    
    while read -r line; do
        resource=$(echo "$line" | tr -d '\r' | sed 's/[[:space:]]//g')
        [[ -z "$resource" || "$resource" =~ ^# ]] && continue
        
        # Проверяем: это IP или подсеть (с маской или без)
        if [[ "$resource" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/([0-9]|[1-2][0-9]|3[0-2]))?$ ]]; then
            echo "$resource" >> "$INPUT_STREAM"
            echo "$resource" >> "$cache_file"
            ((resolve_ok++))
        else
            # Это домен — резолвим через исправленную функцию
            ip=$(resolve_domain "$resource")
            if [[ -n "$ip" ]]; then
                echo "$ip" >> "$INPUT_STREAM"
                echo "$ip" >> "$cache_file"
                ((resolve_ok++))
            else
                # Не удалось резолвить — пишем в лог
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] $source_file (TARGETS) : $resource" >> "$FAILED_LOG"
                ((resolve_failed++))
                ((file_failed++))
            fi
        fi
        
        ((current++))
        percent=$(( current * 100 / total_lines ))
        printf "\r    Прогресс: [%-50s] %d%% (%d/%d)" "$(printf '#%.0s' $(seq 1 $((percent/2))))" "$percent" "$current" "$total_lines"
    done < "$source_file"
    echo -e "\n"
    
    # Отчёт по файлу
    if [[ $file_failed -gt 0 ]]; then
        echo -e "    ${Y}[!] В файле не резолвилось доменов: $file_failed${NC}"
    fi
}

# Обработка TXT если есть
[[ -f "$TXT_RANGES" ]] && process_targets "$TXT_RANGES"

# Обработка JSON если есть
if [[ -f "$JSON_RANGES" ]]; then
    echo -e "[i] Извлечение данных из JSON: $JSON_RANGES"
    if command -v jq &> /dev/null; then
        jq -r '.values[].properties.addressPrefixes[]' "$JSON_RANGES" 2>/dev/null | grep -v ':' >> "$INPUT_STREAM"
        echo -e "    Готово: данные JSON добавлены в очередь проверки."
    else
        echo -e "${R}[!] Ошибка: 'jq' не установлен. JSON проигнорирован.${NC}"
    fi
fi

# --- Шаг 3: Массовая сверка ---
echo -e "${B}[*] Шаг 3: Массовая сверка через grepcidr...${NC}"

if [[ ! -s "$INPUT_STREAM" ]]; then
    echo -e "${R}[-] Ошибка: Нечего проверять (список целей пуст).${NC}"
else
    results=$(grepcidr -f "$CLEAN_DB" "$INPUT_STREAM" 2>/dev/null)
    echo -e "------------------------------------------------"
    if [[ -n "$results" ]]; then
        match_count=$(echo "$results" | sort -u | wc -l)
        echo -e "${G}[ОК] Найдено совпадений: $match_count${NC}"
        echo "------------------------------------------------"
        echo "$results" | sort -u | sed "s/^/$(echo -e ${G}[MATCH]${NC} )/"
    else
        echo -e "${Y}[!] Совпадений не найдено.${NC}"
    fi
fi

# --- Итоговая статистика ---
echo "------------------------------------------------"
echo -e "${B}[+] Готово.${NC}"
echo -e "[i] Успешно обработано: ${G}$resolve_ok${NC}"
if [[ $resolve_failed -gt 0 ]]; then
    echo -e "[i] Не удалось резолвить: ${R}$resolve_failed${NC}"
    echo -e "${Y}[i] Лог ошибок: $FAILED_LOG${NC}"
else
    echo -e "[i] Все домены успешно резолвились"
fi
echo -e "${Y}[i] Кэш сохранён в: ${CACHE_DIR}${NC}"
echo -e "${Y}[i] Логи сохранены в: ${LOG_DIR}${NC}"
echo -e "${Y}[i] Автоочистка: кэш > ${CACHE_MAX_AGE} дн., логи > ${LOG_MAX_AGE} дн.${NC}"
echo "------------------------------------------------"

# Очистка временных файлов
rm -f "$CLEAN_DB" "$INPUT_STREAM"
