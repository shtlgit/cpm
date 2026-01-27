DROP TABLE IF EXISTS replset.excluded_expenses CASCADE;  CREATE TABLE replset.excluded_expenses AS SELECT * FROM replset.excluded_expenses WHERE 1=0; -- Таблица пуста 
