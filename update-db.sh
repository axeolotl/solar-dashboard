#!/bin/sh
N=1
cd "$(dirname "$0")" || exit 1
set -a; . ./.env; set +a
TMPFILE=${SOLAR_HEAT_DIR}/delta.txt
if [ -n "$1" ] ; then
  N=$1
fi
if [ -f "$TMPFILE" ] ; then
  rm "$TMPFILE"
fi
touch "$TMPFILE"
while [ $N -ge 0 ] ; do
  D="-$N days"
  cat "${SOLAR_HEAT_DIR}/$(date +%Y "--date=$D")/$(date +%m "--date=$D")/$(date +%Y%m%d "--date=$D").TXT" >> "$TMPFILE"
  N=$((N - 1))
done
docker compose exec -T postgres psql -U postgres <update-db.sql
