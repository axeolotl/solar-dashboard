#!/bin/bash
# End-to-end smoke test of the complete stack with synthetic data.
#
# Runs a copy of the repository with a test .env and secrets/ (DASHBOARD_DOMAIN=localhost,
# so Caddy uses its internal CA instead of Let's Encrypt), imports generated
# SolexMidi log files and checks Postgres, Grafana, the dashboard queries,
# Caddy/HTTPS, the viewer user and the configuration checks. See UPDATING.md.
#
# WARNING: uses the same compose project name, container names and volumes as
# a real installation (solar_dashboard, postgres, solar_dashboard_grafana-storage, ...) and
# binds ports 80/443. Run it on a test machine or CI runner, not on the host
# running your dashboard. It refuses to run if solar_dashboard containers exist.
#
# usage: test/smoke-test.sh
# env:   SANDBOX=1  add test/compose.sandbox.yml (no Docker DNS, see there)
#        KEEP=1     leave the test stack running for manual inspection
#        DAYS=n     days of generated test data (default 14)
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d /tmp/solar-smoke.XXXXXX)
DATA="$WORK/SC514"
RUN="$WORK/repo"
DAYS=${DAYS:-14}
DASHBOARD_UID=jnVLWvdZk
FAILED=0

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; FAILED=$((FAILED + 1)); }
check() { # check "description" command...
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

if [ -n "$(docker ps -aq --filter label=com.docker.compose.project=solar_dashboard)" ] ; then
  echo "solar_dashboard containers exist - refusing to run (see warning in $0)" >&2
  exit 2
fi

# --- prepare a copy of the repo with test configuration ----------------------
cp -r "$REPO" "$RUN"
rm -rf "$RUN/.git" "$RUN/.env" "$RUN/secrets"
python3 "$REPO/test/gen-testdata.py" "$DATA" "$DAYS"
cat > "$RUN/.env" <<EOF
SOLAR_HEAT_DIR=$DATA
WLAN_SD_IP=127.0.0.1
DASHBOARD_DOMAIN=localhost
GRAFANA_VIEWER_USER=viewer
EOF
# the static IPs override, picked up by every docker compose call in $RUN
if [ "${SANDBOX:-0}" = 1 ] ; then
  echo "COMPOSE_FILE=docker-compose.yml:test/compose.sandbox.yml" >> "$RUN/.env"
fi
# passwords with characters that need care in shell, JSON, SQL and YAML
GRAFANA_ADMIN_PASSWORD='smoke admin #1'
GRAFANA_VIEWER_USER=viewer
GRAFANA_VIEWER_PASSWORD='smoke "viewer" pw\'
PG_ADMIN_PASSWORD="smoke-pg-admin'"
PG_GRAFANA_PASSWORD='smoke reader "pw" #'
secret() { printf '%s' "$2" > "$RUN/secrets/$1"; chmod 644 "$RUN/secrets/$1"; }
mkdir -m 700 "$RUN/secrets"
secret grafana_admin_password "$GRAFANA_ADMIN_PASSWORD"
secret grafana_viewer_password "$GRAFANA_VIEWER_PASSWORD"
secret pg_admin_password "$PG_ADMIN_PASSWORD"
secret pg_grafana_password "$PG_GRAFANA_PASSWORD"
# docker compose, run like a user would: in the repository directory
compose() { (cd "$RUN" && docker compose "$@"); }
COMPOSE=(compose)
ADMIN=(-u "admin:$GRAFANA_ADMIN_PASSWORD")
VIEWER=(-u "$GRAFANA_VIEWER_USER:$GRAFANA_VIEWER_PASSWORD")
URL=https://localhost
CURL=(curl -sk --max-time 20)

cleanup() {
  if [ "$FAILED" != 0 ] ; then
    echo; echo "=== container logs (last 50 lines each) ==="
    "${COMPOSE[@]}" logs --no-color --tail 50 2>&1
  fi
  if [ "${KEEP:-0}" = 1 ] ; then
    echo "KEEP=1: stack left running, files in $WORK"
    echo "        login: $URL/ admin / $GRAFANA_ADMIN_PASSWORD"
    echo "        stop:  $RUN/docker-down.sh && docker volume rm solar_dashboard_grafana-storage solar_dashboard_postgres-data solar_dashboard_caddy-data solar_dashboard_caddy-config"
    return
  fi
  "$RUN/docker-down.sh" >/dev/null 2>&1
  docker volume rm solar_dashboard_grafana-storage solar_dashboard_postgres-data \
    solar_dashboard_caddy-data solar_dashboard_caddy-config >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

# --- versions pinned in docker-compose.yml ------------------------------------
img() { grep -E "^\s+image: $1:" "$RUN/docker-compose.yml" | head -1 | sed -E 's/.*:([^:]+)$/\1/'; }
GRAFANA_TAG=$(img grafana/grafana); POSTGRES_TAG=$(img postgres); CADDY_TAG=$(img caddy)
echo "testing grafana $GRAFANA_TAG, postgres $POSTGRES_TAG, caddy $CADDY_TAG"
check "compose file is valid" "${COMPOSE[@]}" config -q

# --- configuration checks (check-config.sh) -----------------------------------
check "check-config.sh accepts the test configuration" "$RUN/check-config.sh"
cfg_rejects() {
  if "$RUN/check-config.sh" >/dev/null 2>&1 ; then fail "check-config.sh rejects $1"; else pass "check-config.sh rejects $1"; fi
}
S=$RUN/secrets
mv "$S/pg_admin_password" "$WORK/"; cfg_rejects "a missing secret"; mv "$WORK/pg_admin_password" "$S/"
cp -p "$S/pg_admin_password" "$WORK/"; : > "$S/pg_admin_password"; cfg_rejects "an empty secret"; cp -p "$WORK/pg_admin_password" "$S/"
echo x > "$S/grafana_viewer_password"; cfg_rejects "a secret ending with a newline"; secret grafana_viewer_password "$GRAFANA_VIEWER_PASSWORD"
chmod 600 "$S/grafana_admin_password"; cfg_rejects "a secret grafana can't read (mode 600)"; chmod 644 "$S/grafana_admin_password"
printf 'a$b' > "$S/pg_grafana_password"; cfg_rejects "'\$' in pg_grafana_password"; secret pg_grafana_password "$PG_GRAFANA_PASSWORD"
mv "$RUN/.env" "$WORK/"; cfg_rejects "a missing .env"; mv "$WORK/.env" "$RUN/"
cp "$RUN/.env" "$WORK/"; sed -i '/^WLAN_SD_IP=/d' "$RUN/.env"; cfg_rejects "a setting missing in .env"; cp "$WORK/.env" "$RUN/"
check "check-config.sh accepts the restored configuration" "$RUN/check-config.sh"
mv "$S/pg_admin_password" "$WORK/"
"$RUN/docker-up.sh" >/dev/null 2>&1 && fail "docker-up.sh refuses to start without a secret" || pass "docker-up.sh refuses to start without a secret"
mv "$WORK/pg_admin_password" "$S/"
[ -z "$(docker ps -aq --filter label=com.docker.compose.project=solar_dashboard)" ] \
  && pass "nothing started with incomplete configuration" || fail "nothing started with incomplete configuration"
[ "$(grep -cE "^\s+image: grafana/grafana:$GRAFANA_TAG$" "$RUN/docker-compose.yml")" = 2 ] \
  && pass "grafana and grafana-users use the same image" || fail "grafana and grafana-users use the same image"

# --- startup and import --------------------------------------------------------
check "docker-up.sh (waits for grafana healthcheck)" "$RUN/docker-up.sh"
for i in $(seq 30); do docker exec postgres pg_isready -U postgres >/dev/null 2>&1 && break; sleep 2; done
OUT=$("$RUN/init-db.sh" 2>&1)
echo "$OUT" | grep -q '^COPY [1-9]' && ! echo "$OUT" | grep -q ERROR \
  && pass "init-db.sh imports data without errors" || { fail "init-db.sh imports data without errors"; echo "$OUT"; }
OUT=$("$RUN/init-db.sh" 2>&1)
! echo "$OUT" | grep -q ERROR && pass "init-db.sh can be re-run" || { fail "init-db.sh can be re-run"; echo "$OUT"; }
OUT=$("$RUN/update-db.sh" 2>&1)
echo "$OUT" | grep -q '^INSERT 0 [1-9]' && ! echo "$OUT" | grep -q ERROR \
  && pass "update-db.sh" || { fail "update-db.sh"; echo "$OUT"; }
ROWS=$(docker exec postgres psql -U postgres -Atc "select count(*) from heizung")
[ "${ROWS:-0}" -gt 0 ] && pass "heizung has $ROWS rows" || fail "heizung has rows"
DAYROWS=$(docker exec postgres psql -U postgres -Atc "select count(*) from heizung_pro_tag")
[ "${DAYROWS:-0}" -ge "$DAYS" ] && pass "heizung_pro_tag has $DAYROWS days" || fail "heizung_pro_tag has >= $DAYS days ($DAYROWS)"

# --- secrets -------------------------------------------------------------------
LEAKS=""
for c in postgres solar_dashboard-grafana-1 solar_dashboard-grafana-users-1 solar_dashboard-caddy-1 ; do
  ENV=$(docker inspect "$c" --format '{{range .Config.Env}}{{println .}}{{end}}')
  for pw in "$GRAFANA_ADMIN_PASSWORD" "$GRAFANA_VIEWER_PASSWORD" "$PG_ADMIN_PASSWORD" "$PG_GRAFANA_PASSWORD" ; do
    echo "$ENV" | grep -qF -- "$pw" && LEAKS="$LEAKS $c"
  done
done
[ -z "$LEAKS" ] && pass "no passwords in container environments" || fail "no passwords in container environments:$LEAKS"
# (pg_hba trusts connections via localhost, so test passwords via the container IP)
PGIP=$(docker inspect postgres --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
docker exec -e PGPASSWORD="$PG_ADMIN_PASSWORD" postgres psql -h "$PGIP" -U postgres -Atc 'select 1' >/dev/null 2>&1 \
  && pass "postgres admin password from secret" || fail "postgres admin password from secret"
[ "$(cd "$RUN" && docker compose ps -q | wc -l)" -ge 3 ] \
  && pass "plain 'docker compose ps' in the repository directory" || fail "plain 'docker compose ps' in the repository directory"

# --- running versions ----------------------------------------------------------
PGV=$(docker exec postgres psql -U postgres -Atc "show server_version" | cut -d' ' -f1)
[ "$PGV" = "$POSTGRES_TAG" ] && pass "postgres server version $PGV" || fail "postgres server version $PGV != $POSTGRES_TAG"
GV=$("${CURL[@]}" "$URL/api/health" | grep -o '"version": *"[^"]*"' | grep -o '[0-9][^"]*')
[ "$GV" = "${GRAFANA_TAG%%-*}" ] && pass "grafana version $GV" || fail "grafana version '$GV' != ${GRAFANA_TAG%%-*}"

# --- grafana provisioning ------------------------------------------------------
"${CURL[@]}" "${ADMIN[@]}" "$URL/api/datasources/uid/solar-postgres/health" | grep -q '"status":"OK"' \
  && pass "data source health" || fail "data source health"
DASH=$("${CURL[@]}" "${ADMIN[@]}" "$URL/api/dashboards/uid/$DASHBOARD_UID")
echo "$DASH" | grep -q '"provisioned":true' && pass "dashboard provisioned" || fail "dashboard provisioned"
# every panel query must return data for the test period (checks SQL + macros)
echo "$DASH" > "$WORK/dashboard.json"
python3 - "$WORK/dashboard.json" > "$WORK/queries.txt" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))["dashboard"]
for p in d["panels"]:
    if p.get("type") in ("graph", "singlestat", "table-old"):
        print(f"LEGACY\t{p['title']}\t{p['type']}")
    for t in p.get("targets", []):
        q = {"from": "now-%dd" % 7, "to": "now", "queries": [{
            "refId": t["refId"], "datasource": t.get("datasource", p.get("datasource")),
            "rawSql": t["rawSql"], "format": t.get("format", "time_series"),
            "intervalMs": 3600000, "maxDataPoints": 500}]}
        print(f"QUERY\t{p['title']}/{t['refId']}\t{json.dumps(q)}")
EOF
while IFS=$'\t' read -r kind name payload ; do
  if [ "$kind" = LEGACY ] ; then fail "panel '$name' uses removed panel type $payload"; continue; fi
  RES=$("${CURL[@]}" "${ADMIN[@]}" -H 'Content-Type: application/json' "$URL/api/ds/query" -d "$payload")
  echo "$RES" | python3 -c '
import json, sys
r = json.load(sys.stdin)["results"]
vals = [v for res in r.values() if not res.get("error") for f in res.get("frames", []) for col in f["data"]["values"] for v in col]
sys.exit(0 if vals else 1)' && pass "query returns data: $name" || { fail "query returns data: $name"; echo "$RES" | head -c 500; echo; }
done < "$WORK/queries.txt"

# --- caddy / https -------------------------------------------------------------
[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost/)" = 308 ] && pass "http redirects to https" || fail "http redirects to https"
HDRS=$("${CURL[@]}" -I "$URL/login")
echo "$HDRS" | grep -qi '^strict-transport-security:' && pass "HSTS header" || fail "HSTS header"
echo "$HDRS" | grep -qi '^server:' && fail "Server header removed" || pass "Server header removed"
"${CURL[@]}" -c "$WORK/cookies" -H 'Content-Type: application/json' "$URL/login" \
  -d "{\"user\":\"admin\",\"password\":\"$GRAFANA_ADMIN_PASSWORD\"}" >/dev/null
grep -E 'grafana_session\s' "$WORK/cookies" | awk '{exit ($4=="TRUE")?0:1}' \
  && pass "session cookie is secure" || fail "session cookie is secure"
curl -s --max-time 3 http://localhost:3000/ >/dev/null 2>&1 && fail "grafana port 3000 not published" || pass "grafana port 3000 not published"

# --- viewer user ---------------------------------------------------------------
"${CURL[@]}" "${VIEWER[@]}" "$URL/api/user/orgs" | grep -q '"role":"Viewer"' && pass "viewer user has role Viewer" || fail "viewer user has role Viewer"
[ "$("${CURL[@]}" -o /dev/null -w '%{http_code}' "${VIEWER[@]}" "$URL/api/dashboards/uid/$DASHBOARD_UID")" = 200 ] \
  && pass "viewer can read dashboard" || fail "viewer can read dashboard"
[ "$("${CURL[@]}" -o /dev/null -w '%{http_code}' "${VIEWER[@]}" -H 'Content-Type: application/json' "$URL/api/dashboards/db" -d '{"dashboard":{"title":"x"}}')" = 403 ] \
  && pass "viewer cannot save dashboards" || fail "viewer cannot save dashboards"

# --- persistence across down/up, changed grafanareader password -------------
# docker-up.sh syncs the database password, grafana reads the new file on start
PG_GRAFANA_PASSWORD='changed "reader" pw'
secret pg_grafana_password "$PG_GRAFANA_PASSWORD"
"$RUN/docker-down.sh" >/dev/null 2>&1
check "docker-up.sh after docker-down.sh" "$RUN/docker-up.sh"
for i in $(seq 30); do docker exec postgres pg_isready -U postgres >/dev/null 2>&1 && break; sleep 2; done
[ "$(docker exec postgres psql -U postgres -Atc "select count(*) from heizung")" = "$ROWS" ] \
  && pass "database survives down/up" || fail "database survives down/up"
docker logs solar_dashboard-grafana-users-1 2>&1 | grep -q "password unchanged" \
  && pass "viewer user unchanged after restart" || fail "viewer user unchanged after restart"
"${CURL[@]}" "${ADMIN[@]}" "$URL/api/datasources/uid/solar-postgres/health" | grep -q '"status":"OK"' \
  && pass "data source health after restart with changed password" || fail "data source health after restart with changed password"
PGIP=$(docker inspect postgres --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}")
docker exec -e PGPASSWORD="$PG_GRAFANA_PASSWORD" postgres psql -h "$PGIP" -U grafanareader -d postgres -Atc 'select count(*) > 0 from heizung' 2>/dev/null | grep -qx t \
  && pass "grafanareader password synced by docker-up.sh" || fail "grafanareader password synced by docker-up.sh"

# --- optional screenshot -------------------------------------------------------
if python3 -c 'import playwright' 2>/dev/null ; then
  python3 "$REPO/test/screenshot.py" "$URL/d/$DASHBOARD_UID/solar-dashboard?orgId=1&from=now-7d&to=now" \
    "$REPO/test/screenshot.png" admin "$GRAFANA_ADMIN_PASSWORD" \
    && echo "INFO  screenshot written to test/screenshot.png - compare with docs/dashboard.png"
fi

echo
if [ "$FAILED" = 0 ] ; then echo "ALL CHECKS PASSED"; else echo "$FAILED CHECK(S) FAILED"; fi
exit "$FAILED"
