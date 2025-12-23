local typedefs = require "kong.db.schema.typedefs"

return {
    name = "api-key-to-project-key",
    fields = {
        {
            protocols = typedefs.protocols_http,
        },
        {
            config = {
                type = "record",
                fields = {
                    {
                        source_header = {
                            type = "string",
                            required = false,
                            default = "x-api-key",
                            description = "The source header name to read the API key from (default: 'x-api-key')",
                        },
                    },
                    {
                        target_header = {
                            type = "string",
                            required = false,
                            default = "x-project-key",
                            description = "The target header name to copy the API key to (default: 'x-project-key')",
                        },
                    },
                },
            },
        },
    },
}

