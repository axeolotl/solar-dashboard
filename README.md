
Prerequisites:
- docker
- docker-compose

Installation:
- edit config.sh to provide `SOLAR_HEAT_DIR` and `WLAN_SD_IP`
- edit config.sh to chose your passwords for `GRAFANA_ADMIN_PASSWORD` and `PG_ADMIN_PASSWORD`
- edit crontab to provide project directory
- then:
```bash
# create docker resources
./init-docker.sh
# docker compose up
./run-docker.sh
# load data from files into database
./init-db.sh
# regularly update files from WLAN-SD card
crontab < crontab
```
- login as admin at http://localhost:3000/ 
- TODO: fix daily / weekly graphs
- see your data
