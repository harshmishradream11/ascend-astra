FROM dreamsports.jfrog.io/d11-docker-artifacts/actions-runner-maven:ubuntu-20.04

USER root

RUN set -ex \
    && apt update -y \
    && apt install -y luajit=2.1.0~beta3+dfsg-5.1build1 \
    && apt install -y cmake=3.16.3-1ubuntu1.20.04.1 \
    && apt install -y luarocks \
    && wget https://luarocks.org/releases/luarocks-3.9.2.tar.gz \
    && tar -zxpf luarocks-3.9.2.tar.gz \
    && cd luarocks-3.9.2 \
    && ./configure \
    && make \
    && make install \
    && luarocks install --server=https://luarocks.org/dev luaformatter \
    && cd /usr/local/bin \
    && ln -s /luarocks-3.9.2/lua_modules/lib/luarocks/rocks-5.1/luaformatter/scm-1/bin/lua-format lua-format \
    && rm /luarocks-3.9.2.tar.gz

USER runner
