-- Migration: Create tables for tenant-manager plugin
-- Tables: tenants, projects, api_keys
return {
    postgres = {
        up = [[
            -- ============================================
            -- TENANTS TABLE
            -- ============================================
            CREATE TABLE IF NOT EXISTS tenants (
                id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                name            VARCHAR(255) NOT NULL UNIQUE,
                description     TEXT,
                contact_email   VARCHAR(255) NOT NULL,
                status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
                created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                updated_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );

            CREATE INDEX IF NOT EXISTS idx_tenants_name ON tenants(name);
            CREATE INDEX IF NOT EXISTS idx_tenants_status ON tenants(status);
            CREATE INDEX IF NOT EXISTS idx_tenants_contact_email ON tenants(contact_email);

            DO $$
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_tenant_status') THEN
                    ALTER TABLE tenants ADD CONSTRAINT chk_tenant_status
                        CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED'));
                END IF;
                IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_tenant_name_length') THEN
                    ALTER TABLE tenants ADD CONSTRAINT chk_tenant_name_length
                        CHECK (LENGTH(name) >= 3);
                END IF;
            END $$;

            -- ============================================
            -- PROJECTS TABLE
            -- ============================================
            CREATE TABLE IF NOT EXISTS projects (
                id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
                project_key     VARCHAR(100) NOT NULL,
                name            VARCHAR(255) NOT NULL,
                status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
                created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                updated_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(tenant_id, project_key)
            );

            CREATE INDEX IF NOT EXISTS idx_projects_tenant_id ON projects(tenant_id);
            CREATE INDEX IF NOT EXISTS idx_projects_project_key ON projects(project_key);
            CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status);

            DO $$
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_project_status') THEN
                    ALTER TABLE projects ADD CONSTRAINT chk_project_status
                        CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED'));
                END IF;
                IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_project_key_format') THEN
                    ALTER TABLE projects ADD CONSTRAINT chk_project_key_format
                        CHECK (project_key ~ '^[a-z0-9-]+$');
                END IF;
            END $$;

            -- ============================================
            -- API KEYS TABLE
            -- ============================================
            CREATE TABLE IF NOT EXISTS api_keys (
                id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                name            VARCHAR(255) NOT NULL,
                api_key         UUID NOT NULL UNIQUE,
                status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
                created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                updated_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                last_rotated_at TIMESTAMP WITH TIME ZONE,
                last_used_at    TIMESTAMP WITH TIME ZONE
            );

            CREATE INDEX IF NOT EXISTS idx_api_keys_project_id ON api_keys(project_id);
            CREATE INDEX IF NOT EXISTS idx_api_keys_api_key ON api_keys(api_key);
            CREATE INDEX IF NOT EXISTS idx_api_keys_status ON api_keys(status);

            DO $$
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_api_key_status') THEN
                    ALTER TABLE api_keys ADD CONSTRAINT chk_api_key_status
                        CHECK (status IN ('ACTIVE', 'INACTIVE', 'REVOKED'));
                END IF;
            END $$;
        ]],
    },
}
