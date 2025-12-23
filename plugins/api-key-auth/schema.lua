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
                },
            },
        },
    },
}

