
Prerequisites:
- docker
- docker-compose

Installation:
- edit config.sh to provide `SOLAR_HEAT_DIR` and WLAN_SD_IP
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
- TODO: automatically configure datasource and dashboard
- see your data
