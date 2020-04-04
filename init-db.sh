#!/bin/sh
# raspberry pie edition
SCRIPTDIR=`dirname $0`
. "$SCRIPTDIR/config.sh"
docker run -i -a stdin -a stdout -a stderr --rm --network solar_dashboard_grafnet --link postgres:postgres -e PGPASSWORD="${PG_ADMIN_PASSWORD}" postgres psql -h postgres -U postgres <$SCRIPTDIR/init-db.sql 