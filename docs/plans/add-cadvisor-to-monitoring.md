# Task: Integrate cAdvisor into the Monitoring Stack

**Audience:** another agent (or engineer) picking this up from scratch.
**Goal:** Research, plan, and implement cAdvisor support in `tasks/setup-monitoring.sh` so the stack provides per-container CPU/memory/disk/network metrics in Prometheus and a ready-to-use Grafana dashboard.

Read `AGENTS.md` at the repo root first — it defines binding conventions (linting, idempotency, templating, `/srv` layout). When planning or implementing code changes, load and follow the `karpathy-guidelines` skill (surgical changes, no speculative features).

---

## 1. Context (what already exists)

The monitoring stack is deployed by `tasks/setup-monitoring.sh` (Docker Compose, idempotent, `envsubst`-rendered templates in `templates/monitoring/`):

| Component | Notes |
|---|---|
| Prometheus (`prom/prometheus:v3.13.2`) | Scrapes itself + containers via **docker_sd_configs**: any container labeled `prometheus.scrape=true` is kept; `prometheus.port=<port>` overrides the scrape port. Config rendered from `templates/monitoring/prometheus.yml`. |
| Grafana (`grafana/grafana:13.1.1`) | Non-root (UID 472), admin creds in mode-600 `/srv/grafana/.env`, datasources + dashboards **auto-provisioned**: every JSON dropped into `/srv/grafana/dashboards/` (template `grafana-dashboard.json`, provider `grafana-provisioning.yml`) shows up in Grafana. |
| Node Exporter (`quay.io/prometheus/node-exporter:v1.12.1`) | Host metrics via `pid: host` + host mounts; discovered via the `prometheus.scrape` labels. |

Key files:
- `tasks/setup-monitoring.sh` — the script (config vars, pre-flight, dir creation, rendering, health checks, summary output)
- `templates/monitoring/docker-compose-direct.yml` and `docker-compose-traefik.yml` — **two** compose templates, selected by `GRAFANA_TRAEFIK` (both must stay in sync for shared services)
- `templates/monitoring/prometheus.yml` — scrape jobs
- `templates/monitoring/grafana-dashboard.json` + `grafana-provisioning.yml` + `grafana-datasource.yml`
- `lib/helpers.sh` — shared functions (`run_preflight_checks`, `ensure_proxy_network`, …) — reuse, don't duplicate
- `docs/plans/monitoring-feature-plan.md` — original feature spec, useful background
- `machine-config.yml.example` — orchestrator config; every task has an entry there

**Currently missing:** per-container metrics. No cAdvisor, no docker-daemon metrics job. The `node` job only covers the host aggregate.

## 2. Research phase (do this first, record findings in §5 "Plan")

Answer, with sources (official docs/registry), and verify current values — do not trust this list blindly:

1. **Image & version pin**
   - Which registry hosts the official cAdvisor image and what is the latest stable tag? (Historically `gcr.io/cadvisor/cadvisor`; check for a Docker Hub/`quay.io`/`ghcr.io` option or the Bitnami image — prefer a Docker-Hub-pullable, actively maintained option. Note: `gcr.io` has had access flakiness for some users — weigh that.)
   - Pin an exact tag, same style as the other services. Expose it as `CADVISOR_IMAGE_VERSION` env var with that pin as default (match the pattern of `PROMETHEUS_IMAGE_VERSION` etc.).
2. **Runtime requirements**
   - Required mounts: `/var/run/docker.sock`, `/sys/fs/cgroup`, Docker data-root (e.g. `/var/lib/docker` — detect via `docker info`? research best practice), `/` read-only, possibly `/var/lib/kubelet` (skip if irrelevant).
   - What UID/GID does the image run as (image default user)? cAdvisor is read-mostly — does it need any writable host dir at all? (It keeps a small internal cache; confirm whether a persistent volume is needed — prefer **no** persistent dir if that's safe.)
   - Flags worth setting for a host-Docker setup (e.g. storage duration, `--docker_only` vs all runtimes, log level). Keep minimal — no speculative flags.
3. **Security**
   - cAdvisor gets a docker socket — same risk class as the existing Prometheus socket mount (accepted, documented in the script). Is `:ro` sufficient for the socket? Any additional hardening (read-only rootfs, `no-new-privileges`, dropping capabilities)? Follow what the other services in the compose templates do — don't invent a new pattern.
4. **Metrics**
   - List the core metric families cAdvisor exposes (`container_cpu_usage_seconds_total`, `container_memory_usage_bytes`, `container_fs_usage_bytes`, `container_network_receive_bytes_total`, `container_last_seen`, …) and the important labels (`name`, `id`, `image`, `pod_name`?).
   - How do container names come through (leading `/` in `name` label? — check, dashboards often need `{name=~"^.*/?(.*)$"}` handling).
5. **Grafana dashboard**
   - Which community/official dashboard fits (e.g. the well-known "cAdvisor" dashboard, IDs 14282 / 193)? Pick one, note its datasource-UID assumptions (ours is `prometheus`) and schema version.
   - Decide: adapt the JSON (fix datasource uid, trim panels) or keep it close to upstream for future upgrades. The repo style (see `grafana-dashboard.json`) is a curated, self-contained JSON committed to `templates/monitoring/`.
6. **Health endpoint** — what does cAdvisor expose for health (`/healthz`, `/metrics`)? We poll via `container_healthy` in the script; decide whether cAdvisor joins the health wait or stays out of it (it's non-blocking for the stack to be useful; recommend keeping the current two-service health check unless trivial).

## 3. Requirements (must satisfy)

1. **Discovery must use the existing label mechanism** — cAdvisor is added to both compose templates with `prometheus.scrape=true` + `prometheus.port=8080` labels. **No new scrape job / no `prometheus.yml` changes** (verify this actually works with docker_sd during implementation; only if it demonstrably fails may you add a static job, and explain why).
2. **Both compose templates** (`direct` and `traefik`) get the cAdvisor service — it is internal to `monitoring-net` in both modes (no ports published, no Traefik labels).
3. **New env var** `CADVISOR_IMAGE_VERSION` (pinned default from research) in the script's config block + header `IMPORTANT VARIABLES` list + exports for envsubst.
4. **Grafana dashboard** committed as `templates/monitoring/grafana-cadvisor.json`, copied by the script into `/srv/grafana/dashboards/` (reusing the existing `sudo cp` pattern) — it must appear in Grafana automatically via the existing dashboard provider. Datasource reference must use uid `prometheus` (our provisioned datasource).
5. **Idempotency preserved**: re-running the script must not wipe or duplicate anything; cAdvisor adds no state of its own (confirm from research).
6. **Script header** (`DESCRIPTION`, `KEY ACTIONS`, `IMPORTANT VARIABLES`) and the final **summary output** stay accurate (mention cAdvisor + where to find its dashboard).
7. **Documentation**:
   - `README.md` — add a cAdvisor note in the monitoring section (match the style of the other service docs).
   - `machine-config.yml.example` — the `setup-monitoring` entry already exists; no change needed unless you add user-facing env vars worth showcasing (e.g. keep it minimal).
8. **Linting (binding, from AGENTS.md)**:
   - `shellcheck tasks/setup-monitoring.sh` → clean
   - `yamllint templates/monitoring/*.yml` → no new findings
   - `jq . templates/monitoring/grafana-cadvisor.json` → valid
9. **Known bug to avoid re-introducing**: rendered files from `mktemp` start mode 600 — anything moved into place for a container to read must be `chmod 644` first (see the existing note in the rendering section).

## 4. Implementation TODO

- [x] §2 research complete; findings + design decisions written into §5
- [ ] Pin `CADVISOR_IMAGE_VERSION` default; add to script config block, header docs, and envsubst exports
- [ ] Add `cadvisor` service to `templates/monitoring/docker-compose-direct.yml` (image, mounts per research, `user:`/`security_opt` consistent with repo style, `restart: unless-stopped`, labels `prometheus.scrape=true` + `prometheus.port=8080`, networks: `monitoring-net` only)
- [ ] Mirror the identical service in `templates/monitoring/docker-compose-traefik.yml`
- [ ] Create `templates/monitoring/grafana-cadvisor.json` (adapted dashboard, datasource uid `prometheus`)
- [ ] Script: `sudo cp` the dashboard into `${GRAFANA_HOME}/dashboards/` alongside the existing dashboard copy; update header + summary output
- [ ] `machine-config.yml.example` / `README.md` updates per requirement 7
- [ ] Lint everything (requirement 8)
- [ ] Verification per §6 passes on a real Docker host
- [ ] Self-review diff against §3 requirements; note any deviations with justification

## 5. Plan (research findings + design decisions)

All findings below were verified empirically on a Docker 29.7.2 / cgroup-v2 host by pulling and running the image, not just from docs.

- **Image:** `ghcr.io/google/cadvisor:v0.60.5` (latest stable release, pinned).
  - Registry: the official image moved from `gcr.io/cadvisor/cadvisor` to `ghcr.io/google/cadvisor` starting with v0.53.0 (gcr.io has been flaky/deprecated). No Docker-Hub-mirrored official image exists; `ghcr.io/google/cadvisor` is the current official distribution and pulled cleanly here. (An earlier ghcr publishing gap affected v0.54.0–v0.56.2, issue #3871; v0.60.5 manifests resolve fine.)
  - Exposed port: 8080 (image `EXPOSE`).
- **Mounts (all read-only, verified working with this exact set):**
  - `/:/rootfs:ro` — machine/filesystem stats (upstream docs mount `/:/rootfs:ro`).
  - `/var/run/docker.sock:/var/run/docker.sock:ro` — Docker API (container list/stats); `:ro` is sufficient for a unix socket client (same pattern as the existing prometheus socket mount).
  - `/sys:/sys:ro` — covers `/sys/fs/cgroup` on cgroup v2 (Ubuntu default) for per-container CPU/memory.
  - `/var/lib/docker:/var/lib/docker:ro` — containerd overlay root; upstream `docs/running.md` mounts it; needed for full filesystem usage stats.
  - No `/var/lib/kubelet`, no `/dev/disk`, no writable mount: cAdvisor v0.60 keeps its internal cache in memory (verified: runs with only `:ro` mounts), so **no persistent volume** is needed. Docker data-root defaults to `/var/lib/docker` (confirmed via `docker info`); a `--docker_root` override is not needed since cAdvisor ≥ v0.35 reads it from `docker info` (flag is deprecated).
- **Flags:** none. Defaults are correct for a host-Docker setup (`--docker_only` defaults to `true`, storage duration default fine). No speculative flags per Karpathy guidelines.
- **Security:**
  - Image has no `USER` directive (verified via `docker inspect`) and runs as root in-container — required to read host cgroups and `/var/lib/docker` (upstream issues #2452, #3051). We keep the image default (no `user:` override) and document the docker-socket risk class as already accepted for Prometheus.
  - All four mounts are `:ro`; no `privileged`, no `pid: host`. We do not add `security_opt`/`read_only` because no other service in these compose templates uses them (stay consistent with repo style).
- **Metrics & labels (verified from live `/metrics` of v0.60.5):**
  - Families: `container_cpu_usage_seconds_total`, `container_memory_usage_bytes`, `container_memory_cache`, `container_memory_working_set_bytes`, `container_fs_usage_bytes`, `container_fs_reads_bytes_total`, `container_fs_writes_bytes_total`, `container_network_receive_bytes_total`, `container_network_transmit_bytes_total`, `container_last_seen`, `container_spec_*`.
  - `name` label: **no leading `/`** (e.g. `name="forgejo"`) in v0.60 — dashboards can filter with `name=~".+"` directly; no leading-slash normalization needed.
  - `id` label is the cgroup path (`/system.slice/docker-<id>.scope` on this host), so dashboards must not rely on `id=~"^/docker/*"`.
- **Grafana dashboard:** ID **19908** "cAdvisor Docker Insights" (schemaVersion 38, 14 panels, modern `timeseries`/`stat` panels). Chosen over 193 (schemaVersion 12, obsolete, uses `id`-based filters that don't match systemd cgroup paths) and 14282 (older, minimal). Adaptations to repo style:
  1. Replace all 9 `"uid": "${DS_PROMETHEUS}"` datasource references with the fixed provisioned uid `"prometheus"` (matches `grafana-dashboard.json` style; removes the need for import-time input mapping).
  2. Set a fixed `uid` (`cadvisor-container-insights`) and `title` `cAdvisor - Container Metrics`; add `tags` like the existing dashboard.
  3. All queries verified to use metrics that exist in v0.60.5 (`container_last_seen`, `container_memory_cache`, …) and the slash-free `name` label.
- **Health:** cAdvisor exposes `GET /healthz` → `ok` (verified). Decision: keep the script's health wait at the existing two services (Prometheus + Grafana) — cAdvisor is useful once Prometheus is up, and adding it gains little; a slow cAdvisor start (machine inventory scan) must not delay script completion.
- **Discovery:** label-based `docker_sd_configs` only (`prometheus.scrape=true` + `prometheus.port=8080`), no `prometheus.yml` change — to be confirmed by the §6 target check on a live stack.
- **Deviations from §3:**
  1. **README:** the README has *no* monitoring section at all (`setup-monitoring.sh` is undocumented). To add a cAdvisor note I add a minimal new `### Monitoring & Observability` section containing the standard-style `#### setup-monitoring.sh` entry (description + env vars + cAdvisor note). This is the smallest change that satisfies "add a cAdvisor note in the monitoring section".
  2. `machine-config.yml.example`: no change (plan says keep it minimal; no new user-facing env vars beyond the image pin, which is not showcased for the other services either… actually all image pins are listed in the script header only, so this stays consistent).
- **Verification:** run the exact §6 steps (direct mode, `GRAFANA_PORT=3100`), plus the §6 target check filtered to the `cadvisor :8080` instance (the §6 snippet shows the `node` job filter as an example — cAdvisor lands in the same `node` job via docker_sd).

## 6. Verification (acceptance criteria)

Run on a Docker host (the dev machine is fine; ports: Grafana direct mode needs a free port, e.g. `GRAFANA_PORT=3100`):

```bash
# 0. Fresh state (or clean /srv/monitoring first)
GRAFANA_PORT=3100 ./tasks/setup-monitoring.sh

# 1. All three+ containers up
docker ps --filter name=cadvisor --format '{{.Status}}'

# 2. cAdvisor target discovered via LABELS (not a static job) and UP
PROMIP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' prometheus | awk '{print $1}')
curl -s "http://$PROMIP:9090/api/v1/targets" | jq -r '.data.activeTargets[] | select(.labels.job=="node") | "\(.labels.instance) \(.health)"'
# → expect a cadvisor :8080 target with health "up"

# 3. Container metrics actually flow
curl -s "http://$PROMIP:9090/api/v1/query?query=container_memory_usage_bytes" | jq '.data.result | length'   # > 0
curl -s "http://$PROMIP:9090/api/v1/query?query=container_cpu_usage_seconds_total" | jq '.data.result | length' # > 0
# sanity: our own services (grafana/prometheus/node_exporter/cadvisor) appear by name

# 4. Dashboard auto-provisioned in Grafana (no manual import)
#    Grafana → Dashboards → "cAdvisor" (or your chosen title) exists; panels render with data
#    (verify API-side if headless: curl the Grafana /api/search with basic auth from /srv/grafana/.env)

# 5. Idempotency: re-run the script (accept re-create), data preserved, no duplicate containers/targets
GRAFANA_PORT=3100 MONITORING_FORCE=true ./tasks/setup-monitoring.sh
curl -s "http://$PROMIP:9090/api/v1/targets" | jq '[.data.activeTargets[] | select(.labels.job=="node")] | length'  # cadvisor appears exactly once

# 6. Lint
shellcheck tasks/setup-monitoring.sh
yamllint templates/monitoring/
jq . templates/monitoring/grafana-cadvisor.json
```

**Definition of done:** all §6 checks pass, §3 requirements met, §5 plan section filled in, diff reviewed for scope creep (only monitoring files touched), and this file's TODO list fully checked off.
