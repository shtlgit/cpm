#!/bin/bash

# Конфигурация
CONTAINER_NAME="fmbipostgres"
DB_USER="fmbidb"
DB_NAME="fmbidb"
LOG_DIR="/opt/mergifai1/fermagbi/logs"
CURRENT_DATE=$(date '+%Y-%m-%d')
LOG_FILE="$LOG_DIR/kkm_sync_$CURRENT_DATE.log"

# Создаем папку для логов, если её нет
mkdir -p "$LOG_DIR"

echo "[$(date '+%H:%M:%S')] 🚀 Запуск обновления..." >> "$LOG_FILE"

# 1. Проверка контейнера
if [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null)" != "true" ]; then
    echo "[$(date '+%H:%M:%S')] ❌ Ошибка: Контейнер $CONTAINER_NAME не запущен." >> "$LOG_FILE"
    exit 1
fi

# 2. Запуск функции в БД
docker exec -i $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME --set ON_ERROR_STOP=1 -c "SELECT dbo.incremental_refresh_kkm();" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "[$(date '+%H:%M:%S')] ✅ Успешно." >> "$LOG_FILE"
else
    echo "[$(date '+%H:%M:%S')] ❌ Ошибка выполнения SQL." >> "$LOG_FILE"
fi

# 3. Ротация: Удаляем логи старше 15 дней
find "$LOG_DIR" -name "kkm_sync_*.log" -type f -mtime +15 -delete

echo "------------------------------------------" >> "$LOG_FILE"