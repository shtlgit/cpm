CREATE TABLE release_queue (
    id SERIAL PRIMARY KEY,
    object_type VARCHAR(50) NOT NULL,      -- 'card', 'dashboard', 'view', 'mview', 'table'
    object_id INT NOT NULL DEFAULT 0,      -- для card/dashboard = ID, для SQL объектов = 0
    release_version VARCHAR(50) NOT NULL,  -- v2025.10.01
    ddl_sql TEXT NULL,                     -- SQL код (для view/mview/table)
    is_data_included BOOLEAN DEFAULT false,-- если true → в таблице есть данные
    status VARCHAR(20) NOT NULL DEFAULT 'planned',  -- planned, exported, deployed
    created_at TIMESTAMP DEFAULT now(),
    created_by VARCHAR(100) DEFAULT current_user,
    updated_at TIMESTAMP DEFAULT now()
);

CREATE OR REPLACE FUNCTION update_release_queue_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_release_queue_timestamp
BEFORE UPDATE ON release_queue
FOR EACH ROW
EXECUTE FUNCTION update_release_queue_timestamp();
