#!/bin/bash
set -e

# Папка для логов
LOGDIR="$HOME/dslogs"
mkdir -p "$LOGDIR"

# Лог с датой
LOGFILE="$LOGDIR/data_update_$(date +%F_%T).log"

# Включаем трассировку и направляем её в лог
exec > >(tee -a "$LOGFILE") 2>&1
set -x

# Обёртка для выполнения SQL в контейнере
run_sql() {
  local sql="$1"
  docker exec -i fmbipostgres \
    psql -U fmbidb -d fmbidb -v ON_ERROR_STOP=1 -c "$sql"
}

echo "==== Запуск обновления данных $(date) ===="

# 1. Обходим каждое соединение
docker exec -i fmbipostgres \
  psql -U fmbidb -d fmbidb -At -F '|' \
  -c "SELECT name, prefix FROM replset.connset" |
while IFS='|' read -r conn_name prefix; do
  [ -z "$conn_name" ] && continue

  echo "=== Обработка подключения $conn_name (prefix=$prefix) ==="

  tmssql_name="replset.${prefix}_tablesonmssql"

  # 1.1 Три процедуры updatereplicatedtables*
  run_sql "SELECT replset.updatereplicatedtables('$conn_name');"
  run_sql "SELECT replset.updatereplicatedtables2('$conn_name');"
  run_sql "SELECT replset.updatereplicatedtables3('$conn_name');"

  # 1.2 Получаем список таблиц для этого соединения
  tables=$(docker exec -i fmbipostgres \
    psql -U fmbidb -d fmbidb -At -c \
    "SELECT fulltablename
       FROM $tmssql_name
      WHERE tabletype LIKE 'Reg%' AND totransfer=true")

  # 1.3 Для каждой таблицы вызываем updatereplicatetablebyname
  while IFS= read -r fulltablename; do
    [ -z "$fulltablename" ] && continue
    echo "   -> Обновление таблицы $fulltablename"
    run_sql "SELECT replset.updatereplicatedtablebyname('$conn_name', '$fulltablename');"
  done <<< "$tables"

done <<< "$connections"

# 2. Обновляем все материализованные представления в схеме replset
run_sql "SELECT replset.refresh_all_matviews('replset');"

echo "==== Завершено $(date) ===="

# 3. Ротация логов
# Сжимаем логи старше 7 дней и ещё не сжатые
find "$LOGDIR" -type f -name "data_update_*.log" -mtime +7 -exec gzip {} \;

# 4. Удаляем сжатые архивы старше 30 дней
find "$LOGDIR" -type f -name "data_update_*.log.gz" -mtime +30 -delete

