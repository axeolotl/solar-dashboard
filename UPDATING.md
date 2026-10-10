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
   If deploying needs a manual step that `auto-deploy.sh` can't do (see
   [what is deployed automatically](#what-is-deployed-automatically)), add a
   `Deploy: manual` trailer to the commit message, with the instructions in
   the message body.

4. **Run the smoke test** (see [Testing](#testing)) – it must end with
   `ALL CHECKS PASSED` – and compare `test/screenshot.png` with
   `docs/dashboard.png` (same six panels with data, no "panel plugin not found").

5. **Open a PR**, listing versions before/after and the smoke-test result.

6. **Deploy** on the dashboard host after merging - automatically by
   `auto-deploy.sh` (see [Automatic deployment](#automatic-deployment)) or by hand:

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
- **Major updates** (18 → 19): the data directory is *not* compatible, and
  the new image refuses to start while the old version's data is in the volume
  ("there appears to be PostgreSQL data in /var/lib/postgresql/18/docker",
  verified with 18.6 → 19beta4). The database only contains data imported from
  the log files, so no dump/restore is needed: delete the volume and re-import.
  With auto-deploy: `AUTO_DEPLOY_PG_REINIT=1 ./auto-deploy.sh` does exactly
  that. By hand: `./docker-down.sh && docker volume rm solar_dashboard_postgres-data
  && ./docker-up.sh && ./init-db.sh`.
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

## Automatic deployment

`auto-deploy.sh` runs from cron on the dashboard host. It fetches `master` and,
if there are new commits, checks them, fast-forwards the checkout and
activates the changes. It is silent when there is nothing to do, so cron
mail or the log only contain deployments and problems.

### Activation

1. Move local settings out of `config.sh` (a tracked file must not have local
   changes, otherwise `git pull` conflicts and auto-deploy refuses to run):

   ```bash
   cd ~/solar-dashboard
   grep -E '^[A-Z_]+=' config.sh > config.local.sh   # current values
   git checkout config.sh                            # back to the defaults
   git status --short                                # must show no 'M' lines
   ```

2. Make sure the checkout is on `master` and tracks GitHub
   (`git remote -v`; a public repo needs no credentials for `git fetch`).

3. Try it:

   ```bash
   AUTO_DEPLOY_DRY_RUN=1 ./auto-deploy.sh   # shows what would happen
   ./auto-deploy.sh; echo $?                # 0 = nothing to do or deployed
   ```

4. Enable it in the crontab (`crontab -e`, see the commented line in `crontab`):

   ```
   */15 * * * * $HOME/solar-dashboard/auto-deploy.sh >> $HOME/solar-dashboard/auto-deploy.log 2>&1
   ```

   The cron user needs access to docker (member of the `docker` group), and
   cron's `PATH` must contain `docker`, `git` and `curl` (on macOS add e.g.
   `PATH=/usr/local/bin:/usr/bin:/bin` at the top of the crontab). Without the
   redirection cron mails the output instead.

Exit codes: `0` nothing to do / deployed and healthy, `1` deployment refused
(nothing changed, see message), `2` deployed but unhealthy (see below).

### What it does

1. **Preflight** (refuses with exit code 1, nothing is changed):
   - checkout not on `master`, local changes to tracked files, or local
     commits that prevent a fast-forward
   - a new commit has a `Deploy: manual` trailer
   - `config.sh` gained a setting that is not set in `config.local.sh`
     (defaults are placeholders, e.g. passwords). Add it there and the next
     run deploys.
   - PostgreSQL major version changes, unless `AUTO_DEPLOY_PG_REINIT=1`
2. **Activate**:
   - only docs, tests or CI changed (`*.md`, `docs/`, `test/`, `.github/`):
     just update the checkout
   - otherwise `git merge --ff-only`, `docker compose pull`, then the new
     version's `docker-up.sh` (`docker compose up -d --remove-orphans`), which
     recreates services whose image or configuration changed and re-runs the
     `grafana-users` job. Put one-time migrations that must run before
     `docker compose up` into `docker-up.sh`, so they apply to manual and
     automatic deploys alike.
   - restart `grafana` if `datasources.yml`, `dashboards.yml` or
     `dashboard.json` changed, and `caddy` if `Caddyfile` changed. These are
     single-file bind mounts: after git replaced a file, the container still
     sees the old one until it restarts.
   - re-import the database (`init-db.sh`) if `init-db.sql` changed
   - PostgreSQL major upgrade (with `AUTO_DEPLOY_PG_REINIT=1`): delete the
     `solar_dashboard_postgres-data` volume, start the new version, re-import.
     It refuses if `SOLAR_HEAT_DIR` contains no log files.
3. **Verify** (max. about 1 minute): a dashboard query through Grafana
   (`select count(*) from heizung`, as the viewer user - or admin with
   `GRAFANA_ADMIN_PASSWORD` if there is no viewer user, which fails once the
   admin password was changed in the UI) returns data,
   `caddy`, `grafana` and `postgres` are running, and the `grafana-users` job exited
   with 0. Otherwise exit code 2 with the last log lines of each service.

The script runs as a single function parsed before execution, so it can
safely update itself. A lock directory (`.auto-deploy.lock`, removed after 2
hours if stale) prevents overlapping runs.

### What is deployed automatically

| Change | Automatic? | How |
|---|---|---|
| Docs, tests, CI | yes | checkout updated only |
| Image patch/minor updates (Grafana, Caddy, PostgreSQL minor) | yes | pull + recreate |
| Grafana major update | yes | Grafana migrates its own database on start; dashboard/data source changes come in the same, smoke-tested PR. Not reversible, see [Rollback](#rollback) |
| `dashboard.json`, `datasources.yml`, `dashboards.yml` | yes | Grafana restart |
| `Caddyfile` | yes | Caddy restart |
| `docker-compose.yml` (env, ports, networks, new services) | yes | recreate affected services. New *named volumes* are created automatically; removed services are deleted (`--remove-orphans`) |
| `grafana-users.sh`, viewer user changes | yes | job re-runs on every deploy |
| `init-db.sql` (schema, views) | yes | full re-import from the log files (a few seconds of empty dashboard) |
| `update-db.sql`, `update-db.sh`, `update-files.sh` | yes | used by the next cron run |
| `auto-deploy.sh` itself | yes | next run uses the new version |
| New setting in `config.sh` | **after you set it** in `config.local.sh` | refused until then |
| PostgreSQL major update | **on request**: `AUTO_DEPLOY_PG_REINIT=1 ./auto-deploy.sh` | volume deleted, re-import |
| `crontab` | **no** | a note is printed; install it with `crontab crontab` after review |
| External volumes (`grafana-storage`), host requirements (Docker version, ports, DNS, firewall) | **no** | mark the commit `Deploy: manual` |
| Changes needing data migration that can't be rebuilt from the log files (e.g. Grafana users/settings, data not in the log files) | **no** | mark the commit `Deploy: manual` and describe the steps |
| Changes in `config.local.sh` (your settings) | not via git | run `./docker-up.sh` (and `./init-db.sh` for `PG_GRAFANA_PASSWORD`) yourself |

### When it fails

- **Exit 1 (refused)**: nothing was changed, the dashboard keeps running the
  previous version. Fix the reason given (e.g. add a setting to
  `config.local.sh`). For a `Deploy: manual` commit, follow the instructions in
  its message and deploy by hand (`git merge --ff-only origin/master`, then the
  steps from the message). The next run continues from there.
- **Exit 2 (unhealthy)**: the new version is checked out and running, but a
  check failed. It is reported once; later runs stay silent until there are
  new commits. Either push a fix to `master` (deployed by the next run) or roll
  back (see below).

## Rollback

Revert the merge commit on `master` (`git revert -m 1 <merge>` and push, or
the "Revert" button of the PR) and redeploy - with auto-deploy enabled, the
next run deploys the revert. Don't just reset the checkout on the host: it
would then be behind `master` and the next auto-deploy run would bring the
broken version back (comment out the crontab line first if you need to
experiment on the host). Grafana's database migrations are not
reversible: if an older Grafana refuses to start on the migrated volume, reset
it with `docker volume rm grafana-storage && ./init-docker.sh` (everything
important is provisioned). A PostgreSQL major rollback is a major
version change like an upgrade: `AUTO_DEPLOY_PG_REINIT=1 ./auto-deploy.sh`
(or by hand: fresh `solar_dashboard_postgres-data` volume and `./init-db.sh`).

## Automating update runs

Configured in this repo:

- **Dependabot** (`.github/dependabot.yml`) checks the image tags in
  `docker-compose.yml` every Monday morning: patch updates of all images come
  as one grouped PR, minor updates as another, each major update as its own PR. Once a month it
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

- **Auto-merge** (`.github/workflows/dependabot-automerge.yml`) enables
  GitHub auto-merge (squash) for Dependabot PRs that contain only patch
  updates. **Branch protection** on `master` requires the `smoke-test` check
  (from GitHub Actions), so such a PR is merged only when the smoke test is
  green. Repository setting *Allow auto-merge* must stay enabled.

Typical flow:

- **Patch PR**: merged automatically when green. Afterwards deploy on the
  dashboard host (step 6). With [auto-deploy](#automatic-deployment) enabled,
  patch updates go from Dependabot to the running dashboard without
  interaction. Note that merges done by the workflow token do not
  trigger the push workflow on `master`; the PR's smoke test already covered
  the exact change.
- **Green minor PR**: review the release notes, merge, deploy (automatic
  with auto-deploy).
- **Red PR or major update**: follow this guide. Read the release notes, fix the
  files, push to the Dependabot branch and let the workflow re-run. A red
  patch PR stays open (auto-merge waits for green).

To change the protection settings: *Settings → Branches → master*, or
`gh api repos/axeolotl/solar-dashboard/branches/master/protection`.
Admins can still push to `master` directly (`enforce_admins` is off).

Further options:
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
