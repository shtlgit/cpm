#!/bin/bash
set -e

### === Конфигурация ===
PG_CONTAINER="fmbipostgres"
PG_DB="fmbidb"
PG_USER="fmbidb"
PG_PASS="qwe12345678~"
GIT_REPO_DIR="/opt/mergifai1/fermagbi"

RELEASE_VER=$1
if [ -z "$RELEASE_VER" ]; then
    echo "❌ Ошибка: Укажите версию (например: ./deploy_mviews.sh v2025.12.25.02)"
    exit 1
fi

REL_DIR="$GIT_REPO_DIR/exports/$RELEASE_VER"

echo "🚀 Начинаем деплой Materialized Views для версии $RELEASE_VER"

# Ищем файлы mview_*.sql и сортируем их по Depth (который мы заложили в имя при выгрузке)
MVIEW_FILES=$(find "$REL_DIR" -name "mview_*.sql" | sort)

if [ -z "$MVIEW_FILES" ]; then
    echo "⚠️ Файлы Materialized Views не найдены."
    exit 0
fi

for sql_f in $MVIEW_FILES; do
    echo "------------------------------------------"
    echo "➡️ Применяю MView: $(basename "$sql_f")"
    
    # Копируем и выполняем
    docker cp "$sql_f" "$PG_CONTAINER:/tmp/deploy_mview.sql"
    
    if ! docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
        psql -U "$PG_USER" -d "$PG_DB" \
        --set ON_ERROR_STOP=1 \
        -f /tmp/deploy_mview.sql; then
        
        echo "❌ ОШИБКА в MView $(basename "$sql_f")"
        exit 1
    fi
    echo "✅ Успешно: $(basename "$sql_f")"
done

echo "------------------------------------------"
echo "🎉 Все Materialized Views версии $RELEASE_VER успешно созданы!"