-- Примеры добавления объектов в release_queue для тестового релиза vTEST.01

-- Карточка Metabase
INSERT INTO release_queue (object_type, object_id, release_version, created_by)
VALUES ('card', 101, 'vTEST.01', 'dev_user');

-- Дашборд Metabase
INSERT INTO release_queue (object_type, object_id, release_version, created_by)
VALUES ('dashboard', 202, 'vTEST.01', 'dev_user');

-- Представление
INSERT INTO release_queue (object_type, release_version, ddl_sql, created_by)
VALUES ('view', 'vTEST.01',
$$
CREATE OR REPLACE VIEW test_view AS
SELECT 1 AS value, now() AS created_at;
$$, 'dev_user');

-- Материализованное представление
INSERT INTO release_queue (object_type, release_version, ddl_sql, created_by)
VALUES ('mview', 'vTEST.01',
$$
CREATE MATERIALIZED VIEW test_mview AS
SELECT generate_series(1, 10) AS n;
$$, 'dev_user');

-- Таблица с данными
INSERT INTO release_queue (object_type, release_version, ddl_sql, is_data_included, created_by)
VALUES ('table', 'vTEST.01',
$$
CREATE TABLE test_table (
    id SERIAL PRIMARY KEY,
    name TEXT,
    created_at TIMESTAMP DEFAULT now()
);
INSERT INTO test_table (name) VALUES ('alpha'), ('beta'), ('gamma');
$$, true, 'dev_user');
