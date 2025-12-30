local utils = require "kong.plugins.tenant-manager.utils"
local kong = kong

local _M = {}

-- ============================================
-- CREATE TENANT
-- POST /v1/tenants
-- ============================================
function _M.create(body, conf)
    -- Validate required fields
    if not body.name or type(body.name) ~= "string" or #body.name < 3 then
        return utils.send_error(400, utils.ERROR_CODES.VALIDATION_ERROR,
            "Invalid name", "Name is required and must be at least 3 characters")
    end

    if not body.contact_email or not utils.is_valid_email(body.contact_email) then
        return utils.send_error(400, utils.ERROR_CODES.VALIDATION_ERROR,
            "Invalid contact_email", "A valid email address is required")
    end

    local tenant_id = utils.generate_uuid()
    local now = utils.get_utc_timestamp()

    -- Check for duplicate name
    local check_sql = "SELECT id FROM tenants WHERE name = $1"
    local existing, check_err = utils.execute_query(check_sql, body.name)
    if check_err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Database error", check_err)
    end
    if existing and #existing > 0 then
        return utils.send_error(409, utils.ERROR_CODES.DUPLICATE,
            "Tenant already exists", "A tenant with this name already exists")
    end

    -- Insert new tenant
    local insert_sql = [[
        INSERT INTO tenants (id, name, description, contact_email, status, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id, name, description, contact_email, status, created_at, updated_at
    ]]

    local result, insert_err = utils.execute_query(
        insert_sql,
        tenant_id,
        body.name,
        body.description or "",
        body.contact_email,
        "ACTIVE",
        now,
        now
    )

    if insert_err then
        kong.log.err("Failed to create tenant: ", insert_err)
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Failed to create tenant", insert_err)
    end

    local tenant = result and result[1]
    if not tenant then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR,
            "Failed to create tenant", "No result returned from insert")
    end

    return utils.send_success(201, {
        tenant_id = tenant.id,
        name = tenant.name,
        status = tenant.status,
        created_at = tenant.created_at,
    })
end

-- ============================================
-- LIST TENANTS
-- GET /v1/tenants
-- ============================================
function _M.list(query_params, conf)
    local pagination = utils.get_pagination_params(query_params, conf)

    local sql = [[
        SELECT id, name, contact_email, status, created_at, updated_at
        FROM tenants
        ORDER BY created_at DESC
        LIMIT $1 OFFSET $2
    ]]
    local count_sql = "SELECT COUNT(*) as total FROM tenants"

    local result, err = utils.execute_query(sql, pagination.limit, pagination.offset)
    if err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR, "Database error", err)
    end

    local count_result, count_err = utils.execute_query(count_sql)
    if count_err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR, "Database error", count_err)
    end

    local tenants = {}
    if result then
        for _, row in ipairs(result) do
            table.insert(tenants, {
                tenant_id = row.id,
                name = row.name,
                contact_email = row.contact_email,
            })
        end
    end

    local total = count_result and count_result[1] and count_result[1].total or 0

    return utils.send_success(200, {
        tenants = tenants,
        pagination = utils.build_pagination_response(pagination.page, pagination.limit, total),
    })
end

-- ============================================
-- GET TENANT DETAILS
-- GET /v1/tenants/{tenant_id}
-- ============================================
function _M.get(tenant_id, conf)
    if not tenant_id or not utils.is_valid_uuid(tenant_id) then
        return utils.send_error(400, utils.ERROR_CODES.VALIDATION_ERROR,
            "Invalid tenant_id", "A valid tenant ID is required")
    end

    local sql = [[
        SELECT id, name, description, contact_email, status, created_at, updated_at
        FROM tenants WHERE id = $1
    ]]

    local result, err = utils.execute_query(sql, tenant_id)
    if err then
        return utils.send_error(500, utils.ERROR_CODES.DATABASE_ERROR, "Database error", err)
    end

    if not result or #result == 0 then
        return utils.send_error(404, utils.ERROR_CODES.NOT_FOUND,
            "Tenant not found", "No tenant found with the given ID")
    end

    local tenant = result[1]
    return utils.send_success(200, {
        tenant_id = tenant.id,
        name = tenant.name,
        description = tenant.description,
        contact_email = tenant.contact_email,
        status = tenant.status,
        created_at = tenant.created_at,
        updated_at = tenant.updated_at,
    })
end

-- ============================================
-- HELPER: Check if tenant exists
-- ============================================
function _M.exists(tenant_id)
    if not tenant_id or not utils.is_valid_uuid(tenant_id) then
        return false, "Invalid tenant_id"
    end

    local sql = "SELECT id FROM tenants WHERE id = $1"
    local result, err = utils.execute_query(sql, tenant_id)

    if err then
        return false, err
    end

    return result and #result > 0, nil
end

return _M

