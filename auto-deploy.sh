#!/bin/bash
# Pulls new commits from the master branch and activates them.
# Meant to run from cron on the dashboard host, see UPDATING.md
# ("Automatic deployment"). Prints nothing if there is nothing to do, so cron
# only mails (or logs) actual deployments and problems.
#
# Exit codes: 0 = nothing to do / deployed and healthy,
#             1 = deployment refused (needs manual action, nothing changed),
#             2 = deployed but health check failed (needs attention)
#
# Environment (optional):
#   AUTO_DEPLOY_REMOTE   git remote to pull from   (default: origin)
#   AUTO_DEPLOY_BRANCH   branch to deploy          (default: master)
#   AUTO_DEPLOY_DRY_RUN  1 = only report what would be done
#   AUTO_DEPLOY_PG_REINIT 1 = allow a PostgreSQL major upgrade: deletes the
#                        database volume and re-imports all log files
#                        (refused without it, see UPDATING.md)

# The whole script is one function that is parsed completely before it runs,
# so that a new version of this file arriving via "git merge" can't affect the
# running instance.
main() {
  set -u
  SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)
  cd "$SCRIPTDIR" || exit 1
  REMOTE=${AUTO_DEPLOY_REMOTE:-origin}
  BRANCH=${AUTO_DEPLOY_BRANCH:-master}
  DRY_RUN=${AUTO_DEPLOY_DRY_RUN:-0}
  PG_REINIT=${AUTO_DEPLOY_PG_REINIT:-0}

  log() { echo "$(date '+%Y-%m-%d %H:%M:%S') auto-deploy: $*"; }
  refuse() { log "NOT DEPLOYED: $*"; exit 1; }

  # --- single instance (mkdir is atomic, works without flock, e.g. on macOS)
  LOCK="$SCRIPTDIR/.auto-deploy.lock"
  if ! mkdir "$LOCK" 2>/dev/null ; then
    # stale lock from a crashed run (older than 2 hours)?
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +120 2>/dev/null)" ] ; then
      rmdir "$LOCK" && mkdir "$LOCK" || exit 1
    else
      exit 0
    fi
  fi
  trap 'rmdir "$LOCK" 2>/dev/null' EXIT

  # --- what is new? -----------------------------------------------------------
  if ! git fetch --quiet "$REMOTE" "$BRANCH" ; then
    log "git fetch $REMOTE $BRANCH failed"
    exit 1
  fi
  OLD=$(git rev-parse HEAD)
  NEW=$(git rev-parse FETCH_HEAD)
  [ "$OLD" = "$NEW" ] && exit 0

  # --- preflight: refuse anything that needs a human --------------------------
  if [ "$(git rev-parse --abbrev-ref HEAD)" != "$BRANCH" ] ; then
    refuse "checkout is on branch '$(git rev-parse --abbrev-ref HEAD)', not '$BRANCH'"
  fi
  if ! git diff --quiet HEAD -- ; then
    refuse "tracked files have local changes (move local settings to config.local.sh):
$(git status --short --untracked-files=no)"
  fi
  if ! git merge-base --is-ancestor "$OLD" "$NEW" ; then
    refuse "local branch has diverged from $REMOTE/$BRANCH (no fast-forward possible)"
  fi

  CHANGED=$(git diff --name-only "$OLD" "$NEW")
  changed() { echo "$CHANGED" | grep -qxE "$1"; }
  log "new commits $(git rev-parse --short "$OLD")..$(git rev-parse --short "$NEW"):"
  git log --oneline "$OLD..$NEW" | sed 's/^/    /'

  # commits can opt out of automatic deployment with a "Deploy: manual" trailer
  MANUAL=$(git log --format='%h %s' --grep='^Deploy: *manual' -i "$OLD..$NEW")
  if [ -n "$MANUAL" ] ; then
    refuse "commit(s) marked 'Deploy: manual', follow their instructions and deploy by hand:
$MANUAL"
  fi

  # new settings in config.sh must be set explicitly in config.local.sh
  vars() { sed -nE 's/^([A-Z_][A-Z0-9_]*)=.*/\1/p' | sort -u; }
  NEWVARS=$(comm -13 <(git show "$OLD:config.sh" | vars) <(git show "$NEW:config.sh" | vars))
  MISSING=""
  for v in $NEWVARS ; do
    grep -qE "^$v=" config.local.sh 2>/dev/null || MISSING="$MISSING $v"
  done
  if [ -n "$MISSING" ] ; then
    refuse "new setting(s) in config.sh:$MISSING - set them in config.local.sh (the defaults are placeholders):
$(git show "$NEW:config.sh" | grep -B3 -E "^($(echo $MISSING | tr ' ' '|'))=")"
  fi

  # --- plan --------------------------------------------------------------------
  image_tag() { git show "$1:docker-compose.yml" | sed -nE "s#^[[:space:]]+image: $2:([^ ]+)[[:space:]]*\$#\1#p" | head -1; }
  PG_OLD=$(image_tag "$OLD" postgres); PG_NEW=$(image_tag "$NEW" postgres)
  REIMPORT=0; RESTART=""; WIPE_PG=0
  # schema change -> rebuild the database from the log files
  changed 'init-db\.sql' && REIMPORT=1
  # new PostgreSQL major version: the data directory is not compatible and the
  # image refuses to start next to the old version's data. The database only
  # holds data imported from the log files, so it can be recreated - but only
  # on explicit request, as this deletes the volume.
  if [ "${PG_OLD%%.*}" != "${PG_NEW%%.*}" ] ; then
    if [ "$PG_REINIT" != 1 ] ; then
      refuse "PostgreSQL major upgrade $PG_OLD -> $PG_NEW: the database must be recreated from the log files.
    Run once by hand: AUTO_DEPLOY_PG_REINIT=1 $SCRIPTDIR/auto-deploy.sh"
    fi
    set -a; . "$SCRIPTDIR/config.sh"; set +a
    if [ -z "$(find "${SOLAR_HEAT_DIR:-/nonexistent}" -name '*.TXT' 2>/dev/null | head -1)" ] ; then
      refuse "PostgreSQL major upgrade: no log files (*.TXT) in SOLAR_HEAT_DIR=${SOLAR_HEAT_DIR:-}, refusing to delete the database"
    fi
    WIPE_PG=1; REIMPORT=1
  fi
  # single-file bind mounts keep pointing to the old file after git replaced
  # it, and grafana reads provisioning only at startup -> restart
  changed '(datasources|dashboards)\.yml|dashboard\.json' && RESTART="$RESTART grafana"
  changed 'Caddyfile' && RESTART="$RESTART caddy"
  changed 'crontab' && log "NOTE: crontab changed - not installed automatically, review with: git diff $OLD $NEW -- crontab"

  # only documentation, tests or CI changed -> nothing to activate
  if ! echo "$CHANGED" | grep -qvxE '(README|UPDATING)\.md|docs/.*|test/.*|\.github/.*|\.gitignore' ; then
    if [ "$DRY_RUN" = 1 ] ; then log "plan: update checkout only (no runtime files changed)"; exit 0; fi
    git merge --quiet --ff-only "$NEW" || refuse "git merge --ff-only failed"
    log "updated checkout to $(git rev-parse --short HEAD), no runtime files changed"
    exit 0
  fi

  log "plan: pull images,$([ $WIPE_PG = 1 ] && echo " delete database volume (postgres $PG_OLD -> $PG_NEW),") docker-up${RESTART:+, restart$RESTART}$([ $REIMPORT = 1 ] && echo ", re-import database")"
  if [ "$DRY_RUN" = 1 ] ; then
    log "dry run, nothing changed"
    exit 0
  fi

  # --- activate ---------------------------------------------------------------
  git merge --quiet --ff-only "$NEW" || refuse "git merge --ff-only failed"
  set -a; . "$SCRIPTDIR/config.sh"; set +a
  COMPOSE=(docker compose -p solar_dashboard -f "$SCRIPTDIR/docker-compose.yml")
  if ! PULL_OUT=$("${COMPOSE[@]}" pull --quiet 2>&1) ; then
    log "WARNING: docker compose pull failed, continuing with local images:"
    echo "$PULL_OUT" | tail -5 | sed 's/^/    /'
  fi
  if [ $WIPE_PG = 1 ] ; then
    log "deleting database volume solar_dashboard_postgres-data"
    "${COMPOSE[@]}" rm --stop --force postgres >/dev/null 2>&1
    docker volume rm solar_dashboard_postgres-data >/dev/null || refuse "could not delete volume solar_dashboard_postgres-data"
  fi
  # docker-up.sh of the new version, so that anything it does before or after
  # "docker compose up" (e.g. one-time migrations) also applies here
  "$SCRIPTDIR/docker-up.sh" 2>&1 | grep -vE ' (Running|Waiting|Healthy)$' | sed 's/^/    /'
  for s in $RESTART ; do
    "${COMPOSE[@]}" restart "$s" 2>&1 | sed 's/^/    /'
  done
  # wait (max. 60 s) until "$@" succeeds
  wait_for() { local end=$((SECONDS + 60)); until "$@" >/dev/null 2>&1 ; do [ $SECONDS -ge $end ] && return 1; sleep 2; done; }
  if [ $REIMPORT = 1 ] ; then
    if wait_for "${COMPOSE[@]}" exec -T postgres pg_isready -U postgres -q ; then
      log "re-importing database"
      "$SCRIPTDIR/init-db.sh" 2>&1 | grep -E 'COPY|ERROR' | sed 's/^/    /'
    else
      log "postgres not ready, database NOT re-imported"
    fi
  fi

  # --- verify -----------------------------------------------------------------
  ds_healthy() {
    "${COMPOSE[@]}" exec -T grafana curl -fsS --max-time 5 -u "admin:${GRAFANA_ADMIN_PASSWORD}" \
      http://localhost:3000/api/datasources/uid/solar-postgres/health | grep -q '"status":"OK"'
  }
  HEALTHY=0
  wait_for ds_healthy && HEALTHY=1
  PROBLEMS=""
  [ $HEALTHY = 1 ] || PROBLEMS="$PROBLEMS grafana/data source not healthy;"
  for s in caddy grafana postgres ; do
    [ "$("${COMPOSE[@]}" ps --status running -q "$s" | wc -l)" -ge 1 ] || PROBLEMS="$PROBLEMS $s not running;"
  done
  USERS_EXIT=$(docker inspect solar_dashboard-grafana-users-1 --format '{{.State.ExitCode}}' 2>/dev/null)
  [ "${USERS_EXIT:-1}" = 0 ] || PROBLEMS="$PROBLEMS grafana-users exited with ${USERS_EXIT:-?};"

  if [ -n "$PROBLEMS" ] ; then
    log "DEPLOYED $(git rev-parse --short HEAD) BUT UNHEALTHY:$PROBLEMS"
    for s in postgres grafana caddy ; do
      "${COMPOSE[@]}" logs --no-color --tail 8 "$s" 2>&1 | cut -c1-300 | sed 's/^/    /'
    done
    log "previous version was $(git rev-parse --short "$OLD"), see UPDATING.md (Rollback)"
    exit 2
  fi
  log "deployed $(git rev-parse --short HEAD), healthy"
  exit 0
}

main "$@"
exit
