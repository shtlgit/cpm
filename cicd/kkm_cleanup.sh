#!/bin/bash

CONTAINER_NAME="fmbipostgres"
DB_USER="fmbidb"
DB_NAME="fmbidb"
LOG_DIR="/opt/mergifai1/fermagbi/logs"
CURRENT_DATE=$(date '+%Y-%m-%d')
LOG_FILE="$LOG_DIR/kkm_cleanup_$CURRENT_DATE.log"

mkdir -p "$LOG_DIR"

echo "[$(date '+%H:%M:%S')] 🧹 Запуск ночной очистки KKM..." >> "$LOG_FILE"

# Запуск функции очистки
docker exec -i $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -c "SELECT dbo.daily_cleanup_kkm();" >> "$LOG_FILE" 2>&1

# Удаляем логи очистки старше 15 дней
find "$LOG_DIR" -name "kkm_cleanup_*.log" -type f -mtime +15 -delete

echo "[$(date '+%H:%M:%S')] ✨ Завершено." >> "$LOG_FILE"