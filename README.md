# Solar Dashboard for PAW Solex
## Intro
This project allows to inspect the data logged by a PAW Solex solar thermal system (SolexMidi etc) in grafana.

In order to get monitoring data out of your solar thermal system, get an SD WLAN card that is able to sign into your existing home WLAN (I am using a Toshiba FlashAir configured in client mode, APPMODE=5), and insert it into the Solex' SD card slot. Make note of the WLAN card's IP address. You may also want to fixate the card's IP adress in your router.

In the Solex menu, activate logging to the SD card. The scripts in this project will mirror the files from the SD card to the local disk.

For starters, you can also use a regular SD card and copy the files manually.

Data will then be imported into a database running in a docker image. A second docker image running grafana accesses and displays the data.

## Software setup

Prerequisites:

* docker
* docker-compose

Installation:

* edit config.sh to provide `SOLAR_HEAT_DIR` and `WLAN_SD_IP`
* edit config.sh to chose your passwords for `GRAFANA_ADMIN_PASSWORD` and `PG_ADMIN_PASSWORD`
* edit crontab to provide project directory
* then:

```bash
# create docker resources
./init-docker.sh
# docker compose up
./docker-up.sh
# load data from files into database
./init-db.sh
# regularly update files from WLAN-SD card
crontab < crontab
```

* login as admin at http://localhost:3000/ 
* select dashboard "Solar Dashboard"
* see your data
* create a user in "Viewer" role if desired e.g. for running in kiosk mode

## TODO
* turn update scripts into a docker image, too