#!/bin/bash
# Creates or updates the Grafana viewer user configured in config.sh
# (GRAFANA_VIEWER_USER / GRAFANA_VIEWER_PASSWORD) via the Grafana HTTP API.
# Runs as one-shot service "grafana-users" on every "docker compose up",
# once Grafana is healthy. Idempotent: the password is only reset if it changed,
# so existing viewer sessions (e.g. kiosk mode) are not interrupted.
set -eu

GRAFANA_URL=${GRAFANA_URL:-http://grafana:3000}
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
GRAFANA_VIEWER_USER=${GRAFANA_VIEWER_USER:-}
GRAFANA_VIEWER_PASSWORD=${GRAFANA_VIEWER_PASSWORD:-}

if [ -z "$GRAFANA_VIEWER_USER" ] ; then
  echo "GRAFANA_VIEWER_USER not set, no viewer user configured"
  exit 0
fi
if [ -z "$GRAFANA_VIEWER_PASSWORD" ] ; then
  echo "GRAFANA_VIEWER_PASSWORD must be set for GRAFANA_VIEWER_USER=$GRAFANA_VIEWER_USER" >&2
  exit 1
fi
if [ "$GRAFANA_VIEWER_USER" = "$GRAFANA_ADMIN_USER" ] ; then
  echo "GRAFANA_VIEWER_USER must differ from the admin user" >&2
  exit 1
fi

# JSON string literal (escapes backslash and double quote)
json() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }

RESPONSE=$(mktemp)
# api METHOD PATH [curl args...] -> prints HTTP status, body in $RESPONSE
api() {
  local method=$1 path=$2; shift 2
  curl -sS -o "$RESPONSE" -w '%{http_code}' -X "$method" \
    -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    -H 'Content-Type: application/json' "$@" "${GRAFANA_URL}${path}"
}
fail() { echo "$1 (HTTP $2): $(cat "$RESPONSE")" >&2; exit 1; }
user_id() { grep -o '"id":[0-9]*' "$RESPONSE" | head -1 | cut -d: -f2; }

status=$(api GET /api/users/lookup --get --data-urlencode "loginOrEmail=${GRAFANA_VIEWER_USER}")
case "$status" in
  200)
    id=$(user_id)
    # does the configured password already work?
    pw_status=$(curl -sS -o /dev/null -w '%{http_code}' \
      -u "${GRAFANA_VIEWER_USER}:${GRAFANA_VIEWER_PASSWORD}" "${GRAFANA_URL}/api/user")
    if [ "$pw_status" = 200 ] ; then
      echo "viewer user '$GRAFANA_VIEWER_USER' exists, password unchanged"
    else
      status=$(api PUT "/api/admin/users/${id}/password" -d "{\"password\":$(json "$GRAFANA_VIEWER_PASSWORD")}")
      [ "$status" = 200 ] || fail "updating password failed" "$status"
      echo "viewer user '$GRAFANA_VIEWER_USER' exists, password updated"
    fi
    ;;
  404)
    status=$(api POST /api/admin/users -d "{\"name\":$(json "$GRAFANA_VIEWER_USER"),\"login\":$(json "$GRAFANA_VIEWER_USER"),\"password\":$(json "$GRAFANA_VIEWER_PASSWORD"),\"OrgId\":1}")
    [ "$status" = 200 ] || fail "creating user failed" "$status"
    id=$(user_id)
    echo "viewer user '$GRAFANA_VIEWER_USER' created"
    ;;
  401)
    fail "admin login failed - GRAFANA_ADMIN_PASSWORD only applies on Grafana's first start; update it in config.sh if you changed it in the UI" "$status"
    ;;
  *)
    fail "user lookup failed" "$status"
    ;;
esac

# make sure the user has (only) the Viewer role in the main org
status=$(api PATCH "/api/orgs/1/users/${id}" -d '{"role":"Viewer"}')
[ "$status" = 200 ] || fail "setting Viewer role failed" "$status"
echo "viewer user '$GRAFANA_VIEWER_USER' has role Viewer"
