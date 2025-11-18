#!/bin/bash

# Установочный скрипт для Xray Time Control Service
# Автоматизированная установка и настройка systemd-сервиса

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Пути
SCRIPT_NAME="xray_time_control.sh"
INSTALL_PATH="/usr/local/bin/xray-time-control"
SERVICE_NAME="xray-time-control"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
CONFIG_DIR="/etc/xray"
CONFIG_FILE="${CONFIG_DIR}/time_control.conf"
LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/xray_time_control.log"

# URL скрипта (замени на свой GitHub raw URL)
SCRIPT_URL="https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/xray_time_control.sh"

# Функция проверки прав root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}❌ Запустите скрипт с правами root (sudo)${NC}"
        exit 1
    fi
}

# Функция проверки зависимостей
check_dependencies() {
    echo -e "${CYAN}🔍 Проверка зависимостей...${NC}"
    
    local missing_deps=()
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v bc &> /dev/null; then
        missing_deps+=("bc")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}📦 Установка недостающих пакетов: ${missing_deps[*]}${NC}"
        apt-get update
        apt-get install -y "${missing_deps[@]}"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Зависимости установлены${NC}"
        else
            echo -e "${RED}❌ Ошибка установки зависимостей${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}✅ Все зависимости установлены${NC}"
    fi
}

# Функция установки скрипта
install_script() {
    echo -e "${CYAN}📥 Установка скрипта...${NC}"
    
    # Если скрипт в текущей директории
    if [ -f "./${SCRIPT_NAME}" ]; then
        echo -e "${BLUE}   Копирование локального скрипта...${NC}"
        cp "./${SCRIPT_NAME}" "$INSTALL_PATH"
    # Иначе скачиваем с GitHub
    elif [ -n "$SCRIPT_URL" ] && [[ "$SCRIPT_URL" != *"YOUR_USERNAME"* ]]; then
        echo -e "${BLUE}   Скачивание с GitHub...${NC}"
        curl -fsSL "$SCRIPT_URL" -o "$INSTALL_PATH"
    else
        echo -e "${RED}❌ Скрипт не найден. Поместите ${SCRIPT_NAME} в текущую директорию${NC}"
        exit 1
    fi
    
    # Проверка успешности
    if [ ! -f "$INSTALL_PATH" ]; then
        echo -e "${RED}❌ Не удалось установить скрипт${NC}"
        exit 1
    fi
    
    # Даем права на выполнение
    chmod +x "$INSTALL_PATH"
    echo -e "${GREEN}✅ Скрипт установлен: $INSTALL_PATH${NC}"
}

# Функция создания конфигурации
create_config() {
    echo -e "${CYAN}⚙️  Создание конфигурации...${NC}"
    
    # Создаем директорию если не существует
    mkdir -p "$CONFIG_DIR"
    
    # Создаем конфиг с настройками
    cat > "$CONFIG_FILE" << 'EOF'
# Конфигурация Xray Time Control
# Лимит времени для пользователей без подписки (в часах)
# ⚠️ ИЗМЕНИ ЭТО ЗНАЧЕНИЕ ДЛЯ ПРОДАКШЕНА ⚠️
# Текущее значение: 0.1 часа (6 минут) - для тестирования
# Рекомендуемое для прода: 24 (сутки) или 720 (месяц)
DEFAULT_TIME_LIMIT_HOURS=0.1

# Интервал проверки (в секундах)
# ⚠️ ИЗМЕНИ ЭТО ЗНАЧЕНИЕ ДЛЯ ПРОДАКШЕНА ⚠️
# Текущее значение: 60 секунд (1 минута) - для тестирования
# Рекомендуемое для прода: 3600 (1 час) или 7200 (2 часа)
DEFAULT_CHECK_INTERVAL=60
EOF
    
    chmod 644 "$CONFIG_FILE"
    echo -e "${GREEN}✅ Конфигурация создана: $CONFIG_FILE${NC}"
    echo -e "${YELLOW}⚠️  ВАЖНО: Для продакшена измени настройки в файле:${NC}"
    echo -e "${YELLOW}   $CONFIG_FILE${NC}"
}

# Функция создания systemd-сервиса
create_service() {
    echo -e "${CYAN}🔧 Создание systemd-сервиса...${NC}"
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Xray Time Control Service - Automatic User Expiration Management
Documentation=https://github.com/YOUR_USERNAME/YOUR_REPO
After=network.target xray.service
Wants=xray.service

[Service]
Type=simple
User=root
Group=root

# Запуск в режиме непрерывного мониторинга
# Параметры берутся из конфигурационного файла
ExecStart=$INSTALL_PATH monitor

# Автоматический перезапуск при падении
Restart=always
RestartSec=10

# Ограничения ресурсов
CPUQuota=20%
MemoryLimit=128M

# Логирование
StandardOutput=journal
StandardError=journal
SyslogIdentifier=xray-time-control

# Безопасность
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    echo -e "${GREEN}✅ Systemd-сервис создан: $SERVICE_FILE${NC}"
}

# Функция создания директории логов
setup_logging() {
    echo -e "${CYAN}📝 Настройка логирования...${NC}"
    
    # Создаем лог-файл если не существует
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    echo -e "${GREEN}✅ Лог-файл готов: $LOG_FILE${NC}"
}

# Функция включения и запуска сервиса
enable_service() {
    echo -e "${CYAN}🚀 Включение и запуск сервиса...${NC}"
    
    # Перезагружаем systemd
    systemctl daemon-reload
    
    # Включаем автозапуск
    systemctl enable "$SERVICE_NAME"
    
    # Запускаем сервис
    systemctl start "$SERVICE_NAME"
    
    # Проверяем статус
    sleep 2
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}✅ Сервис успешно запущен и работает${NC}"
    else
        echo -e "${RED}❌ Ошибка запуска сервиса${NC}"
        echo -e "${YELLOW}Проверьте статус: systemctl status $SERVICE_NAME${NC}"
        exit 1
    fi
}

# Функция показа финальной информации
show_summary() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              ✅ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА                   ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}🎉 Xray Time Control Service установлен и запущен!${NC}"
    echo ""
    echo -e "${YELLOW}📋 ОСНОВНАЯ ИНФОРМАЦИЯ:${NC}"
    echo -e "   Сервис: ${CYAN}$SERVICE_NAME${NC}"
    echo -e "   Скрипт: ${CYAN}$INSTALL_PATH${NC}"
    echo -e "   Конфиг: ${CYAN}$CONFIG_FILE${NC}"
    echo -e "   Лог:    ${CYAN}$LOG_FILE${NC}"
    echo ""
    echo -e "${YELLOW}⚙️  ТЕКУЩИЕ НАСТРОЙКИ (ТЕСТОВЫЕ):${NC}"
    echo -e "   Лимит времени: ${RED}0.1 часа (6 минут)${NC} ⚠️  ДЛЯ ТЕСТА"
    echo -e "   Интервал проверки: ${RED}60 секунд${NC} ⚠️  ДЛЯ ТЕСТА"
    echo ""
    echo -e "${RED}⚠️  ВАЖНО ДЛЯ ПРОДАКШЕНА:${NC}"
    echo -e "${YELLOW}   Измени настройки в файле: $CONFIG_FILE${NC}"
    echo -e "${YELLOW}   Рекомендуемые значения для прода:${NC}"
    echo -e "   - DEFAULT_TIME_LIMIT_HOURS=24 (или 720 для месяца)"
    echo -e "   - DEFAULT_CHECK_INTERVAL=3600 (или 7200 для 2 часов)"
    echo ""
    echo -e "${YELLOW}🔧 УПРАВЛЕНИЕ СЕРВИСОМ:${NC}"
    echo -e "   Статус:      ${CYAN}systemctl status $SERVICE_NAME${NC}"
    echo -e "   Остановить:  ${CYAN}systemctl stop $SERVICE_NAME${NC}"
    echo -e "   Запустить:   ${CYAN}systemctl start $SERVICE_NAME${NC}"
    echo -e "   Перезапуск:  ${CYAN}systemctl restart $SERVICE_NAME${NC}"
    echo -e "   Отключить:   ${CYAN}systemctl disable $SERVICE_NAME${NC}"
    echo ""
    echo -e "${YELLOW}📊 ПРОСМОТР ЛОГОВ:${NC}"
    echo -e "   Реал-тайм:   ${CYAN}journalctl -u $SERVICE_NAME -f${NC}"
    echo -e "   Последние:   ${CYAN}journalctl -u $SERVICE_NAME -n 50${NC}"
    echo -e "   Файл:        ${CYAN}tail -f $LOG_FILE${NC}"
    echo ""
    echo -e "${YELLOW}🛠️  РУЧНОЕ УПРАВЛЕНИЕ:${NC}"
    echo -e "   Интерактивно: ${CYAN}$INSTALL_PATH${NC}"
    echo -e "   Проверка:     ${CYAN}$INSTALL_PATH check${NC}"
    echo -e "   Статус:       ${CYAN}$INSTALL_PATH status${NC}"
    echo ""
    echo -e "${GREEN}✅ Сервис автоматически запустится после перезагрузки системы${NC}"
    echo ""
}

# Главная функция установки
main() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         🚀 УСТАНОВКА XRAY TIME CONTROL SERVICE                ║${NC}"
    echo -e "${CYAN}║           Автоматическое управление временем жизни            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_root
    check_dependencies
    install_script
    create_config
    setup_logging
    create_service
    enable_service
    show_summary
}

# Запуск установки
main
