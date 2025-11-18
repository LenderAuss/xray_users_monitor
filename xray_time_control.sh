#!/bin/bash

# Скрипт автоматического контроля времени Xray (Single-Port Architecture)
# Работает с единым портом 443, все пользователи в clients array
# Удаление происходит ПО ИМЕНИ для безопасности

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Конфигурация по умолчанию
DEFAULT_TIME_LIMIT_HOURS=24
DEFAULT_CHECK_INTERVAL=3600  # 1 час в секундах
LOG_FILE="/var/log/xray_time_control.log"
CONFIG_FILE="/usr/local/etc/xray/config.json"

# Функция для очистки экрана и возврата курсора
clear_screen() {
    # Очищаем экран и возвращаем курсор в начало
    clear
}

# Функция для подсчета строк вывода (для динамического обновления)
count_output_lines() {
    local count="$1"
    echo "$count"
}

# Функция логирования
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

# Функция для вычисления времени жизни пользователя в часах
get_user_age_hours() {
    local created_date="$1"
    
    # Преобразуем дату создания в timestamp
    local created_timestamp=$(date -d "$created_date" +%s 2>/dev/null)
    
    if [ -z "$created_timestamp" ] || [ "$created_timestamp" = "" ]; then
        echo "0"
        return 1
    fi
    
    # Текущий timestamp
    local current_timestamp=$(date +%s)
    
    # Разница в секундах
    local diff_seconds=$((current_timestamp - created_timestamp))
    
    # Конвертируем в часы
    local hours=$(echo "scale=2; $diff_seconds / 3600" | bc)
    
    echo "$hours"
}

# Функция для удаления пользователя ПО ИМЕНИ
remove_user_by_name() {
    local user_email="$1"
    local age_hours="$2"
    local time_limit="$3"
    
    log_message "WARNING: User '$user_email' - Time expired: ${age_hours}h / ${time_limit}h"
    
    # Защита главного пользователя
    if [[ "$user_email" == "main" ]]; then
        log_message "ERROR: Attempted to remove protected user 'main'"
        return 1
    fi
    
    log_message "ACTION: Removing user '$user_email'"
    
    # Проверяем существование пользователя перед удалением
    local user_exists=$(jq -r --arg email "$user_email" '.inbounds[0].settings.clients[] | select(.email == $email) | .email' "$CONFIG_FILE")
    
    if [[ -z "$user_exists" ]]; then
        log_message "ERROR: User '$user_email' not found in config"
        return 1
    fi
    
    # Удаляем пользователя ПО EMAIL через jq
    jq --arg email "$user_email" \
       '.inbounds[0].settings.clients |= map(select(.email != $email))' \
       "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
    
    if [ $? -eq 0 ]; then
        mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        systemctl restart xray
        
        if [ $? -eq 0 ]; then
            log_message "SUCCESS: User '$user_email' removed successfully - Time expired"
            
            # Отправить уведомление (если настроено)
            send_notification "🗑️ Удалён пользователь: $user_email" "Причина: истёк срок действия\nПрошло: ${age_hours}h / Лимит: ${time_limit}h"
            
            return 0
        else
            log_message "ERROR: Failed to restart Xray after removing '$user_email'"
            return 1
        fi
    else
        log_message "ERROR: Failed to remove user '$user_email' from config"
        rm -f "${CONFIG_FILE}.tmp"
        return 1
    fi
}

# Функция для отправки уведомлений (опционально)
send_notification() {
    local title="$1"
    local message="$2"
    
    # Telegram уведомление (если настроено)
    if [ -f /etc/xray/telegram.conf ]; then
        source /etc/xray/telegram.conf
        if [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                -d chat_id="${CHAT_ID}" \
                -d text="$title\n$message" \
                &>/dev/null
        fi
    fi
}

# Функция мониторинга с динамическим обновлением
monitor_users() {
    local time_limit_hours=$1
    local check_interval=$2
    
    log_message "=== Monitoring started. Time limit: ${time_limit_hours}h, Interval: ${check_interval}s ==="
    
    local check_count=0
    
    while true; do
        check_count=$((check_count + 1))
        
        # Очищаем экран для обновления
        clear_screen
        
        # Заголовок
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║           🔍 АВТОМАТИЧЕСКИЙ КОНТРОЛЬ ВРЕМЕНИ XRAY              ║${NC}"
        echo -e "${CYAN}║              (Single-Port Architecture)                        ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}⚙️  Настройки:${NC}"
        echo -e "   Лимит времени (без подписки): ${GREEN}${time_limit_hours} часов${NC}"
        echo -e "   Интервал проверки: ${GREEN}${check_interval} секунд${NC}"
        echo -e "   Лог файл: ${BLUE}${LOG_FILE}${NC}"
        echo -e "   Порт: ${CYAN}443${NC} (общий для всех пользователей)"
        echo ""
        
        local current_time=$(date '+%Y-%m-%d %H:%M:%S')
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}🔍 Проверка #${check_count} - ${current_time}${NC}"
        echo ""
        
        # Получаем список пользователей из clients array
        local clients=$(jq -c '.inbounds[0].settings.clients[]' "$CONFIG_FILE")
        
        if [[ -z "$clients" ]]; then
            echo -e "${YELLOW}⚠️  Нет активных пользователей${NC}"
            log_message "INFO: No active users found"
        else
            local users_checked=0
            local users_removed=0
            local users_ok=0
            
            # Проверяем каждого пользователя
            while IFS= read -r client; do
                local email=$(echo "$client" | jq -r '.email')
                local subscription=$(echo "$client" | jq -r '.metadata.subscription // "n/a"')
                local created_date=$(echo "$client" | jq -r '.metadata.created_date // "n/a"')
                
                # Получаем возраст пользователя в часах
                local age_hours="0"
                if [ "$created_date" != "n/a" ]; then
                    age_hours=$(get_user_age_hours "$created_date")
                fi
                
                local should_remove=false
                
                # Проверка: Истечение времени для пользователей без подписки
                if [ "$subscription" = "n" ] && [ "$created_date" != "n/a" ]; then
                    if (( $(echo "$age_hours >= $time_limit_hours" | bc -l) )); then
                        should_remove=true
                    fi
                fi
                
                # Удаляем пользователя если нужно
                if [ "$should_remove" = true ]; then
                    users_removed=$((users_removed + 1))
                    echo -e "${RED}❌ УДАЛЕНИЕ: $email${NC}"
                    echo -e "   Подписка: $subscription | Создан: $created_date"
                    echo -e "   Возраст: ${age_hours}h / Лимит: ${time_limit_hours}h"
                    echo ""
                    
                    remove_user_by_name "$email" "$age_hours" "$time_limit_hours"
                    
                    # После удаления обновляем список клиентов
                    clients=$(jq -c '.inbounds[0].settings.clients[]' "$CONFIG_FILE")
                else
                    users_ok=$((users_ok + 1))
                    # Пользователь в норме - краткий вывод
                    local time_status=""
                    
                    if [ "$subscription" = "n" ] && [ "$created_date" != "n/a" ]; then
                        local time_percent=$(echo "scale=1; $age_hours * 100 / $time_limit_hours" | bc)
                        local remaining=$(echo "scale=2; $time_limit_hours - $age_hours" | bc)
                        time_status="${age_hours}h/${time_limit_hours}h (${time_percent}%) | Осталось: ${remaining}h"
                    elif [ "$subscription" = "y" ]; then
                        time_status="Подписка: активна (∞)"
                    else
                        time_status="N/A"
                    fi
                    
                    echo -e "${GREEN}✓${NC} $email | $time_status"
                fi
                
                users_checked=$((users_checked + 1))
            done <<< "$clients"
            
            echo ""
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${CYAN}📊 Статистика:${NC}"
            echo -e "   Всего пользователей: ${CYAN}${users_checked}${NC}"
            echo -e "   В норме: ${GREEN}${users_ok}${NC}"
            if [ $users_removed -gt 0 ]; then
                echo -e "   Удалено за эту проверку: ${RED}${users_removed}${NC}"
            else
                echo -e "   Удалено за эту проверку: ${GREEN}0${NC}"
            fi
        fi
        
        echo ""
        echo -e "${BLUE}⏳ Следующая проверка через ${check_interval} секунд... (Ctrl+C для остановки)${NC}"
        
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
    echo -e "${YELLOW}Порт: 443 (общий для всех пользователей)${NC}"
    echo ""
    
    local clients=$(jq -c '.inbounds[0].settings.clients[]' "$CONFIG_FILE")
    
    if [[ -z "$clients" ]]; then
        echo -e "${YELLOW}⚠️  Нет активных пользователей${NC}"
        return 0
    fi
    
    printf "${BLUE}%-5s${NC} ${GREEN}%-20s${NC} ${CYAN}%-12s${NC} ${MAGENTA}%-15s${NC} ${WHITE}%-10s${NC}\n" \
        "#" "Пользователь" "Подписка" "Возраст" "Статус"
    echo "────────────────────────────────────────────────────────────────────────────────"
    
    local total_to_remove=0
    declare -a users_to_remove=()
    local user_number=1
    
    while IFS= read -r client; do
        local email=$(echo "$client" | jq -r '.email')
        local subscription=$(echo "$client" | jq -r '.metadata.subscription // "n/a"')
        local created_date=$(echo "$client" | jq -r '.metadata.created_date // "n/a"')
        
        # Получаем возраст
        local age_hours="0"
        if [ "$created_date" != "n/a" ]; then
            age_hours=$(get_user_age_hours "$created_date")
        fi
        
        local should_remove=false
        local status="OK"
        
        # Проверяем условия
        if [ "$subscription" = "n" ] && [ "$created_date" != "n/a" ]; then
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
            printf "%-5s %-20s %-12s ${RED}%-15s${NC} %b\n" \
                "$user_number" "$email" "$subscription" "${age_hours}h" "$status"
            total_to_remove=$((total_to_remove + 1))
            users_to_remove+=("$email|$age_hours")
        else
            local age_display="${age_hours}h"
            if [ "$subscription" = "y" ]; then
                age_display="${age_hours}h (∞)"
            fi
            printf "%-5s %-20s %-12s %-15s %b\n" \
                "$user_number" "$email" "$subscription" "$age_display" "$status"
        fi
        
        user_number=$((user_number + 1))
    done <<< "$clients"
    
    echo ""
    if [ $total_to_remove -gt 0 ]; then
        echo -e "${RED}⚠️  Пользователей для удаления: ${total_to_remove}${NC}"
        echo ""
        
        read -p "Удалить пользователей с истёкшим сроком? (y/n): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            for item in "${users_to_remove[@]}"; do
                IFS='|' read -r user_email user_age <<< "$item"
                echo -e "${RED}🗑️  Удаление: $user_email...${NC}"
                remove_user_by_name "$user_email" "$user_age" "$time_limit_hours"
            done
            
            echo ""
            echo -e "${GREEN}✅ Удаление завершено${NC}"
        else
            echo -e "${YELLOW}Удаление отменено${NC}"
        fi
    else
        echo -e "${GREEN}✅ Все пользователи в пределах лимита времени${NC}"
    fi
}

# Функция просмотра статуса всех пользователей
show_status() {
    local time_limit_hours=$1
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                 📊 СТАТУС ВСЕХ ПОЛЬЗОВАТЕЛЕЙ                  ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Лимит времени (без подписки): ${time_limit_hours} часов${NC}"
    echo -e "${YELLOW}Порт: 443 (общий для всех пользователей)${NC}"
    echo ""
    
    local clients=$(jq -c '.inbounds[0].settings.clients[]' "$CONFIG_FILE")
    
    if [[ -z "$clients" ]]; then
        echo -e "${YELLOW}⚠️  Нет активных пользователей${NC}"
        return 0
    fi
    
    echo "════════════════════════════════════════════════════════════════════════════════"
    
    local user_number=1
    
    while IFS= read -r client; do
        local email=$(echo "$client" | jq -r '.email')
        local subscription=$(echo "$client" | jq -r '.metadata.subscription // "n/a"')
        local created_date=$(echo "$client" | jq -r '.metadata.created_date // "n/a"')
        local uuid=$(echo "$client" | jq -r '.id')
        
        # Получаем возраст
        local age_hours="0"
        if [ "$created_date" != "n/a" ]; then
            age_hours=$(get_user_age_hours "$created_date")
        fi
        
        echo -e "${CYAN}[$user_number] $email${NC}"
        echo "   Порт: 443 (общий)"
        echo "   UUID: $uuid"
        echo "   Подписка: $subscription"
        echo "   Создан: $created_date"
        
        if [ "$subscription" = "n" ] && [ "$created_date" != "n/a" ]; then
            local remaining=$(echo "scale=2; $time_limit_hours - $age_hours" | bc)
            local percent=$(echo "scale=1; $age_hours * 100 / $time_limit_hours" | bc)
            
            if (( $(echo "$age_hours >= $time_limit_hours" | bc -l) )); then
                echo -e "   Возраст: ${RED}${age_hours}h${NC} (${percent}%)"
                echo -e "   Статус: ${RED}ИСТЁК СРОК${NC}"
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
        
        echo "────────────────────────────────────────────────────────────────────────────────"
        
        user_number=$((user_number + 1))
    done <<< "$clients"
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

# Функция настройки Telegram уведомлений
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
    
    # Тестовое уведомление
    read -p "Отправить тестовое уведомление? (y/n): " test
    if [ "$test" = "y" ]; then
        curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
            -d chat_id="${chat_id}" \
            -d text="✅ Xray Time Control: Тестовое уведомление" \
            &>/dev/null
        echo -e "${GREEN}✅ Тестовое сообщение отправлено${NC}"
    fi
}

# Главное меню
show_menu() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           🛡️  АВТОМАТИЧЕСКИЙ КОНТРОЛЬ ВРЕМЕНИ XRAY            ║${NC}"
    echo -e "${CYAN}║              (Single-Port Architecture)                        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo " 1) 🔄 Запустить мониторинг (непрерывный)"
    echo " 2) 🔍 Проверить сейчас (одноразово с удалением)"
    echo " 3) 📊 Показать статус всех пользователей"
    echo " 4) 📜 Показать логи"
    echo " 5) 📱 Настроить Telegram уведомления"
    echo " 6) ⚙️  Изменить настройки по умолчанию"
    echo " 0) ❌ Выход"
    echo ""
    read -p "Выберите действие: " choice
    
    case $choice in
        1)
            read -p "Лимит времени для пользователей без подписки в часах (по умолчанию $DEFAULT_TIME_LIMIT_HOURS): " time_limit
            time_limit=${time_limit:-$DEFAULT_TIME_LIMIT_HOURS}
            
            read -p "Интервал проверки в секундах (по умолчанию $DEFAULT_CHECK_INTERVAL): " interval
            interval=${interval:-$DEFAULT_CHECK_INTERVAL}
            
            monitor_users "$time_limit" "$interval"
            ;;
        2)
            read -p "Лимит времени для пользователей без подписки в часах (по умолчанию $DEFAULT_TIME_LIMIT_HOURS): " time_limit
            time_limit=${time_limit:-$DEFAULT_TIME_LIMIT_HOURS}
            
            check_once "$time_limit"
            ;;
        3)
            read -p "Лимит времени для справки в часах (по умолчанию $DEFAULT_TIME_LIMIT_HOURS): " time_limit
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
        6)
            echo ""
            read -p "Лимит времени по умолчанию в часах ($DEFAULT_TIME_LIMIT_HOURS): " new_time_limit
            new_time_limit=${new_time_limit:-$DEFAULT_TIME_LIMIT_HOURS}
            
            read -p "Интервал проверки по умолчанию в секундах ($DEFAULT_CHECK_INTERVAL): " new_interval
            new_interval=${new_interval:-$DEFAULT_CHECK_INTERVAL}
            
            # Сохраняем в конфиг
            mkdir -p /etc/xray
            cat > /etc/xray/time_control.conf << EOF
DEFAULT_TIME_LIMIT_HOURS=$new_time_limit
DEFAULT_CHECK_INTERVAL=$new_interval
EOF
            
            echo -e "${GREEN}✅ Настройки сохранены${NC}"
            DEFAULT_TIME_LIMIT_HOURS=$new_time_limit
            DEFAULT_CHECK_INTERVAL=$new_interval
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

# Проверка наличия необходимых утилит
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Ошибка: jq не установлен. Установите: apt install jq${NC}"
    exit 1
fi

if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}Установка bc...${NC}"
    apt-get update && apt-get install -y bc
fi

# Проверка наличия конфигурации Xray
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Ошибка: файл конфигурации Xray не найден: $CONFIG_FILE${NC}"
    exit 1
fi

# Загрузить конфиг если есть
if [ -f /etc/xray/time_control.conf ]; then
    source /etc/xray/time_control.conf
fi

# Если запущен с аргументами
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
        telegram|setup-telegram)
            setup_telegram
            ;;
        *)
            echo "Использование: $0 [monitor|check|status|logs|telegram] [параметры]"
            echo ""
            echo "Примеры:"
            echo "  $0 monitor 24 3600    - мониторинг: лимит 24ч, проверка каждые 3600 сек (1 час)"
            echo "  $0 monitor 0.5 1800   - мониторинг: лимит 30 минут, проверка каждые 30 минут"
            echo "  $0 monitor 0.1 600    - мониторинг: лимит 6 минут, проверка каждые 10 минут"
            echo "  $0 check 12           - проверить: лимит 12ч"
            echo "  $0 status 24          - показать статус с лимитом 24ч"
            echo "  $0 logs 50            - показать 50 последних строк лога"
            echo "  $0 telegram           - настроить Telegram"
            echo ""
            echo "Без аргументов запускается интерактивное меню"
            exit 1
            ;;
    esac
else
    # Интерактивное меню
    show_menu
fi
