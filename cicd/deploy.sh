#!/bin/bash
set -e

### === Конфигурация ===
MB_URL="http://192.168.137.15:3000"
MB_USER="fmbidb@fermag.kz"
MB_PASS="qwe12345678~"
PG_CONTAINER="fmbipostgres"
PG_DB="fmbidb"
PG_USER="fmbidb"
PG_PASS="qwe12345678~"
BACKUP_DIR="/mnt/backups/metabase"
GIT_REPO_DIR="/opt/mergifai1/fermagbi"

RELEASE_VER=$1
if [ -z "$RELEASE_VER" ]; then
    echo "❌ Ошибка: Укажите версию (например: ./deploy.sh v2025.12.25)"
    exit 1
fi

REL_DIR="$GIT_REPO_DIR/exports/$RELEASE_VER"

# Функция для обновления статуса в БД
update_registry() {
    local status=$1
    docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -c \
    "INSERT INTO replset.release_registry (release_version, status, created_at) VALUES ('$RELEASE_VER', '$status', CURRENT_TIMESTAMP) 
     ON CONFLICT (release_version) DO UPDATE SET status = '$status', updated_at = CURRENT_TIMESTAMP;" > /dev/null
}

echo "🚀 Запуск деплоя версии $RELEASE_VER"
update_registry "deploying"

# 1. Бэкап
echo "💾 Создание бэкапа перед деплоем..."
BACKUP_FILE="$BACKUP_DIR/backup_${RELEASE_VER}_$(date +%F_%H%M).sql"
if ! docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" pg_dump -U "$PG_USER" -d "$PG_DB" -F c > "$BACKUP_FILE"; then
    echo "❌ Ошибка при создании бэкапа"
    update_registry "backup_failed"
    exit 1
fi

# 2. Авторизация в Metabase
SESSION=$(curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"username\": \"$MB_USER\", \"password\": \"$MB_PASS\"}" \
  $MB_URL/api/session | jq -r '.id')

# Перехват ошибок для отката
trap 'echo "⚠️ Критическая ошибка. Выполняю откат..."; docker exec -i -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" pg_restore -U "$PG_USER" -d "$PG_DB" --clean < "$BACKUP_FILE"; update_registry "rolled_back"; exit 1' ERR

# 3. ПРИМЕНЕНИЕ SQL
echo "⚙️ Применение SQL структур..."
for sql_f in $(find "$REL_DIR" -name "*.sql" | sort); do
    echo "  ➡️ Выполняю $(basename "$sql_f")"
    docker cp "$sql_f" "$PG_CONTAINER:/tmp/deploy.sql"
    docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -f /tmp/deploy.sql
done

# 4. ИМПОРТ METABASE (Cards -> Dashboards)
echo "📊 Обновление Metabase..."
# Карточки
for json_f in $(find "$REL_DIR" -name "card_*.json" | sort); do
    echo "  ➡️ Импорт карточки: $(basename "$json_f")"
    curl -s -f -X POST -H "X-Metabase-Session: $SESSION" -H "Content-Type: application/json" \
         -d @"$json_f" "$MB_URL/api/card" > /dev/null
done

# Дашборды
for json_f in $(find "$REL_DIR" -name "dashboard_*.json" | sort); do
    echo "  ➡️ Импорт дашборда: $(basename "$json_f")"
    curl -s -f -X POST -H "X-Metabase-Session: $SESSION" -H "Content-Type: application/json" \
         -d @"$json_f" "$MB_URL/api/dashboard" > /dev/null
done

# 5. Финализация
update_registry "success"
echo "✅ Релиз $RELEASE_VER успешно развернут и зафиксирован в реестре!"