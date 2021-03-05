#!/bin/bash
SCRIPTDIR=`dirname $0`
. "${SCRIPTDIR}/config.sh"
export PG_ADMIN_PASSWORD SOLAR_HEAT_DIR GRAFANA_ADMIN_PASSWORD INFLUXDB_ADMIN_PASSWORD INFLUXDB_WRITE_USER_PASSWORD INFLUXDB_READ_USER_PASSWORD
docker-compose up -d 

# docker run \
#  -d \
#  -p 3000:3000 \
#  --name=grafana \
#  -v grafana-storage:/var/lib/grafana \
#  grafana/grafana
