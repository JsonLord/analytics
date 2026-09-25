---
title: Plausible Analytics
emoji: 📈
colorFrom: blue
colorTo: indigo
sdk: docker
app_port: 7860
pinned: false
---

# Plausible Analytics on Hugging Face Spaces

This is an optimized deployment of [Plausible Analytics Community Edition (CE)](https://github.com/plausible/analytics) on Hugging Face Spaces.

## Setup & Running
This Space is built using the Docker SDK with mandatory endpoints exposed.
- **Port:** `7860`
- **Health Endpoint:** `/health`
- **Documentation:** `/api-docs`

## Self-contained database (open source, no external services)

Plausible needs a PostgreSQL database and a ClickHouse database. This Space
runs both **inside the same container**, using the open-source PostgreSQL
and ClickHouse server binaries, so it works with zero external database
setup — no managed Postgres/ClickHouse account required.

This happens automatically: if `DATABASE_URL` and `CLICKHOUSE_DATABASE_URL`
are not set as Space secrets, `rel/docker-entrypoint.sh` sources
`rel/self_contained_db.sh` to initialize and start a local PostgreSQL 15
and ClickHouse server (both loopback-only, not exposed outside the
container), then runs the Ecto migrations before the app boots.

To use an external, managed Postgres/ClickHouse instead (e.g. for
production traffic beyond what a single container can handle), just set
`DATABASE_URL` and `CLICKHOUSE_DATABASE_URL` as Space secrets — the
embedded databases are skipped entirely whenever either is set.

### Persisting data across restarts

Without Hugging Face's **Persistent Storage** add-on enabled on this Space,
the embedded databases live on the container's local (ephemeral) disk at
`/var/lib/plausible` — data survives simple restarts of a running instance
but is **lost on every rebuild/redeploy**. Enabling Persistent Storage
(mounted at `/data`) is detected automatically and used instead, so data
survives redeploys too.
