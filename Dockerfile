FROM kong:3.6-ubuntu

USER root

# Install build dependencies for luarocks
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy rockspec and install dependencies
COPY ascend-kong/kong.rockspec /tmp/kong.rockspec
WORKDIR /tmp

# Install open source dependencies from rockspec
RUN luarocks install kong-circuit-breaker 2.1.1 && \
    luarocks install host-interpolate-by-header 1.3.0 && \
    luarocks install kong-advanced-router 0.2.1 && \
    luarocks install lua-resty-jwt 0.2.2

# Copy all custom plugins
COPY plugins/maintenance /usr/local/share/lua/5.1/kong/plugins/maintenance
COPY plugins/conditional-req-termination /usr/local/share/lua/5.1/kong/plugins/conditional-req-termination
COPY plugins/strip-headers /usr/local/share/lua/5.1/kong/plugins/strip-headers
COPY plugins/rate-limiting-v2 /usr/local/share/lua/5.1/kong/plugins/rate-limiting-v2
COPY plugins/swap-header /usr/local/share/lua/5.1/kong/plugins/swap-header
COPY plugins/cors /usr/local/share/lua/5.1/kong/plugins/cors

# Switch back to kong user
USER kong

WORKDIR /

ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
CMD ["kong", "docker-start"]

