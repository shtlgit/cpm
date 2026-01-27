-- DDL для release_registry (см. README)
CREATE TABLE release_registry (
    id SERIAL PRIMARY KEY,
    release_version VARCHAR(50) NOT NULL UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'new',   -- new, downloaded, extracted, imported
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

CREATE OR REPLACE FUNCTION update_release_registry_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_release_registry_timestamp
BEFORE UPDATE ON release_registry
FOR EACH ROW
EXECUTE FUNCTION update_release_registry_timestamp();
