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

# Определяем начальную и конечную даты
START_DATE="2025-08-12"
END_DATE="2025-09-13"

# Цикл по каждой дате в заданном диапазоне
for (( date_current=$(date -d "$START_DATE" +%s); date_current<=$(date -d "$END_DATE" +%s); date_current+=86400 )); do
    # Форматируем дату в DD.MM.YYYY для URL
    formatted_date=$(date -d "@$date_current" +"%d.%m.%Y")

    # Формируем URL с нужной датой
    URL="https://nationalbank.kz/rss/get_rates.cfm?fdate=$formatted_date"

    echo "--- Загрузка данных за $formatted_date ---"

    # Получаем XML-данные
    DATA=$(curl -s "$URL")

    # Проверяем, что ответ не пустой
    if [[ -z "$DATA" ]]; then
        echo "Нет данных или ошибка при загрузке URL. Пропускаем."
        continue
    fi

    echo "Data: $DATA"
  
    # Извлекаем дату из XML (поле <date>)
    REQUEST_DATE=$(echo "$DATA" | xmlstarlet sel -t -v "//date")

    # Проверяем, что дата из XML корректна
    if [[ -z "$REQUEST_DATE" ]]; then
        echo "Не удалось извлечь дату из XML. Пропускаем."
        continue
    fi

    # Форматируем дату для базы данных
    DATE_DB=$(echo "$REQUEST_DATE" | awk -F. '{print $3"-"$2"-"$1}')
    echo ">> Форматированная дата для БД: $DATE_DB"

    # Парсим данные и формируем SQL-запрос за одну операцию
    INSERT_VALUES=$(
        echo "$DATA" | xmlstarlet sel -t -m "//item" \
            -v "title" -o "|" \
            -v "description" -o "|" \
            -v "quant" -o "|" \
            -o '\n' \
        | while IFS="|" read CODE RATE QUANT; do
            # Удаляем пробелы
            CODE=$(echo "$CODE" | tr -d '[:space:]')
            RATE=$(echo "$RATE" | tr -d '[:space:]')
            QUANT=$(echo "$QUANT" | tr -d '[:space:]')

            # Проверяем, что все ключевые поля не пустые
            if [[ -n "$CODE" && -n "$RATE" && -n "$QUANT" ]]; then
                # Форматируем курс
                RATE_DB=$(echo "$RATE" | tr "," ".")

                # Выводим отформатированную строку VALUES
                echo "('$CODE', $RATE_DB, $QUANT, '$DATE_DB')"
            fi
        done | tr '\n' ',' | sed 's/,$//'
    )

    echo ">> Подготовлены значения для вставки: $INSERT_VALUES"

    # Выполняем один большой запрос, если есть данные
    if [ -n "$INSERT_VALUES" ]; then
        docker exec -i "$DB_CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" <<EOF
INSERT INTO replset.nbrk_exchange_rates (currency_code, rate, quantity, rate_date)
VALUES $INSERT_VALUES
ON CONFLICT (currency_code, rate_date) DO UPDATE
SET rate = EXCLUDED.rate, quantity = EXCLUDED.quantity;
EOF
        echo ">> Успешно вставлены данные."
    else
        echo "Нет данных для вставки за $formatted_date или данные некорректны."
    fi
done

