#!/bin/bash
BACKUP_NAME=influx-`date -I`.bak
BACKUP_PATH=$HOME/backups/$BACKUP_NAME
if [ -d "$BACKUP_PATH"] ; then
  echo "Backup directory already exists: $BACKUP_PATH"
  exit 1
fi
if ! mkdir -p $BACKUP_PATH ; then
  echo "Could not create backup directory: $BACKUP_PATH"
  exit 1
fi
docker run -it -v $BACKUP_PATH/:/backup/ --network solar-dashboard_frontnet --link influxdb influxdb:1.8 influxd backup -host influxdb:8088 -portable /backup
( cd $BACKUP_PATH ; tar cfz $BACKUP_PATH.tgz . )
rm -rf $BACKUP_PATH
