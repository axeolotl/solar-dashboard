#!/bin/sh
N=1
SCRIPTDIR=`dirname $0`
. "${SCRIPTDIR}/config.sh"
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
docker run -i -a stdin -a stdout -a stderr --rm --network solar_dashboard_grafnet --link postgres:postgres -e PGPASSWORD="topsecret" postgres psql -h postgres -U postgres <${SCRIPTDIR}/update-db.sql 
