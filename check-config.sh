#!/bin/bash
# Checks the local configuration against what the repository expects:
#  - .env exists and sets every key listed in .env.example
#  - every secret file referenced in docker-compose.yml exists in secrets/,
#    is readable by the containers and well-formed
# Prints the problems and exits 1 if anything is wrong. Called by
# docker-up.sh and init-db.sh, and by auto-deploy.sh for the new revision
# before it is merged.
#
# usage: check-config.sh [git-rev]
#   git-rev: check against .env.example / docker-compose.yml of that revision
#            instead of the checked-out files
#   CONFIG_DIR: checkout to check (default: directory of this script)
set -u
cd "${CONFIG_DIR:-$(dirname "$0")}" || exit 1
REV=${1:-}
show() { if [ -n "$REV" ] ; then git show "$REV:$1" ; else cat "$1" ; fi ; }
ERR=0
err() { echo "config: $*" >&2; ERR=1; }

if [ ! -f .env ] ; then
  err ".env missing - create it from .env.example (see README.md, Installation)"
  exit 1
fi
keys() { sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p' | sort -u; }
for k in $(show .env.example | keys) ; do
  grep -qE "^$k=" .env || err "$k missing in .env (new setting? see .env.example)"
done
set -a; . ./.env; set +a
for k in SOLAR_HEAT_DIR DASHBOARD_DOMAIN ; do
  [ -n "${!k:-}" ] || err "$k must not be empty in .env"
done
[ -z "${SOLAR_HEAT_DIR:-}" ] || [ -d "$SOLAR_HEAT_DIR" ] ||
  err "SOLAR_HEAT_DIR=$SOLAR_HEAT_DIR is not a directory"

for name in $(show docker-compose.yml | sed -nE 's#^[[:space:]]+file: \./secrets/([^[:space:]]+).*#\1#p') ; do
  f=secrets/$name
  if [ ! -f "$f" ] ; then
    err "$f missing - create it with: printf '%s' 'the-password' > $f; chmod 644 $f"
    continue
  fi
  if [ ! -s "$f" ] ; then err "$f is empty" ; continue ; fi
  # Grafana runs as uid 472 and reads its secrets inside the container; if it
  # can't, it silently falls back to the default admin password on a new volume.
  # Keep the files 644 and protect the directory instead (chmod 700 secrets).
  [ -n "$(find "$f" -perm -004)" ] ||
    err "$f must be readable by the containers: chmod 644 $f (protect the directory with chmod 700 secrets)"
  # "echo pw > file" adds a newline, which would become part of the password
  [ -n "$(tail -c1 "$f")" ] ||
    err "$f ends with a newline - write it with: printf '%s' 'the-password' > $f"
  # Grafana expands "$..." in values it reads from configuration files
  case $name in
    grafana_admin_password|pg_grafana_password)
      ! grep -q '\$' "$f" || err "$f must not contain '\$' (Grafana would expand it)" ;;
  esac
done
if [ -d secrets ] && [ -n "$(find secrets -maxdepth 0 -perm -005)" ] ; then
  echo "config: WARNING: secrets/ is accessible by other users, consider: chmod 700 secrets" >&2
fi
exit $ERR
