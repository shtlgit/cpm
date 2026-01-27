#!/bin/bash

# Лог с датой
LOGFILE="$HOME/dslogs/data_sync_$(date +%F_%T).log"

# Запуск SQL-функции через psql внутри контейнера
# По Buh
# Удаляем все представления
docker exec -i fmbipostgres psql -U fmbidb -d fmbidb -c "SELECT replset.drop_buh_vw_mvw();" >> $LOGFILE 2>&1
docker exec -i fmbipostgres psql -U fmbidb -d fmbidb -c "SELECT replset.drop_rarus_vw_mvw();" >> $LOGFILE 2>&1

# Перенос данных
docker exec -i fmbipostgres psql -U fmbidb -d fmbidb -c "SELECT replset.createfillreplicatedtables('Buh');" >> $LOGFILE 2>&1
docker exec -i fmbipostgres psql -U fmbidb -d fmbidb -c "SELECT replset.createfillreplicatedtables2('Buh');" >> $LOGFILE 2>&1
docker exec -i fmbipostgres psql -U fmbidb -d fmbidb -c "SELECT replset.createfillreplicatedtables3('Buh');" >> $LOGFILE 2>&1
docker exec -i fmbipostgres psql -U fmbidb -d fmbidb -c "SELECT replset.createreplicatetablebyname('Buh', 'dbo.\"buh__accrg494\"');" >> $LOGFILE 2>&1

# Создаем представления
docker exec -i fmbipostgres psql -U fmbidb -d fmbidb -c "SELECT replset.create_rarus_mvw_vw();" >> $LOGFILE 2>&1
docker exec -i fmbipostgres psql -U fmbidb -d fmbidb -c "SELECT replset.create_buh_mvw_vw();" >> $LOGFILE 2>&1

