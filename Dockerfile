FROM kong:3.7.1-ubuntu

USER root

# Install build dependencies for luarocks and deck CLI
RUN apt-get update && apt-get install -y build-essential wget curl && \
   # Install deck CLI
   curl -sL https://github.com/kong/deck/releases/download/v1.40.2/deck_1.40.2_linux_amd64.tar.gz -o /tmp/deck.tar.gz && \
   tar -xf /tmp/deck.tar.gz -C /tmp && \
   mv /tmp/deck /usr/local/bin/deck && \
   chmod +x /usr/local/bin/deck && \
   rm -f /tmp/deck.tar.gz && \
   # Find the actual LuaJIT headers path
   LUAJIT_PATH=$(find /usr -name "lua.h" 2>/dev/null | head -1 | xargs dirname) && \
   echo "Using LuaJIT headers at: $LUAJIT_PATH" && \
   # Install fixed LuaRocks version
   wget -q https://luarocks.org/releases/luarocks-3.12.0.tar.gz && \
   tar -xf luarocks-3.12.0.tar.gz && cd luarocks-3.12.0 && \
   ./configure --with-lua-include="$LUAJIT_PATH" && \
   make install && cd / && rm -rf luarocks-3.12.0* && \
   # Clean up
   apt-get remove -y build-essential wget && apt-get autoremove -y

# Copy rockspec and install dependencies
COPY ascend-astra/kong.rockspec /tmp/kong.rockspec
WORKDIR /tmp

# Install open source dependencies from rockspec
RUN luarocks install kong-circuit-breaker 2.1.1 --server=https://rocks.konghq.com && \
    luarocks install host-interpolate-by-header 1.3.0 --server=https://rocks.konghq.com && \
    luarocks install kong-advanced-router 0.2.1 --server=https://rocks.konghq.com

# Copy all custom plugins
COPY plugins/maintenance /usr/local/share/lua/5.1/kong/plugins/maintenance
COPY plugins/conditional-req-termination /usr/local/share/lua/5.1/kong/plugins/conditional-req-termination
COPY plugins/strip-headers /usr/local/share/lua/5.1/kong/plugins/strip-headers
COPY plugins/rate-limiting-v2 /usr/local/share/lua/5.1/kong/plugins/rate-limiting-v2
COPY plugins/swap-header /usr/local/share/lua/5.1/kong/plugins/swap-header
COPY plugins/cors /usr/local/share/lua/5.1/kong/plugins/cors
COPY plugins/api-key-auth /usr/local/share/lua/5.1/kong/plugins/api-key-auth
COPY plugins/tenant-manager /usr/local/share/lua/5.1/kong/plugins/tenant-manager

# Copy initialization scripts
COPY docker/init-db.sql /docker-entrypoint-initdb.d/
COPY docker/seed-tenant.sh /usr/local/bin/seed-tenant.sh
COPY docker/entrypoint.sh /usr/local/bin/custom-entrypoint.sh

RUN chmod +x /usr/local/bin/seed-tenant.sh /usr/local/bin/custom-entrypoint.sh

# Switch back to kong user
USER kong

WORKDIR /

ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
CMD ["kong", "docker-start"]

