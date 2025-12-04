local typedefs = require "kong.db.schema.typedefs"

return {
    name = "cors",
    fields = {
        {
            consumer = typedefs.no_consumer,
        },
        {
            protocols = typedefs.protocols_http,
        },
        {
            config = {
                type = "record",
                fields = {
                    {
                        origins = {
                            type = "array",
                            required = true,
                            elements = {
                                type = "string",
                            },
                            default = { "*" },
                            description = "Allowed origin domains. Use '*' for all origins, or specific domains like 'https://example.com'. Supports wildcard subdomains like '*.example.com'.",
                        },
                    },
                    {
                        methods = {
                            type = "array",
                            required = true,
                            elements = {
                                type = "string",
                                one_of = {
                                    "GET",
                                    "POST",
                                    "PUT",
                                    "PATCH",
                                    "DELETE",
                                    "OPTIONS",
                                    "HEAD",
                                },
                            },
                            default = {
                                "GET",
                                "POST",
                                "PUT",
                                "PATCH",
                                "DELETE",
                                "OPTIONS",
                                "HEAD",
                            },
                            description = "HTTP methods allowed for CORS requests.",
                        },
                    },
                    {
                        headers = {
                            type = "array",
                            elements = {
                                type = "string",
                            },
                            default = {
                                "Accept",
                                "Accept-Language",
                                "Content-Language",
                                "Content-Type",
                                "Authorization",
                                "X-Requested-With",
                                "X-Request-ID",
                            },
                            description = "Headers allowed in CORS requests. If empty, echoes Access-Control-Request-Headers.",
                        },
                    },
                    {
                        exposed_headers = {
                            type = "array",
                            elements = {
                                type = "string",
                            },
                            default = {
                                "X-Request-ID",
                                "X-Kong-Request-Id",
                            },
                            description = "Headers exposed to the browser in the response.",
                        },
                    },
                    {
                        credentials = {
                            type = "boolean",
                            default = true,
                            description = "Allow credentials (cookies, authorization headers, TLS client certificates).",
                        },
                    },
                    {
                        max_age = {
                            type = "integer",
                            default = 3600,
                            description = "How long (in seconds) the preflight response can be cached.",
                        },
                    },
                    {
                        preflight_continue = {
                            type = "boolean",
                            default = false,
                            description = "Forward preflight OPTIONS requests to upstream service instead of handling them.",
                        },
                    },
                },
                custom_validator = function(config)
                    -- Credentials cannot be used with wildcard origin
                    if config.credentials then
                        for _, origin in ipairs(config.origins) do
                            if origin == "*" then
                                return nil, "credentials cannot be enabled when using wildcard (*) origin. Use specific origins instead."
                            end
                        end
                    end
                    return true
                end,
            },
        },
    },
}

