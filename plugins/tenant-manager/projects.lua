local utils = require "kong.plugins.tenant-manager.utils"
local tenants = require "kong.plugins.tenant-manager.tenants"
local kong = kong

local _M = {}

-- ============================================
-- CREATE PROJECT
-- POST /v1/tenants/{tenant_id}/projects
-- ============================================
function _M.create(tenant_id, body, conf)
    -- Validate tenant_id
    if not tenant_id or not utils.is_valid_uuid(tenant_id) then
        return utils.send_error(400, utils.ERROR_CODES.VALIDATION_ERROR,
            "Invalid tenant_id", "A valid tenant ID is required")
    end

    -- Check if tenant exists
    local tenant_exists, tenant_err = tenants.exists(tenant_id)
    if tenant_err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Database error", tenant_err)
    end
    if not tenant_exists then
        return utils.send_error(404, utils.ERROR_CODES.NOT_FOUND,
            "Tenant not found", "No tenant found with the given ID")
    end

    -- Validate required fields
    if not body.name or type(body.name) ~= "string" or #body.name < 1 then
        return utils.send_error(400, utils.ERROR_CODES.VALIDATION_ERROR,
            "Invalid name", "Project name is required")
    end

    -- Generate project_key from name
    local project_key = utils.generate_project_key(body.name)
    if not utils.is_valid_project_key(project_key) then
        return utils.send_error(400, utils.ERROR_CODES.VALIDATION_ERROR,
            "Invalid project name", "Project name must contain valid characters (lowercase alphanumeric and hyphens)")
    end

    local project_id = utils.generate_uuid()
    local now = utils.get_utc_timestamp()

    -- Check for duplicate project_key within tenant
    local check_sql = "SELECT id FROM projects WHERE tenant_id = $1 AND project_key = $2"
    local existing, check_err = utils.execute_query(check_sql, tenant_id, project_key)
    if check_err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Database error", check_err)
    end
    if existing and #existing > 0 then
        return utils.send_error(409, utils.ERROR_CODES.DUPLICATE,
            "Project already exists", "A project with this key already exists for this tenant")
    end

    -- Insert new project
    local insert_sql = [[
        INSERT INTO projects (id, tenant_id, project_key, name, status, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id, tenant_id, project_key, name, status, created_at, updated_at
    ]]

    local result, insert_err = utils.execute_query(
        insert_sql,
        project_id,
        tenant_id,
        project_key,
        body.name,
        "ACTIVE",
        now,
        now
    )

    if insert_err then
        kong.log.err("Failed to create project: ", insert_err)
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Failed to create project", insert_err)
    end

    local project = result and result[1]
    if not project then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Failed to create project", "No result returned from insert")
    end

    -- Auto-generate API key for the new project
    local key_id = utils.generate_uuid()
    local api_key = utils.generate_api_key()
    local key_name = body.name  -- Use project name as default key name

    local insert_key_sql = [[
        INSERT INTO api_keys (id, project_id, name, api_key, status, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id, name, api_key, created_at
    ]]

    local key_result, key_err = utils.execute_query(
        insert_key_sql,
        key_id,
        project_id,
        key_name,
        api_key,
        "ACTIVE",
        now,
        now
    )

    if key_err then
        kong.log.err("Failed to create API key for project: ", key_err)
        -- Project was created but API key failed - still return project with warning
        return utils.send_success(201, {
            tenant_id = project.tenant_id,
            project_id = project.id,
            project_key = project.project_key,
            name = project.name,
            status = project.status,
            api_key = nil,
            api_key_error = "Failed to auto-generate API key"
        })
    end

    local api_key_record = key_result and key_result[1]

    return utils.send_success(201, {
        tenant_id = project.tenant_id,
        project_id = project.id,
        project_key = project.project_key,
        name = project.name,
        status = project.status,
        api_key = api_key_record and api_key_record.api_key or nil,
        api_key_id = api_key_record and api_key_record.id or nil,
        api_key_name = api_key_record and api_key_record.name or nil,
    })
end

-- ============================================
-- LIST PROJECTS FOR TENANT
-- GET /v1/tenants/{tenant_id}/projects
-- ============================================
function _M.list(tenant_id, query_params, conf)
    -- Validate tenant_id
    if not tenant_id or not utils.is_valid_uuid(tenant_id) then
        return utils.send_error(400, utils.ERROR_CODES.VALIDATION_ERROR,
            "Invalid tenant_id", "A valid tenant ID is required")
    end

    -- Check if tenant exists
    local tenant_exists, tenant_err = tenants.exists(tenant_id)
    if tenant_err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Database error", tenant_err)
    end
    if not tenant_exists then
        return utils.send_error(404, utils.ERROR_CODES.NOT_FOUND,
            "Tenant not found", "No tenant found with the given ID")
    end

    local pagination = utils.get_pagination_params(query_params, conf)

    local sql = [[
        SELECT 
            p.id, 
            p.tenant_id,
            p.project_key, 
            p.name, 
            p.status, 
            p.created_at, 
            p.updated_at,
            ak.id AS api_key_id,
            ak.name AS api_key_name,
            ak.api_key,
            ak.status AS api_key_status,
            ak.last_rotated_at,
            ak.last_used_at,
            ak.created_at AS api_key_created_at
        FROM projects p
        LEFT JOIN api_keys ak ON ak.project_id = p.id AND ak.status = 'ACTIVE'
        WHERE p.tenant_id = $1
        ORDER BY p.created_at DESC
        LIMIT $2 OFFSET $3
    ]]
    local count_sql = "SELECT COUNT(*) as total FROM projects WHERE tenant_id = $1"

    local result, err = utils.execute_query(sql, tenant_id, pagination.limit, pagination.offset)
    if err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR, "Database error", err)
    end

    local count_result, count_err = utils.execute_query(count_sql, tenant_id)
    if count_err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR, "Database error", count_err)
    end

    local projects = {}
    if result then
        for _, row in ipairs(result) do
            table.insert(projects, {
                project_id = row.id,
                tenant_id = row.tenant_id,
                project_key = row.project_key,
                name = row.name,
                status = row.status,
                created_at = row.created_at,
                updated_at = row.updated_at,
                api_key = row.api_key,
                api_key_id = row.api_key_id,
                api_key_name = row.api_key_name,
                api_key_status = row.api_key_status,
                last_rotated_at = row.last_rotated_at,
                last_used_at = row.last_used_at,
                api_key_created_at = row.api_key_created_at,
            })
        end
    end

    local total = count_result and count_result[1] and count_result[1].total or 0

    return utils.send_success(200, {
        projects = projects,
        pagination = utils.build_pagination_response(pagination.page, pagination.limit, total),
    })
end

-- ============================================
-- GET PROJECT DETAILS
-- GET /v1/tenants/{tenant_id}/projects/{project_id}
-- ============================================
function _M.get(tenant_id, project_id, conf)
    -- Validate tenant_id
    if not tenant_id or not utils.is_valid_uuid(tenant_id) then
        return utils.send_error(400, utils.ERROR_CODES.VALIDATION_ERROR,
            "Invalid tenant_id", "A valid tenant ID is required")
    end

    -- Validate project_id
    if not project_id or not utils.is_valid_uuid(project_id) then
        return utils.send_error(400, utils.ERROR_CODES.VALIDATION_ERROR,
            "Invalid project_id", "A valid project ID is required")
    end

    local sql = [[
        SELECT p.id, p.tenant_id, p.project_key, p.name, p.status, p.created_at, p.updated_at
        FROM projects p
        WHERE p.id = $1 AND p.tenant_id = $2
    ]]

    local result, err = utils.execute_query(sql, project_id, tenant_id)
    if err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR, "Database error", err)
    end

    if not result or #result == 0 then
        return utils.send_error(404, utils.ERROR_CODES.NOT_FOUND,
            "Project not found", "No project found with the given ID for this tenant")
    end

    local project = result[1]
    return utils.send_success(200, {
        project_id = project.id,
        tenant_id = project.tenant_id,
        name = project.name,
        created_at = project.created_at,
    })
end

-- ============================================
-- HELPER: Check if project exists for tenant
-- ============================================
function _M.exists(tenant_id, project_id)
    if not tenant_id or not utils.is_valid_uuid(tenant_id) then
        return false, "Invalid tenant_id"
    end
    if not project_id or not utils.is_valid_uuid(project_id) then
        return false, "Invalid project_id"
    end

    local sql = "SELECT id, project_key FROM projects WHERE id = $1 AND tenant_id = $2"
    local result, err = utils.execute_query(sql, project_id, tenant_id)

    if err then
        return false, err
    end

    if result and #result > 0 then
        return true, nil, result[1].project_key
    end

    return false, nil
end

return _M

