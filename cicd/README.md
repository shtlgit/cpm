
# 📘 Metabase Release Management CI/CD (полный комплект)

## 🔹 Обзор
Эта система автоматизирует процесс переноса **дашбордов, карточек и SQL-объектов (представлений, материализованных представлений, таблиц)** из тестовой среды Metabase в продуктив.  

- **release_queue** — управляет объектами (дашборды, карточки, SQL).  
- **release_registry** — управляет версиями релизов и их статусами.  
- **export_metabase.sh** — экспортирует объекты из тестовой среды.  
- **deploy.sh** — накатывает релизы на PROD с rollback при ошибках.  
- Поддерживаются GitLab CI/CD и GitHub Actions.  

---

## 🔹 Поддерживаемые типы объектов
- `card` → карточка Metabase (JSON).  
- `dashboard` → дашборд Metabase (JSON).  
- `view` → SQL-представление.  
- `mview` → материализованное представление.  
- `table` → таблица (с данными или без).  

---

## 🔹 Диаграммы
- ER: `metabase_release_mgmt.png`  
- Workflow: `metabase_release_workflow.png`  

---

## 🔹 CI/CD варианты
- **GitLab CI/CD** → `.gitlab-ci.yml`  
- **GitHub Actions** → `.github/workflows/metabase.yml`  

---
## 🔹 Структура таблиц

### release_queue
```sql
CREATE TABLE release_queue (
    id SERIAL PRIMARY KEY,
    object_type VARCHAR(50) NOT NULL,      -- 'card', 'dashboard', 'view', 'mview', 'table'
    object_id INT NOT NULL DEFAULT 0,      -- для card/dashboard = ID, для SQL объектов = 0
    release_version VARCHAR(50) NOT NULL,
    ddl_sql TEXT NULL,                     -- SQL код (для view/mview/table)
    is_data_included BOOLEAN DEFAULT false,
    status VARCHAR(20) NOT NULL DEFAULT 'planned',
    created_at TIMESTAMP DEFAULT now(),
    created_by VARCHAR(100) DEFAULT current_user,
    updated_at TIMESTAMP DEFAULT now()
);
```
**Статусы:**
- `planned` → разработчик добавил объект.  
- `exported` → объект выгружен в Git.  
- `deployed` → объект успешно применён на PROD.  


### release_registry
```sql
CREATE TABLE release_registry (
    id SERIAL PRIMARY KEY,
    release_version VARCHAR(50) NOT NULL UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'new',
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);
```
**Статусы:**
- `new` → новый релиз зарегистрирован.  
- `downloaded` → архив скачан.  
- `extracted` → архив распакован.  
- `imported` → успешно установлен.  

---

## 🔹 Скрипты

### export_metabase.sh
- Экспортирует дашборды/карточки из Metabase API.  
- Экспортирует SQL-объекты из поля `ddl_sql`.  
- Сохраняет JSON и SQL файлы в пакет релиза.  
- Обновляет статусы `planned → exported`.  
- Коммитит изменения в Git.  
- Собирает `.tar.gz` архив.  

### deploy.sh
- Скачивает архив релиза.  
- Делает backup metadata DB.  
- Импортирует `.json` объекты в Metabase.  
- Выполняет `.sql` объекты в PostgreSQL.  
- При ошибке откатывает через `pg_restore`.  
- Обновляет статусы `release_registry` и `release_queue`.  

---
## 🔹 Поток работы

1. **Разработчик** в Metabase отмечает объекты для релиза (добавляет в `release_queue` со статусом `planned`).  
2. **export_metabase.sh**:
   - экспортирует объекты → `exported`,  
   - коммитит в Git,  
   - создаёт релиз на GitHub/GitLab,  
   - регистрирует релиз в `release_registry` (`new`).  
3. **deploy.sh**:
   - скачивает релиз → `downloaded`,  
   - делает backup → `extracted`,  
   - импортирует JSON → `imported`,  
   - обновляет объекты в `release_queue` → `deployed`.  
4. Если ошибка на этапе импорта → выполняется rollback из backup.  

---



# 🚀 Развертывание с нуля

## 1. Подготовка PostgreSQL (metadata DB Metabase)
```bash
psql -h localhost -U metabase -d metabase -f release_queue.sql
psql -h localhost -U metabase -d metabase -f release_registry.sql
```

## 2. Настройка Git-репозитория
```bash
git clone git@gitlab.com:yourgroup/metabase-releases.git /opt/metabase-dashboards-repo
cd /opt/metabase-dashboards-repo
git checkout -b main
```

## 3. Установка зависимостей (тестовый сервер)
```bash
sudo apt-get update
sudo apt-get install -y curl jq postgresql-client git
```

## 🔹 Пример использования

### Добавление карточки
```sql
INSERT INTO release_queue (object_type, object_id, release_version, created_by)
VALUES ('card', 123, 'v2025.10.01', 'dev_user');
```

### Добавление дашборда
```sql
INSERT INTO release_queue (object_type, object_id, release_version, created_by)
VALUES ('dashboard', 456, 'v2025.10.01', 'dev_user');
```

### Добавление представления
```sql
INSERT INTO release_queue (object_type, release_version, ddl_sql, created_by)
VALUES ('view', 'v2025.10.01',
$$
CREATE OR REPLACE VIEW sales_summary AS
SELECT store_id, SUM(amount) AS total_sales
FROM sales
GROUP BY store_id;
$$, 'dev_user');
```

### Добавление материализованного представления
```sql
INSERT INTO release_queue (object_type, release_version, ddl_sql, created_by)
VALUES ('mview', 'v2025.10.01',
$$
CREATE MATERIALIZED VIEW top_customers AS
SELECT customer_id, SUM(amount) AS total
FROM sales
GROUP BY customer_id
ORDER BY total DESC
LIMIT 100;
$$, 'dev_user');
```

## 5. Экспорт релиза
```bash
chmod +x ./export_metabase.sh
./export_metabase.sh
```

## 6. Публикация релиза
- GitLab → `.gitlab-ci.yml`  
- GitHub → `.github/workflows/metabase.yml`  

CI/CD создаст **релиз с архивом .tar.gz**.

## 7. Деплой на PROD
```bash
chmod +x ./deploy.sh
./deploy.sh v2025.10.01   # один релиз
./deploy.sh               # все новые релизы
```

## 8. Автоматизация деплоя
```bash
0 * * * * /opt/deploy.sh >> /var/log/metabase_deploy.log 2>&1
```

---

📌 Теперь README покрывает весь цикл: от DDL → Git → CI/CD → деплой.
