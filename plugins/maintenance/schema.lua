local typedefs = require "kong.db.schema.typedefs"
local json = require "cjson"

local is_present = function(v)
    return type(v) == "string" and #v > 0
end

local default_body = {
    error = {
        MsgCode = "MG1008",
        MsgShowUp = "Popup",
        MsgText = "Ascend is temporarily unavailable due to scheduled system maintenance. We’ll be up & running shortly",
        MsgTitle = "We are Under Maintenance",
        MsgType = "Error",
    },
}

return {
    name = "maintenance",
    fields = {
        {
            protocols = typedefs.protocols_http,
        },
        {
            config = {
                type = "record",
                fields = {
                    {
                        status_code = {
                            type = "integer",
                            default = 400,
                            between = {
                                100,
                                599,
                            },
                        },
                    },
                    {
                        message = {
                            type = "string",
                        },
                    },
                    {
                        content_type = {
                            type = "string",
                            default = "application/json",
                        },
                    },
                    {
                        body = {
                            type = "string",
                            default = json.encode(default_body),
                        },
                    },
                    {
                        exclude_paths = {
                            type = "array",
                            elements = {
                                type = "string",
                            },
                            default = {
                                "/kong-healthcheck",
                            },
                        },
                    },
                },
                custom_validator = function(config)
                    if is_present(config.message) and (is_present(config.content_type) or is_present(config.body)) then
                        return nil, "message cannot be used with content_type or body"
                    end
                    if is_present(config.content_type) and not is_present(config.body) then
                        return nil, "content_type requires a body"
                    end
                    return true
                end,
            },
        },
    },
}
