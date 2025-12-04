local kong = kong

local CorsHandler = {}

CorsHandler.PRIORITY = 2000
CorsHandler.VERSION = "1.0.0"

--- Check if origin is allowed based on configuration
local function is_origin_allowed(origin, allowed_origins)
    if not origin then
        return false
    end

    for _, allowed in ipairs(allowed_origins) do
        -- Wildcard allows all origins
        if allowed == "*" then
            return true
        end

        -- Exact match
        if allowed == origin then
            return true
        end

        -- Pattern matching for wildcard subdomains (e.g., *.example.com)
        if allowed:sub(1, 1) == "*" then
            local pattern = allowed:gsub("%.", "%%."):gsub("%*", ".*")
            if origin:match("^" .. pattern .. "$") then
                return true
            end
        end
    end

    return false
end

--- Build the Access-Control-Allow-Origin header value
local function get_allowed_origin(origin, allowed_origins, credentials)
    if not is_origin_allowed(origin, allowed_origins) then
        return nil
    end

    -- When credentials are enabled, cannot use wildcard - must echo origin
    if credentials then
        return origin
    end

    -- Check if wildcard is in allowed origins
    for _, allowed in ipairs(allowed_origins) do
        if allowed == "*" then
            return "*"
        end
    end

    -- Return the specific origin
    return origin
end

--- Set CORS headers on the response
local function set_cors_headers(conf, origin)
    local allowed_origin = get_allowed_origin(origin, conf.origins, conf.credentials)

    if not allowed_origin then
        kong.log.debug("CORS: Origin not allowed: ", origin)
        return false
    end

    kong.response.set_header("Access-Control-Allow-Origin", allowed_origin)

    if conf.credentials then
        kong.response.set_header("Access-Control-Allow-Credentials", "true")
    end

    if conf.exposed_headers and #conf.exposed_headers > 0 then
        kong.response.set_header("Access-Control-Expose-Headers", table.concat(conf.exposed_headers, ", "))
    end

    -- Vary header for caching
    local vary = kong.response.get_header("Vary")
    if vary then
        kong.response.set_header("Vary", vary .. ", Origin")
    else
        kong.response.set_header("Vary", "Origin")
    end

    return true
end

--- Handle preflight OPTIONS request
local function handle_preflight(conf, origin)
    local allowed_origin = get_allowed_origin(origin, conf.origins, conf.credentials)

    if not allowed_origin then
        kong.log.debug("CORS: Preflight origin not allowed: ", origin)
        return kong.response.exit(403, { message = "Origin not allowed" })
    end

    local headers = {
        ["Access-Control-Allow-Origin"] = allowed_origin,
        ["Access-Control-Allow-Methods"] = table.concat(conf.methods, ", "),
        ["Vary"] = "Origin",
    }

    if conf.headers and #conf.headers > 0 then
        headers["Access-Control-Allow-Headers"] = table.concat(conf.headers, ", ")
    else
        -- If no specific headers configured, allow the requested headers
        local requested_headers = kong.request.get_header("Access-Control-Request-Headers")
        if requested_headers then
            headers["Access-Control-Allow-Headers"] = requested_headers
        end
    end

    if conf.credentials then
        headers["Access-Control-Allow-Credentials"] = "true"
    end

    if conf.max_age then
        headers["Access-Control-Max-Age"] = tostring(conf.max_age)
    end

    kong.log.debug("CORS: Preflight response for origin: ", origin)
    return kong.response.exit(204, nil, headers)
end

--- Access phase: handle preflight requests
function CorsHandler:access(conf)
    local origin = kong.request.get_header("Origin")

    -- No Origin header, skip CORS processing
    if not origin then
        kong.log.debug("CORS: No Origin header, skipping")
        return
    end

    local method = kong.request.get_method()

    -- Handle preflight OPTIONS request
    if method == "OPTIONS" then
        local request_method = kong.request.get_header("Access-Control-Request-Method")

        -- This is a CORS preflight request
        if request_method then
            if conf.preflight_continue then
                -- Let the request continue to upstream
                kong.log.debug("CORS: Preflight continue enabled, forwarding to upstream")
                kong.ctx.plugin.is_preflight = true
            else
                -- Handle preflight here and return
                return handle_preflight(conf, origin)
            end
        end
    end

    -- Store origin for header phase
    kong.ctx.plugin.origin = origin
end

--- Header filter phase: add CORS headers to response
function CorsHandler:header_filter(conf)
    local origin = kong.ctx.plugin.origin

    if not origin then
        return
    end

    -- Handle preflight response if preflight_continue is enabled
    if kong.ctx.plugin.is_preflight then
        local allowed_origin = get_allowed_origin(origin, conf.origins, conf.credentials)

        if allowed_origin then
            kong.response.set_header("Access-Control-Allow-Origin", allowed_origin)
            kong.response.set_header("Access-Control-Allow-Methods", table.concat(conf.methods, ", "))

            if conf.headers and #conf.headers > 0 then
                kong.response.set_header("Access-Control-Allow-Headers", table.concat(conf.headers, ", "))
            end

            if conf.credentials then
                kong.response.set_header("Access-Control-Allow-Credentials", "true")
            end

            if conf.max_age then
                kong.response.set_header("Access-Control-Max-Age", tostring(conf.max_age))
            end
        end

        return
    end

    -- Add CORS headers to regular response
    set_cors_headers(conf, origin)
end

return CorsHandler

