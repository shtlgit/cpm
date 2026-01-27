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
    echo "❌ Ошибка: Укажите версию (например: ./deploy_tables.sh v2025.12.25)"
    exit 1
fi

REL_DIR="$GIT_REPO_DIR/exports/$RELEASE_VER"

# Проверка наличия папки
if [ ! -d "$REL_DIR" ]; then
    echo "❌ Ошибка: Папка $REL_DIR не найдена. Сделайте git pull."
    exit 1
fi

echo "🚀 Начинаем деплой ТАБЛИЦ для версии $RELEASE_VER"

# Ищем файлы, которые начинаются на table_ (согласно нашей логике выгрузки)
# Если префикса нет, скрипт возьмет все .sql, но мы ищем именно таблицы
TABLE_FILES=$(find "$REL_DIR" -name "table_*.sql" | sort)

if [ -z "$TABLE_FILES" ]; then
    echo "⚠️ Файлы таблиц (table_*.sql) не найдены в папке релиза."
    exit 0
fi

for sql_f in $TABLE_FILES; do
    echo "------------------------------------------"
    echo "➡️ Обработка файла: $(basename "$sql_f")"
    
    # 1. Копируем файл в контейнер
    docker cp "$sql_f" "$PG_CONTAINER:/tmp/deploy_table.sql"
    
    # 2. Выполняем с выводом всех ошибок
    # Флаг --set ON_ERROR_STOP=1 заставит psql вернуть ошибку, если SQL упадет
    if ! docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
        psql -U "$PG_USER" -d "$PG_DB" \
        --set ON_ERROR_STOP=1 \
        -f /tmp/deploy_table.sql; then
        
        echo "❌ ОШИБКА в файле $(basename "$sql_f")"
        exit 1
    fi
    
    echo "✅ Успешно применен: $(basename "$sql_f")"
done

echo "------------------------------------------"
echo "🎉 Все таблицы версии $RELEASE_VER успешно загружены!"