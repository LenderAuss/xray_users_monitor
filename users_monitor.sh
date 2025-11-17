#!/bin/bash

# Скрипт автоматического контроля времени и подписок Xray
# Для архитектуры: single-port (443) с массивом clients

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Конфигурация
CONFIG_FILE="/usr/local/etc/xray/config.json"
LOG_FILE="/var/log/xray_auto_cleanup.log"
DEFAULT_TIME_LIMIT_HOURS=24
DEFAULT_CHECK_INTERVAL=60

# Функция логирования
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Функция для вычисления возраста пользователя в часах
get_user_age_hours() {
    local created_date="$1"
    
    local created_timestamp=$(date -d "$created_date" +%s 2>/dev/null)
    
    if [ -z "$created_timestamp" ] || [ "$created_timestamp" = "" ]; then
        echo "0"
        return 1
    fi
    
    local current_timestamp=$(date +%s)
    local diff_seconds=$((current_timestamp - created_timestamp))
    local hours=$(echo "scale=2; $diff_seconds / 3600" | bc)
    
    echo "$hours"
}

# Функция удаления пользователя по индексу (защита main - индекс 0)
remove_user_by_index() {
    local user_index=$1
    local user_num=$((user_index + 1))
    local age_hours=$2
    local time_limit=$3
    
    # Защита главного пользователя (первый в массиве)
    if [[ $user_index -eq 0 ]]; then
        log_message "WARNING: Attempt to remove protected user #1 (main) - BLOCKED"
        echo -e "${RED}❌ Нельзя удалить защищенного пользователя #1 (main)${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}⚠️  Пользователь #$user_num: Истёк срок действия${NC}"
    echo -e "    Прошло: ${age_hours}h / Лимит: ${time_limit}h"
    log_message "WARNING: User #$user_num - Time expired: ${age_hours}h / ${time_limit}h"
    
    echo -e "${RED}🗑️  Удаление пользователя #$user_num...${NC}"
    log_message "ACTION: Removing user #$user_num"
    
    # Удаляем из config.json по индексу
    jq "del(.inbounds[0].settings.clients[$user_index])" \
       "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    if [ $? -eq 0 ]; then
        systemctl restart xray
        echo -e "${GREEN}✅ Пользователь #$user_num успешно удалён${NC}"
        log_message "SUCCESS: User #$user_num removed - Time expired"
        
        # Отправить уведомление (если настроено)
        send_notification "🗑️ Удалён пользователь #$user_num" "Причина: истёк срок\nПрошло: ${age_hours}h / Лимит: ${time_limit}h"
        
        return 0
    else
        echo -e "${RED}❌ Ошибка при удалении пользователя #$user_num${NC}"
        log_message "ERROR: Failed to remove user #$user_num"
        return 1
    fi
}

# Функция отправки уведомлений
send_notification() {
    local title="$1"
    local message="$2"
    
    if [ -f /etc/xray/telegram.conf ]; then
        source /etc/xray/telegram.conf
        if [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                -d chat_id="${CHAT_ID}" \
                -d text="$title"$'\n'"$message" \
                &>/dev/null
        fi
    fi
}

# Функция мониторинга
monitor_users() {
    local time_limit_hours=$1
    local check_interval=$2
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           🔍 АВТОМАТИЧЕСКИЙ КОНТРОЛЬ ВРЕМЕНИ XRAY              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}⚙️  Настройки:${NC}"
    echo -e "   Лимит времени (без подписки): ${GREEN}${time_limit_hours} часов${NC}"
    echo -e "   Интервал проверки: ${GREEN}${check_interval} секунд${NC}"
    echo -e "   Конфигурация: ${BLUE}${CONFIG_FILE}${NC}"
    echo -e "   Лог файл: ${BLUE}${LOG_FILE}${NC}"
    echo ""
    echo -e "${YELLOW}📝 Запуск мониторинга... (Ctrl+C для остановки)${NC}"
    echo ""
    
    log_message "=== Monitoring started. Time limit: ${time_limit_hours}h, Interval: ${check_interval}s ==="
    
    local check_count=0
    
    while true; do
        check_count=$((check_count + 1))
        
        local current_time=$(date '+%Y-%m-%d %H:%M:%S')
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}🔍 Проверка #${check_count} - ${current_time}${NC}"
        echo ""
        
        # Получаем количество клиентов
        local total_clients=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE")
        
        if [ "$total_clients" -eq 0 ]; then
            echo -e "${YELLOW}⚠️  Нет активных пользователей${NC}"
            log_message "INFO: No active users found"
        else
            local users_checked=0
            local users_removed=0
            
            # Проходим по клиентам в обратном порядке (чтобы индексы не сбивались при удалении)
            for ((i=$total_clients-1; i>=0; i--)); do
                local user_num=$((i + 1))
                
                # Получаем метаданные
                local subscription=$(jq -r ".inbounds[0].settings.clients[$i].metadata.subscription // \"n/a\"" "$CONFIG_FILE")
                local created_date=$(jq -r ".inbounds[0].settings.clients[$i].metadata.created_date // \"n/a\"" "$CONFIG_FILE")
                
                # Получаем возраст
                local age_hours="0"
                if [ "$created_date" != "n/a" ]; then
                    age_hours=$(get_user_age_hours "$created_date")
                fi
                
                local should_remove=false
                
                # Проверка: удаляем только пользователей без подписки с истекшим временем
                if [ "$subscription" = "n" ] && [ "$created_date" != "n/a" ] && [ $i -ne 0 ]; then
                    if (( $(echo "$age_hours >= $time_limit_hours" | bc -l) )); then
                        should_remove=true
                    fi
                fi
                
                if [ "$should_remove" = true ]; then
                    users_removed=$((users_removed + 1))
                    echo -e "${RED}❌ Пользователь #$user_num${NC}"
                    echo -e "   Подписка: $subscription | Создан: $created_date"
                    echo -e "   Возраст: ${age_hours}h / Лимит: ${time_limit_hours}h"
                    
                    remove_user_by_index "$i" "$age_hours" "$time_limit_hours"
                    
                    # После удаления обновляем счетчик
                    total_clients=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE")
                    
                    echo ""
                else
                    # Пользователь в норме
                    local time_status=""
                    local protected=""
                    
                    if [ $i -eq 0 ]; then
                        protected=" ${GREEN}[MAIN]${NC}"
                    fi
                    
                    if [ "$subscription" = "n" ] && [ "$created_date" != "n/a" ]; then
                        local time_percent=$(echo "scale=1; $age_hours * 100 / $time_limit_hours" | bc)
                        local remaining=$(echo "scale=2; $time_limit_hours - $age_hours" | bc)
                        time_status="Возраст: ${age_hours}h / ${time_limit_hours}h (${time_percent}%) | Осталось: ${remaining}h"
                    elif [ "$subscription" = "y" ]; then
                        time_status="Подписка: активна (∞)"
                    else
                        time_status="Подписка: n/a | Дата создания: отсутствует"
                    fi
                    
                    echo -e "${GREEN}✓${NC} Пользователь #$user_num$protected"
                    echo -e "   $time_status"
                fi
                
                users_checked=$((users_checked + 1))
            done
            
            echo ""
            echo -e "${CYAN}📊 Статистика проверки:${NC}"
            echo -e "   Проверено пользователей: ${users_checked}"
            if [ $users_removed -gt 0 ]; then
                echo -e "   Удалено: ${RED}${users_removed}${NC}"
            else
                echo -e "   Удалено: ${GREEN}0${NC}"
            fi
        fi
        
        echo ""
        echo -e "${BLUE}⏳ Следующая проверка через ${check_interval} секунд...${NC}"
        echo ""
        
        sleep "$check_interval"
    done
}

# Функция одноразовой проверки
check_once() {
    local time_limit_hours=$1
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          🔍 ПРОВЕРКА ВРЕМЕНИ ПОЛЬЗОВАТЕЛЕЙ (ОДНОРАЗОВО)       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Лимит времени (без подписки): ${time_limit_hours} часов${NC}"
    echo ""
    
    local total_clients=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE")
    
    if [ "$total_clients" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  Нет активных пользователей${NC}"
        return 0
    fi
    
    printf "${BLUE}%-8s${NC} ${YELLOW}%-12s${NC} ${CYAN}%-20s${NC} ${MAGENTA}%-15s${NC} ${WHITE}%-10s${NC}\n" \
        "#" "Подписка" "Дата создания" "Возраст" "Статус"
    echo "────────────────────────────────────────────────────────────────────────"
    
    local total_to_remove=0
    declare -a users_to_remove=()
    
    for ((i=0; i<$total_clients; i++)); do
        local user_num=$((i + 1))
        
        # Получаем метаданные
        local subscription=$(jq -r ".inbounds[0].settings.clients[$i].metadata.subscription // \"n/a\"" "$CONFIG_FILE")
        local created_date=$(jq -r ".inbounds[0].settings.clients[$i].metadata.created_date // \"n/a\"" "$CONFIG_FILE")
        
        # Получаем возраст
        local age_hours="0"
        if [ "$created_date" != "n/a" ]; then
            age_hours=$(get_user_age_hours "$created_date")
        fi
        
        local should_remove=false
        local status="OK"
        local protected=""
        
        if [ $i -eq 0 ]; then
            protected=" [MAIN]"
        fi
        
        # Проверяем условия
        if [ "$subscription" = "n" ] && [ "$created_date" != "n/a" ] && [ $i -ne 0 ]; then
            if (( $(echo "$age_hours >= $time_limit_hours" | bc -l) )); then
                should_remove=true
                status="${RED}ИСТЁК${NC}"
            else
                local time_percent=$(echo "scale=0; $age_hours * 100 / $time_limit_hours" | bc)
                status="${GREEN}OK (${time_percent}%)${NC}"
            fi
        elif [ "$subscription" = "y" ]; then
            status="${GREEN}∞${NC}"
        else
            status="${YELLOW}N/A${NC}"
        fi
        
        # Форматируем вывод
        if [ "$should_remove" = true ]; then
            printf "%-8s %-12s %-20s ${RED}%-15s${NC} %b\n" \
                "#$user_num" "$subscription" "$created_date" "${age_hours}h" "$status"
            total_to_remove=$((total_to_remove + 1))
            users_to_remove+=("$i|$age_hours")
        else
            local age_display="${age_hours}h"
            if [ "$subscription" = "y" ]; then
                age_display="${age_hours}h (∞)"
            fi
            printf "%-8s %-12s %-20s %-15s %b%s\n" \
                "#$user_num" "$subscription" "$created_date" "$age_display" "$status" "$protected"
        fi
    done
    
    echo ""
    if [ $total_to_remove -gt 0 ]; then
        echo -e "${RED}⚠️  Пользователей для удаления: ${total_to_remove}${NC}"
        echo ""
        
        read -p "Удалить пользователей с истёкшим сроком? (y/n): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            # Удаляем в обратном порядке
            for ((idx=${#users_to_remove[@]}-1; idx>=0; idx--)); do
                IFS='|' read -r user_index user_age <<< "${users_to_remove[$idx]}"
                remove_user_by_index "$user_index" "$user_age" "$time_limit_hours"
                echo ""
            done
            echo -e "${GREEN}✅ Удаление завершено${NC}"
        else
            echo -e "${YELLOW}Отменено${NC}"
        fi
    else
        echo -e "${GREEN}✅ Все пользователи в пределах лимита времени${NC}"
    fi
}

# Функция просмотра статуса
show_status() {
    local time_limit_hours=$1
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                 📊 СТАТУС ВСЕХ ПОЛЬЗОВАТЕЛЕЙ                  ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Лимит времени (без подписки): ${time_limit_hours} часов${NC}"
    echo ""
    
    local total_clients=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE")
    
    if [ "$total_clients" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  Нет активных пользователей${NC}"
        return 0
    fi
    
    echo "════════════════════════════════════════════════════════════════════"
    
    for ((i=0; i<$total_clients; i++)); do
        local user_num=$((i + 1))
        
        # Получаем метаданные
        local subscription=$(jq -r ".inbounds[0].settings.clients[$i].metadata.subscription // \"n/a\"" "$CONFIG_FILE")
        local created_date=$(jq -r ".inbounds[0].settings.clients[$i].metadata.created_date // \"n/a\"" "$CONFIG_FILE")
        
        # Получаем возраст
        local age_hours="0"
        if [ "$created_date" != "n/a" ]; then
            age_hours=$(get_user_age_hours "$created_date")
        fi
        
        local protected=""
        if [ $i -eq 0 ]; then
            protected=" ${GREEN}[MAIN - ЗАЩИЩЕН]${NC}"
        fi
        
        echo -e "${CYAN}Пользователь #$user_num$protected${NC}"
        echo "   Подписка: $subscription"
        echo "   Создан: $created_date"
        
        if [ "$subscription" = "n" ] && [ "$created_date" != "n/a" ]; then
            local remaining=$(echo "scale=2; $time_limit_hours - $age_hours" | bc)
            local percent=$(echo "scale=1; $age_hours * 100 / $time_limit_hours" | bc)
            
            if (( $(echo "$age_hours >= $time_limit_hours" | bc -l) )); then
                echo -e "   Возраст: ${RED}${age_hours}h${NC} (${percent}%)"
                if [ $i -eq 0 ]; then
                    echo -e "   Статус: ${GREEN}ЗАЩИЩЕН${NC}"
                else
                    echo -e "   Статус: ${RED}ИСТЁК СРОК${NC}"
                fi
            else
                echo -e "   Возраст: ${GREEN}${age_hours}h${NC} из ${time_limit_hours}h (${percent}%)"
                echo -e "   Осталось: ${GREEN}${remaining}h${NC}"
                echo -e "   Статус: ${GREEN}АКТИВЕН${NC}"
            fi
        elif [ "$subscription" = "y" ]; then
            echo -e "   Возраст: ${age_hours}h"
            echo -e "   Статус: ${GREEN}АКТИВЕН (∞)${NC}"
        else
            echo -e "   Возраст: N/A"
            echo -e "   Статус: ${YELLOW}N/A${NC}"
        fi
        
        echo "────────────────────────────────────────────────────────────────────"
    done
}

# Функция просмотра логов
show_logs() {
    local lines=${1:-20}
    
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}⚠️  Лог файл не найден${NC}"
        return 1
    fi
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    📜 ЛОГИ (последние ${lines})                    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    tail -n "$lines" "$LOG_FILE" | while IFS= read -r line; do
        if [[ $line == *"ERROR"* ]]; then
            echo -e "${RED}$line${NC}"
        elif [[ $line == *"WARNING"* ]]; then
            echo -e "${YELLOW}$line${NC}"
        elif [[ $line == *"SUCCESS"* ]]; then
            echo -e "${GREEN}$line${NC}"
        else
            echo "$line"
        fi
    done
}

# Функция настройки Telegram
setup_telegram() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              📱 НАСТРОЙКА TELEGRAM УВЕДОМЛЕНИЙ                ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Введите BOT_TOKEN: " bot_token
    read -p "Введите CHAT_ID: " chat_id
    
    mkdir -p /etc/xray
    cat > /etc/xray/telegram.conf << EOF
BOT_TOKEN="$bot_token"
CHAT_ID="$chat_id"
EOF
    
    chmod 600 /etc/xray/telegram.conf
    
    echo -e "${GREEN}✅ Telegram уведомления настроены${NC}"
    echo ""
    
    read -p "Отправить тестовое уведомление? (y/n): " test
    if [ "$test" = "y" ]; then
        curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
            -d chat_id="${chat_id}" \
            -d text="✅ Xray Auto Cleanup: Тестовое уведомление" \
            &>/dev/null
        echo -e "${GREEN}✅ Тестовое сообщение отправлено${NC}"
    fi
}

# Главное меню
show_menu() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        🛡️  АВТОУДАЛЕНИЕ ПОЛЬЗОВАТЕЛЕЙ БЕЗ ПОДПИСКИ           ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo " 1) 🔄 Запустить мониторинг (непрерывный)"
    echo " 2) 🔍 Проверить сейчас (одноразово)"
    echo " 3) 📊 Показать статус всех пользователей"
    echo " 4) 📜 Показать логи"
    echo " 5) 📱 Настроить Telegram уведомления"
    echo " 0) ❌ Выход"
    echo ""
    read -p "Выберите действие: " choice
    
    case $choice in
        1)
            read -p "Лимит времени (часов, по умолчанию $DEFAULT_TIME_LIMIT_HOURS): " time_limit
            time_limit=${time_limit:-$DEFAULT_TIME_LIMIT_HOURS}
            
            read -p "Интервал проверки (секунд, по умолчанию $DEFAULT_CHECK_INTERVAL): " interval
            interval=${interval:-$DEFAULT_CHECK_INTERVAL}
            
            monitor_users "$time_limit" "$interval"
            ;;
        2)
            read -p "Лимит времени (часов, по умолчанию $DEFAULT_TIME_LIMIT_HOURS): " time_limit
            time_limit=${time_limit:-$DEFAULT_TIME_LIMIT_HOURS}
            
            check_once "$time_limit"
            ;;
        3)
            read -p "Лимит времени для справки (часов, по умолчанию $DEFAULT_TIME_LIMIT_HOURS): " time_limit
            time_limit=${time_limit:-$DEFAULT_TIME_LIMIT_HOURS}
            
            show_status "$time_limit"
            ;;
        4)
            read -p "Количество строк (по умолчанию 20): " lines
            lines=${lines:-20}
            show_logs "$lines"
            ;;
        5)
            setup_telegram
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор${NC}"
            ;;
    esac
    
    if [ "$choice" != "1" ] && [ "$choice" != "0" ]; then
        echo ""
        read -p "Нажмите Enter для продолжения..."
        show_menu
    fi
}

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Запустите скрипт с правами root (sudo)${NC}"
    exit 1
fi

# Проверка зависимостей
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Ошибка: jq не установлен. Установите: apt install jq${NC}"
    exit 1
fi

if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}Установка bc...${NC}"
    apt-get update && apt-get install -y bc
fi

# Проверка конфига
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Ошибка: конфиг не найден: $CONFIG_FILE${NC}"
    exit 1
fi

# Запуск с аргументами или меню
if [ $# -gt 0 ]; then
    case "$1" in
        monitor|watch|start)
            time_limit=${2:-$DEFAULT_TIME_LIMIT_HOURS}
            interval=${3:-$DEFAULT_CHECK_INTERVAL}
            monitor_users "$time_limit" "$interval"
            ;;
        check|once)
            time_limit=${2:-$DEFAULT_TIME_LIMIT_HOURS}
            check_once "$time_limit"
            ;;
        status)
            time_limit=${2:-$DEFAULT_TIME_LIMIT_HOURS}
            show_status "$time_limit"
            ;;
        logs)
            lines=${2:-20}
            show_logs "$lines"
            ;;
        telegram)
            setup_telegram
            ;;
        *)
            echo "Использование: $0 [monitor|check|status|logs|telegram] [параметры]"
            echo ""
            echo "Примеры:"
            echo "  $0 monitor 24 60      - мониторинг: лимит 24ч, проверка каждые 60 сек"
            echo "  $0 check 12           - проверить: лимит 12ч"
            echo "  $0 status 24          - показать статус с лимитом 24ч"
            echo "  $0 logs 50            - показать 50 последних строк лога"
            exit 1
            ;;
    esac
else
    show_menu
fi
```

**Основные изменения:**

1. ❌ **Убрал все упоминания `email`** - работаю с индексами
2. 🛡️ **Защита пользователя #1** (индекс 0) - это main
3. 📍 **Удаление по индексу** - `jq "del(.inbounds[0].settings.clients[$i])"`
4. 🔄 **Обратный порядок проверки** - чтобы индексы не сбивались
5. 📊 **Отображение "Пользователь #N"** вместо email

**Примеры вывода:**
```
✓ Пользователь #1 [MAIN]
   Подписка: активна (∞)

✓ Пользователь #2
   Возраст: 12.5h / 24h (52%) | Осталось: 11.5h

❌ Пользователь #3
   Подписка: n | Создан: 2024-11-15 10:00:00
   Возраст: 25.2h / Лимит: 24h
🗑️  Удаление пользователя #3...
