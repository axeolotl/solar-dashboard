#!/bin/sh
# (Re-)creates the database from the log files in SOLAR_HEAT_DIR. The
# grafanareader password is read from secrets/pg_grafana_password inside the
# postgres container (see init-db.sql).
cd "$(dirname "$0")" || exit 1
./check-config.sh || exit 1
docker compose exec -T postgres psql -U postgres <init-db.sql
