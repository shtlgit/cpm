#!/bin/bash
set -e

MB_URL="http://192.168.137.15:3000"
MB_USER="fmbidb@fermag.kz"
MB_PASS="qwe12345678~"

# 1. Авторизация
SESSION=$(curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"username\": \"$MB_USER\", \"password\": \"$MB_PASS\"}" \
  $MB_URL/api/session | jq -r '.id')

if [ "$SESSION" = "null" ]; then echo "❌ Ошибка авторизации"; exit 1; fi

echo "🧹 Начинаем полную очистку Metabase..."

# 2. Удаление всех Дашбордов
DASHES=$(curl -s -H "X-Metabase-Session: $SESSION" "$MB_URL/api/dashboard" | jq -r '.[].id')
for id in $DASHES; do
    echo "🗑 Удаление дашборда ID: $id"
    curl -s -X DELETE -H "X-Metabase-Session: $SESSION" "$MB_URL/api/dashboard/$id" > /dev/null
done

# 3. Удаление всех Карточек (Вопросов)
CARDS=$(curl -s -H "X-Metabase-Session: $SESSION" "$MB_URL/api/card" | jq -r '.[].id')
for id in $CARDS; do
    echo "🗑 Удаление карточки ID: $id"
    curl -s -X DELETE -H "X-Metabase-Session: $SESSION" "$MB_URL/api/card/$id" > /dev/null
done

echo "✨ Система полностью очищена от контента."