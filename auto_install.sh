#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
# XRAY TIME CONTROL - АВТОМАТИЧЕСКИЙ УСТАНОВЩИК И ЗАПУСК
# ═══════════════════════════════════════════════════════════════════════════════
# Скачивает основной скрипт, устанавливает, настраивает и запускает systemd-сервис
# 
# Использование:
#   wget -O - https://raw.githubusercontent.com/LenderAuss/xray_users_monitor/main/auto_install.sh | sudo bash
#
# Или:
#   curl -fsSL https://raw.githubusercontent.com/LenderAuss/xray_users_monitor/main/auto_install.sh | sudo bash
# ═══════════════════════════════════════════════════════════════════════════════

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# URL основного скрипта
MAIN_SCRIPT_URL="https://raw.githubusercontent.com/LenderAuss/xray_users_monitor/main/xray_time_control.sh"

# Пути установки
INSTALL_PATH="/usr/local/bin/xray-time-control"
SERVICE_NAME="xray-time-control"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
CONFIG_DIR="/etc/xray"
CONFIG_FILE="${CONFIG_DIR}/time_control.conf"
LOG_FILE="/var/log/xray_time_control.log"

# Очистка экрана и приветствие
clear
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         🛡️  XRAY TIME CONTROL - АВТОМАТИЧЕСКАЯ УСТАНОВКА                     ║${NC}"
echo -e "${CYAN}║             Автоматическое управление временем жизни пользователей            ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Функция для вывода с анимацией
log_step() {
    echo -e "${BLUE}▶${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    log_error "Требуются права root!"
    echo -e "${YELLOW}Запустите: ${CYAN}wget -O - $MAIN_SCRIPT_URL | sudo bash${NC}"
    exit 1
fi

log_success "Права root подтверждены"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# ШАГ 1: ПРОВЕРКА И УСТАНОВКА ЗАВИСИМОСТЕЙ
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[1/6]${NC} 📦 Проверка зависимостей..."

missing_deps=()

for cmd in jq bc curl systemctl; do
    if ! command -v $cmd &> /dev/null; then
        missing_deps+=("$cmd")
    fi
done

if [ ${#missing_deps[@]} -gt 0 ]; then
    log_warning "Не хватает пакетов: ${missing_deps[*]}"
    log_step "Устанавливаю недостающие пакеты..."
    
    apt-get update -qq
    apt-get install -y -qq jq bc curl systemd &>/dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Все зависимости установлены"
    else
        log_error "Ошибка установки зависимостей"
        exit 1
    fi
else
    log_success "Все зависимости уже установлены"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# ШАГ 2: СКАЧИВАНИЕ ОСНОВНОГО СКРИПТА
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[2/6]${NC} 📥 Скачивание основного скрипта..."

curl -fsSL "$MAIN_SCRIPT_URL" -o "$INSTALL_PATH"

if [ $? -eq 0 ] && [ -f "$INSTALL_PATH" ]; then
    chmod +x "$INSTALL_PATH"
    log_success "Скрипт скачан и установлен: $INSTALL_PATH"
else
    log_error "Не удалось скачать скрипт с GitHub"
    log_warning "Проверьте URL: $MAIN_SCRIPT_URL"
    exit 1
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# ШАГ 3: СОЗДАНИЕ КОНФИГУРАЦИИ
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[3/6]${NC} ⚙️  Создание конфигурации..."

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" << 'EOF'
# ═══════════════════════════════════════════════════════════════════════════════
# КОНФИГУРАЦИЯ XRAY TIME CONTROL
# ═══════════════════════════════════════════════════════════════════════════════

# ⚠️  ТЕСТОВЫЕ НАСТРОЙКИ (ДЛЯ ПРОВЕРКИ РАБОТЫ)
# После проверки измени эти значения для продакшена!

# Лимит времени для пользователей без подписки (в часах)
# Текущее: 0.1 часа = 6 минут (для быстрого теста)
# Рекомендуемое для прода: 24 (сутки) или 720 (месяц)
DEFAULT_TIME_LIMIT_HOURS=0.1

# Интервал проверки (в секундах)
# Текущее: 60 секунд = 1 минута (для быстрого теста)
# Рекомендуемое для прода: 3600 (1 час) или 7200 (2 часа)
DEFAULT_CHECK_INTERVAL=60

# ═══════════════════════════════════════════════════════════════════════════════
# КАК ИЗМЕНИТЬ ДЛЯ ПРОДАКШЕНА:
# 
# sudo nano /etc/xray/time_control.conf
# 
# Измени значения выше на:
#   DEFAULT_TIME_LIMIT_HOURS=24
#   DEFAULT_CHECK_INTERVAL=3600
#
# Затем перезапусти сервис:
#   sudo systemctl restart xray-time-control
# ═══════════════════════════════════════════════════════════════════════════════
EOF

chmod 644 "$CONFIG_FILE"
log_success "Конфигурация создана: $CONFIG_FILE"
log_warning "ВАЖНО: Тестовые настройки (6 минут лимит, проверка каждую минуту)"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# ШАГ 4: СОЗДАНИЕ SYSTEMD-СЕРВИСА
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[4/6]${NC} 🔧 Создание systemd-сервиса..."

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Xray Time Control Service - Automatic User Expiration Management
Documentation=https://github.com/LenderAuss/xray_users_monitor
After=network.target xray.service
Wants=xray.service

[Service]
Type=simple
User=root
Group=root

# Запуск в режиме непрерывного мониторинга
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

log_success "Systemd-сервис создан: $SERVICE_FILE"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# ШАГ 5: НАСТРОЙКА ЛОГИРОВАНИЯ
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[5/6]${NC} 📝 Настройка логирования..."

touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

log_success "Лог-файл создан: $LOG_FILE"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# ШАГ 6: ЗАПУСК СЕРВИСА
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[6/6]${NC} 🚀 Запуск сервиса..."

# Перезагружаем systemd
systemctl daemon-reload

# Включаем автозапуск
systemctl enable "$SERVICE_NAME" &>/dev/null

# Запускаем сервис
systemctl start "$SERVICE_NAME"

# Ждем немного
sleep 2

# Проверяем статус
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log_success "Сервис успешно запущен и работает!"
else
    log_error "Ошибка запуска сервиса"
    echo ""
    echo -e "${YELLOW}Проверьте статус: ${CYAN}systemctl status $SERVICE_NAME${NC}"
    echo -e "${YELLOW}Логи: ${CYAN}journalctl -u $SERVICE_NAME -n 50${NC}"
    exit 1
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# ФИНАЛЬНАЯ ИНФОРМАЦИЯ
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    ✅ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${MAGENTA}🎉 Xray Time Control Service установлен и запущен!${NC}"
echo ""

# Показываем статус
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}📊 ТЕКУЩИЙ СТАТУС:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

systemctl status "$SERVICE_NAME" --no-pager -l | head -n 10

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}⚙️  УСТАНОВЛЕННЫЕ КОМПОНЕНТЫ:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "   Сервис:   ${GREEN}$SERVICE_NAME${NC}"
echo -e "   Скрипт:   ${GREEN}$INSTALL_PATH${NC}"
echo -e "   Конфиг:   ${GREEN}$CONFIG_FILE${NC}"
echo -e "   Логи:     ${GREEN}$LOG_FILE${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}⚙️  ТЕКУЩИЕ НАСТРОЙКИ (ТЕСТОВЫЕ):${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "   Лимит времени:      ${RED}0.1 часа (6 минут)${NC} ${YELLOW}⚠️  ДЛЯ ТЕСТА${NC}"
echo -e "   Интервал проверки:  ${RED}60 секунд (1 минута)${NC} ${YELLOW}⚠️  ДЛЯ ТЕСТА${NC}"
echo ""

echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                    ⚠️  ВАЖНО ДЛЯ ПРОДАКШЕНА!                                 ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Сейчас установлены ТЕСТОВЫЕ настройки для проверки работы:${NC}"
echo -e "   ${RED}• Пользователи без подписки удаляются через 6 минут${NC}"
echo -e "   ${RED}• Проверка происходит каждую минуту${NC}"
echo ""
echo -e "${GREEN}Для продакшена измени настройки:${NC}"
echo ""
echo -e "   ${CYAN}1.${NC} Открой конфиг:"
echo -e "      ${CYAN}sudo nano $CONFIG_FILE${NC}"
echo ""
echo -e "   ${CYAN}2.${NC} Измени значения:"
echo -e "      ${YELLOW}DEFAULT_TIME_LIMIT_HOURS=0.1${NC}  →  ${GREEN}24${NC}    ${BLUE}(или 720 для месяца)${NC}"
echo -e "      ${YELLOW}DEFAULT_CHECK_INTERVAL=60${NC}     →  ${GREEN}3600${NC}  ${BLUE}(или 7200 для 2 часов)${NC}"
echo ""
echo -e "   ${CYAN}3.${NC} Сохрани: ${BLUE}Ctrl+O, Enter, Ctrl+X${NC}"
echo ""
echo -e "   ${CYAN}4.${NC} Перезапусти сервис:"
echo -e "      ${CYAN}sudo systemctl restart xray-time-control${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔧 ОСНОВНЫЕ КОМАНДЫ:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "   Статус:      ${CYAN}systemctl status xray-time-control${NC}"
echo -e "   Остановить:  ${CYAN}systemctl stop xray-time-control${NC}"
echo -e "   Запустить:   ${CYAN}systemctl start xray-time-control${NC}"
echo -e "   Перезапуск:  ${CYAN}systemctl restart xray-time-control${NC}"
echo ""
echo -e "   Логи (live): ${CYAN}journalctl -u xray-time-control -f${NC}"
echo -e "   Логи (файл): ${CYAN}tail -f $LOG_FILE${NC}"
echo ""
echo -e "   Интерактивно: ${CYAN}xray-time-control${NC}"
echo -e "   Проверить:    ${CYAN}xray-time-control check${NC}"
echo -e "   Статус всех:  ${CYAN}xray-time-control status${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Автозапуск настроен - сервис будет запускаться после перезагрузки${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${MAGENTA}🚀 Сервис работает! Можешь проверить логи прямо сейчас:${NC}"
echo -e "   ${CYAN}journalctl -u xray-time-control -f${NC}"
echo ""
