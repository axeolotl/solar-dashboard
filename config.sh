# the location where data files are kept on local (host) disk
SOLAR_HEAT_DIR=/Users/axel/Documents/Wohnung/sophienallee/heizungsgruppe/SC514
# host name or ip address of the WLAN_SD card in the solar appliance
WLAN_SD_IP=192.168.80.42
# public domain name of the dashboard: its DNS A/AAAA record must point to
# this host and ports 80 and 443 must be reachable from the internet, so that
# caddy can obtain a certificate from Let's Encrypt
DASHBOARD_DOMAIN=solar.example.com
# configure to your liking.
GRAFANA_ADMIN_PASSWORD=admin
# optional read-only grafana user (role "Viewer"), e.g. for kiosk mode;
# created/updated on every ./docker-up.sh, leave GRAFANA_VIEWER_USER empty to skip
GRAFANA_VIEWER_USER=viewer
GRAFANA_VIEWER_PASSWORD=viewer-secret
PG_ADMIN_PASSWORD=topsecret
# password of the read-only database user "grafanareader" used by the grafana data source
# (must not contain "$", grafana would expand it as a variable reference)
PG_GRAFANA_PASSWORD=readonly-secret
# Local settings: put your actual values into config.local.sh (same syntax,
# not under version control) instead of editing this file, so that
# "git pull" / auto-deploy.sh never conflict with local changes.
if [ -f "${SCRIPTDIR}/config.local.sh" ] ; then
  . "${SCRIPTDIR}/config.local.sh"
fi
