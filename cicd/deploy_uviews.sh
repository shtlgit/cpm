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
    echo "❌ Ошибка: Укажите версию (например: ./deploy_uviews.sh v2025.12.25.02)"
    exit 1
fi

REL_DIR="$GIT_REPO_DIR/exports/$RELEASE_VER"

echo "🚀 Начинаем деплой Unified Views (View + MView) для версии $RELEASE_VER"

# 1. Ищем файлы uview_*.sql
# Используем sort -V, чтобы правильно сортировать числа в именах (uview_9.sql < uview_10.sql)
UVIEW_FILES=$(find "$REL_DIR" -name "uview_*.sql" | sort -V)

if [ -z "$UVIEW_FILES" ]; then
    echo "⚠️ Файлы Unified Views не найдены."
    exit 0
fi

# 2. Цикл выполнения
for sql_f in $UVIEW_FILES; do
    FILE_NAME=$(basename "$sql_f")
    echo "------------------------------------------"
    echo "➡️ Применяю объект: $FILE_NAME"
    
    # Копируем файл внутрь контейнера
    docker cp "$sql_f" "$PG_CONTAINER:/tmp/deploy_obj.sql"
    
    # Выполняем SQL. Флаг ON_ERROR_STOP=1 прервет выполнение при первой ошибке
    if ! docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
        psql -U "$PG_USER" -d "$PG_DB" \
        --set ON_ERROR_STOP=1 \
        -f /tmp/deploy_obj.sql; then
        
        echo "❌ ОШИБКА при выполнении $FILE_NAME"
        exit 1
    fi
    echo "✅ Успешно: $FILE_NAME"
done

echo "------------------------------------------"
echo "🎉 Все представления (View и Materialized View) версии $RELEASE_VER успешно развернуты!"