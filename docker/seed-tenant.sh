#!/bin/bash

# ============================================
# Seed Default Tenant Script
# This script:
# 1. Creates Kong Service/Route for tenant-manager
# 2. Enables the tenant-manager plugin
# 3. Creates a default tenant and project
# ============================================

set -e

ADMIN_API="http://localhost:8001"
PROXY_API="http://localhost:8000"

# Wait for Kong to be ready
wait_for_kong() {
    echo "Waiting for Kong Admin API to be ready..."
    local max_retries=30
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        if curl -s "${ADMIN_API}/status" > /dev/null 2>&1; then
            echo "Kong Admin API is ready!"
            return 0
        fi
        retry=$((retry + 1))
        echo "Waiting for Kong... ($retry/$max_retries)"
        sleep 2
    done
    
    echo "Kong Admin API is not responding after $max_retries attempts"
    return 1
}

# Setup Kong configuration for tenant-manager
setup_tenant_manager_route() {
    echo "Setting up tenant-manager service and route..."
    
    # Check if service already exists
    local service_check=$(curl -s "${ADMIN_API}/services/tenant-manager-service")
    
    if echo "$service_check" | grep -q '"id"'; then
        echo "Tenant-manager service already exists, skipping setup"
        return 0
    fi
    
    echo "Creating tenant-manager service..."
    curl -s -X POST "${ADMIN_API}/services" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "tenant-manager-service",
            "url": "http://localhost:8001"
        }'
    echo ""
    
    echo "Creating tenant-manager route..."
    curl -s -X POST "${ADMIN_API}/services/tenant-manager-service/routes" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "tenant-manager-route",
            "paths": ["~/v1/tenants.*"],
            "strip_path": false
        }'
    echo ""
    
    echo "Enabling tenant-manager plugin..."
    curl -s -X POST "${ADMIN_API}/services/tenant-manager-service/plugins" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "tenant-manager"
        }'
    echo ""
    
    echo "Tenant-manager configuration created successfully!"
    
    # Wait for Kong to fully register the route
    echo "Waiting for route to be registered..."
    sleep 3
    
    # Debug: show registered routes
    echo "Registered routes:"
    curl -s "${ADMIN_API}/routes" | grep -o '"paths":\[[^]]*\]' || true
}

# Create default tenant via tenant-manager API
create_default_tenant() {
    local tenant_name="${DEFAULT_TENANT_NAME:-default}"
    local tenant_email="${DEFAULT_TENANT_EMAIL:-admin@bifrost.local}"
    
    echo "Checking if default tenant exists..."
    
    # Give Kong a moment to recognize the new route
    sleep 2
    
    # Try to list tenants first
    local response=$(curl -s -w "\n%{http_code}" "${PROXY_API}/v1/tenants" 2>/dev/null || echo -e "\n000")
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ]; then
        # Check if tenant already exists in the response
        if echo "$body" | grep -q "\"name\":\"$tenant_name\""; then
            echo "Default tenant '$tenant_name' already exists"
            return 0
        fi
    fi
    
    echo "Creating default tenant: $tenant_name"
    
    local create_response=$(curl -s -w "\n%{http_code}" -X POST "${PROXY_API}/v1/tenants" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$tenant_name\",
            \"description\": \"Default tenant for Ascend\",
            \"contact_email\": \"$tenant_email\"
        }" 2>/dev/null || echo -e "\n000")
    
    local create_code=$(echo "$create_response" | tail -n1)
    local create_body=$(echo "$create_response" | sed '$d')
    
    if [ "$create_code" = "201" ]; then
        echo "Default tenant created successfully!"
        echo "$create_body"
        
        # Extract tenant_id and create default project
        local tenant_id=$(echo "$create_body" | grep -o '"tenant_id":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$tenant_id" ]; then
            create_default_project "$tenant_id"
        fi
    elif [ "$create_code" = "409" ]; then
        echo "Default tenant already exists (conflict)"
    else
        echo "Failed to create default tenant (HTTP $create_code)"
        echo "$create_body"
    fi
}

# Create default project for a tenant
create_default_project() {
    local tenant_id="$1"
    local project_name="${DEFAULT_PROJECT_NAME:-Default Project}"
    local project_key="${DEFAULT_PROJECT_KEY:-default-project}"
    
    echo "Creating default project for tenant: $tenant_id"
    
    local project_response=$(curl -s -w "\n%{http_code}" -X POST "${PROXY_API}/v1/tenants/$tenant_id/projects" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$project_name\",
            \"project_key\": \"$project_key\"
        }" 2>/dev/null || echo -e "\n000")
    
    local project_code=$(echo "$project_response" | tail -n1)
    local project_body=$(echo "$project_response" | sed '$d')
    
    if [ "$project_code" = "201" ]; then
        echo "Default project created successfully!"
        echo "$project_body"
    elif [ "$project_code" = "409" ]; then
        echo "Default project already exists (conflict)"
    else
        echo "Failed to create default project (HTTP $project_code)"
        echo "$project_body"
    fi
}

# Main
main() {
    if [ "${SEED_DEFAULT_TENANT}" = "true" ]; then
        wait_for_kong
        setup_tenant_manager_route
        create_default_tenant
    else
        echo "SEED_DEFAULT_TENANT is not set to 'true', skipping tenant seeding"
    fi
}

main "$@"
