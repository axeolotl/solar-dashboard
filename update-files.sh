#!/bin/sh
N=1
SCRIPTDIR=`dirname $0`
. "$SCRIPTDIR/config.sh"
if [ -n "$1" ] ; then
  N=$1
fi
while [ $N -ge 0 ] ; do
  D="-$N days"
  DIR=$(date +%Y "--date=$D")/$(date +%m "--date=$D")
  FILE=$(date +%Y%m%d "--date=$D").TXT
  wget -x -nH --cut-dirs=1 "--directory-prefix=${SOLAR_HEAT_DIR}" http://${WLAN_SD_IP}/SC514/${DIR}/${FILE}
  N=$((N - 1))
done
