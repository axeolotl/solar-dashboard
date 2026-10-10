# Solar Dashboard for PAW Solex

[![smoke test](https://github.com/axeolotl/solar-dashboard/actions/workflows/smoke-test.yml/badge.svg)](https://github.com/axeolotl/solar-dashboard/actions/workflows/smoke-test.yml)

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
* Caddy 2.11.7 (`caddy:2.11.7`)

See [UPDATING.md](UPDATING.md) for how to update them and how to test an update
(`test/smoke-test.sh`).

Installation:

* edit config.sh to provide `SOLAR_HEAT_DIR`, `WLAN_SD_IP` and `DASHBOARD_DOMAIN`
* edit config.sh to chose your passwords for `GRAFANA_ADMIN_PASSWORD`, `PG_ADMIN_PASSWORD` and `PG_GRAFANA_PASSWORD` (read-only database user used by Grafana, must not contain `$`)
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

* login as admin at https://DASHBOARD_DOMAIN/
* select dashboard "Solar Dashboard"
* see your data
* a read-only user `GRAFANA_VIEWER_USER` (role "Viewer", e.g. for kiosk mode) is
  created by the one-shot service `grafana-users` (`grafana-users.sh`) on every
  `./docker-up.sh`; changing `GRAFANA_VIEWER_PASSWORD` in config.sh and running
  `./docker-up.sh` updates the password. Leave `GRAFANA_VIEWER_USER` empty to skip.

Note: `GRAFANA_ADMIN_PASSWORD` is only applied when Grafana initializes its
database in the `grafana-storage` volume for the first time. Change the
password in the Grafana UI afterwards (or `docker volume rm grafana-storage`
and re-run `./init-docker.sh` to start from scratch).

## HTTPS

Grafana is only reachable through the [Caddy](https://caddyserver.com/)
reverse proxy (see `Caddyfile`), which obtains and renews a Let's Encrypt
certificate for `DASHBOARD_DOMAIN` automatically. Requirements:

* a DNS A/AAAA record for `DASHBOARD_DOMAIN` pointing to the docker host
* ports 80 and 443 (TCP, plus 443/UDP for HTTP/3) forwarded to the docker host

Certificates are kept in the `caddy-data` volume; don't delete it, or Caddy
has to request new certificates (Let's Encrypt rate limits apply).
For a quick local test, `DASHBOARD_DOMAIN=localhost` makes Caddy use a
self-signed certificate from its internal CA instead.

PostgreSQL is attached to an internal network only: it is reachable by Grafana
(and via `docker compose exec`), but has no connection to the outside.

 the Grafana 6 / PostgreSQL 9 setup

The database contents are imported from the log files, so no dump/restore
is needed:

```bash
./docker-down.sh
git pull
./docker-up.sh
# re-import all log files into the new PostgreSQL 18 database
./init-db.sh
```

To change `PG_GRAFANA_PASSWORD` later, edit config.sh, re-run `./init-db.sh`
(sets the database password) and `./docker-up.sh` (recreates Grafana with the
new data source password).

PostgreSQL data is now kept in the named volume `solar_dashboard_postgres-data`
(mounted at `/var/lib/postgresql`, as required by the PostgreSQL 18 images).
The old PostgreSQL 9 data lived in an anonymous volume and can be removed
with `docker volume prune`.

## TODO
* turn update scripts into a docker image, too