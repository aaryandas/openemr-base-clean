# OpenEMR — Setup & Deployment

This document records how this OpenEMR fork is run **locally** (with realistic
sample patient data) and how it is **deployed to Railway**. It doubles as a map
of the system's runtime dependencies.

- **Canonical repo:** `ssh://git@labs.gauntletai.com:22022/aaryandas/openemr-agentforge-aaryan.git` (self-hosted GitLab, branch `main`)
- **OpenEMR version:** 8.2.0-dev (upstream master import)
- **Live Railway URL:** https://openemr-production-47c2.up.railway.app
- **Default login:** `admin` / `pass`

---

## 1. What OpenEMR needs to run

OpenEMR is a monolithic PHP web application. A running instance requires:

| Dependency | Role | Local (dev stack) | Railway |
|---|---|---|---|
| **PHP 8.2+ / Apache** | Serves the app (`interface/`, `src/`, legacy `library/`) | Bundled in `openemr/openemr:flex` image | Same image, built via `Dockerfile` |
| **MySQL / MariaDB** | Primary datastore (~280 tables) | `mariadb:11.8.8` container | Railway **MySQL** plugin (`mysql:9.4`) |
| **Composer (PHP deps)** | `vendor/` — Laminas, Symfony, Doctrine DBAL, etc. | Built at container startup | Built at container startup |
| **Node / npm + Webpack** | Compiles themes & JS assets into `public/` | Built at container startup | Built at container startup |
| Selenium (Chromium) | E2E tests / browser debugging | `selenium/standalone-chromium` | — (not deployed) |
| CouchDB | Optional document storage | `couchdb:3.5.2` | — (not deployed) |
| Mailpit | Dev SMTP catcher | `axllent/mailpit` | — (not deployed) |
| OpenLDAP | Optional auth backend | `openemr/dev-ldap` | — (not deployed) |

The two **hard** dependencies are PHP/Apache and MySQL. Everything else is
optional tooling that the "development-easy" stack bundles for convenience.

### The `flex` image (key to both environments)

Both environments use `openemr/openemr:flex`. Unlike the versioned production
images (which bake source in), the flex image **fetches OpenEMR source at
runtime** and then builds Composer + npm dependencies and runs the database
install on first boot. Its behavior is driven by env vars:

- `FLEX_REPOSITORY` / `FLEX_REPOSITORY_BRANCH` — git repo + branch to clone
- `MYSQL_HOST` / `MYSQL_PORT` / `MYSQL_ROOT_USER` / `MYSQL_ROOT_PASS` — DB bootstrap (root creates the app DB + user)
- `MYSQL_USER` / `MYSQL_PASS` / `MYSQL_DATABASE` — the app's own DB credentials
- `OE_USER` / `OE_PASS` — the OpenEMR admin login to create

Locally the source is **bind-mounted**. On Railway this fork's source is
**baked into the image** (`COPY . /openemr`) and installed at first boot — see
§3 for why cloning didn't work for a renamed fork.

---

## 2. Local development environment

### 2.1 Prerequisites

- Docker Desktop (tested: Docker 28.3, Compose v2.38) on macOS (Apple Silicon).
- The repo checked out. No host PHP/Node/Composer toolchain is required —
  everything runs in containers.

### 2.2 Start the stack

The primary dev stack lives in `docker/development-easy/`. It is normally driven
by the project's `openemr-cmd` helper, but it is plain Docker Compose
underneath.

> **Critical on macOS:** the compose file defaults `HOST_UID`/`HOST_GID` to
> `1000`. On macOS your user is uid `501`, gid `20`. If you bring the stack up
> without exporting these, Apache runs as the wrong uid and the bind-mounted
> document root becomes unreadable — the container goes `unhealthy` and every
> request returns **HTTP 403** (`AH00036: access ... Operation not permitted`).
> `openemr-cmd` exports these automatically; with raw `docker compose` you must
> do it yourself.

```bash
cd docker/development-easy
export HOST_UID=$(id -u) HOST_GID=$(id -g)   # 501 / 20 on macOS — do NOT skip
docker compose up --detach --wait
```

Services and ports:

| Service | URL |
|---|---|
| OpenEMR (HTTP) | http://localhost:8300/ |
| OpenEMR (HTTPS) | https://localhost:9300/ |
| phpMyAdmin | http://localhost:8310/ |
| Mailpit (email UI) | http://localhost:8025/ |

Login: `admin` / `pass`.

### 2.3 Verify it's up

```bash
# Should be 302 -> /interface/login/login.php (not 403)
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8300/

docker inspect --format='{{.State.Health.Status}}' development-easy-openemr-1
# -> healthy
```

If you see 403 / `unhealthy`, it is almost always the `HOST_UID` issue above.
Recreate the container with the env exported:

```bash
cd docker/development-easy
export HOST_UID=$(id -u) HOST_GID=$(id -g)
docker compose up -d --force-recreate openemr
```

### 2.4 Sample patient data

The fork ships OpenEMR's canonical demo dataset in `sql/`:

- `sql/example_patient_data.sql` — **14 sample patients** (demographics:
  Ted Shaw, Eduardo Perez, Farrah Rolle, Nora Cohen, …)
- `sql/example_patient_users.sql` — associated provider/user records

The "development-easy" install loads this automatically, so a freshly-built
stack already has the 14 patients. Confirm:

```bash
docker exec development-easy-mysql-1 \
  mariadb -uopenemr -popenemr openemr \
  -e 'SELECT pid, fname, lname, DOB, sex FROM patient_data ORDER BY pid LIMIT 5;'
```

To (re)load the demo data manually into any OpenEMR database:

```bash
docker exec -i development-easy-mysql-1 mariadb -uopenemr -popenemr openemr \
  < sql/example_patient_data.sql
docker exec -i development-easy-mysql-1 mariadb -uopenemr -popenemr openemr \
  < sql/example_patient_users.sql
```

**Richer / more realistic data (optional).** The built-in set is demographics
only. For clinically realistic records (encounters, conditions, meds, labs),
generate [Synthea](https://github.com/synthetichealth/synthea) FHIR bundles and
import them via OpenEMR's FHIR API (`FHIR_README.md`), or restore a demo
database dump from https://demo.openemr.io.

### 2.5 Verified working

Logged in through the bundled Selenium/Chromium container as `admin`; the
authenticated main application renders (OpenEMR 8.2.0-dev) and the patient
finder lists the 14 sample patients.

---

## 3. Railway deployment

The fork is deployed to Railway **from a local checkout of the canonical GitLab
repo via `railway up`**. Railway can link GitHub repos as a build source but not
a self-hosted GitLab, so deploys are explicit CLI uploads: check out the GitLab
repo, `railway up`, done. The upload respects [`.railwayignore`](./.railwayignore),
so what ships is exactly the committed tree. (The service was originally linked
to a GitHub mirror; that source connection has been removed.)

### 3.1 Architecture

Two Railway services in one project (`openemr-fork`):

```
┌─────────────────────────────┐        ┌───────────────────────────┐
│  openemr  (railway up)      │  MySQL  │  MySQL  (Railway plugin)  │
│  Dockerfile → flex image    │ ──────► │  mysql:9.4                │
│  fork source baked in;      │  priv.  │  volume: /var/lib/mysql   │
│  installs at first boot     │  net.   │                           │
│  volume: /…/openemr/sites   │         │                           │
│  public domain :80          │         │                           │
└─────────────────────────────┘        └───────────────────────────┘
        │ https (edge TLS)
        ▼
  openemr-production-47c2.up.railway.app
```

**Why a Dockerfile is required.** Railway auto-detects builds (Nixpacks) for
simple apps, but OpenEMR (Apache + PHP + a Composer install + an npm/Webpack
asset build + a DB-install step) is not auto-detectable. So the repo commits a
`Dockerfile` and a `railway.json` pinning the `DOCKERFILE` builder.

**Why source is baked, not cloned.** The flex image's runtime clone path is
hard-coded to a git directory named `openemr` (it does `rsync openemr …` /
`rm -fr openemr`). Cloning any fork not named `openemr` (like this one) lands in
a differently-named directory, so those commands miss and the entrypoint crashes
under `set -euo pipefail`. The Dockerfile therefore **bakes the fork into
`/openemr`** (`COPY . /openemr`) and sets `EASY_DEV_MODE_NEW=yes`, which makes
flex use that local source instead of cloning. Because Railway rebuilds the
image from the uploaded source on each `railway up`, the running image always
contains the fork's committed code.

Files added for the deploy:
- [`Dockerfile`](./Dockerfile) — `FROM openemr/openemr:flex` (digest-pinned) + `COPY . /openemr` + `EASY_DEV_MODE_NEW=yes`, and `mkdir /couchdb/data` so a dev-only rsync in the entrypoint is a no-op on Railway
- [`.dockerignore`](./.dockerignore) — keeps the build context lean (excludes `.git`, `vendor`, `node_modules`, `tmp`, `project-review`)
- [`.railwayignore`](./.railwayignore) — keeps the `railway up` upload identical to the committed tree (excludes local working material)
- [`railway.json`](./railway.json) — forces the Dockerfile builder

### 3.2 Reproduce the deploy (Railway CLI)

```bash
# 0. Auth + project
railway login
railway init --name openemr-fork

# 1. Database
railway add --database mysql          # provisions mysql:9.4 + a volume

# 2. App service (empty — source arrives via `railway up` in step 5), with DB
#    + admin env wired in one shot. ${{MySQL.*}} are cross-service references
#    resolved by Railway at deploy. (EASY_DEV_MODE_NEW is baked into the
#    Dockerfile, not set here.)
railway add \
  --service openemr \
  --variables 'MYSQL_HOST=${{MySQL.MYSQLHOST}}' \
  --variables 'MYSQL_PORT=${{MySQL.MYSQLPORT}}' \
  --variables 'MYSQL_ROOT_USER=root' \
  --variables 'MYSQL_ROOT_PASS=${{MySQL.MYSQL_ROOT_PASSWORD}}' \
  --variables 'MYSQL_USER=openemr' \
  --variables 'MYSQL_PASS=openemr' \
  --variables 'MYSQL_DATABASE=openemr' \
  --variables 'OE_USER=admin' \
  --variables 'OE_PASS=pass'

# 3. Persist the OpenEMR site config (sqlconf.php etc.) across restarts,
#    so a redeploy doesn't try to reinstall over a populated database.
railway service link openemr
railway volume add --mount-path /var/www/localhost/htdocs/openemr/sites

# 4. Public domain, routed to the container's HTTP port 80
#    (Railway terminates TLS at the edge).
railway domain --service openemr --port 80

# 5. Build + deploy the current checkout (must be a clean checkout of the
#    GitLab repo's main). Railway cannot watch a self-hosted GitLab, so every
#    deploy is this explicit upload:
railway up --service openemr --ci -m "deploy <short description>"
```

First boot runs rsync (baked source) → Composer build → npm/Webpack build → DB
install, which takes **~10–15 minutes**. The URL returns 502/errors until that
finishes; then it serves the login page. Watch progress with:

```bash
railway service status       # BUILDING → SUCCESS (container running)
railway logs --deployment    # streams container logs (look for "OpenEMR configured")
```

### 3.3 Verified live

Confirmed end-to-end: `https://openemr-production-47c2.up.railway.app/` →
302 to the OpenEMR login → logged in as `admin`/`pass` → the main application
(Calendar / Providers / patient search) renders with compiled themes
(OpenEMR 8.2.0-dev). Driven with a real browser (Selenium) against the public
URL.

### 3.4 Notes, gotchas & known limitations

- **Private networking is IPv6.** `MYSQL_HOST` resolves to
  `mysql.railway.internal` (IPv6-only); the MariaDB client and PHP `mysqli`
  handle this fine.
- **Root is used only to bootstrap.** OpenEMR uses the MySQL root credential
  once to create the `openemr` database and user, then connects as `openemr`.
- **Health endpoint quirk.** `/meta/health/readyz` may report
  `"installed": false` even on a working instance — that check scopes
  `global $config` in a context where it isn't populated. The real proof of
  install is that `admin`/`pass` logs into the main application (verified).
- **Deps rebuild on restart.** Only `sites/` is on a volume; `vendor/`,
  `node_modules/`, and `public/` live on the ephemeral container filesystem, so
  a container restart re-runs the ~10-min Composer + npm build before serving.
  Acceptable for a demo; to make restarts fast, bake those into the image at
  build time instead.
- **Sample data on Railway.** The install path seeds a clean OpenEMR database
  (no demo patients). To load the 14 demo patients on the live instance, pipe
  the two `sql/example_*` files into the MySQL service (e.g. via
  `railway connect MySQL`).
- **NOT production-hardened (by design, per scope).** The instance is publicly
  reachable with default `admin` / `pass` credentials and demo data. Before any
  real use: change the admin password, rotate `MYSQL_*` secrets, restrict
  access, and enable HTTPS enforcement.

---

## 4. Quick reference

| Item | Value |
|---|---|
| Local HTTP | http://localhost:8300/ |
| Local HTTPS | https://localhost:9300/ |
| phpMyAdmin | http://localhost:8310/ |
| Railway URL | https://openemr-production-47c2.up.railway.app |
| Login | `admin` / `pass` |
| DB (local) | `mariadb` container, db `openemr`, user `openemr`/`openemr` |
| Sample data | `sql/example_patient_data.sql`, `sql/example_patient_users.sql` |
