# Updating the components

How to bring Grafana, PostgreSQL and Caddy to new versions, adapt the
configuration and verify the result. Written down after the update from
Grafana 6.7.1 / PostgreSQL 9 to Grafana 13.2.3 / PostgreSQL 18.6 (#1–#4),
so that future regular updates are mostly mechanical.

## What is pinned where

| Component | Pinned in | Files that may need adapting |
|---|---|---|
| Grafana | `docker-compose.yml` (`grafana` **and** `grafana-users` service, keep both tags identical) | `dashboard.json`, `datasources.yml`, `dashboards.yml`, `grafana-users.sh` (HTTP API), `GF_*` env in `docker-compose.yml` |
| PostgreSQL | `docker-compose.yml` (`postgres`) | `init-db.sql`, `update-db.sql`, volume mount, `postgresVersion` in `datasources.yml` |
| Caddy | `docker-compose.yml` (`caddy`) | `Caddyfile` |
| Docker / Compose | host | `docker-compose.yml` syntax, `*.sh` |

Tags are always pinned to a full version (`13.2.3-ubuntu`, `18.6`, `2.11.7`),
never `latest`, so that an update is a reviewable, testable commit.

## Procedure

1. **Find new versions**

   ```bash
   test/check-versions.py
   ```

   prints, for every image in `docker-compose.yml`, whether a newer stable tag
   (same suffix, e.g. `-ubuntu`) exists on Docker Hub, and flags major upgrades.

2. **Read the release notes** for every version you skip, focusing on breaking
   changes (see the component notes below for links and known pitfalls).

3. **One commit per component** on a branch, e.g. `update-2027-04`:
   bump the tag, adapt the files listed in the table above, update the
   versions in `README.md` and the history table at the end of this file.
   Patch/minor updates are usually just the tag bump.

4. **Run the smoke test** (see [Testing](#testing)) – it must end with
   `ALL CHECKS PASSED` – and compare `test/screenshot.png` with
   `docs/dashboard.png` (same six panels with data, no "panel plugin not found").

5. **Open a PR**, listing versions before/after and the smoke-test result.

6. **Deploy** on the dashboard host after merging:

   ```bash
   ./docker-down.sh
   git pull
   ./docker-up.sh
   ./init-db.sh      # only needed after a PostgreSQL major upgrade (see below)
   ```

   Check the dashboard in the browser and `docker compose -p solar_dashboard logs grafana`.

## Component notes

### Grafana

- Release notes: <https://grafana.com/docs/grafana/latest/whatsnew/>,
  breaking changes: <https://grafana.com/docs/grafana/latest/breaking-changes/>,
  upgrade guide: <https://grafana.com/docs/grafana/latest/upgrade-guide/>.
- Grafana keeps its own database (users, sessions, preferences) in the
  `grafana-storage` volume and migrates it automatically on start. Everything
  else (data source, dashboard, viewer user) is provisioned from the repo, so a
  broken Grafana state can always be reset with
  `docker volume rm grafana-storage && ./init-docker.sh` (admin password is then
  reset to `GRAFANA_ADMIN_PASSWORD`).
- **Panels**: Grafana 12 removed Angular, so all old panel types (`graph`,
  `singlestat`, `table-old`, ...) are gone. Grafana only migrates them on the fly in
  the browser, never in the provisioned file. `dashboard.json` must only use
  current panel types (`timeseries` here; bars via `drawStyle: "bars"`).
  The smoke test fails on legacy panel types.
- **Dashboard schema**: keep `schemaVersion` at the current value
  (`LATEST_VERSION` in
  [`apps/dashboard/pkg/migration/schemaversion/migrations.go`](https://github.com/grafana/grafana/blob/main/apps/dashboard/pkg/migration/schemaversion/migrations.go)
  for the release tag; 42 for 13.2). Easiest way to update `dashboard.json`
  after a big jump: run the smoke test with `KEEP=1`, open the dashboard,
  *Edit → Settings → JSON Model* (or *Export → Export as JSON*), copy the
  migrated JSON back, keep `uid` `jnVLWvdZk` and the data source references,
  and remove `id`/`version` noise.
- **Queries** use the SQL code editor (`editorMode: "code"`, `rawQuery: true`)
  and `$__timeFilter`, `$__timeGroupAlias`, `$__interval` macros; the
  smoke test executes every panel query via `/api/ds/query`.
- **Data source** (`datasources.yml`): plugin id is
  `grafana-postgresql-datasource` (since 10.3; `postgres` is an alias), fixed
  `uid: solar-postgres` referenced by every panel/target, `database` belongs in
  `jsonData`. `postgresVersion` is an enum of the UI options (highest is
  currently `1500` = "15+"); check the plugin's options when PostgreSQL moves on
  (`grep -o 'label:"15+",value:[0-9]*' -r /usr/share/grafana/data/plugins-bundled/grafana-postgresql-datasource/`
  inside the image).
- **`$` in provisioned values**: Grafana expands `$VAR` / `$__env{VAR}` in
  provisioning files and *again* inside the substituted value, so passwords
  must not contain `$` (`init-db.sh` enforces this for `PG_GRAFANA_PASSWORD`).
- `GF_SECURITY_ADMIN_PASSWORD` only applies on the very first start of an empty
  `grafana-storage` volume.
- The `-ubuntu` image variant contains `curl` and `bash`, which the
  healthcheck and `grafana-users.sh` rely on. Check this if switching variants.
- `grafana-users.sh` uses `/api/users/lookup`, `/api/admin/users`,
  `/api/admin/users/:id/password` and `/api/orgs/1/users/:id`. Check the HTTP API
  changelog for these endpoints on major upgrades.

### PostgreSQL

- Release notes: <https://www.postgresql.org/docs/release/>,
  image docs: <https://hub.docker.com/_/postgres>.
- **Minor updates** (18.6 → 18.7): tag bump only, data files are compatible.
- **Major updates** (18 → 19): the data directory is *not* compatible. The
  database only contains data imported from the log files, so no dump/restore is
  needed: deploy, then `docker volume rm solar_dashboard_postgres-data` (after
  `./docker-down.sh`) or let the new version start on a fresh volume, and run
  `./init-db.sh` to re-import everything.
- Since 18 the image uses `PGDATA=/var/lib/postgresql/<major>/docker` and
  declares the volume at `/var/lib/postgresql`; the named volume is mounted
  there. Older images used `/var/lib/postgresql/data`. Check `docker inspect
  postgres:<tag> --format '{{json .Config.Volumes}} {{json .Config.Env}}'` after
  a major upgrade.
- Features the SQL relies on: `COPY ... FROM PROGRAM` (superuser, needs `find`,
  `grep`, `sed`, `cat` in the image), `SET datestyle = 'German, DMY'`, three
  argument `date_trunc(field, timestamptz, zone)` (≥ 12), `\gexec` and
  `:'var'` interpolation in psql.
- Default auth is `scram-sha-256` (since 14); the Grafana data source supports it.
- `init-db.sh`/`update-db.sh` run `psql` via `docker compose exec` in the
  postgres container, so client and server version always match.

### Caddy

- Releases: <https://github.com/caddyserver/caddy/releases>.
- The `Caddyfile` only uses stable directives (`reverse_proxy`, `encode`,
  `header`); 2.x updates are usually tag bumps.
- Certificates live in the `caddy-data` volume – never delete it on the
  production host (Let's Encrypt rate limits).
- The smoke test runs with `DASHBOARD_DOMAIN=localhost`, so Caddy uses its
  internal CA; the real ACME flow can only be verified on the production host
  (`docker compose -p solar_dashboard logs caddy`).

### Docker / Compose

- Only Compose v2 (`docker compose`) is supported; there is no top-level
  `version:` key.
- The healthcheck uses `start_interval` (Docker Engine ≥ 25).

## Testing

`test/smoke-test.sh` runs the complete stack from a temporary copy of the
repo with generated test data (`test/gen-testdata.py`, SolexMidi format,
last 14 days) and checks:

- compose file valid, identical Grafana tags in both services
- `init-docker.sh`, `docker-up.sh` (waits for the Grafana healthcheck),
  `init-db.sh` (also re-run), `update-db.sh`
- running PostgreSQL and Grafana versions match the pinned tags
- data source health, dashboard provisioned, no legacy panel types, **every
  panel query returns data**
- HTTP→HTTPS redirect, HSTS, no `Server` header, secure session cookie,
  port 3000 not published
- viewer user: role Viewer, can read the dashboard, cannot save dashboards
- data and viewer user survive `docker-down.sh` / `docker-up.sh`
- optionally a screenshot `test/screenshot.png` (if Python `playwright` is installed)

```bash
test/smoke-test.sh            # ~30 s once the images are pulled
KEEP=1 test/smoke-test.sh     # leave the stack running at https://localhost/
```

The test uses the same project, container and volume names as a real
installation and binds ports 80/443: run it on a workstation, CI runner or
sandbox, **not on the dashboard host**. It refuses to start if
`solar_dashboard` containers exist.

### Running in a sandbox without iptables

Some sandboxes/VMs (e.g. AI agent sandboxes) have no iptables/nftables
support in the kernel. Docker then only starts with:

```bash
echo '{"iptables": false, "ip6tables": false}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
```

In that mode Docker's embedded DNS does not resolve service names, so run the
test with `SANDBOX=1`, which adds `test/compose.sandbox.yml` (static IPs +
`extra_hosts`). Published ports still work.

### Visual check

Compare `test/screenshot.png` with `docs/dashboard.png`: six panels (daily and
weekly yield as bars, primary circuit temperatures with max values in the
legend, storage temperature, pump activity, heat transmitted). Replace
`docs/dashboard.png` when the look changes intentionally.

## Rollback

Revert the merge commit and redeploy. Grafana's database migrations are not
reversible: if an older Grafana refuses to start on the migrated volume, reset
it with `docker volume rm grafana-storage && ./init-docker.sh` (everything
important is provisioned). After a PostgreSQL major rollback, re-import with
`./init-db.sh` on a fresh `solar_dashboard_postgres-data` volume.

## Automating update runs

Configured in this repo:

- **Dependabot** (`.github/dependabot.yml`) checks the image tags in
  `docker-compose.yml` every Monday morning: patch/minor updates of all images
  come as one grouped PR, each major update as its own PR. Once a month it
  also bumps the actions used in the workflow. Dependabot only changes tags. It
  never touches `dashboard.json`, `datasources.yml` or the SQL, so major
  updates may need follow-up commits on the Dependabot branch (steps above).
  The config is read from the default branch, so it takes effect once it is
  merged to `master`.
- **Smoke test workflow** (`.github/workflows/smoke-test.yml`) runs
  `test/smoke-test.sh` on every PR (including Dependabot's), on pushes to
  `master` and manually (*Actions → smoke test → Run workflow*). The PASS/FAIL
  list is shown in the job summary, container logs are printed on failure, and
  the dashboard screenshot is attached as artifact `dashboard-screenshot`
  (compare with `docs/dashboard.png`).

Typical flow: a green grouped minor/patch PR can be merged (then deploy, see
step 6). A red PR, or any major update, gets reviewed with this guide: read
the release notes, fix the files, push to the Dependabot branch and let the
workflow re-run.

Further options:

- **Auto-merge** green patch PRs with a small workflow using
  `dependabot/fetch-metadata` and `gh pr merge --auto` (requires branch
  protection with the smoke test as a required check).
- **AI agent** (e.g. a scheduled Perplexity Computer task, or one triggered by
  a failing Dependabot PR): give it this file as the procedure, let it run
  `test/check-versions.py`, apply and test the changes (`SANDBOX=1` if needed)
  and open or fix a PR. A prompt that worked:

  > Update https://github.com/axeolotl/solar-dashboard to the newest versions of
  > all components following UPDATING.md: one commit per component, adapt the
  > compose file, dashboard, data source and SQL as needed, run
  > test/smoke-test.sh until all checks pass, compare the screenshot with
  > docs/dashboard.png, add a line to the update history and open a PR.

## Update history

| Date | Grafana | PostgreSQL | Caddy | Notes |
|---|---|---|---|---|
| 2020 | 6.7.1 | 9 | – | initial version |
| 2026-10 | 13.2.3 | 18.6 | 2.11.7 | Compose v2, graph → timeseries panels, new data source plugin id, PGDATA layout of PG 18, Caddy/HTTPS, viewer user (#1–#4); this guide and the smoke test |
