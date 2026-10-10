#!/bin/bash
SCRIPTDIR=`dirname $0`
set -a  # export all variables from config.sh (used by docker-compose.yml)
. "${SCRIPTDIR}/config.sh"
set +a
COMPOSE=(docker compose -p solar_dashboard -f "${SCRIPTDIR}/docker-compose.yml")

# One-time migration: grafana-storage used to be an external volume created by
# the former init-docker.sh. It is now managed by compose like the other
# volumes, as solar_dashboard_grafana-storage. Copy the data once (with
# Grafana stopped, for a consistent grafana.db) and keep the old volume as a
# backup - remove it with "docker volume rm grafana-storage" once satisfied.
OLD_VOL=grafana-storage NEW_VOL=solar_dashboard_grafana-storage
if docker volume inspect "$OLD_VOL" >/dev/null 2>&1 &&
   ! docker volume inspect "$NEW_VOL" >/dev/null 2>&1 ; then
  echo "migrating volume $OLD_VOL to $NEW_VOL (keeping $OLD_VOL as a backup)"
  "${COMPOSE[@]}" stop grafana >/dev/null 2>&1
  GRAFANA_IMAGE=$("${COMPOSE[@]}" config --images | grep -m1 grafana)
  if ! { docker volume create --label com.docker.compose.project=solar_dashboard \
           --label com.docker.compose.volume=grafana-storage "$NEW_VOL" >/dev/null &&
         docker run --rm --user 0 --entrypoint cp -v "$OLD_VOL:/from:ro" -v "$NEW_VOL:/to" \
           "$GRAFANA_IMAGE" -a /from/. /to/ ; } ; then
    echo "ERROR: migration of $OLD_VOL failed, Grafana not started" >&2
    docker volume rm "$NEW_VOL" >/dev/null 2>&1
    exit 1
  fi
fi

"${COMPOSE[@]}" up -d --remove-orphans
