#!/bin/bash
set -e

# Папка для логов
LOGDIR="/var/log/data_sync"
mkdir -p "$LOGDIR"

# Лог с датой
LOGFILE="$LOGDIR/data_sync_$(date +%F_%T).log"

# Включаем трассировку и направляем её в лог
exec > >(tee -a "$LOGFILE") 2>&1
set -x

# Обёртка для выполнения SQL в контейнере
run_sql() {
  local sql="$1"
  docker exec -i fmbipostgres \
    psql -U fmbidb -d fmbidb -v ON_ERROR_STOP=1 -c "$sql"
}

echo "==== Запуск синхронизации $(date) ===="

# 1. Удаляем все представления
run_sql "SELECT replset.drop_buh_vw_mvw();"
run_sql "SELECT replset.drop_rarus_vw_mvw();"

# 2. Получаем список соединений (name|prefix)
connections=$(docker exec -i fmbipostgres \
  psql -U fmbidb -d fmbidb -At -F '|' -c "SELECT name, prefix FROM replset.connset")

# 3. Обходим каждое соединение
while IFS='|' read -r conn_name prefix; do
  [ -z "$conn_name" ] && continue

  echo "=== Обработка подключения $conn_name (prefix=$prefix) ==="

  tmssql_name="replset.${prefix}_tablesonmssql"

  # 3.1 Три процедуры createfillreplicatedtables*
  run_sql "SELECT replset.createfillreplicatedtables('$conn_name');"
  run_sql "SELECT replset.createfillreplicatedtables2('$conn_name');"
  run_sql "SELECT replset.createfillreplicatedtables3('$conn_name');"

  # 3.2 Получаем список таблиц для этого соединения
  tables=$(docker exec -i fmbipostgres \
    psql -U fmbidb -d fmbidb -At -c \
    "SELECT fulltablename
       FROM $tmssql_name
      WHERE tabletype LIKE 'Reg%' AND totransfer=true")

  # 3.3 Для каждой таблицы вызываем createreplicatetablebyname
  while IFS= read -r fulltablename; do
    [ -z "$fulltablename" ] && continue
    echo "   -> Репликация таблицы $fulltablename"
    run_sql "SELECT replset.createreplicatetablebyname('$conn_name', '$fulltablename');"
  done <<< "$tables"

done <<< "$connections"

# 4. Создаём представления заново
run_sql "SELECT replset.create_rarus_mvw_vw();"
run_sql "SELECT replset.create_buh_mvw_vw();"

echo "==== Завершено $(date) ===="

# 5. Ротация логов
# Сжимаем логи старше 7 дней и ещё не сжатые
find "$LOGDIR" -type f -name "data_sync_*.log" -mtime +7 -exec gzip {} \;

# Удаляем сжатые архивы старше 30 дней
find "$LOGDIR" -type f -name "data_sync_*.log.gz" -mtime +30 -delete

