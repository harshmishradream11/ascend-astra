local typedefs = require "kong.db.schema.typedefs"

return {
    name = "api-key-auth",
    fields = {
        {
            protocols = typedefs.protocols_http,
        },
        {
            config = {
                type = "record",
                fields = {
                    {
                        input_header = {
                            type = "string",
                            required = false,
                            default = "x-api-key",
                            description = "Header name containing the API key (default: x-api-key)",
                        },
                    },
                    {
                        output_header = {
                            type = "string",
                            required = false,
                            default = "x-project-key",
                            description = "Header name to set with project key (default: x-project-key)",
                        },
                    },
                    {
                        hide_api_key = {
                            type = "boolean",
                            required = false,
                            default = true,
                            description = "Remove the API key header before forwarding to upstream (default: true)",
                        },
                    },
                    {
                        add_tenant_header = {
                            type = "boolean",
                            required = false,
                            default = false,
                            description = "Add x-tenant-id and x-tenant-name headers (default: false)",
                        },
                    },
                    {
                        add_project_id_header = {
                            type = "boolean",
                            required = false,
                            default = false,
                            description = "Add x-project-id header (default: false)",
                        },
                    },
                    {
                        anonymous_on_missing = {
                            type = "boolean",
                            required = false,
                            default = false,
                            description = "Allow requests without API key to pass through (default: false)",
                        },
                    },
                    -- Redis caching options
                    {
                        cache_enabled = {
                            type = "boolean",
                            required = false,
                            default = true,
                            description = "Enable Redis caching for API key validation (default: true)",
                        },
                    },
                    {
                        cache_ttl = {
                            type = "integer",
                            required = false,
                            default = 300,
                            description = "Cache TTL in seconds (default: 300 = 5 minutes)",
                        },
                    },
                    {
                        redis_host = {
                            type = "string",
                            required = false,
                            default = "redis",
                            description = "Redis host (default: redis)",
                        },
                    },
                    {
                        redis_port = {
                            type = "integer",
                            required = false,
                            default = 6379,
                            description = "Redis port (default: 6379)",
                        },
                    },
                    {
                        redis_timeout = {
                            type = "integer",
                            required = false,
                            default = 2000,
                            description = "Redis connection timeout in ms (default: 2000)",
                        },
                    },
                    {
                        redis_prefix = {
                            type = "string",
                            required = false,
                            default = "api_key_auth:",
                            description = "Redis key prefix (default: api_key_auth:)",
                        },
                    },
                },
            },
        },
    },
}

