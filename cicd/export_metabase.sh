#!/bin/bash
set -e

### === Конфигурация ===
MB_URL="http://192.168.137.16:3000"
MB_USER="fmbidb@fermag.kz"
MB_PASS="qwe12345678~"

PG_CONTAINER="fmbipostgres" 
PG_DB="fmbidb"
PG_USER="fmbidb"
PG_PASS="qwe12345678~"

EXPORT_DIR="exports"
DIST_DIR="dist"
GIT_REPO_DIR="/opt/mergifai1/fermagbi"
GIT_BRANCH="main"

### === 1. Авторизация в Metabase ===
echo "🔐 Авторизация в Metabase..."
SESSION=$(curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"username\": \"$MB_USER\", \"password\": \"$MB_PASS\"}" \
  $MB_URL/api/session | jq -r '.id')

if [ "$SESSION" = "null" ] || [ -z "$SESSION" ]; then
  echo "❌ Ошибка авторизации в Metabase"
  exit 1
fi

### === 2. Получение списка объектов ===
echo "🔎 Получение списка объектов из базы данных..."
QUERY="SELECT id || '^' || object_type || '^' || object_id || '^' || release_version || '^' || REPLACE(REPLACE(COALESCE(ddl_sql,''), CHR(10), ' '), CHR(13), ' ') FROM replset.release_queue WHERE status='planned' ORDER BY release_version, id;"
OBJECTS=$(docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -t -A -c "$QUERY")

if [ -z "$OBJECTS" ]; then
  echo "ℹ️ Нет объектов для экспорта."
  exit 0
fi

### === 3. Экспорт объектов ===
cd "$GIT_REPO_DIR"
mkdir -p "$EXPORT_DIR"

EXPORTED_IDS=()
# Список версий, которые участвуют в текущем экспорте
CURRENT_VERSIONS=()

while IFS="^" read -r rq_id type oid rel_version ddl_sql; do
  [ -z "$rq_id" ] && continue
  
  REL_DIR="$EXPORT_DIR/$rel_version"
  mkdir -p "$REL_DIR"
  CURRENT_VERSIONS+=("$rel_version")

if [ "$type" = "card" ]; then
    echo "➡️ Экспортируем Card $oid (Интеллектуальный сбор полей)"
    CARD_DATA=$(curl -s -H "X-Metabase-Session: $SESSION" "$MB_URL/api/card/$oid")
    
    # 🔍 Расширенный поиск ID полей (включая Field Filters)
    FIELD_IDS=$(echo "$CARD_DATA" | jq -r '.. | (select(type == "array" and .[0] == "field" and (.[1]|type == "number")) | .[1]), .field_id? // empty' | sort -u)
    
    MAPPING_JSON="{}"
    for FID in $FIELD_IDS; do
        if [[ "$FID" =~ ^[0-9]+$ ]]; then
            # Получаем метаданные поля
            FIELD_INFO=$(curl -s -H "X-Metabase-Session: $SESSION" "$MB_URL/api/field/$FID")
            
            # Проверяем, что получили валидный ответ с данными о таблице
            F_PATH=$(echo "$FIELD_INFO" | jq -r 'if .table then [.table.schema, .table.name, .name] | join(".") else empty end')
            
            if [ -z "$F_PATH" ] || [ "$F_PATH" == "null" ]; then
                echo "      ⚠️ Предупреждение: Не удалось получить путь для Field ID $FID"
                continue
            fi
            
            MAPPING_JSON=$(echo "$MAPPING_JSON" | jq --arg id "$FID" --arg path "$F_PATH" '. + {($id): $path}')
            echo "      ✅ Найдено поле: $F_PATH (ID: $FID)"
        fi
    done
    
    # Сохраняем карточку с маппингом
    echo "$CARD_DATA" | jq --argjson mapping "$MAPPING_JSON" '. + {"_field_mapping": $mapping}' > "$REL_DIR/card_${oid}.json"

  elif [ "$type" = "dashboard" ]; then
    echo "➡️ Экспортируем Dashboard $oid"
    curl -s -H "X-Metabase-Session: $SESSION" "$MB_URL/api/dashboard/$oid" | jq '.' > "$REL_DIR/dashboard_${oid}.json"

  elif [ "$type" = "view" ] || [ "$type" = "mview" ]; then
    echo "➡️ Экспортируем SQL объект $type (id=$rq_id)"
    echo "$ddl_sql" > "$REL_DIR/uview_${rq_id}.sql"

  elif [ "$type" = "table" ]; then
    echo "➡️ Экспортируем SQL объект $type (id=$rq_id)"
    echo "$ddl_sql" > "$REL_DIR/table_${rq_id}.sql"
  fi

  EXPORTED_IDS+=("$rq_id")
done <<< "$OBJECTS"

### === 4. Обновляем release_queue ===
if [ ${#EXPORTED_IDS[@]} -gt 0 ]; then
  IDS_LIST=$(IFS=,; echo "${EXPORTED_IDS[*]}")
  docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -c \
    "UPDATE replset.release_queue SET status='exported' WHERE id IN ($IDS_LIST);"
fi

### === 5. Git commit & push ===
if ! git diff --quiet || [ -n "$(git status --porcelain)" ]; then
  git add "$EXPORT_DIR"
  git commit -m "Exported release objects ($(date +%F_%H-%M-%S))"
  git pull origin $GIT_BRANCH --rebase
  git push origin $GIT_BRANCH
  echo "✅ Изменения в Git отправлены."
fi

### === 6. Сборка пакетов (только для затронутых версий) ===
mkdir -p "$DIST_DIR"
# Оставляем только уникальные версии из текущего прогона
UNIQUE_VERSIONS=$(echo "${CURRENT_VERSIONS[@]}" | tr ' ' '\n' | sort -u)

for rel in $UNIQUE_VERSIONS; do
  VERSION_FILE="metabase_release_${rel}_$(date +%Y%m%d_%H%M).tar.gz"
  tar czf "$DIST_DIR/$VERSION_FILE" -C "$EXPORT_DIR" "$rel"
  echo "📦 Собран пакет: $DIST_DIR/$VERSION_FILE"
done

echo "🏁 Процесс экспорта завершен."