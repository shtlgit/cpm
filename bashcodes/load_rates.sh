#!/bin/bash
set -e

# Настройки подключения к БД
DB_HOST="localhost"
DB_NAME="fmbidb"
DB_USER="fmbidb"
DB_PASS="qwe12345678~"
# Имя Docker контейнера для PostgreSQL
DB_CONTAINER_NAME="fmbipostgres"

# Экспорт пароля, чтобы не запрашивал psql
export PGPASSWORD=$DB_PASS

URL="https://nationalbank.kz/rss/rates_all.xml"

# Парсим данные и формируем SQL-запрос
INSERT_VALUES=$(
    # Весь конвейер выполняется в одной подоболочке
    curl -s "$URL" | xmlstarlet sel -t -m "//item" \
        -v "title" -o "|" \
        -v "description" -o "|" \
        -v "quant" -o "|" \
        -v "pubDate" -n \
    | while IFS="|" read CODE RATE QUANT DATE; do
        # Форматируем данные
        DATE=$(echo "$DATE" | awk -F. '{print $3"-"$2"-"$1}')
        RATE=$(echo "$RATE" | tr "," ".")
        
        # Выводим отформатированную строку VALUES
        echo "('$CODE', $RATE, $QUANT, '$DATE')"
    done | tr '\n' ',' | sed 's/,$//'
)

# Выполняем один большой запрос, если есть данные
if [ -n "$INSERT_VALUES" ]; then
    docker exec -i "$DB_CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" <<EOF
INSERT INTO replset.nbrk_exchange_rates (currency_code, rate, quantity, rate_date)
VALUES $INSERT_VALUES
ON CONFLICT (currency_code, rate_date) DO UPDATE
SET rate = EXCLUDED.rate, quantity = EXCLUDED.quantity;
EOF
else
    echo "Нет данных для вставки."
fi
