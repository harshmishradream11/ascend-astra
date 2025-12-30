local utils = require "kong.plugins.tenant-manager.utils"
local projects = require "kong.plugins.tenant-manager.projects"
local kong = kong

local _M = {}

-- ============================================
-- GENERATE API KEY
-- POST /v1/tenants/{tenant_id}/projects/{project_id}/api-keys
-- ============================================
function _M.generate(tenant_id, project_id, body, conf)
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

    -- Check if project exists for tenant
    local project_exists, project_err, project_key = projects.exists(tenant_id, project_id)
    if project_err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Database error", project_err)
    end
    if not project_exists then
        return utils.send_error(404, utils.ERROR_CODES.NOT_FOUND,
            "Project not found", "No project found with the given ID for this tenant")
    end

    -- Get project name for default key name
    local project_sql = "SELECT name FROM projects WHERE id = $1"
    local project_result, _ = utils.execute_query(project_sql, project_id)
    local project_name = project_result and project_result[1] and project_result[1].name or "API Key"

    local key_name = (body and body.name) or project_name
    local key_id = utils.generate_uuid()
    local now = utils.get_utc_timestamp()

    -- Generate API key (UUID - no hashing needed)
    local api_key = utils.generate_api_key()

    -- Insert new API key
    local insert_sql = [[
        INSERT INTO api_keys (id, project_id, name, api_key, status, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id, name, status, created_at
    ]]

    local result, insert_err = utils.execute_query(
        insert_sql,
        key_id,
        project_id,
        key_name,
        api_key,
        "ACTIVE",
        now,
        now
    )

    if insert_err then
        kong.log.err("Failed to create API key: ", insert_err)
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Failed to create API key", insert_err)
    end

    local api_key_record = result and result[1]
    if not api_key_record then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Failed to create API key", "No result returned from insert")
    end

    -- Return with API key
    return utils.send_success(201, {
        key_id = api_key_record.id,
        name = api_key_record.name,
        api_key = api_key,
        created_at = api_key_record.created_at,
    })
end

-- ============================================
-- ROTATE API KEY
-- POST /v1/tenants/{tenant_id}/projects/{project_id}/api-keys/{key_id}/rotate
-- ============================================
function _M.rotate(tenant_id, project_id, key_id, conf)
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

    -- Validate key_id
    if not key_id or not utils.is_valid_uuid(key_id) then
        return utils.send_error(400, utils.ERROR_CODES.VALIDATION_ERROR,
            "Invalid key_id", "A valid API key ID is required")
    end

    -- Check if project exists for tenant
    local project_exists, project_err = projects.exists(tenant_id, project_id)
    if project_err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Database error", project_err)
    end
    if not project_exists then
        return utils.send_error(404, utils.ERROR_CODES.NOT_FOUND,
            "Project not found", "No project found with the given ID for this tenant")
    end

    -- Check if API key exists for project
    local check_sql = "SELECT id, name, status FROM api_keys WHERE id = $1 AND project_id = $2"
    local existing, check_err = utils.execute_query(check_sql, key_id, project_id)
    if check_err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Database error", check_err)
    end
    if not existing or #existing == 0 then
        return utils.send_error(404, utils.ERROR_CODES.NOT_FOUND,
            "API key not found", "No API key found with the given ID for this project")
    end

    local existing_key = existing[1]
    if existing_key.status == "REVOKED" then
        return utils.send_error(400, utils.ERROR_CODES.VALIDATION_ERROR,
            "Cannot rotate revoked key", "This API key has been revoked and cannot be rotated")
    end

    local now = utils.get_utc_timestamp()

    -- Generate new API key (UUID - no hashing needed)
    local new_api_key = utils.generate_api_key()

    -- Update API key
    local update_sql = [[
        UPDATE api_keys
        SET api_key = $1, updated_at = $2, last_rotated_at = $3
        WHERE id = $4
        RETURNING id, name, status, created_at, last_rotated_at
    ]]

    local result, update_err = utils.execute_query(
        update_sql,
        new_api_key,
        now,
        now,
        key_id
    )

    if update_err then
        kong.log.err("Failed to rotate API key: ", update_err)
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Failed to rotate API key", update_err)
    end

    local api_key_record = result and result[1]
    if not api_key_record then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Failed to rotate API key", "No result returned from update")
    end

    -- Return with new API key
    return utils.send_success(200, {
        key_id = api_key_record.id,
        name = api_key_record.name,
        api_key = new_api_key,
        rotated_at = api_key_record.last_rotated_at,
    })
end

-- ============================================
-- GET API KEY METADATA
-- GET /v1/tenants/{tenant_id}/projects/{project_id}/api-keys/{key_id}
-- ============================================
function _M.get(tenant_id, project_id, key_id, conf)
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

    -- Validate key_id
    if not key_id or not utils.is_valid_uuid(key_id) then
        return utils.send_error(400, utils.ERROR_CODES.VALIDATION_ERROR,
            "Invalid key_id", "A valid API key ID is required")
    end

    -- Check if project exists for tenant and get project_key
    local project_exists, project_err, project_key = projects.exists(tenant_id, project_id)
    if project_err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Database error", project_err)
    end
    if not project_exists then
        return utils.send_error(404, utils.ERROR_CODES.NOT_FOUND,
            "Project not found", "No project found with the given ID for this tenant")
    end

    -- Get API key details
    local sql = [[
        SELECT id, project_id, name, status, created_at, updated_at, last_rotated_at
        FROM api_keys
        WHERE id = $1 AND project_id = $2
    ]]

    local result, err = utils.execute_query(sql, key_id, project_id)
    if err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR, "Database error", err)
    end

    if not result or #result == 0 then
        return utils.send_error(404, utils.ERROR_CODES.NOT_FOUND,
            "API key not found", "No API key found with the given ID for this project")
    end

    local api_key = result[1]
    return utils.send_success(200, {
        key_id = api_key.id,
        project_id = api_key.project_id,
        project_key = project_key,
        name = api_key.name,
        status = api_key.status,
        created_at = api_key.created_at,
        last_rotated_at = api_key.last_rotated_at,
    })
end

return _M

