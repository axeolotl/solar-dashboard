#!/bin/bash
SCRIPTDIR=`dirname $0`
set -a  # export all variables from config.sh (used by docker-compose.yml)
. "${SCRIPTDIR}/config.sh"
set +a
docker compose -p solar_dashboard -f "${SCRIPTDIR}/docker-compose.yml" down
