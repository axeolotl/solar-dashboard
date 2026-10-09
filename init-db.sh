#!/bin/sh
# raspberry pie edition
SCRIPTDIR=`dirname $0`
. "$SCRIPTDIR/config.sh"
export PG_ADMIN_PASSWORD SOLAR_HEAT_DIR GRAFANA_ADMIN_PASSWORD
docker compose -p solar_dashboard -f "${SCRIPTDIR}/docker-compose.yml" exec -T postgres psql -U postgres <${SCRIPTDIR}/init-db.sql
