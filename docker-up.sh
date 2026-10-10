#!/bin/bash
SCRIPTDIR=`dirname $0`
set -a  # export all variables from config.sh (used by docker-compose.yml)
. "${SCRIPTDIR}/config.sh"
set +a
docker compose -p solar_dashboard -f "${SCRIPTDIR}/docker-compose.yml" up -d --remove-orphans

# docker run \
#  -d \
#  -p 3000:3000 \
#  --name=grafana \
#  -v grafana-storage:/var/lib/grafana \
#  grafana/grafana
