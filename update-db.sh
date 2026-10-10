#!/bin/sh
N=1
SCRIPTDIR=`dirname $0`
set -a  # export all variables from config.sh (used by docker-compose.yml)
. "${SCRIPTDIR}/config.sh"
set +a
TMPFILE=${SOLAR_HEAT_DIR}/delta.txt
if [ -n "$1" ] ; then
  N=$1
fi
if [ -f "$TMPFILE" ] ; then
  rm $TMPFILE
fi
touch $TMPFILE
while [ $N -ge 0 ] ; do
  D="-$N days"
  cat ${SOLAR_HEAT_DIR}/$(date +%Y "--date=$D")/$(date +%m "--date=$D")/$(date +%Y%m%d "--date=$D").TXT >> $TMPFILE
  N=$((N - 1))
done
docker compose -p solar_dashboard -f "${SCRIPTDIR}/docker-compose.yml" exec -T postgres psql -U postgres <${SCRIPTDIR}/update-db.sql
