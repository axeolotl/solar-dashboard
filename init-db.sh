#!/bin/sh
# raspberry pie edition
SCRIPTDIR=`dirname $0`
set -a  # export all variables from config.sh (used by docker-compose.yml)
. "${SCRIPTDIR}/config.sh"
set +a
if [ -z "${PG_GRAFANA_PASSWORD}" ] ; then
  echo "PG_GRAFANA_PASSWORD must be set in config.sh" >&2
  exit 1
fi
case "${PG_GRAFANA_PASSWORD}" in
  *'$'*) echo "PG_GRAFANA_PASSWORD must not contain '\$' (grafana expands it in datasources.yml)" >&2
         exit 1 ;;
esac
docker compose -p solar_dashboard -f "${SCRIPTDIR}/docker-compose.yml" exec -T postgres \
  psql -U postgres -v grafana_password="${PG_GRAFANA_PASSWORD}" <${SCRIPTDIR}/init-db.sql
