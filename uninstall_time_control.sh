#!/bin/bash

# Скрипт удаления Xray Time Control Service

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Пути
INSTALL_PATH="/usr/local/bin/xray-time-control"
SERVICE_NAME="xray-time-control"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
CONFIG_DIR="/etc/xray"
CONFIG_FILE="${CONFIG_DIR}/time_control.conf"
TELEGRAM_CONFIG="${CONFIG_DIR}/telegram.conf"
LOG_FILE="/var/log/xray_time_control.log"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Запустите скрипт с правами root (sudo)${NC}"
    exit 1
fi

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         🗑️  УДАЛЕНИЕ XRAY TIME CONTROL SERVICE                ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Подтверждение
read -p "Вы уверены, что хотите удалить сервис? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}Удаление отменено${NC}"
    exit 0
fi

echo ""
echo -e "${CYAN}🛑 Остановка и отключение сервиса...${NC}"

# Остановка сервиса
if systemctl is-active --quiet "$SERVICE_NAME"; then
    systemctl stop "$SERVICE_NAME"
    echo -e "${GREEN}✅ Сервис остановлен${NC}"
fi

# Отключение автозапуска
if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl disable "$SERVICE_NAME"
    echo -e "${GREEN}✅ Автозапуск отключен${NC}"
fi

# Удаление systemd-сервиса
if [ -f "$SERVICE_FILE" ]; then
    rm -f "$SERVICE_FILE"
    echo -e "${GREEN}✅ Systemd-сервис удален${NC}"
fi

# Перезагрузка systemd
systemctl daemon-reload
systemctl reset-failed

# Удаление скрипта
if [ -f "$INSTALL_PATH" ]; then
    rm -f "$INSTALL_PATH"
    echo -e "${GREEN}✅ Исполняемый файл удален${NC}"
fi

# Спрашиваем про конфигурацию
echo ""
read -p "Удалить файлы конфигурации? (y/n): " remove_config
if [ "$remove_config" = "y" ]; then
    [ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE" && echo -e "${GREEN}✅ Конфиг удален${NC}"
    [ -f "$TELEGRAM_CONFIG" ] && rm -f "$TELEGRAM_CONFIG" && echo -e "${GREEN}✅ Telegram конфиг удален${NC}"
fi

# Спрашиваем про логи
echo ""
read -p "Удалить лог-файлы? (y/n): " remove_logs
if [ "$remove_logs" = "y" ]; then
    [ -f "$LOG_FILE" ] && rm -f "$LOG_FILE" && echo -e "${GREEN}✅ Логи удалены${NC}"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅ УДАЛЕНИЕ УСПЕШНО ЗАВЕРШЕНО                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Xray Time Control Service полностью удален${NC}"
echo ""
