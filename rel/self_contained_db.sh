# Starts an embedded, open-source PostgreSQL + ClickHouse stack inside this
# container, so Plausible has no external database dependency. This is for
# single-container deployments (e.g. Hugging Face Spaces) where no separate
# database services can be provisioned alongside the app.
#
# Sourced (not executed) from rel/docker-entrypoint.sh, which decides
# whether self-contained mode applies and calls self_contained_db_start /
# self_contained_db_stop.

self_contained_db_start() {
  data_root="${DEFAULT_DATA_DIR:-/var/lib/plausible}"
  if [ -d /data ] && [ -w /data ]; then
    # Hugging Face Space "Persistent Storage" is mounted at /data; prefer it
    # so the databases survive Space restarts/rebuilds.
    data_root="/data"
  fi

  pg_data="$data_root/postgresql"
  pg_run="$data_root/postgresql-run"
  ch_data="$data_root/clickhouse"

  mkdir -p "$pg_data" "$pg_run" \
    "$ch_data/tmp" "$ch_data/user_files" "$ch_data/format_schemas"

  if [ ! -s "$pg_data/PG_VERSION" ]; then
    echo "[self-contained-db] Initializing embedded PostgreSQL at $pg_data"
    initdb -D "$pg_data" -U postgres --auth=trust --no-locale --encoding=UTF8
  fi

  echo "[self-contained-db] Starting embedded PostgreSQL"
  postgres -D "$pg_data" \
    -c listen_addresses=127.0.0.1 \
    -c unix_socket_directories="$pg_run" \
    -c port=5432 &
  pg_pid=$!

  i=0
  until pg_isready -h "$pg_run" -U postgres -q; do
    i=$((i + 1))
    if [ "$i" -ge 60 ]; then
      echo "[self-contained-db] PostgreSQL did not become ready within 60s" >&2
      exit 1
    fi
    sleep 1
  done

  echo "[self-contained-db] Starting embedded ClickHouse"
  clickhouse server \
    --config-file=/etc/clickhouse-server/config.xml \
    -- \
    --path="$ch_data/" \
    --tmp_path="$ch_data/tmp/" \
    --user_files_path="$ch_data/user_files/" \
    --format_schema_path="$ch_data/format_schemas/" &
  ch_pid=$!

  i=0
  until wget -q -O /dev/null "http://127.0.0.1:8123/ping"; do
    i=$((i + 1))
    if [ "$i" -ge 60 ]; then
      echo "[self-contained-db] ClickHouse did not become ready within 60s" >&2
      exit 1
    fi
    sleep 1
  done

  export DATABASE_URL="${DATABASE_URL:-postgresql://postgres:@/plausible_db?host=$pg_run}"
  export CLICKHOUSE_DATABASE_URL="${CLICKHOUSE_DATABASE_URL:-http://127.0.0.1:8123/plausible_events_db}"

  echo "[self-contained-db] Ensuring schema is up to date"
  /app/bin/plausible eval "Plausible.Release.createdb(); Plausible.Release.interweave_migrate()"
}

self_contained_db_stop() {
  echo "[self-contained-db] Shutting down embedded PostgreSQL and ClickHouse"
  [ -n "$pg_data" ] && pg_ctl -D "$pg_data" -m fast stop >/dev/null 2>&1
  [ -n "$ch_pid" ] && kill "$ch_pid" 2>/dev/null
  exit 0
}
