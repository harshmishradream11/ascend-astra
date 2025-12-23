local kong = kong
local utils = require "kong.plugins.tenant-manager.utils"
local tenants = require "kong.plugins.tenant-manager.tenants"
local projects = require "kong.plugins.tenant-manager.projects"
local api_keys = require "kong.plugins.tenant-manager.api_keys"

local TenantManager = {
    PRIORITY = 900,
    VERSION = "1.0.0",
}

-- ============================================
-- ROUTE PATTERNS
-- ============================================
-- All routes are under conf.api_path_prefix (default: /v1)
--
-- TENANTS:
--   POST   /v1/tenants                                           -> Create tenant
--   GET    /v1/tenants                                           -> List tenants
--   GET    /v1/tenants/{tenant_id}                               -> Get tenant details
--
-- PROJECTS:
--   POST   /v1/tenants/{tenant_id}/projects                      -> Create project
--   GET    /v1/tenants/{tenant_id}/projects                      -> List projects
--   GET    /v1/tenants/{tenant_id}/projects/{project_id}         -> Get project details
--
-- API KEYS:
--   POST   /v1/tenants/{tenant_id}/projects/{project_id}/api-keys                    -> Generate API key
--   GET    /v1/tenants/{tenant_id}/projects/{project_id}/api-keys/{key_id}           -> Get API key metadata
--   POST   /v1/tenants/{tenant_id}/projects/{project_id}/api-keys/{key_id}/rotate    -> Rotate API key
-- ============================================

-- Route parser: extracts resource type and IDs from path
local function parse_route(path, prefix)
    -- Remove prefix and leading/trailing slashes
    local remaining = path:sub(#prefix + 1)
    remaining = remaining:gsub("^/+", ""):gsub("/+$", "")

    if remaining == "" then
        return nil
    end

    local segments = {}
    for segment in remaining:gmatch("[^/]+") do
        table.insert(segments, segment)
    end

    -- Parse route based on segments
    -- /tenants -> { resource = "tenants" }
    -- /tenants/{id} -> { resource = "tenant", tenant_id = id }
    -- /tenants/{id}/projects -> { resource = "projects", tenant_id = id }
    -- /tenants/{id}/projects/{id} -> { resource = "project", tenant_id = id, project_id = id }
    -- /tenants/{id}/projects/{id}/api-keys -> { resource = "api-keys", tenant_id = id, project_id = id }
    -- /tenants/{id}/projects/{id}/api-keys/{id} -> { resource = "api-key", tenant_id = id, project_id = id, key_id = id }
    -- /tenants/{id}/projects/{id}/api-keys/{id}/rotate -> { resource = "api-key-rotate", tenant_id = id, project_id = id, key_id = id }

    local route = {}
    local n = #segments

    if n == 0 then
        return nil
    end

    -- First segment must be "tenants"
    if segments[1] ~= "tenants" then
        return nil
    end

    if n == 1 then
        -- /tenants
        route.resource = "tenants"
        return route
    end

    if n == 2 then
        -- /tenants/{tenant_id}
        route.resource = "tenant"
        route.tenant_id = segments[2]
        return route
    end

    if n == 3 and segments[3] == "projects" then
        -- /tenants/{tenant_id}/projects
        route.resource = "projects"
        route.tenant_id = segments[2]
        return route
    end

    if n == 4 and segments[3] == "projects" then
        -- /tenants/{tenant_id}/projects/{project_id}
        route.resource = "project"
        route.tenant_id = segments[2]
        route.project_id = segments[4]
        return route
    end

    if n == 5 and segments[3] == "projects" and segments[5] == "api-keys" then
        -- /tenants/{tenant_id}/projects/{project_id}/api-keys
        route.resource = "api-keys"
        route.tenant_id = segments[2]
        route.project_id = segments[4]
        return route
    end

    if n == 6 and segments[3] == "projects" and segments[5] == "api-keys" then
        -- /tenants/{tenant_id}/projects/{project_id}/api-keys/{key_id}
        route.resource = "api-key"
        route.tenant_id = segments[2]
        route.project_id = segments[4]
        route.key_id = segments[6]
        return route
    end

    if n == 7 and segments[3] == "projects" and segments[5] == "api-keys" and segments[7] == "rotate" then
        -- /tenants/{tenant_id}/projects/{project_id}/api-keys/{key_id}/rotate
        route.resource = "api-key-rotate"
        route.tenant_id = segments[2]
        route.project_id = segments[4]
        route.key_id = segments[6]
        return route
    end

    return nil
end

-- Get request body safely
local function get_body()
    local body, err = kong.request.get_body()
    if err then
        return nil, err
    end
    return body or {}
end

-- Main access handler
function TenantManager:access(conf)
    local path = kong.request.get_path()
    local method = kong.request.get_method()
    local prefix = conf.api_path_prefix

    -- Check if this request is for our API
    if not path:find("^" .. prefix:gsub("%-", "%%-"):gsub("%.", "%%.") .. "/tenants") then
        return -- Not our request, pass through
    end

    local route = parse_route(path, prefix)
    if not route then
        return utils.send_error(404, utils.ERROR_CODES.NOT_FOUND,
            "Not found", "The requested endpoint does not exist")
    end

    local query_params = kong.request.get_query()

    -- ============================================
    -- TENANT ROUTES
    -- ============================================

    -- POST /v1/tenants - Create tenant
    if route.resource == "tenants" and method == "POST" then
        local body, err = get_body()
        if err then
            return utils.send_error(400, utils.ERROR_CODES.INVALID_BODY,
                "Invalid request body", err)
        end
        return tenants.create(body, conf)
    end

    -- GET /v1/tenants - List tenants
    if route.resource == "tenants" and method == "GET" then
        return tenants.list(query_params, conf)
    end

    -- GET /v1/tenants/{tenant_id} - Get tenant details
    if route.resource == "tenant" and method == "GET" then
        return tenants.get(route.tenant_id, conf)
    end

    -- ============================================
    -- PROJECT ROUTES
    -- ============================================

    -- POST /v1/tenants/{tenant_id}/projects - Create project
    if route.resource == "projects" and method == "POST" then
        local body, err = get_body()
        if err then
            return utils.send_error(400, utils.ERROR_CODES.INVALID_BODY,
                "Invalid request body", err)
        end
        return projects.create(route.tenant_id, body, conf)
    end

    -- GET /v1/tenants/{tenant_id}/projects - List projects
    if route.resource == "projects" and method == "GET" then
        return projects.list(route.tenant_id, query_params, conf)
    end

    -- GET /v1/tenants/{tenant_id}/projects/{project_id} - Get project details
    if route.resource == "project" and method == "GET" then
        return projects.get(route.tenant_id, route.project_id, conf)
    end

    -- ============================================
    -- API KEY ROUTES
    -- ============================================

    -- POST /v1/tenants/{tenant_id}/projects/{project_id}/api-keys - Generate API key
    if route.resource == "api-keys" and method == "POST" then
        local body, err = get_body()
        if err then
            return utils.send_error(400, utils.ERROR_CODES.INVALID_BODY,
                "Invalid request body", err)
        end
        return api_keys.generate(route.tenant_id, route.project_id, body, conf)
    end

    -- GET /v1/tenants/{tenant_id}/projects/{project_id}/api-keys/{key_id} - Get API key metadata
    if route.resource == "api-key" and method == "GET" then
        return api_keys.get(route.tenant_id, route.project_id, route.key_id, conf)
    end

    -- POST /v1/tenants/{tenant_id}/projects/{project_id}/api-keys/{key_id}/rotate - Rotate API key
    if route.resource == "api-key-rotate" and method == "POST" then
        return api_keys.rotate(route.tenant_id, route.project_id, route.key_id, conf)
    end

    -- ============================================
    -- METHOD NOT ALLOWED
    -- ============================================
    return utils.send_error(405, utils.ERROR_CODES.METHOD_NOT_ALLOWED,
        "Method not allowed", "This HTTP method is not supported for this endpoint")
end

return TenantManager

