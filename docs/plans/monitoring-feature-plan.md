# Feature Specification: Monitoring Stack (Prometheus & Grafana)

## Description
Automated deployment of a containerized monitoring stack comprising Prometheus, Grafana, and Node Exporter. The setup is designed to provide immediate visibility into host and container metrics via Traefik-integrated web interfaces. The stack is deployed by a single idempotent bash task script (`tasks/setup-monitoring.sh`) integrated into the `run-setup.sh` orchestrator.

## Goals
- Deploy a fully functional observability stack with zero manual configuration after running the script.
- Enable automatic discovery of Docker containers for metric scraping using Prometheus Docker service discovery (`docker_sd_config`).
- Provide instant "out-of-the-box" visibility by provisioning a default Node Exporter dashboard in Grafana via provisioning files (no manual import).
- Ensure high flexibility through environment variable overrides (networks, domains, versions, credentials).
- Guarantee idempotency: repeated runs must never destroy existing data in `/srv/prometheus` or `/srv/grafana`.

## Verified Version Pins (researched from official registries)
These are the current stable tags to use as defaults (override via env vars). Re-verify before production pinning.
- **Prometheus**: `prom/prometheus:v3.13.2` (Docker Hub)
- **Grafana (OSS)**: `grafana/grafana:13.1.1` (Docker Hub — the `grafana/grafana-oss` repo is no longer updated; use `grafana/grafana`)
- **Node Exporter**: `quay.io/prometheus/node-exporter:v1.12.1` (quay.io)

## Behaviors

### 1. Deployment Architecture
- **Services**: All services run as Docker containers within a shared user-defined Docker bridge network (`monitoring-net` by default).
    - **Prometheus**: Scrapes metrics from Node Exporter and other discoverable containers. Mounts the host Docker socket (`/var/run/docker.sock:ro`) to enable `docker_sd_config`. Data persisted on host.
    - **Grafana**: Web interface for visualizing metrics, accessible via Traefik. Attached to **both** the monitoring network (to reach Prometheus at `http://prometheus:9090`) **and** the external Traefik `proxy` network.
    - **Node Exporter**: Runs as a container, mounted to host paths (`/proc`, `/sys`, `/`) to monitor the host machine's health. Uses `pid: host` and `--path.rootfs=/host` with a `/:ro,rslave` host-root bind mount.
- **Network topology**:
    - `monitoring` network: `driver: bridge`, **not** `internal: true` (an internal network would block outbound scraping and complicate host-networked targets). All three services join it.
    - `proxy` network: declared `external: true` (created by the Traefik stack). Only Grafana joins it, so Traefik can reach the Grafana backend.
- **Reverse Proxy Integration**:
    - Grafana is configured with Traefik labels for external access via a subdomain (e.g., `grafana.example.com`) using the `websecure` entrypoint and the `letsencrypt` certresolver.
    - `traefik.docker.network=proxy` must be set so Traefik uses the correct backend IP when Grafana is on multiple networks.
    - Prometheus remains internal to the monitoring network, reachable only by monitoring services and other containers on the same network.

### 2. Data Persistence
All persistent data is stored on the host in dedicated directories (host bind mounts, not named volumes):
- **Prometheus data**: `/srv/prometheus/data` (TSDB), `/srv/prometheus/config` (rendered `prometheus.yml`)
- **Grafana data**: `/srv/grafana/data` (SQLite/state), `/srv/grafana/provisioning` (datasource + dashboard provider YAML), `/srv/grafana/dashboards` (dashboard JSON)

**Ownership (critical for container write access):**
- Prometheus container runs as UID/GID `65534:65534` (nobody) → `/srv/prometheus/*` owned by `65534:65534`.
- Grafana container runs as UID `472:472` → `/srv/grafana/*` owned by `472:472`.
- Node Exporter runs as root (needs `/proc`, `/sys`, `/`) → no host writable dirs needed.

### 3. Automated Configuration & Discovery
- **Docker Service Discovery**: Prometheus uses `docker_sd_configs` with `host: unix:///var/run/docker.sock` and a relabel rule that **keeps only containers carrying the `prometheus.scrape=true` label** (the meta label is `__meta_docker_container_label_prometheus_scrape`). This is the canonical pattern from the official `prometheus-docker.yml` example.
- **Host Monitoring**: Node Exporter is discovered automatically via docker_sd on the shared monitoring network (it joins the `monitoring` network rather than `network_mode: host`). Prometheus reaches it by container IP at port `9100`. This avoids the host-networking gotcha where `localhost` would resolve to the Prometheus container itself.
- **Dashboard Provisioning**: Upon deployment, Grafana is configured via provisioning files to automatically load and display a pre-configured Node Exporter dashboard:
    - Datasource provider file registers a Prometheus datasource pointing at `http://prometheus:9090`.
    - Dashboard provider file (type: `file`, `options.path: /var/lib/grafana/dashboards`) auto-loads the dashboard JSON.
    - Binding `/srv/grafana/provisioning` over `/etc/grafana/provisioning` replaces the stock Grafana provisioning tree, disabling the built-in sample dashboards.

### 4. Configuration & Customization (Environment Variables)
The setup script must support the following overrides:
- `MONITORING_HOME`: Base data directory (default: `/srv`)
- `MONITORING_DOCKER_NETWORK`: Name of the internal Docker network (default: `monitoring-net`)
- `PROXY_NETWORK`: Traefik's external Docker network (default: `proxy`) — used for Grafana routing
- `GRAFANA_DOMAIN`: Subdomain/domain used for Traefik routing (e.g., `grafana.example.com`) — **required** when Traefik integration is enabled
- `GRAFANA_ADMIN_USER`: Grafana admin username (default: `admin`)
- `GRAFANA_ADMIN_PASSWORD`: Grafana admin password (auto-generated with `openssl rand` if not set, stored in `/srv/grafana/.env` with mode 600)
- `PROMETHEUS_IMAGE_VERSION`: Prometheus image tag (default: `prom/prometheus:v3.13.2`)
- `GRAFANA_IMAGE_VERSION`: Grafana image tag (default: `grafana/grafana:13.1.1`)
- `NODE_EXPORTER_IMAGE_VERSION`: Node Exporter image tag (default: `quay.io/prometheus/node-exporter:v1.12.1`)

## Implementation Details

### Files to Create
- `tasks/setup-monitoring.sh`: The main automation script (sources `lib/helpers.sh`, uses its step/info/success/warn/error helpers and pre-flight checks).
- `templates/monitoring/docker-compose.yml`: Template for the service definitions (rendered by the script; env-substituted for network names, versions, domain, credentials).
- `templates/monitoring/prometheus.yml`: Prometheus configuration template (docker_sd_config + node-exporter discovery via labels).
- `templates/monitoring/grafana-dashboard.json`: The pre-configured Node Exporter dashboard JSON.
- `templates/monitoring/grafana-datasource.yml`: Grafana datasource provisioning file (registers Prometheus datasource).
- `templates/monitoring/grafana-provisioning.yml`: Grafana dashboard provider provisioning file (auto-loads JSON dashboards).

### Script Flow (`setup-monitoring.sh`)
1. **Pre-flight**: Source `lib/helpers.sh`; verify Docker + daemon; verify Docker Compose v2; validate `GRAFANA_DOMAIN` is set when Traefik integration is on; ensure the `proxy` network exists via `ensure_proxy_network`.
2. **Directory creation + ownership**: Create `/srv/prometheus/{data,config}` owned by `65534:65534` and `/srv/grafana/{data,provisioning,dashboards}` owned by `472:472`. Use guarded creation (`install -d -o ... -g ...`) that only chowns when a directory is newly created (never `chown -R` over existing data on re-runs).
3. **Credential generation**: Generate `GRAFANA_ADMIN_PASSWORD` via `openssl rand` if unset; store in `/srv/grafana/.env` (mode 600). Reuse existing password on re-run (idempotent).
4. **Render templates**: Render `prometheus.yml` into `/srv/prometheus/config/prometheus.yml`; render datasource + dashboard provider into `/srv/grafana/provisioning/`; copy dashboard JSON into `/srv/grafana/dashboards/`. Render `docker-compose.yml` into `/srv/monitoring/docker-compose.yml`.
5. **Pull + start**: `docker compose pull`, then `docker compose up -d`.
6. **Health check**: Poll Grafana `/api/health` (and Prometheus `/-/healthy`) up to a bounded timeout; report access URL.
7. **Summary**: Print access info, credentials location, and useful management commands.

### Idempotency & Re-run Handling
- If the compose file already exists, do **not** tear down data. Apply the same pattern used by `setup-forgejo.sh`: prompt (or skip in non-interactive) whether to re-create the stack, explicitly preserving `/srv/prometheus` and `/srv/grafana`. Never `down -v`.
- Re-running must reuse the stored admin password (read from `.env` if present).
- Only chown newly-created directories.

### Requirements & Constraints
- **Linting**: Generated shell script must pass `shellcheck`; all YAML files must pass `yamllint`; the dashboard JSON must pass `jq` validation.
- **Permissions**: Handle directory creation and ownership as specified in Behavior 2.
- **Docker socket gotcha**: Prometheus must read `/var/run/docker.sock:ro`; the Prometheus container runs as `nobody` (65534). If the socket is not world-readable, the setup script must verify access and either add the supplementary `docker` group to the Prometheus service (`group_add`) or warn clearly. Verify `ls -l /var/run/docker.sock` at install time.
- **Compose conventions**: Compose v2 — omit the obsolete top-level `version:` key. Set a `name: monitoring` project name.
- **Integration**: Add a `setup-monitoring` entry to both `machine-config.yml` and `machine-config.yml.example` (disabled by default), following the existing schema (`enabled`, `description`, `env`, `args`).

## Success Criteria
1. Running `run-setup.sh` with the monitoring module enabled successfully starts all three containers (`prometheus`, `grafana`, `node_exporter`).
2. The Grafana dashboard is accessible via the configured Traefik domain over HTTPS.
3. The Grafana dashboard is automatically provisioned (no manual import) and displays live metrics from the host machine (CPU, Memory, Disk).
4. A new container started on the same `monitoring` network carrying the `prometheus.scrape=true` label is automatically discovered and scraped by Prometheus (visible in the Prometheus targets UI).
5. Re-running the script does not destroy existing Prometheus TSDB data or Grafana state, and preserves the admin password.

## Open Questions (resolved during research)
- ~~How Prometheus reaches a host-networked node_exporter~~ → Resolved: node_exporter joins the `monitoring` network; docker_sd discovers it by container IP on that network. Avoid `network_mode: host` for this stack.
- ~~Single provisioning file vs datasource+dashboard providers~~ → Resolved: need both a datasource provider YAML and a dashboard provider YAML; the plan's single `grafana-provisioning.yml` is expanded to two files.
- ~~Prometheus docker.sock access as UID 65534~~ → Handled in script via group_add / access verification (see Requirements).
