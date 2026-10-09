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
* docker compose plugin (Compose v2, `docker compose ...`)

Components (pinned in `docker-compose.yml`):

* Grafana 13.2.3 (`grafana/grafana:13.2.3-ubuntu`)
* PostgreSQL 18.6 (`postgres:18.6`)

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

Note: `GRAFANA_ADMIN_PASSWORD` is only applied when Grafana initializes its
database in the `grafana-storage` volume for the first time. Change the
password in the Grafana UI afterwards (or `docker volume rm grafana-storage`
and re-run `./init-docker.sh` to start from scratch).

## Upgrading from the Grafana 6 / PostgreSQL 9 setup

The database contents are imported from the log files, so no dump/restore
is needed:

```bash
./docker-down.sh
git pull
./docker-up.sh
# re-import all log files into the new PostgreSQL 18 database
./init-db.sh
```

PostgreSQL data is now kept in the named volume `solar_dashboard_postgres-data`
(mounted at `/var/lib/postgresql`, as required by the PostgreSQL 18 images).
The old PostgreSQL 9 data lived in an anonymous volume and can be removed
with `docker volume prune`.

## TODO
* turn update scripts into a docker image, too