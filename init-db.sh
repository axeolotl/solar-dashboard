#!/bin/sh
# raspberry pie edition
SCRIPTDIR=`dirname $0`
cd "${SCRIPTDIR}"
. ./config.sh
DOCKER_COMPOSE_PROJECT=`basename "$PWD"`
docker run -i -a stdin -a stdout -a stderr --rm --network ${DOCKER_COMPOSE_PROJECT}_grafnet --link postgres:postgres -e PGPASSWORD="${PG_ADMIN_PASSWORD}" postgres psql -h postgres -U postgres <$SCRIPTDIR/init-db.sql 