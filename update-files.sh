#!/bin/sh
N=1
SCRIPTDIR=`dirname $0`
. "$SCRIPTDIR/config.sh"
if [ -n "$1" ] ; then
  N=$1
fi
while [ $N -ge 0 ] ; do
  D="-$N days"
  wget -x -nH --cut-dirs=1 "--directory-prefix=${SOLAR_HEAT_DIR}" http://${WLAN_SD_IP}/SC514/$(date +%Y "--date=$D")/$(date +%m "--date=$D")/$(date +%Y%m%d "--date=$D").TXT
  N=$((N - 1))
done
