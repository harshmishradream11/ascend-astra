package = "ascend-astra"

version = "1.0.0-1"

supported_platforms = {"linux", "macosx"}
source = {
    url = "https://github.com/dream11/ascend-astra"
}

description = {
    summary = "Kong with all its custom plugins",
    homepage = "https://github.com/dream11/ascend-astra"
}

dependencies = {
    -- Install open sourced plugins
    "kong-circuit-breaker == 2.1.1",
    "host-interpolate-by-header == 1.3.0",
    "kong-advanced-router == 0.2.1",
    "lua-resty-jwt == 0.2.2",
}

build = {
    type = "builtin",
    modules = {

        -- maintenance plugin
        ["kong.plugins.maintenance.handler"] = "plugins/maintenance/handler.lua",
        ["kong.plugins.maintenance.schema"] = "plugins/maintenance/schema.lua",

        -- conditional-req-termination plugin
        ["kong.plugins.conditional-req-termination.handler"] = "plugins/conditional-req-termination/handler.lua",
        ["kong.plugins.conditional-req-termination.schema"] = "plugins/conditional-req-termination/schema.lua",

        -- strip-headers plugin
        ["kong.plugins.strip-headers.handler"] = "plugins/strip-headers/handler.lua",
        ["kong.plugins.strip-headers.schema"] = "plugins/strip-headers/schema.lua",

        -- swap-header plugin
        ["kong.plugins.swap-header.handler"] = "plugins/swap-header/handler.lua",
        ["kong.plugins.swap-header.schema"] = "plugins/swap-header/schema.lua",

        -- rate-limiting-v2 plugin
        ["kong.plugins.rate-limiting-v2.handler"] = "plugins/rate-limiting-v2/handler.lua",
        ["kong.plugins.rate-limiting-v2.schema"] = "plugins/rate-limiting-v2/schema.lua",
        ["kong.plugins.rate-limiting-v2.expiration"] = "plugins/rate-limiting-v2/expiration.lua",
        ["kong.plugins.rate-limiting-v2.policies"] = "plugins/rate-limiting-v2/policies.lua",
        ["kong.plugins.rate-limiting-v2.algorithms"] = "plugins/rate-limiting-v2/algorithms.lua",
        ["kong.plugins.rate-limiting-v2.connections"] = "plugins/rate-limiting-v2/connections.lua",
        ["kong.plugins.rate-limiting-v2.utils"] = "plugins/rate-limiting-v2/utils.lua",
    },
}
