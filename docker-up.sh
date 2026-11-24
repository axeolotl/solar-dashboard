#!/bin/bash
# Starts (or updates) all containers with the settings from .env and the
# passwords from secrets/, then syncs the grafanareader database password.
cd "$(dirname "$0")" || exit 1
./check-config.sh || exit 1

docker compose up -d --remove-orphans || exit 1

# Keep the password of the database user grafanareader (created by
# init-db.sh) in sync with secrets/pg_grafana_password, so that changing the
# file and running docker-up.sh is enough. The password is read inside the
# container and never appears on a command line.
end=$((SECONDS + 60))
until docker compose exec -T postgres pg_isready -U postgres -q 2>/dev/null ; do
  if [ $SECONDS -ge $end ] ; then
    echo "postgres not ready, grafanareader password not synced" >&2
    exit 1
  fi
  sleep 2
done
docker compose exec -T postgres psql -U postgres -q -v ON_ERROR_STOP=1 <<'SQL' || exit 1
\set grafana_password `cat /run/secrets/pg_grafana_password`
SELECT format('ALTER ROLE grafanareader WITH LOGIN PASSWORD %L', :'grafana_password')
  WHERE EXISTS (SELECT FROM pg_roles WHERE rolname = 'grafanareader')\gexec
SQL
