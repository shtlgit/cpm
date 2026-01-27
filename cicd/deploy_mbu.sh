#!/bin/bash
set -e

### === 1. Конфигурация ===
MB_URL="http://192.168.137.15:3000"
MB_USER="fmbidb@fermag.kz"
MB_PASS="qwe12345678~"
TARGET_DB_ID=2 

RELEASE_VER=$1
if [ -z "$RELEASE_VER" ]; then
    echo "❌ Ошибка: Укажите версию релиза (напр. v2025.12.25.11)"
    exit 1
fi

REL_DIR="/opt/mergifai1/fermagbi/exports/$RELEASE_VER"

# 1. Авторизация
echo "🔐 Авторизация в Metabase..."
SESSION=$(curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"username\": \"$MB_USER\", \"password\": \"$MB_PASS\"}" \
  $MB_URL/api/session | jq -r '.id')

if [ "$SESSION" = "null" ] || [ -z "$SESSION" ]; then echo "❌ Ошибка авторизации"; exit 1; fi

### === 2. Подготовка маппинга полей на целевом сервере ===
echo "🔍 Шаг 1: Получение актуальных ID полей с целевого сервера..."

# Скачиваем все поля базы данных за один запрос
PROD_FIELDS_JSON=$(curl -s -H "X-Metabase-Session: $SESSION" "$MB_URL/api/database/$TARGET_DB_ID/fields")

# Создаем ассоциативный массив в Bash: "schema.table.column" -> "ID"
declare -A PROD_FIELD_MAP

while IFS=$'\t' read -r f_path f_id; do
    if [ -n "$f_path" ]; then
        PROD_FIELD_MAP["$f_path"]="$f_id"
    fi
done < <(echo "$PROD_FIELDS_JSON" | jq -r '.[] | "\(.table_schema).\(.table_name).\(.name)\t\(.id)"')

### === 3. Синхронизация КАРТОЧЕК ===
echo "📊 Шаг 2: Загрузка карточек с интеллектуальной заменой ID..."

# Получаем список текущих карточек на сервере для обновления (Idempotency)
EXISTING_CARDS=$(curl -s -H "X-Metabase-Session: $SESSION" "$MB_URL/api/card")

for card_file in $(find "$REL_DIR" -name "card_*.json"); do
    CARD_NAME=$(jq -r '.name' "$card_file")
    
    # Извлекаем маппинг, который мы создали при экспорте
    MAP_DATA=$(jq -r '._field_mapping // {}' "$card_file")
    
    # Начинаем готовить PAYLOAD, удаляя старые системные поля
    PAYLOAD=$(jq 'del(.id, .collection_id, .creator_id, .created_at, .updated_at, .dashboard_id, ._field_mapping, .dashboard)' "$card_file")
    
    echo "  ➡️ Обработка: '$CARD_NAME'"

    # 🔄 ИНТЕЛЛЕКТУАЛЬНАЯ ЗАМЕНА
    # Проходим по всем старым ID из маппинга экспорта
    for old_fid in $(echo "$MAP_DATA" | jq -r 'keys[]?'); do
        # Получаем путь (schema.table.column) для этого старого ID
        f_path=$(echo "$MAP_DATA" | jq -r --arg k "$old_fid" '.[$k]')
        
        # Ищем, какой ID у этого пути на текущем сервере (проде)
        new_fid=${PROD_FIELD_MAP["$f_path"]}
        
        if [ -n "$new_fid" ] && [ "$new_fid" != "null" ]; then
            echo "    ✅ Замена Field ID: $old_fid -> $new_fid ($f_path)"
            
            # Используем jq walk для глубокой замены числа во всем дереве JSON
            # (это заменит ID и в native query, и в визуализации, и в параметрах)
            PAYLOAD=$(echo "$PAYLOAD" | jq --argjson old "$old_fid" --argjson new "$new_fid" '
                walk(
                  if type == "number" and . == $old then $new 
                  elif type == "array" then map(if . == $old then $new else . end)
                  else . end
                )
            ')
        else
            echo "    ⚠️ Предупреждение: Поле $f_path не найдено на целевом сервере!"
        fi
    done

    # Устанавливаем актуальный ID базы данных
    PAYLOAD=$(echo "$PAYLOAD" | jq --arg db_id "$TARGET_DB_ID" '.database_id = ($db_id | tonumber) | .dataset_query.database = ($db_id | tonumber)')

    # Проверяем, существует ли уже такая карточка по имени
    PROD_ID=$(echo "$EXISTING_CARDS" | jq -r --arg name "$CARD_NAME" '.[] | select(.name == $name) | .id' | head -n 1)

    if [ -n "$PROD_ID" ] && [ "$PROD_ID" != "null" ]; then
        echo "    🔄 Обновление существующей карточки (ID: $PROD_ID)"
        curl -s -X PUT -H "Content-Type: application/json" -H "X-Metabase-Session: $SESSION" \
             -d "$PAYLOAD" "$MB_URL/api/card/$PROD_ID" > /dev/null
    else
        echo "    ✨ Создание новой карточки"
        curl -s -X POST -H "Content-Type: application/json" -H "X-Metabase-Session: $SESSION" \
             -d "$PAYLOAD" "$MB_URL/api/card" > /dev/null
    fi
done

echo "🏁 Тестовая загрузка карточек завершена!"