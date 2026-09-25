#!/bin/sh
set -e

if [ "$1" = 'run' ]; then
      if [ "${SELF_CONTAINED_DB:-auto}" != "false" ] && [ -z "${DATABASE_URL}" ] && [ -z "${CLICKHOUSE_DATABASE_URL}" ]; then
        # No external Postgres/ClickHouse configured: run an embedded,
        # open-source instance of each inside this container.
        . /self_contained_db.sh
        self_contained_db_start
        trap self_contained_db_stop TERM INT

        /app/bin/plausible start &
        wait $!
        exit $?
      fi

      exec /app/bin/plausible start

elif [ "$1" = 'db' ]; then
      exec /app/"$2".sh
 else
      exec "$@"

fi

exec "$@"
