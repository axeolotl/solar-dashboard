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

* Grafana 13.3.0 (`grafana/grafana:13.3.0-ubuntu`)
* PostgreSQL 18.6 (`postgres:18.6`)
* Caddy 2.11.7 (`caddy:2.11.7`)

See [UPDATING.md](UPDATING.md) for how to update them and how to test an update
(`test/smoke-test.sh`).

Installation:

* settings: create `.env` (read by docker compose and the scripts, not under
  version control) from `.env.example` and set `SOLAR_HEAT_DIR`, `WLAN_SD_IP`,
  `DASHBOARD_DOMAIN` and `GRAFANA_VIEWER_USER`. Plain `KEY=value` lines (the
  scripts also source it with `sh`), single-quote values containing spaces:

  ```bash
  cp .env.example .env   # then edit .env
  ```
* passwords: one file per password in `secrets/` (not under version control),
  passed to the containers as [compose secrets](https://docs.docker.com/compose/how-tos/use-secrets/)
  (mounted at `/run/secrets/<name>`, not visible in `docker inspect`):

  | file | password of |
  |---|---|
  | `secrets/grafana_admin_password` | Grafana user `admin` (no `$`) |
  | `secrets/grafana_viewer_password` | Grafana user `GRAFANA_VIEWER_USER` (any content if empty) |
  | `secrets/pg_admin_password` | PostgreSQL superuser `postgres` |
  | `secrets/pg_grafana_password` | read-only database user `grafanareader` of the Grafana data source (no `$`) |

  Write them without trailing newline (`printf '%s'`, not `echo`). The files
  must be readable by the containers (Grafana runs as uid 472), so make them
  `644` and protect the directory instead:

  ```bash
  mkdir -m 700 secrets
  printf '%s' 'your-admin-password'   > secrets/grafana_admin_password
  printf '%s' 'your-viewer-password'  > secrets/grafana_viewer_password
  printf '%s' 'your-pg-admin-password' > secrets/pg_admin_password
  printf '%s' 'your-reader-password'  > secrets/pg_grafana_password
  chmod 644 secrets/*
  ./check-config.sh   # also run by docker-up.sh, which refuses to start on problems
  ```
* edit crontab to provide project directory
* then:

```bash
# docker compose up (creates the volumes on the first run); plain
# "docker compose ..." commands work in this directory, too
./docker-up.sh
# load data from files into database
./init-db.sh
# regularly update files from WLAN-SD card
crontab < crontab
```

* optionally deploy new versions from GitHub automatically, see
  [UPDATING.md](UPDATING.md#automatic-deployment)

* login as admin at https://DASHBOARD_DOMAIN/
* select dashboard "Solar Dashboard"
* see your data
* a read-only user `GRAFANA_VIEWER_USER` (role "Viewer", e.g. for kiosk mode) is
  created by the one-shot service `grafana-users` (`grafana-users.sh`) on every
  `./docker-up.sh`; changing `secrets/grafana_viewer_password` and running
  `./docker-up.sh` updates the password. Leave `GRAFANA_VIEWER_USER` empty to skip.

Note: `secrets/grafana_admin_password` is only applied when Grafana initializes its
database in the `solar_dashboard_grafana-storage` volume for the first time.
To change it later, change it in the Grafana UI *and* in the file: the
`grafana-users` job (and `auto-deploy.sh` without a viewer user) log in with
it. To start from scratch instead: `./docker-down.sh && docker volume rm
solar_dashboard_grafana-storage && ./docker-up.sh`.

Changing a password file: compose does not notice changed secret contents, so
recreate the containers with `./docker-down.sh && ./docker-up.sh`.
`docker-up.sh` also sets the `grafanareader` database password from
`secrets/pg_grafana_password` on every run.

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

PostgreSQL data is now kept in the named volume `solar_dashboard_postgres-data`
(mounted at `/var/lib/postgresql`, as required by the PostgreSQL 18 images).
The old PostgreSQL 9 data lived in an anonymous volume and can be removed
with `docker volume prune`.

All volumes are managed by docker compose and named `solar_dashboard_<name>`
(`grafana-storage`, `postgres-data`, `caddy-data`, `caddy-config`).

### Migrating from config.sh / config.local.sh

`config.sh` and `config.local.sh` were replaced by `.env` and `secrets/`. The
commit is marked `Deploy: manual`, so `auto-deploy.sh` refuses it and keeps
the dashboard running until you migrate by hand, in the checkout on the host:

```bash
cd ~/solar-dashboard
# 0. the installation must be on the last version before the switch, i.e. it
#    uses the volume solar_dashboard_grafana-storage (not grafana-storage):
docker inspect solar_dashboard-grafana-1 --format '{{range .Mounts}}{{.Name}} {{end}}'
# 1. update the checkout (config.local.sh stays, it is not tracked)
git fetch && git merge --ff-only origin/master
# 2. convert the old settings (old config.sh with your config.local.sh on top)
OLD=$(git log -1 --format=%H --diff-filter=D -- config.sh)^
( SCRIPTDIR=. ; eval "$(git show "$OLD:config.sh")"
  { echo "SOLAR_HEAT_DIR='$SOLAR_HEAT_DIR'"
    echo "WLAN_SD_IP=$WLAN_SD_IP"
    echo "DASHBOARD_DOMAIN=$DASHBOARD_DOMAIN"
    echo "GRAFANA_VIEWER_USER=$GRAFANA_VIEWER_USER"; } > .env
  mkdir -p -m 700 secrets
  printf '%s' "$GRAFANA_ADMIN_PASSWORD"  > secrets/grafana_admin_password
  printf '%s' "${GRAFANA_VIEWER_PASSWORD:-unused}" > secrets/grafana_viewer_password
  printf '%s' "$PG_ADMIN_PASSWORD"       > secrets/pg_admin_password
  printf '%s' "$PG_GRAFANA_PASSWORD"     > secrets/pg_grafana_password
  chmod 644 secrets/* )
cat .env; ./check-config.sh && echo config OK
# 3. recreate the containers with the secrets (data volumes are kept)
./docker-up.sh
./auto-deploy.sh; echo $?   # silent, 0: nothing new to deploy
# 4. check the dashboard in the browser, then remove the old file
rm config.local.sh
```

`GRAFANA_ADMIN_PASSWORD` in `config.local.sh` must be the *current* admin
password (if you changed it in the Grafana UI, put that one into
`secrets/grafana_admin_password`), otherwise the `grafana-users` job fails.
The PostgreSQL superuser password is only set when the database volume is
created, so `secrets/pg_admin_password` is not used by the existing database
(local connections in the container don't need it). No re-import is needed.

## TODO
* turn update scripts into a docker image, too