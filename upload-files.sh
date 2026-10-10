#!/bin/sh
N=1
SCRIPTDIR=`dirname $0`
. "$SCRIPTDIR/config.sh"
if [ -n "$1" ] ; then
  N=$1
fi
while [ $N -ge 0 ] ; do
  D="-$N days"
  YEAR=$(date +%Y "--date=$D")
  MONTH=$(date +%m "--date=$D")
  DIR=${YEAR}/${MONTH}
  FILE=$(date +%Y%m%d "--date=$D").TXT
  # wget -x -nH --cut-dirs=1 "--directory-prefix=${SOLAR_HEAT_DIR}" http://${WLAN_SD_IP}/SC514/${DIR}/${FILE}
  if head -1 ${SOLAR_HEAT_DIR}/${DIR}/$FILE | grep -q DOCTYPE ; then
    echo Error response file, not uploading: ${SOLAR_HEAT_DIR}/${DIR}/$FILE
  else
    # sftp instead of ssh+scp: works with a nologin account restricted to
    # internal-sftp. A leading "-" ignores errors (directory already exists).
    sftp -b - solarinbox@solar.ferne-gefil.de <<EOF
-mkdir SC514
-mkdir "SC514/${YEAR}"
-mkdir "SC514/${DIR}"
put "${SOLAR_HEAT_DIR}/${DIR}/${FILE}" "SC514/${DIR}/${FILE}"
EOF
  fi
  N=$((N - 1))
done
