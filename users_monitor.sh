#!/bin/bash

# Скрипт управления автоматическим удалением пользователей без подписки
# Скачивание: wget -O cleanup_menu.sh https://raw.githubusercontent.com/YOUR_REPO/cleanup_menu.sh && chmod +x cleanup_menu.sh && ./cleanup_menu.sh

LOG_FILE="/var/log/xray_user_cleanup.log"
CONFIG_FILE="/usr/local/etc/xray/config.json"
SCRIPT_PATH="/usr/local/bin/cleanup_users.sh"
SERVICE_FILE="/etc/systemd/system/xray-cleanup.service"
TIMER_FILE="/etc/systemd/system/xray-cleanup.timer"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция вывода заголовка
print_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}   Управление автоудалением пользователей Xray   ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Функция создания скрипта очистки
create_cleanup_script() {
    cat > "$SCRIPT_PATH" << 'CLEANUP_SCRIPT'
#!/bin/bash

LOG_FILE="/var/log/xray_user_cleanup.log"
CONFIG_FILE="/usr/local/etc/xray/config.json"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_message "ERROR: Конфиг $CONFIG_FILE не найден"
    exit 1
fi

log_message "==== Начало проверки пользователей ===="

clients=$(jq -c '.inbounds[0].settings.clients[]' "$CONFIG_FILE")

if [[ -z "$clients" ]]; then
    log_message "Список клиентов пуст"
    exit 0
fi

total_users=0
deleted_users=0
protected_users=0

while IFS= read -r client; do
    email=$(echo "$client" | jq -r '.email')
    subscription=$(echo "$client" | jq -r '.metadata.subscription // "n"')
    
    ((total_users++))
    
    if [[ "$email" == "main" ]]; then
        log_message "INFO: Пользователь '$email' защищен от удаления"
        ((protected_users++))
        continue
    fi
    
    if [[ "$subscription" == "n" ]]; then
        log_message "WARNING: Удаление пользователя '$email' (подписка неактивна)"
        
        jq --arg email "$email" \
           '(.inbounds[0].settings.clients) |= map(select(.email != $email))' \
           "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        
        ((deleted_users++))
        log_message "SUCCESS: Пользователь '$email' удален"
    else
        log_message "INFO: Пользователь '$email' имеет активную подписку"
    fi
done <<< "$clients"

log_message "==== Статистика ===="
log_message "Всего пользователей: $total_users"
log_message "Удалено: $deleted_users"
log_message "Защищено: $protected_users"
log_message "Активных: $((total_users - deleted_users))"

if [[ $deleted_users -gt 0 ]]; then
    log_message "INFO: Перезапуск Xray..."
    systemctl restart xray
    if [[ $? -eq 0 ]]; then
        log_message "SUCCESS: Xray успешно перезапущен"
    else
        log_message "ERROR: Ошибка при перезапуске Xray"
        exit 1
    fi
else
    log_message "INFO: Изменений нет, перезапуск не требуется"
fi

log_message "==== Проверка завершена ===="
CLEANUP_SCRIPT

    chmod +x "$SCRIPT_PATH"
    echo -e "${GREEN}✓${NC} Скрипт очистки создан: $SCRIPT_PATH"
}

# Функция создания systemd service
create_service() {
    cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=Xray User Cleanup Service
After=xray.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cleanup_users.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    echo -e "${GREEN}✓${NC} Service создан: $SERVICE_FILE"
}

# Функция создания systemd timer
create_timer() {
    cat > "$TIMER_FILE" << 'EOF'
[Unit]
Description=Xray User Cleanup Timer
Requires=xray-cleanup.service

[Timer]
OnCalendar=daily
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    echo -e "${GREEN}✓${NC} Timer создан: $TIMER_FILE"
}

# Установка системы автоудаления
install_cleanup() {
    print_header
    echo -e "${YELLOW}Установка системы автоудаления...${NC}"
    echo ""
    
    # Проверка зависимостей
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}✗${NC} jq не установлен. Устанавливаю..."
        apt update && apt install -y jq
    fi
    
    # Создание компонентов
    create_cleanup_script
    create_service
    create_timer
    
    # Активация
    systemctl daemon-reload
    systemctl enable xray-cleanup.timer
    systemctl start xray-cleanup.timer
    
    echo ""
    echo -e "${GREEN}✓ Система автоудаления успешно установлена!${NC}"
    echo -e "  Запуск: каждый день в 03:00"
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Удаление системы автоудаления
uninstall_cleanup() {
    print_header
    echo -e "${YELLOW}Удаление системы автоудаления...${NC}"
    echo ""
    
    systemctl stop xray-cleanup.timer 2>/dev/null
    systemctl disable xray-cleanup.timer 2>/dev/null
    
    rm -f "$SCRIPT_PATH"
    rm -f "$SERVICE_FILE"
    rm -f "$TIMER_FILE"
    
    systemctl daemon-reload
    
    echo -e "${GREEN}✓ Система автоудаления удалена${NC}"
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Ручной запуск очистки
manual_cleanup() {
    print_header
    echo -e "${YELLOW}Запуск ручной очистки пользователей...${NC}"
    echo ""
    
    if [[ ! -f "$SCRIPT_PATH" ]]; then
        echo -e "${RED}✗${NC} Скрипт очистки не найден. Сначала установите систему."
        echo ""
        read -p "Нажмите Enter для продолжения..."
        return
    fi
    
    bash "$SCRIPT_PATH"
    
    echo ""
    echo -e "${GREEN}✓ Очистка завершена${NC}"
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Просмотр логов
view_logs() {
    print_header
    echo -e "${YELLOW}Логи автоудаления (последние 50 строк):${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [[ -f "$LOG_FILE" ]]; then
        tail -n 50 "$LOG_FILE"
    else
        echo -e "${YELLOW}Лог-файл пуст или не найден${NC}"
    fi
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Просмотр статуса
view_status() {
    print_header
    echo -e "${YELLOW}Статус системы автоудаления:${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Проверка установки
    if [[ -f "$SCRIPT_PATH" ]] && [[ -f "$SERVICE_FILE" ]] && [[ -f "$TIMER_FILE" ]]; then
        echo -e "Установка: ${GREEN}✓ Установлена${NC}"
    else
        echo -e "Установка: ${RED}✗ Не установлена${NC}"
        echo ""
        read -p "Нажмите Enter для продолжения..."
        return
    fi
    
    # Статус таймера
    echo ""
    echo -e "${BLUE}Статус таймера:${NC}"
    systemctl status xray-cleanup.timer --no-pager | head -n 10
    
    # Следующий запуск
    echo ""
    echo -e "${BLUE}Расписание:${NC}"
    systemctl list-timers xray-cleanup.timer --no-pager
    
    # Статистика из лога
    if [[ -f "$LOG_FILE" ]]; then
        echo ""
        echo -e "${BLUE}Последняя статистика:${NC}"
        grep "Статистика" "$LOG_FILE" -A 4 | tail -n 5
    fi
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Настройка расписания
configure_schedule() {
    print_header
    echo -e "${YELLOW}Настройка расписания автоудаления${NC}"
    echo ""
    echo "Выберите вариант:"
    echo "  1) Каждый час"
    echo "  2) Каждые 6 часов"
    echo "  3) Каждый день в 03:00 (по умолчанию)"
    echo "  4) Каждую неделю"
    echo "  5) Свое расписание"
    echo "  0) Назад"
    echo ""
    read -p "Ваш выбор: " choice
    
    case $choice in
        1)
            schedule="OnCalendar=hourly"
            ;;
        2)
            schedule="OnCalendar=*-*-* 00,06,12,18:00:00"
            ;;
        3)
            schedule="OnCalendar=*-*-* 03:00:00"
            ;;
        4)
            schedule="OnCalendar=weekly"
            ;;
        5)
            echo ""
            echo "Примеры форматов:"
            echo "  *-*-* 02:00:00  - каждый день в 2:00"
            echo "  *-*-* 00:00:00  - каждый день в полночь"
            echo "  Mon *-*-* 00:00:00 - каждый понедельник в полночь"
            echo ""
            read -p "Введите расписание: " custom_schedule
            schedule="OnCalendar=$custom_schedule"
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}Неверный выбор${NC}"
            sleep 2
            return
            ;;
    esac
    
    # Обновляем timer
    cat > "$TIMER_FILE" << EOF
[Unit]
Description=Xray User Cleanup Timer
Requires=xray-cleanup.service

[Timer]
$schedule
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    systemctl restart xray-cleanup.timer
    
    echo ""
    echo -e "${GREEN}✓ Расписание обновлено${NC}"
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Главное меню
main_menu() {
    while true; do
        print_header
        
        # Показываем статус
        if [[ -f "$TIMER_FILE" ]]; then
            timer_status=$(systemctl is-active xray-cleanup.timer)
            if [[ "$timer_status" == "active" ]]; then
                echo -e "Статус: ${GREEN}●${NC} Активна"
            else
                echo -e "Статус: ${RED}●${NC} Неактивна"
            fi
        else
            echo -e "Статус: ${YELLOW}●${NC} Не установлена"
        fi
        
        echo ""
        echo "Выберите действие:"
        echo ""
        echo "  1) Установить систему автоудаления"
        echo "  2) Удалить систему автоудаления"
        echo "  3) Запустить очистку вручную"
        echo "  4) Просмотреть логи"
        echo "  5) Статус системы"
        echo "  6) Настроить расписание"
        echo "  0) Выход"
        echo ""
        read -p "Ваш выбор: " choice
        
        case $choice in
            1) install_cleanup ;;
            2) uninstall_cleanup ;;
            3) manual_cleanup ;;
            4) view_logs ;;
            5) view_status ;;
            6) configure_schedule ;;
            0) 
                clear
                echo -e "${GREEN}До свидания!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Неверный выбор. Попробуйте снова.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Запуск главного меню
main_menu
