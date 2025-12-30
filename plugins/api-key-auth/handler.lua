local kong = kong
local cjson = require "cjson.safe"
local redis = require "resty.redis"

local ApiKeyAuth = {
    PRIORITY = 1100,  -- Run before most other plugins
    VERSION = "1.1.0",
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

-- Cache status constants
local CACHE_INVALID = "INVALID"

-- ============================================
-- REDIS FUNCTIONS
-- ============================================

local function get_redis_connection(conf)
    local red = redis:new()
    red:set_timeouts(conf.redis_timeout, conf.redis_timeout, conf.redis_timeout)
    
    local ok, err = red:connect(conf.redis_host, conf.redis_port, {
        pool = "api-key-auth",
        pool_size = 10,
    })
    
    if not ok then
        kong.log.warn("Failed to connect to Redis: ", err)
        return nil, err
    end
    
    return red
end

local function release_redis(red)
    if red then
        local ok, err = red:set_keepalive(30000, 100)
        if not ok then
            kong.log.warn("Failed to set Redis keepalive: ", err)
        end
    end
end

local function get_cache_key(conf, api_key)
    return (conf.redis_prefix or "api_key_auth:") .. api_key
end

local function get_from_cache(conf, api_key)
    if not conf.cache_enabled then
        return nil
    end
    
    local red, err = get_redis_connection(conf)
    if not red then
        return nil
    end
    
    local cache_key = get_cache_key(conf, api_key)
    local cached, get_err = red:get(cache_key)
    release_redis(red)
    
    if get_err then
        kong.log.warn("Redis GET error: ", get_err)
        return nil
    end
    
    if cached and cached ~= ngx.null then
        -- Check if it's a cached invalid key
        if cached == CACHE_INVALID then
            return { invalid = true }
        end
        
        local data, decode_err = cjson.decode(cached)
        if decode_err then
            kong.log.warn("Failed to decode cached data: ", decode_err)
            return nil
        end
        
        kong.log.debug("Cache HIT for API key")
        return data
    end
    
    kong.log.debug("Cache MISS for API key")
    return nil
end

local function set_cache(conf, api_key, data)
    if not conf.cache_enabled then
        return
    end
    
    local red, err = get_redis_connection(conf)
    if not red then
        return
    end
    
    local cache_key = get_cache_key(conf, api_key)
    local ttl = conf.cache_ttl or 300
    
    local value
    if data then
        value = cjson.encode(data)
    else
        -- Cache invalid keys to prevent repeated DB queries
        value = CACHE_INVALID
    end
    
    local ok, set_err = red:setex(cache_key, ttl, value)
    release_redis(red)
    
    if not ok then
        kong.log.warn("Redis SETEX error: ", set_err)
    end
end

local function invalidate_cache(conf, api_key)
    if not conf.cache_enabled then
        return
    end
    
    local red, err = get_redis_connection(conf)
    if not red then
        return
    end
    
    local cache_key = get_cache_key(conf, api_key)
    red:del(cache_key)
    release_redis(red)
end

-- ============================================
-- DATABASE FUNCTIONS
-- ============================================

local function get_connector()
    local connector = kong.db.connector
    if not connector then
        return nil, "Database connector not available"
    end
    return connector
end

local function escape_literal(value)
    if value == nil then
        return "NULL"
    end
    if type(value) == "number" then
        return tostring(value)
    end
    if type(value) == "boolean" then
        return value and "TRUE" or "FALSE"
    end
    -- String: escape single quotes by doubling them
    local escaped = tostring(value):gsub("'", "''")
    return "'" .. escaped .. "'"
end

local function execute_query(sql_template, params)
    local connector, err = get_connector()
    if not connector then
        return nil, err
    end

    -- Kong 3.x requires operation type as second argument: 'read' or 'write'
    -- Parameters must be interpolated into the SQL string
    local sql = sql_template
    if params then
        sql = sql:gsub("%$(%d+)", function(num)
            local idx = tonumber(num)
            if idx and params[idx] ~= nil then
                return escape_literal(params[idx])
            end
            return "$" .. num
        end)
    end

    local result, query_err = connector:query(sql, "read")
    if query_err then
        kong.log.err("Database query error: ", query_err)
        return nil, query_err
    end

    return result
end

-- ============================================
-- API KEY VALIDATION
-- ============================================

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

local function validate_api_key_from_db(api_key, conf)
    local key_prefix = api_key:sub(1, 8)
    
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
    
    local result, err = execute_query(sql, {api_key})
    if err then
        kong.log.err("Failed to validate API key: ", err)
        return nil, ERROR_CODES.DATABASE_ERROR, "Invalid API key"
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
    
    return {
        api_key_id = record.api_key_id,
        project_id = record.project_id,
        project_key = record.project_key,
        project_name = record.project_name,
        tenant_id = record.tenant_id,
        tenant_name = record.tenant_name,
    }
end

local function validate_api_key(api_key, conf)
    -- Try cache first
    local cached = get_from_cache(conf, api_key)
    
    if cached then
        if cached.invalid then
            return nil, ERROR_CODES.INVALID_API_KEY, "Invalid API key"
        end
        return cached
    end
    
    -- Cache miss - query database
    local key_data, error_code, error_message = validate_api_key_from_db(api_key, conf)
    
    if key_data then
        -- Cache valid key data
        set_cache(conf, api_key, key_data)
    else
        -- Cache invalid key to prevent repeated DB queries
        set_cache(conf, api_key, nil)
    end
    
    return key_data, error_code, error_message
end

-- ============================================
-- MAIN ACCESS HANDLER
-- ============================================

function ApiKeyAuth:access(conf)
    local input_header = conf.input_header or "x-api-key"
    local api_key = kong.request.get_header(input_header)
    
    -- Check if API key is provided
    if not api_key or api_key == "" then
        if conf.anonymous_on_missing then
            kong.log.debug("No API key provided, allowing anonymous access")
            return
        end
        return send_error(401, ERROR_CODES.MISSING_API_KEY,
            "Unauthorized", "API key is required. Provide it via '" .. input_header .. "' header")
    end
    
    -- Validate the API key (with caching)
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
