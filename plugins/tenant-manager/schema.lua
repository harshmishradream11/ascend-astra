local typedefs = require "kong.db.schema.typedefs"

return {
    name = "tenant-manager",
    fields = {
        {
            protocols = typedefs.protocols_http,
        },
        {
            config = {
                type = "record",
                fields = {
                    {
                        api_path_prefix = {
                            type = "string",
                            required = false,
                            default = "/v1",
                            description = "The base path prefix for tenant management API endpoints",
                        },
                    },
                    {
                        default_page_size = {
                            type = "integer",
                            required = false,
                            default = 20,
                            description = "Default page size for list endpoints",
                        },
                    },
                    {
                        max_page_size = {
                            type = "integer",
                            required = false,
                            default = 100,
                            description = "Maximum page size for list endpoints",
                        },
                    },
                },
            },
        },
    },
}

