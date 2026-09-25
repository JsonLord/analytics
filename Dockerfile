# we can not use the pre-built tar because the distribution is
# platform specific, it makes sense to build it in the docker


#### Builder
FROM hexpm/elixir:1.20.2-erlang-28.5.0.3-alpine-3.22.5@sha256:8875407828c1b789485f9fcc6006e1ace39bb073b0467a95df3a3905d8d86d30 AS buildcontainer

ARG MIX_ENV=ce

# preparation
ENV MIX_ENV=$MIX_ENV
ENV NODE_ENV=production
ENV NODE_OPTIONS=--openssl-legacy-provider

# custom ERL_FLAGS are passed for (public) multi-platform builds
# to fix qemu segfault, more info: https://github.com/erlang/otp/pull/6340
ARG ERL_FLAGS
ENV ERL_FLAGS=$ERL_FLAGS

RUN mkdir /app
WORKDIR /app

# install build dependencies
RUN apk add --no-cache git "nodejs-current=23.11.1-r0" yarn npm python3 ca-certificates wget gnupg make gcc libc-dev brotli

COPY mix.exs ./
COPY mix.lock ./
COPY config ./config
RUN mix local.hex --force && \
  mix local.rebar --force && \
  mix deps.get --only ${MIX_ENV} && \
  mix deps.compile

COPY assets/package.json assets/package-lock.json ./assets/
COPY tracker/package.json tracker/package-lock.json ./tracker/

RUN npm install --prefix ./assets && \
  npm install --prefix ./tracker

COPY assets ./assets
COPY tracker ./tracker
COPY priv ./priv
COPY lib ./lib
COPY extra ./extra

RUN npm run deploy --prefix ./tracker && \
  mix assets.deploy && \
  mix phx.digest priv/static && \
  mix download_country_database && \
  mix sentry.package_source_code

WORKDIR /app
COPY rel rel
RUN mix release plausible

#### Embedded ClickHouse binary, for self-contained deployments (e.g.
#### Hugging Face Spaces) that have no external ClickHouse instance.
FROM clickhouse/clickhouse-server:26.3-alpine AS clickhouse_binary

# Main Docker Image
FROM alpine:3.22.5@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce
LABEL maintainer="plausible.io <hello@plausible.io>"

ARG BUILD_METADATA={}
ENV BUILD_METADATA=$BUILD_METADATA
ENV LANG=C.UTF-8
ARG MIX_ENV=ce
ENV MIX_ENV=$MIX_ENV

RUN adduser -S -H -u 999 -G nogroup plausible

RUN apk upgrade --no-cache
RUN apk add --no-cache openssl ncurses libstdc++ libgcc ca-certificates tini \
  postgresql15 postgresql15-contrib \
  && if [ "$MIX_ENV" = "ce" ]; then apk add --no-cache certbot; fi

# Embedded, open-source ClickHouse server used by rel/self_contained_db.sh
# when no external CLICKHOUSE_DATABASE_URL is configured. The upstream
# "-alpine" image is glibc-linked (unlike this musl-based base), so its
# glibc runtime is copied over alongside the binary.
COPY --from=clickhouse_binary /usr/bin/clickhouse /usr/bin/clickhouse
COPY --from=clickhouse_binary \
  /lib/ld-2.35.so /lib/libc.so.6 /lib/libdl.so.2 /lib/libm.so.6 \
  /lib/libnss_dns.so.2 /lib/libnss_files.so.2 /lib/libpthread.so.0 \
  /lib/libresolv.so.2 /lib/librt.so.1 \
  /lib/
RUN mkdir -p /lib64 \
  && ln -s /lib/ld-2.35.so /lib64/ld-linux-x86-64.so.2 \
  && ln -s /usr/bin/clickhouse /usr/bin/clickhouse-server \
  && ln -s /usr/bin/clickhouse /usr/bin/clickhouse-client \
  && mkdir -p /etc/clickhouse-server \
  && chown -R plausible:nogroup /etc/clickhouse-server
COPY --chmod=644 ./rel/clickhouse/config.xml ./rel/clickhouse/users.xml /etc/clickhouse-server/
RUN chown -R plausible:nogroup /etc/clickhouse-server

COPY --from=buildcontainer --chmod=555 /app/_build/${MIX_ENV}/rel/plausible /app
COPY --chmod=755 ./rel/docker-entrypoint.sh /entrypoint.sh
COPY --chmod=755 ./rel/self_contained_db.sh /self_contained_db.sh

# we need to allow "others" access to app folder, because
# docker container can be started with arbitrary uid
RUN mkdir -p /var/lib/plausible && chmod ugo+rw -R /var/lib/plausible

USER 999
WORKDIR /app
ENV LISTEN_IP=0.0.0.0
ENV PORT=7860
ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
EXPOSE 7860
ENV DEFAULT_DATA_DIR=/var/lib/plausible
VOLUME /var/lib/plausible
CMD ["run"]

