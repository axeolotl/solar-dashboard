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
  # wget -x -nH --cut-dirs=1 "--directory-prefix=${SOLAR_HEAT_DIR}" http://${WLAN_SD_IP}/SC514/${DIR}/${FILE}
  if head -1 ${SOLAR_HEAT_DIR}/${DIR}/$FILE | grep -q DOCTYPE ; then
    echo Error response file, not uploading: ${SOLAR_HEAT_DIR}/${DIR}/$FILE
  else
    ssh solarinbox@solar.ferne-gefil.de "mkdir -p SC514/${DIR}"
    scp ${SOLAR_HEAT_DIR}/${DIR}/${FILE} solarinbox@solar.ferne-gefil.de:SC514/${DIR}/${FILE}
  fi
  N=$((N - 1))
done
