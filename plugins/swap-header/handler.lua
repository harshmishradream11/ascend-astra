local kong = kong

local SwapHeader = {
    PRIORITY = 1000,
    VERSION = "1.0.0",
}

local MISSING_API_KEY_ERROR_MESSAGE = "Missing API key in request header"
local MISSING_API_KEY_ERROR_CODE = "SH-1001"

function SwapHeader:access(conf)
    -- Get header names from config or use defaults
    local source_header = conf.source_header or "x-api-key"
    local target_header = conf.target_header or "x-project-key"

    -- Fetch the API key from the source header
    local api_key = kong.request.get_header(source_header)

    if not api_key then
        kong.log.err("API key not found in header: " .. source_header)
        return kong.response.exit(401, {
            error = {
                message = MISSING_API_KEY_ERROR_MESSAGE,
                code = MISSING_API_KEY_ERROR_CODE,
                cause = "Header '" .. source_header .. "' is not present in the request",
            },
        })
    end

    -- Remove the source header
    kong.service.request.clear_header(source_header)

    -- Set the target header with the API key value
    kong.service.request.set_header(target_header, api_key)

    kong.log.debug("Replaced '" .. source_header .. "' with '" .. target_header .. "'")
end

return SwapHeader

