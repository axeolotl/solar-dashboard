#!/bin/bash
SCRIPTDIR=`dirname $0`
. "${SCRIPTDIR}/config.sh"
export PG_ADMIN_PASSWORD SOLAR_HEAT_DIR
docker-compose -p solar_dashboard up -d 

# docker run \
#  -d \
#  -p 3000:3000 \
#  --name=grafana \
#  -v grafana-storage:/var/lib/grafana \
#  grafana/grafana
