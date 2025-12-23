local kong = kong

local ApiKeyAuth = {
    PRIORITY = 1100,  -- Run before most other plugins
    VERSION = "1.0.0",
}

-- Error codes
local ERROR_CODES = {
    MISSING_API_KEY = "AA-1001",
    INVALID_API_KEY = "AA-1002",
    EXPIRED_API_KEY = "AA-1003",
    DATABASE_ERROR = "AA-1004",
    PROJECT_NOT_FOUND = "AA-1005",
    TENANT_INACTIVE = "AA-1006",
    PROJECT_INACTIVE = "AA-1007",
}

-- Get database connector
local function get_connector()
    local connector = kong.db.connector
    if not connector then
        return nil, "Database connector not available"
    end
    return connector
end

-- Execute SQL query
local function execute_query(sql, ...)
    local connector, err = get_connector()
    if not connector then
        return nil, err
    end

    local result, query_err = connector:query(sql, ...)
    if query_err then
        kong.log.err("Database query error: ", query_err)
        return nil, query_err
    end

    return result
end

-- Send error response
local function send_error(status_code, code, message, cause)
    kong.response.set_header("Content-Type", "application/json")
    return kong.response.exit(status_code, {
        error = {
            message = message,
            code = code,
            cause = cause,
        },
    })
end

-- Validate API key and get project details
local function validate_api_key(api_key, conf)
    -- Extract prefix for logging (first 8 characters of the UUID)
    local key_prefix = api_key:sub(1, 8)
    
    -- Query to find the API key and join with project and tenant
    -- API key is stored directly as UUID, no hashing needed
    local sql = [[
        SELECT 
            aa.id as api_key_id,
            aa.status as api_key_status,
            aa.project_id,
            p.project_key,
            p.name as project_name,
            p.status as project_status,
            p.tenant_id,
            t.name as tenant_name,
            t.status as tenant_status
        FROM api_keys aa
        INNER JOIN projects p ON aa.project_id = p.id
        INNER JOIN tenants t ON p.tenant_id = t.id
        WHERE aa.api_key = $1
        LIMIT 1
    ]]
    
    local result, err = execute_query(sql, api_key)
    if err then
        kong.log.err("Failed to validate API key: ", err)
        return nil, ERROR_CODES.DATABASE_ERROR, "Database error"
    end
    
    if not result or #result == 0 then
        kong.log.warn("Invalid API key attempted: ", key_prefix, "...")
        return nil, ERROR_CODES.INVALID_API_KEY, "Invalid API key"
    end
    
    local record = result[1]
    
    -- Check API key status
    if record.api_key_status ~= "ACTIVE" then
        kong.log.warn("Inactive API key used: ", key_prefix, "..., status: ", record.api_key_status)
        return nil, ERROR_CODES.EXPIRED_API_KEY, "API key is " .. record.api_key_status:lower()
    end
    
    -- Check project status
    if record.project_status ~= "ACTIVE" then
        kong.log.warn("API key belongs to inactive project: ", record.project_key)
        return nil, ERROR_CODES.PROJECT_INACTIVE, "Project is " .. record.project_status:lower()
    end
    
    -- Check tenant status
    if record.tenant_status ~= "ACTIVE" then
        kong.log.warn("API key belongs to inactive tenant: ", record.tenant_name)
        return nil, ERROR_CODES.TENANT_INACTIVE, "Tenant is " .. record.tenant_status:lower()
    end
    
    -- Update last_used_at timestamp (fire and forget)
    local update_sql = "UPDATE api_keys SET last_used_at = NOW() WHERE id = $1"
    execute_query(update_sql, record.api_key_id)
    
    return {
        api_key_id = record.api_key_id,
        project_id = record.project_id,
        project_key = record.project_key,
        project_name = record.project_name,
        tenant_id = record.tenant_id,
        tenant_name = record.tenant_name,
    }
end

-- Main access handler
function ApiKeyAuth:access(conf)
    -- Get the API key from header
    local input_header = conf.input_header or "x-api-key"
    local api_key = kong.request.get_header(input_header)
    
    -- Check if API key is provided
    if not api_key or api_key == "" then
        if conf.anonymous_on_missing then
            -- Allow anonymous access if configured
            kong.log.debug("No API key provided, allowing anonymous access")
            return
        end
        return send_error(401, ERROR_CODES.MISSING_API_KEY,
            "Unauthorized", "API key is required. Provide it via '" .. input_header .. "' header")
    end
    
    -- Validate the API key
    local key_data, error_code, error_message = validate_api_key(api_key, conf)
    
    if not key_data then
        return send_error(401, error_code, "Unauthorized", error_message)
    end
    
    -- Remove the original API key header if configured
    if conf.hide_api_key then
        kong.service.request.clear_header(input_header)
    end
    
    -- Set the output header with project key
    local output_header = conf.output_header or "x-project-key"
    kong.service.request.set_header(output_header, key_data.project_key)

    -- Set additional headers if configured
    if conf.add_tenant_header then
        kong.service.request.set_header("x-tenant-id", key_data.tenant_id)
        kong.service.request.set_header("x-tenant-name", key_data.tenant_name)
    end
    
    if conf.add_project_id_header then
        kong.service.request.set_header("x-project-id", key_data.project_id)
    end
    
    -- Store data in Kong context for other plugins
    kong.ctx.shared.api_key_auth = key_data
    
    kong.log.debug("API key validated successfully for project: ", key_data.project_key)
end

return ApiKeyAuth

