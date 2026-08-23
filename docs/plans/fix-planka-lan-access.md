# Plan: Fix Planka LAN access — socket.io origin rejection (`tasks/setup-planka.sh`)

**Date:** 2026-08-23
**Scope:** `tasks/setup-planka.sh` — Planka deployed on **evobox** (`192.168.178.57`, direct port mode, no Traefik) rejects browser WebSocket connections when accessed from the local network.

---

## 1. Symptoms

| Where | Observed |
|---|---|
| Browser console (LAN client) | `WebSocket connection to 'ws://192.168.178.57:1337/socket.io/?__sails_io_sdk_version=1.2.1&...&EIO=4&transport=websocket' failed:` |
| Server log (`docker logs planka`) | `debug: It looks like your sails.config.sockets.onlyAllowOrigins array only includes references to the localhost origin...` |
| Server log (unrelated) | `2026-08-23 14:02:58 [W] Custom terms not found, falling back to template` |

Page loads and normal HTTP/REST traffic works from the LAN — **only the socket.io (real-time) channel fails.**

## 2. Root cause analysis

### 2.1 The chain

1. **Script default.** `tasks/setup-planka.sh` sets
   `BASE_URL="${BASE_URL:-http://localhost:${HTTP_PORT}}"` → the compose env on evobox is `BASE_URL=http://localhost:1337`.

2. **Planka whitelists socket origins from `BASE_URL`.** Upstream production config (`plankanban/planka` @ `266246e`, `server/config/env/production.js`):
   ```js
   // line 26
   const origins = process.env.BASE_URL.split(',').map((baseUrl) => new URL(baseUrl).origin);
   // line ~224
   sockets: { onlyAllowOrigins: origins }
   ```
   `BASE_URL` natively accepts a **comma-separated list**; each entry's origin is added to the socket.io allow-list.

3. **Client connects to the page origin.** The SPA uses `sails.io.js` with no explicit URL (`client/src/api/socket.js`: `const io = sailsIOClient(socketIOClient); io.sails.path = ...`). The socket.io handshake therefore carries `Origin: http://192.168.178.57:1337` — the host:port the user typed.

4. **Sails enforces the allow-list in production mode** (CSWSH protection, Sails ≥1). `http://192.168.178.57:1337` ∉ `{ http://localhost:1337 }` → handshake rejected → browser logs the WS failure; Sails logs the `localhost`-only debug notice. Real-time features (live board updates, drag & drop sync) are dead; everything else works.

5. `config/custom.js` uses only the **first** `BASE_URL` entry for app-level base URL (email links, secure flag) — so the order of the list matters, and `localhost` should stay first in direct mode.

### 2.2 Red herring

`Custom terms not found, falling back to template` comes from the **terms hook** (`server/api/hooks/terms/index.js:62`): no custom Terms-of-Service documents are configured in app settings, so Planka falls back to the built-in ToS template. Benign, unrelated to the WebSocket failure.

### 2.3 Corroboration

- Sails docs: `sails.config.sockets.onlyAllowOrigins` — production forces explicit origins (CSWSH protection).
- Planka issues with the identical symptom and the same resolution (add all access URLs to `BASE_URL`): #166, #530, #1245.

## 3. Immediate unblock (manual, on evobox)

No script change needed to fix the running instance:

```bash
cd /srv/planka
# in docker-compose.yml: change
#   - BASE_URL=http://localhost:1337
# to
#   - BASE_URL=http://localhost:1337,http://192.168.178.57:1337
docker compose up -d   # recreates the planka container
```

Then verify from a LAN device: page loads, **no** WS error in the browser console, real-time sync works (move a card on one client, watch it update live on the other).

## 4. Script fix (this plan)

Design: keep `BASE_URL` as the single source of truth (Planka already consumes it for the socket allow-list), make the **default** LAN-aware, and let users add further origins (hostname access, Tailscale, etc.).

### 4.1 New/changed env vars

| Var | Default | Purpose |
|---|---|---|
| `BASE_URL` | *(auto, see 4.2)* | Full base URL / comma-separated origin list (existing) |
| `PLANKA_HOST_IP` | auto-detect (first non-loopback IPv4 via `hostname -I`) | IP used to build the LAN origin |
| `PLANKA_EXTRA_ORIGINS` | *(empty)* | Optional comma-separated extra access URLs appended to the allow-list, e.g. `http://evobox:1337` or `http://100.x.y.z:1337` (Tailscale) |

### 4.2 Origin list construction (direct mode, `PLANKA_TRAEFIK != true`)

1. Auto-detect LAN IP: first IPv4 from `hostname -I` matching `^[0-9.]+$`, non-loopback. Fallback: warn and continue with localhost-only (existing behavior) if detection fails.
2. If `BASE_URL` **not** set by user → default to
   `http://localhost:${HTTP_PORT},http://${LAN_IP}:${HTTP_PORT}`.
3. If user-provided `PLANKA_EXTRA_ORIGINS` non-empty → append each entry (after `new URL(...).origin`-style normalization is done upstream anyway, so plain URLs are fine) and **deduplicate**.
4. **Guard:** if the final list contains only `localhost`/`127.0.0.1` origins → `warn` that LAN clients will be rejected by Planka's socket allow-list (exact bug symptom) and print the one-liner to add (e.g. set `PLANKA_HOST_IP`/`PLANKA_EXTRA_ORIGINS`).

Traefik mode: unchanged (`BASE_URL=https://PLANKA_DOMAIN`), but `PLANKA_EXTRA_ORIGINS` still appended for e.g. internal-IP access.

### 4.3 Script changes (surgical) — implemented ✅

- [x] Header comment: document `PLANKA_HOST_IP`, `PLANKA_EXTRA_ORIGINS`; note that `BASE_URL` accepts a comma-separated origin list and controls Planka's socket.io allow-list.
- [x] Replace `BASE_URL="${BASE_URL:-http://localhost:${HTTP_PORT}}"` with the construction from 4.2 (small local helper, e.g. `detect_lan_ip()` + dedupe via `awk '!seen[$0]++'` on a normalized comma list).
- [x] Keep the `BASE_URL=https://${PLANKA_DOMAIN}` override in Traefik pre-flight; add extra-origin append + dedupe there too.
- [x] Add the localhost-only warning from 4.2.4.
- [x] Summary section: print the LAN access URL (`http://${LAN_IP}:${HTTP_PORT}`) and the full allow-list of origins so users can see what is reachable.
- [x] Lint: `shellcheck tasks/setup-planka.sh` → **clean (0 findings)**.

> Note: two pre-existing `SC2015` (info) findings in the admin-user creation block (`&& success … || warn …`) were converted to `if/else` (behavior-preserving) so the file passes shellcheck with zero findings, matching the rest of `tasks/`.

### 4.4 Verification (done)

- [x] 7-case functional test of the resolution block (extracted verbatim from the script): default direct mode, no-LAN-IP fallback + warnings, explicit `BASE_URL` + extras, dedupe, Traefik + extra origin, loopback-only explicit `BASE_URL` + `PLANKA_HOST_IP` (user list respected, warning shown).
- [x] Generated compose files (direct + Traefik modes) linted with `yamllint` — only the two pre-existing findings present in the original script's output as well (missing `---` doc start, one blank line), no new findings.
- [ ] Manual end-to-end on evobox (see §5, items 2–3).

### 4.4 Out of scope (noted, not implemented)

- **UFW:** if ufw is active on the target host, port `1337` must also be allowed for LAN access (`ufw allow 1337/tcp`). On evobox the page already loads from the LAN, so this is not part of the bug. Could be added later via the existing `ufw_firewall_section` helper as an opt-in.
- **Traefik mode** already worked for socket origins (single domain) — no change required beyond 4.2's extra-origin append.
- Pinning `PLANKA_IMAGE` off `:latest` — separate concern.

## 5. Success criteria

1. `shellcheck` passes on the modified script.
2. Re-running on evobox generates `docker-compose.yml` with
   `BASE_URL=http://localhost:1337,http://192.168.178.57:1337` (auto, no user input).
3. From a second LAN device: `http://192.168.178.57:1337` loads, browser console shows **no** WebSocket errors, and a card move propagates live between two clients.
4. Explicit `BASE_URL=http://localhost:1337 ./setup-planka.sh` still works, but the script prints the localhost-only warning.
5. Idempotency: re-running the script with an existing stack still offers teardown/recreate and preserves `${PLANKA_HOME}/data`.
