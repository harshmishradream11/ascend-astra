local kong = kong
local cjson = require "cjson.safe"

local _M = {}

-- ============================================
-- ERROR CODES
-- ============================================
_M.ERROR_CODES = {
    VALIDATION_ERROR = "TM-1001",
    NOT_FOUND = "TM-1002",
    DUPLICATE = "TM-1003",
    DATABASE_ERROR = "TM-1004",
    METHOD_NOT_ALLOWED = "TM-1005",
    INVALID_BODY = "TM-1006",
    FORBIDDEN = "TM-1007",
    UNAUTHORIZED = "TM-1008",
}

-- Valid statuses
_M.TENANT_STATUSES = { ACTIVE = true, INACTIVE = true, SUSPENDED = true }
_M.PROJECT_STATUSES = { ACTIVE = true, INACTIVE = true, SUSPENDED = true }
_M.API_KEY_STATUSES = { ACTIVE = true, INACTIVE = true, REVOKED = true }

-- ============================================
-- RESPONSE HELPERS
-- ============================================

function _M.send_response(status_code, body)
    kong.response.set_header("Content-Type", "application/json")
    return kong.response.exit(status_code, body)
end

function _M.send_error(status_code, code, message, cause)
    return _M.send_response(status_code, {
        error = {
            message = message,
            code = code,
            cause = cause,
        },
    })
end

function _M.send_success(status_code, data)
    return _M.send_response(status_code, { data = data })
end

-- ============================================
-- VALIDATION HELPERS
-- ============================================

function _M.is_valid_email(email)
    if not email or type(email) ~= "string" then
        return false
    end
    local pattern = "^[%w%._%+-]+@[%w%.%-]+%.[%a]+$"
    return email:match(pattern) ~= nil
end

function _M.is_valid_uuid(str)
    if not str or type(str) ~= "string" then
        return false
    end
    local pattern = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
    return str:match(pattern) ~= nil
end

function _M.is_valid_project_key(key)
    if not key or type(key) ~= "string" then
        return false
    end
    -- Must be lowercase alphanumeric with hyphens only
    return key:match("^[a-z0-9%-]+$") ~= nil and #key >= 1 and #key <= 100
end

-- ============================================
-- DATABASE HELPERS
-- ============================================

function _M.get_pg_connector()
    local connector = kong.db.connector
    if not connector then
        return nil, "Database connector not available"
    end
    return connector
end

-- Escape a string value for SQL (prevent SQL injection)
function _M.escape_literal(value)
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

-- Substitute $1, $2, etc. placeholders with escaped values
function _M.build_sql(sql_template, ...)
    local args = {...}
    local result = sql_template
    
    -- Replace each placeholder $N with escaped value
    -- Use a function to handle the replacement properly
    result = result:gsub("%$(%d+)", function(num)
        local idx = tonumber(num)
        if idx and args[idx] ~= nil then
            return _M.escape_literal(args[idx])
        end
        return "$" .. num  -- Leave unchanged if no arg
    end)
    
    return result
end

-- Determine if a query is a read or write operation
local function get_operation_type(sql)
    local trimmed = sql:gsub("^%s*", ""):upper()
    if trimmed:match("^SELECT") or trimmed:match("^WITH.*SELECT") then
        return "read"
    end
    return "write"
end

-- Execute a parameterized query
-- Usage: execute_query("SELECT * FROM tenants WHERE id = $1", tenant_id)
function _M.execute_query(sql_template, ...)
    local connector, err = _M.get_pg_connector()
    if not connector then
        return nil, err
    end

    -- Build the final SQL with substituted parameters
    local sql = _M.build_sql(sql_template, ...)
    local operation = get_operation_type(sql)

    local result, query_err = connector:query(sql, operation)
    if query_err then
        kong.log.err("Database query error: ", query_err)
        return nil, query_err
    end

    return result
end

-- ============================================
-- CRYPTO HELPERS
-- ============================================

function _M.generate_api_key()
    -- API key is simply a UUID - no hashing needed
    local uuid = require "kong.tools.uuid"
    return uuid.uuid()
end

function _M.mask_api_key(api_key)
    if not api_key or #api_key < 8 then
        return "****"
    end
    -- Show first 8 and last 4 characters of UUID
    return api_key:sub(1, 8) .. "..." .. api_key:sub(-4)
end

-- ============================================
-- STRING HELPERS
-- ============================================

function _M.generate_project_key(name)
    -- Convert name to lowercase, replace spaces with hyphens, remove invalid chars
    local key = name:lower()
    key = key:gsub("%s+", "-")
    key = key:gsub("[^a-z0-9%-]", "")
    key = key:gsub("%-+", "-")
    key = key:gsub("^%-", ""):gsub("%-$", "")
    return key
end

function _M.get_utc_timestamp()
    return ngx.utctime()
end

function _M.generate_uuid()
    local uuid = require "kong.tools.uuid"
    return uuid.uuid()
end

-- ============================================
-- PAGINATION HELPERS
-- ============================================

function _M.get_pagination_params(query_params, conf)
    local page = tonumber(query_params.page) or 1
    local limit = tonumber(query_params.limit) or conf.default_page_size

    if page < 1 then page = 1 end
    if limit < 1 then limit = conf.default_page_size end
    if limit > conf.max_page_size then limit = conf.max_page_size end

    local offset = (page - 1) * limit

    return {
        page = page,
        limit = limit,
        offset = offset,
    }
end

function _M.build_pagination_response(page, page_size, total_count)
    return {
        current_page = page,
        page_size = page_size,
        total_count = total_count,
    }
end

return _M

