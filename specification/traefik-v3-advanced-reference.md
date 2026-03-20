# Traefik v3 — Advanced Routing, Middleware & Production Hardening Reference

> Synthesized from official Traefik v3.6 documentation. All examples are v3-syntax.
> Configuration formats shown: YAML (file/structured), TOML, Docker Labels, Kubernetes CRD.

---

## Table of Contents

1. [Router Priority & Conflict Resolution](#1-router-priority--conflict-resolution)
2. [Middleware: Security Headers (HSTS, CSP, CORS, XSS, Frame Options)](#2-middleware-security-headers)
3. [Middleware: Rate Limiting — All Options](#3-middleware-rate-limiting)
4. [Middleware: Compress, Buffering, Retry, Circuit Breaker](#4-middleware-compress-buffering-retry-circuit-breaker)
5. [Middleware: Redirect (Scheme & Regex)](#5-middleware-redirects)
6. [Middleware: StripPrefix & AddPrefix](#6-middleware-stripprefix--addprefix)
7. [Global Middlewares Applied to All Routers](#7-global-middlewares)
8. [Error Pages — Custom Pages per Status Code](#8-error-pages)
9. [Access Logs — JSON Format & Filtering](#9-access-logs)
10. [Metrics — Prometheus Integration](#10-metrics--prometheus)
11. [Traefik Hub — What Is It?](#11-traefik-hub)
12. [Production Hardening Checklist](#12-production-hardening-checklist)
13. [Automation-Friendly Patterns — Environment Variable Substitution](#13-automation-friendly-patterns)

---

## 1. Router Priority & Conflict Resolution

### How Routing Works

An HTTP router connects incoming requests to backend services. Each router has a **rule** (match expression), optional **middlewares**, and a **service**. When multiple routers could match the same request, Traefik must resolve which router wins.

### Rule Matchers (v3 Syntax)

| Matcher | Example |
|---|---|
| `Host(`domain`)` | `Host(`example.com`)` |
| `HostRegexp(`regexp`)` | `HostRegexp(`^.+\.example\.com$`)` |
| `Path(`/path`)` | `Path(`/products`)` |
| `PathPrefix(`/prefix`)` | `PathPrefix(`/api`)` |
| `PathRegexp(`regexp`)` | `PathRegexp(`^/v[0-9]+/`)` |
| `Header(`key`, `value`)` | `Header(`X-Custom`, `foo`)` |
| `HeaderRegexp(`key`, `regexp`)` | `HeaderRegexp(`Content-Type`, `^application/(json\|yaml)$`)` |
| `Method(`verb`)` | `Method(`GET`)` |
| `Query(`key`, `value`)` | `Query(`mobile`, `true`)` |
| `QueryRegexp(`key`, `regexp`)` | `QueryRegexp(`mobile`, `^(true\|yes)$`)` |
| `ClientIP(`ip/cidr`)` | `ClientIP(`192.168.1.0/24`)` |

Combine with `&&` (AND), `||` (OR), `!` (NOT), and parentheses:

```
Host(`example.com`) && PathPrefix(`/api`) && !Method(`OPTIONS`)
```

### Default Priority: Rule Length

By default, Traefik sorts routers in **descending order by rule string length** — longer rules win. This means a very specific but short rule can be shadowed by a long catch-all regex.

```yaml
# Problem: Router-1 has priority 34, Router-2 has priority 26
# Router-1's regex rule is LONGER in characters, so it wins over the more specific Router-2
http:
  routers:
    Router-1:
      rule: "HostRegexp(`[a-z]+\\.traefik\\.com`)"   # priority = 34 (len of rule)
      service: service-1
    Router-2:
      rule: "Host(`foobar.traefik.com`)"              # priority = 26 (shorter!)
      service: service-2
```

**Result**: ALL requests including `foobar.traefik.com` are routed to `Router-1` — probably not what you want.

### Explicit Priority Override

Set `priority` explicitly to resolve conflicts. Higher number = higher priority. `0` means "use default length-based priority".

```yaml
## Dynamic configuration (traefik/dynamic/routers.yaml)
http:
  routers:
    Router-1:
      rule: "HostRegexp(`[a-z]+\\.traefik\\.com`)"
      entryPoints:
        - "web"
      service: service-1
      priority: 1          # Lower priority — regex catch-all
    Router-2:
      rule: "Host(`foobar.traefik.com`)"
      entryPoints:
        - "web"
      service: service-2
      priority: 2          # Higher priority — exact match wins
```

```toml
# Dynamic configuration (TOML)
[http.routers]
  [http.routers.Router-1]
    rule = "HostRegexp(`[a-z]+\\.traefik\\.com`)"
    entryPoints = ["web"]
    service = "service-1"
    priority = 1
  [http.routers.Router-2]
    rule = "Host(`foobar.traefik.com`)"
    entryPoints = ["web"]
    priority = 2
    service = "service-2"
```

```yaml
# Docker Compose labels
services:
  myapp:
    labels:
      - "traefik.http.routers.Router-1.rule=HostRegexp(`[a-z]+\\.traefik\\.com`)"
      - "traefik.http.routers.Router-1.priority=1"
      - "traefik.http.routers.Router-2.rule=Host(`foobar.traefik.com`)"
      - "traefik.http.routers.Router-2.priority=2"
```

### Priority Limits

- Maximum user-defined priority on 64-bit: `9223372036854774807` (`MaxInt64 - 1000`)
- Negative priorities are allowed
- `priority: 0` = use default length-based sorting

### Practical Priority Patterns

```yaml
http:
  routers:
    # Most specific — highest priority
    api-v2-specific:
      rule: "Host(`api.example.com`) && PathPrefix(`/v2/users`)"
      priority: 100
      service: users-v2

    # Less specific
    api-v2-catch:
      rule: "Host(`api.example.com`) && PathPrefix(`/v2`)"
      priority: 50
      service: api-v2

    # Regex wildcard — lowest priority
    subdomain-catch-all:
      rule: "HostRegexp(`^.+\\.example\\.com$`)"
      priority: 1
      service: default-backend
```

---

## 2. Middleware: Security Headers

The `headers` middleware manages request and response headers, including all security-relevant headers.

> **Note**: Custom headers overwrite existing headers with identical names.
> Security header behavior is powered by [unrolled/secure](https://github.com/unrolled/secure).

### Complete Security Headers Example

```yaml
## Dynamic configuration
http:
  middlewares:
    security-headers:
      headers:
        # ── HSTS (HTTP Strict Transport Security) ──────────────────────────
        stsSeconds: 31536000           # 1 year max-age
        stsIncludeSubdomains: true     # include subdomains
        stsPreload: true               # add preload flag
        forceSTSHeader: true           # also send STS over HTTP connections

        # ── X-Frame-Options ────────────────────────────────────────────────
        frameDeny: true                # sets X-Frame-Options: DENY
        # customFrameOptionsValue: "SAMEORIGIN"  # overrides frameDeny

        # ── Content Security Policy ────────────────────────────────────────
        contentSecurityPolicy: "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'"
        # contentSecurityPolicyReportOnly: "default-src 'self'"  # report-only mode

        # ── XSS Protection ─────────────────────────────────────────────────
        browserXssFilter: true         # X-XSS-Protection: 1; mode=block
        # customBrowserXSSValue: "1"   # custom XSS value (overrides browserXssFilter)

        # ── Content Type Sniffing ───────────────────────────────────────────
        contentTypeNosniff: true       # X-Content-Type-Options: nosniff

        # ── Referrer Policy ────────────────────────────────────────────────
        referrerPolicy: "strict-origin-when-cross-origin"

        # ── Permissions Policy ─────────────────────────────────────────────
        permissionsPolicy: "camera=(), microphone=(), geolocation=()"

        # ── Allowed Hosts ──────────────────────────────────────────────────
        allowedHosts:
          - "example.com"
          - "api.example.com"
        hostsProxyHeaders:
          - "X-Forwarded-Host"

        # ── SSL / HTTPS proxy ──────────────────────────────────────────────
        sslProxyHeaders:
          X-Forwarded-Proto: "https"

        # ── Custom Headers ─────────────────────────────────────────────────
        customRequestHeaders:
          X-Request-ID: ""             # strip if present (value = empty string)
          X-Real-IP: ""                # strip forwarded real IP from client
        customResponseHeaders:
          X-Powered-By: ""             # remove "X-Powered-By" from responses
          Server: ""                   # remove Server header
```

```toml
# TOML equivalent
[http.middlewares]
  [http.middlewares.security-headers.headers]
    stsSeconds = 31536000
    stsIncludeSubdomains = true
    stsPreload = true
    forceSTSHeader = true
    frameDeny = true
    contentSecurityPolicy = "default-src 'self'"
    browserXssFilter = true
    contentTypeNosniff = true
    referrerPolicy = "strict-origin-when-cross-origin"
    permissionsPolicy = "camera=(), microphone=()"
    [http.middlewares.security-headers.headers.sslProxyHeaders]
      X-Forwarded-Proto = "https"
    [http.middlewares.security-headers.headers.customResponseHeaders]
      X-Powered-By = ""
      Server = ""
```

### CORS Configuration

```yaml
http:
  middlewares:
    cors-policy:
      headers:
        accessControlAllowMethods:
          - GET
          - POST
          - PUT
          - DELETE
          - OPTIONS
        accessControlAllowHeaders:
          - "Authorization"
          - "Content-Type"
          - "X-Requested-With"
        accessControlAllowOriginList:
          - "https://app.example.com"
          - "https://admin.example.com"
        # OR use regex for dynamic origins:
        # accessControlAllowOriginListRegex:
        #   - "^https://.*\\.example\\.com$"
        accessControlExposeHeaders:
          - "X-Request-ID"
        accessControlMaxAge: 3600      # cache preflight for 1 hour
        accessControlAllowCredentials: true
        addVaryHeader: true            # add Vary: Origin header
```

> **Important**: When CORS headers are configured, Traefik handles preflight `OPTIONS` requests directly — they never reach your backend service.

### Docker Labels — Security Headers

```yaml
services:
  myapp:
    image: myapp:latest
    labels:
      - "traefik.http.middlewares.secure.headers.stsSeconds=31536000"
      - "traefik.http.middlewares.secure.headers.stsIncludeSubdomains=true"
      - "traefik.http.middlewares.secure.headers.stsPreload=true"
      - "traefik.http.middlewares.secure.headers.forceSTSHeader=true"
      - "traefik.http.middlewares.secure.headers.frameDeny=true"
      - "traefik.http.middlewares.secure.headers.contentTypeNosniff=true"
      - "traefik.http.middlewares.secure.headers.browserXssFilter=true"
      - "traefik.http.middlewares.secure.headers.referrerPolicy=strict-origin-when-cross-origin"
      - "traefik.http.middlewares.secure.headers.contentSecurityPolicy=default-src 'self'"
      - "traefik.http.middlewares.secure.headers.customResponseHeaders.X-Powered-By="
      - "traefik.http.middlewares.secure.headers.customResponseHeaders.Server="
      - "traefik.http.routers.myapp.middlewares=secure"
```

### Kubernetes CRD

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: security-headers
  namespace: default
spec:
  headers:
    stsSeconds: 31536000
    stsIncludeSubdomains: true
    stsPreload: true
    forceSTSHeader: true
    frameDeny: true
    contentTypeNosniff: true
    browserXssFilter: true
    contentSecurityPolicy: "default-src 'self'"
    referrerPolicy: "strict-origin-when-cross-origin"
    permissionsPolicy: "camera=(), microphone=()"
    customResponseHeaders:
      X-Powered-By: ""
      Server: ""
```

### All Security Header Options Reference

| Option | HTTP Header Set | Default |
|---|---|---|
| `stsSeconds` | `Strict-Transport-Security: max-age=N` | 0 |
| `stsIncludeSubdomains` | Appends `; includeSubDomains` | false |
| `stsPreload` | Appends `; preload` | false |
| `forceSTSHeader` | Send STS even over HTTP | false |
| `frameDeny` | `X-Frame-Options: DENY` | false |
| `customFrameOptionsValue` | `X-Frame-Options: <value>` (overrides `frameDeny`) | "" |
| `contentTypeNosniff` | `X-Content-Type-Options: nosniff` | false |
| `browserXssFilter` | `X-XSS-Protection: 1; mode=block` | false |
| `customBrowserXSSValue` | `X-XSS-Protection: <value>` (overrides `browserXssFilter`) | "" |
| `contentSecurityPolicy` | `Content-Security-Policy: <value>` | "" |
| `contentSecurityPolicyReportOnly` | `Content-Security-Policy-Report-Only: <value>` | "" |
| `referrerPolicy` | `Referrer-Policy: <value>` | "" |
| `permissionsPolicy` | `Permissions-Policy: <value>` | "" |
| `publicKey` | HPKP certificate pinning | "" |
| `isDevelopment` | Disables `AllowedHosts`, SSL, STS (for local dev) | false |

---

## 3. Middleware: Rate Limiting

The `rateLimit` middleware uses a **token bucket** algorithm. `average` ÷ `period` = refill rate; `burst` = bucket size.

### Basic Rate Limiting

```yaml
http:
  middlewares:
    # 100 req/s average, burst up to 200
    api-rate-limit:
      rateLimit:
        average: 100
        period: 1s
        burst: 200

    # Sub-1-req/s: 10 requests per minute
    slow-rate-limit:
      rateLimit:
        average: 10
        period: 1m
        burst: 5
```

```toml
[http.middlewares]
  [http.middlewares.api-rate-limit.rateLimit]
    average = 100
    period = "1s"
    burst = 200
```

```yaml
# Docker labels
labels:
  - "traefik.http.middlewares.api-rate-limit.ratelimit.average=100"
  - "traefik.http.middlewares.api-rate-limit.ratelimit.period=1s"
  - "traefik.http.middlewares.api-rate-limit.ratelimit.burst=200"
```

### Source Criterion — Who Gets Rate Limited?

By default, rate limiting is per-client-IP (remote address). Use `sourceCriterion` to change how sources are grouped:

```yaml
http:
  middlewares:
    # Rate limit per request host
    per-host-limit:
      rateLimit:
        average: 50
        burst: 10
        sourceCriterion:
          requestHost: true

    # Rate limit by a header value (e.g., API key)
    per-apikey-limit:
      rateLimit:
        average: 200
        burst: 50
        sourceCriterion:
          requestHeaderName: "X-API-Key"

    # Rate limit by real client IP through N-hop proxy
    per-real-ip-limit:
      rateLimit:
        average: 30
        burst: 5
        sourceCriterion:
          ipStrategy:
            depth: 2          # 2nd IP from the right in X-Forwarded-For
            # OR:
            # excludedIPs:    # skip these trusted proxy IPs to find real client
            #   - "10.0.0.1"
            #   - "10.0.0.2"
            ipv6Subnet: 64    # group IPv6 addresses by /64 subnet
```

#### IP Strategy: `depth` Explained

Given `X-Forwarded-For: 10.0.0.1, 11.0.0.1, 12.0.0.1, 13.0.0.1`:

| depth | Selected IP |
|---|---|
| 1 | `13.0.0.1` (rightmost) |
| 2 | `12.0.0.1` |
| 3 | `11.0.0.1` |
| 4 | `10.0.0.1` (real client) |
| 5+ | empty (depth exceeds list length) |

#### IP Strategy: `excludedIPs` Explained

`excludedIPs` scans `X-Forwarded-For` right-to-left, skipping the listed IPs, returning the first non-excluded one:

| X-Forwarded-For | excludedIPs | Result |
|---|---|---|
| `10.0.0.1, 11.0.0.1, 12.0.0.1` | `11.0.0.1, 12.0.0.1` | `10.0.0.1` (each client distinct) |
| `10.0.0.2, 11.0.0.1, 12.0.0.1` | `12.0.0.1` | `11.0.0.1` (multiple clients grouped) |

### Distributed Rate Limiting with Redis

For multi-instance Traefik deployments (e.g., swarm/K8s), use Redis to share rate-limit counters:

```yaml
http:
  middlewares:
    distributed-rate-limit:
      rateLimit:
        average: 100
        period: 1s
        burst: 200
        redis:
          # Multiple endpoints for HA / cluster
          endpoints:
            - "redis-primary.example.com:6379"
            - "redis-replica.example.com:6379"
          username: "ratelimit-user"
          password: "secure-password"   # use env var substitution in prod!
          db: 2

          # Connection pool tuning
          poolSize: 50          # base pool size (default: 10 per CPU core)
          minIdleConns: 10      # keep warm connections
          maxActiveConns: 200   # hard cap (0 = unlimited)

          # Timeouts
          readTimeout: 3s
          writeTimeout: 3s
          dialTimeout: 5s

          # TLS for Redis connection
          tls:
            ca: "/etc/ssl/redis-ca.crt"
            cert: "/etc/ssl/redis-client.crt"
            key: "/etc/ssl/redis-client.key"
            insecureSkipVerify: false
```

```toml
[http.middlewares]
  [http.middlewares.distributed-rate-limit.rateLimit]
    average = 100
    period = "1s"
    burst = 200
    [http.middlewares.distributed-rate-limit.rateLimit.redis]
      endpoints = ["redis-primary.example.com:6379", "redis-replica.example.com:6379"]
      username = "ratelimit-user"
      password = "secure-password"
      db = 2
      poolSize = 50
      minIdleConns = 10
      maxActiveConns = 200
      readTimeout = "3s"
      writeTimeout = "3s"
      dialTimeout = "5s"
      [http.middlewares.distributed-rate-limit.rateLimit.redis.tls]
        ca = "/etc/ssl/redis-ca.crt"
        cert = "/etc/ssl/redis-client.crt"
        key = "/etc/ssl/redis-client.key"
        insecureSkipVerify = false
```

```yaml
# Docker labels (distributed)
labels:
  - "traefik.http.middlewares.distributed-rate-limit.ratelimit.average=100"
  - "traefik.http.middlewares.distributed-rate-limit.ratelimit.burst=200"
  - "traefik.http.middlewares.distributed-rate-limit.ratelimit.redis.endpoints=redis-primary:6379,redis-replica:6379"
  - "traefik.http.middlewares.distributed-rate-limit.ratelimit.redis.password=secure-password"
  - "traefik.http.middlewares.distributed-rate-limit.ratelimit.redis.tls.insecureSkipVerify=false"
```

### Complete Rate Limit Options Reference

| Field | Description | Default |
|---|---|---|
| `average` | Requests allowed per `period`. `0` disables rate limiting | 0 |
| `period` | Time window for the rate calculation | `1s` |
| `burst` | Max requests allowed at one instant (bucket size) | 1 |
| `sourceCriterion.requestHost` | Rate limit by request Host header | false |
| `sourceCriterion.requestHeaderName` | Rate limit by value of this header | "" |
| `sourceCriterion.ipStrategy.depth` | Position in X-Forwarded-For (from right) | 0 |
| `sourceCriterion.ipStrategy.excludedIPs` | Skip these IPs when scanning X-Forwarded-For | — |
| `sourceCriterion.ipStrategy.ipv6Subnet` | Group IPv6 by subnet prefix length (0–128) | — |
| `redis.endpoints` | Redis server(s) for distributed limiting | `127.0.0.1:6379` |
| `redis.username` / `redis.password` | Redis auth | "" |
| `redis.db` | Redis database number | 0 |
| `redis.poolSize` | Base connection pool size | 10/CPU |
| `redis.minIdleConns` | Minimum idle connections | 0 |
| `redis.maxActiveConns` | Max total connections (0 = unlimited) | 0 |
| `redis.readTimeout` / `writeTimeout` / `dialTimeout` | Redis timeouts | 3s / 3s / 5s |
| `redis.tls.*` | TLS config for Redis connection | — |

---

## 4. Middleware: Compress, Buffering, Retry, Circuit Breaker

### 4.1 Compress

Supports **Gzip**, **Brotli**, and **Zstandard** compression. Compression is negotiated via `Accept-Encoding`.

```yaml
http:
  middlewares:
    # Minimal: enable all compression with defaults
    compress-all:
      compress: {}

    # Custom compression configuration
    compress-custom:
      compress:
        # Priority order: top = highest priority
        encodings:
          - zstd    # Zstandard (best ratio, fastest modern)
          - br      # Brotli
          - gzip    # Gzip (widest compatibility)

        # Default encoding when Accept-Encoding is absent or is "*"
        defaultEncoding: gzip

        # Don't compress responses smaller than 1KB (default)
        minResponseBodyBytes: 1024

        # Only compress these content types (mutually exclusive with excludedContentTypes)
        includedContentTypes:
          - "text/html"
          - "text/css"
          - "text/javascript"
          - "application/json"
          - "application/javascript"
          - "image/svg+xml"

        # OR: exclude specific content types (mutually exclusive with includedContentTypes)
        # excludedContentTypes:
        #   - "image/png"
        #   - "image/jpeg"
        #   - "video/mp4"
```

```toml
[http.middlewares]
  [http.middlewares.compress-custom.compress]
    encodings = ["zstd", "br", "gzip"]
    defaultEncoding = "gzip"
    minResponseBodyBytes = 1024
    includedContentTypes = ["text/html", "text/css", "application/json"]
```

```yaml
# Docker labels
labels:
  - "traefik.http.middlewares.compress.compress=true"
  # With options:
  - "traefik.http.middlewares.compress.compress.encodings=zstd,br,gzip"
  - "traefik.http.middlewares.compress.compress.minResponseBodyBytes=1024"
```

**Compression activation conditions** (all must be met):
- `Accept-Encoding` header contains `gzip`, `br`, `zstd`, or `*`
- Response is not already compressed (`Content-Encoding` not set)
- Response `Content-Type` is not excluded (or is included)
- Response body ≥ `minResponseBodyBytes` (default 1024)
- Note: `application/grpc` is **never** compressed

---

### 4.2 Buffering

Reads entire request/response into memory (or disk) before forwarding. Useful to protect services from slow clients and large uploads.

```yaml
http:
  middlewares:
    request-limit:
      buffering:
        # Reject requests larger than 2MB (returns 413)
        maxRequestBodyBytes: 2000000       # 2MB

        # Buffer requests to disk beyond 1MB in memory (default: 1MB)
        memRequestBodyBytes: 1048576       # 1MB

        # Reject responses larger than 10MB (returns 500 to client)
        maxResponseBodyBytes: 10000000     # 10MB

        # Buffer responses to disk beyond 1MB in memory
        memResponseBodyBytes: 1048576      # 1MB

        # Retry expression (replay request on condition)
        # Logical combination of: Attempts(), ResponseCode(), IsNetworkError()
        retryExpression: "IsNetworkError() && Attempts() < 2"
```

```toml
[http.middlewares]
  [http.middlewares.request-limit.buffering]
    maxRequestBodyBytes = 2000000
    memRequestBodyBytes = 1048576
    maxResponseBodyBytes = 10000000
    memResponseBodyBytes = 1048576
    retryExpression = "IsNetworkError() && Attempts() < 2"
```

```yaml
# Docker labels
labels:
  - "traefik.http.middlewares.limit.buffering.maxRequestBodyBytes=2000000"
  - "traefik.http.middlewares.limit.buffering.maxResponseBodyBytes=10000000"
  - "traefik.http.middlewares.limit.buffering.retryExpression=IsNetworkError() && Attempts() < 2"
```

**retryExpression functions**:
- `Attempts()` — current attempt number (starts at 1)
- `ResponseCode()` — HTTP response code from service
- `IsNetworkError()` — true if response code is a networking error

---

### 4.3 Retry

Retries requests to the backend when it doesn't respond. Stops retrying as soon as the server answers (regardless of status code).

```yaml
http:
  middlewares:
    # Retry up to 4 times with exponential backoff starting at 100ms
    retry-with-backoff:
      retry:
        attempts: 4           # required — total retry count (including first attempt)
        initialInterval: 100ms  # first wait; doubles each retry up to 2x initialInterval

    # Retry immediately (no backoff) — useful for instant failover
    retry-immediate:
      retry:
        attempts: 3
        # initialInterval not set = retry immediately
```

```toml
[http.middlewares]
  [http.middlewares.retry-with-backoff.retry]
    attempts = 4
    initialInterval = "100ms"
```

```yaml
# Docker labels
labels:
  - "traefik.http.middlewares.my-retry.retry.attempts=4"
  - "traefik.http.middlewares.my-retry.retry.initialinterval=100ms"
```

**Backoff schedule** with `initialInterval: 100ms`:
- Attempt 1: immediate (original)
- Attempt 2: wait ~100ms
- Attempt 3: wait ~200ms
- Attempt 4: wait ~200ms (max = 2× initialInterval)

---

### 4.4 Circuit Breaker

Prevents cascading failures by stopping requests to unhealthy services. Each router gets its **own independent** circuit breaker instance.

```yaml
http:
  middlewares:
    # Break on high error rate
    error-rate-breaker:
      circuitBreaker:
        expression: "ResponseCodeRatio(500, 600, 0, 600) > 0.30"
        checkPeriod: 100ms        # how often to evaluate expression
        fallbackDuration: 10s     # stay open for this long after tripping
        recoveryDuration: 10s     # gradual recovery window
        responseCode: 503         # HTTP status returned while open (default 503)

    # Break on network errors
    network-breaker:
      circuitBreaker:
        expression: "NetworkErrorRatio() > 0.10"

    # Break on high latency (p50 > 100ms)
    latency-breaker:
      circuitBreaker:
        expression: "LatencyAtQuantileMS(50.0) > 100"

    # Combined expression
    combined-breaker:
      circuitBreaker:
        expression: "ResponseCodeRatio(500, 600, 0, 600) > 0.30 || NetworkErrorRatio() > 0.10"
        fallbackDuration: 30s
        recoveryDuration: 15s
```

```toml
[http.middlewares]
  [http.middlewares.error-rate-breaker.circuitBreaker]
    expression = "ResponseCodeRatio(500, 600, 0, 600) > 0.30"
    checkPeriod = "100ms"
    fallbackDuration = "10s"
    recoveryDuration = "10s"
    responseCode = 503
```

```yaml
# Docker labels
labels:
  - "traefik.http.middlewares.cb.circuitbreaker.expression=NetworkErrorRatio() > 0.10"
  - "traefik.http.middlewares.cb.circuitbreaker.checkPeriod=100ms"
  - "traefik.http.middlewares.cb.circuitbreaker.fallbackDuration=30s"
  - "traefik.http.middlewares.cb.circuitbreaker.recoveryDuration=10s"
```

#### Expression Metrics Reference

| Metric | Signature | Example |
|---|---|---|
| Network error ratio | `NetworkErrorRatio()` | `NetworkErrorRatio() > 0.30` |
| HTTP status code ratio | `ResponseCodeRatio(from, to, divFrom, divTo)` | `ResponseCodeRatio(500, 600, 0, 600) > 0.25` |
| Latency at quantile | `LatencyAtQuantileMS(quantile)` | `LatencyAtQuantileMS(95.0) > 500` |

**`ResponseCodeRatio(from, to, divFrom, divTo)`**:
- Computes: `sum(from..to-1) / sum(divFrom..divTo-1)`
- `from` is inclusive, `to` is exclusive
- Returns 0 if divisor sum is 0

#### Circuit Breaker State Machine

```
           checkPeriod
CLOSED ──────────────────► evaluates expression
  │                            │ expression true
  │                            ▼
  │                         OPEN  ──► returns 503 for fallbackDuration
  │                            │
  │                            ▼
  │                        RECOVERING ──► sends linearly increasing traffic for recoveryDuration
  │◄───────────────────────────┘ (if service healthy during recovery)
  │                            │ (if service fails during recovery)
  └────────────────────────────► OPEN again
```

---

## 5. Middleware: Redirects

### 5.1 RedirectScheme (HTTP → HTTPS)

Redirects requests when the incoming scheme differs from the configured target scheme.

```yaml
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https          # target scheme
        permanent: true        # 301 redirect (false = 302)
        port: "443"            # optional — only if non-standard port needed
```

```toml
[http.middlewares]
  [http.middlewares.redirect-to-https.redirectScheme]
    scheme = "https"
    permanent = true
```

```yaml
# Docker labels
labels:
  - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
  - "traefik.http.middlewares.redirect-to-https.redirectscheme.permanent=true"
```

**Typical pattern** — separate HTTP and HTTPS routers:

```yaml
http:
  routers:
    # HTTP router — only redirects
    web-to-https:
      rule: "HostRegexp(`^.+$`)"
      entryPoints:
        - "web"            # port 80 entrypoint
      middlewares:
        - redirect-to-https
      service: noop@internal

    # HTTPS router — actual traffic
    websecure:
      rule: "Host(`example.com`)"
      entryPoints:
        - "websecure"      # port 443 entrypoint
      tls:
        certResolver: letsencrypt
      service: my-service
```

> **Behind another proxy**: The upstream reverse proxy must be listed as a **trusted** entrypoint for `X-Forwarded-*` headers to be used by RedirectScheme.

---

### 5.2 RedirectRegex

Redirect using regex capture groups. Good for URL migrations, domain changes, path rewriting.

```yaml
http:
  middlewares:
    # Domain migration
    old-to-new-domain:
      redirectRegex:
        regex: "^https?://old-domain\\.com/(.*)"
        replacement: "https://new-domain.com/${1}"
        permanent: true

    # Path migration with capture group
    legacy-api-redirect:
      redirectRegex:
        regex: "^https://api\\.example\\.com/v1/(.*)"
        replacement: "https://api.example.com/v2/${1}"
        permanent: false   # 302 for gradual migration

    # Remove trailing slash
    remove-trailing-slash:
      redirectRegex:
        regex: "^(https?://[^/]+/.*[^/])/$"
        replacement: "${1}"
        permanent: true
```

```toml
[http.middlewares]
  [http.middlewares.old-to-new-domain.redirectRegex]
    regex = "^https?://old-domain\\.com/(.*)"
    replacement = "https://new-domain.com/${1}"
    permanent = true
```

```yaml
# Docker labels — note: $$ doubles the dollar sign in Docker Compose
labels:
  - "traefik.http.middlewares.redirect.redirectregex.regex=^https?://old-domain\\.com/(.*)"
  - "traefik.http.middlewares.redirect.redirectregex.replacement=https://new-domain.com/$${1}"
  - "traefik.http.middlewares.redirect.redirectregex.permanent=true"
```

> **YAML escaping**: In YAML files, backslashes need doubling: `example\.com` → `example\\.com`
> **Docker label escaping**: Dollar signs need doubling: `${1}` → `$${1}`
> **Replacement syntax**: Use `${1}` not `$1x` (which equals `${1x}`)

---

## 6. Middleware: StripPrefix & AddPrefix

### 6.1 StripPrefix

Removes the matching path prefix before forwarding. Stores the stripped prefix in `X-Forwarded-Prefix` header.

**Use case**: Backend listens on `/` but is exposed at `/api/v1/`.

```yaml
http:
  middlewares:
    # Strip single prefix
    strip-api:
      stripPrefix:
        prefixes:
          - "/api"

    # Strip multiple possible prefixes
    strip-versioned:
      stripPrefix:
        prefixes:
          - "/api/v1"
          - "/api/v2"
          - "/legacy"
```

```toml
[http.middlewares]
  [http.middlewares.strip-api.stripPrefix]
    prefixes = ["/api"]

  [http.middlewares.strip-versioned.stripPrefix]
    prefixes = ["/api/v1", "/api/v2", "/legacy"]
```

```yaml
# Docker labels
labels:
  - "traefik.http.middlewares.strip-api.stripprefix.prefixes=/api"
  # Multiple prefixes comma-separated:
  - "traefik.http.middlewares.strip-versioned.stripprefix.prefixes=/api/v1,/api/v2"
```

```yaml
# Kubernetes CRD
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: strip-api
spec:
  stripPrefix:
    prefixes:
      - /api/v1
      - /api/v2
```

**Example flow**:
- Request: `GET /api/v1/users`
- After middleware: `GET /users` (sent to backend)
- Backend also receives: `X-Forwarded-Prefix: /api/v1`
- Backend can reconstruct full URLs using `X-Forwarded-Prefix`

**Full router + middleware pattern**:

```yaml
http:
  routers:
    my-api:
      rule: "Host(`example.com`) && PathPrefix(`/api/v1`)"
      middlewares:
        - strip-api-v1
      service: backend-service

  middlewares:
    strip-api-v1:
      stripPrefix:
        prefixes:
          - "/api/v1"

  services:
    backend-service:
      loadBalancer:
        servers:
          - url: "http://backend:8080"
```

---

### 6.2 AddPrefix

Prepends a path prefix before forwarding to the backend.

**Use case**: Route `/` at the proxy, but the backend serves from `/app`.

```yaml
http:
  middlewares:
    add-app-prefix:
      addPrefix:
        prefix: "/app"          # must start with /

    add-api-v2:
      addPrefix:
        prefix: "/api/v2"
```

```toml
[http.middlewares]
  [http.middlewares.add-app-prefix.addPrefix]
    prefix = "/app"
```

```yaml
# Docker labels
labels:
  - "traefik.http.middlewares.add-prefix.addprefix.prefix=/app"
```

```yaml
# Kubernetes CRD
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: add-app-prefix
spec:
  addPrefix:
    prefix: /app
```

**Example flow**:
- Request: `GET /dashboard`
- After middleware: `GET /app/dashboard` (sent to backend)

---

## 7. Global Middlewares

### Apply to All Routers via EntryPoint

The most production-appropriate pattern: attach middlewares at the **entrypoint** level so they apply to every router using that entrypoint.

```yaml
# traefik.yml (static/install configuration)
entryPoints:
  web:
    address: ":80"
    http:
      middlewares:
        - redirect-to-https@file   # "@file" = defined in file provider

  websecure:
    address: ":443"
    http:
      middlewares:
        - security-headers@file
        - compress@file
      tls:
        certResolver: letsencrypt
```

```toml
# traefik.toml (static configuration)
[entryPoints]
  [entryPoints.web]
    address = ":80"
    [entryPoints.web.http]
      middlewares = ["redirect-to-https@file"]

  [entryPoints.websecure]
    address = ":443"
    [entryPoints.websecure.http]
      middlewares = ["security-headers@file", "compress@file"]
    [entryPoints.websecure.http.tls]
      certResolver = "letsencrypt"
```

Then define the actual middlewares in your dynamic config (`/etc/traefik/dynamic/middlewares.yaml`):

```yaml
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https
        permanent: true

    security-headers:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        frameDeny: true
        contentTypeNosniff: true
        browserXssFilter: true
        contentSecurityPolicy: "default-src 'self'"
        referrerPolicy: "strict-origin-when-cross-origin"
        customResponseHeaders:
          Server: ""
          X-Powered-By: ""

    compress:
      compress:
        encodings:
          - zstd
          - br
          - gzip
```

### CLI Equivalent

```bash
# In traefik.yml or CLI arguments
--entrypoints.websecure.http.middlewares=security-headers@file,compress@file
```

### Middleware Provider Syntax

When referencing cross-provider middlewares, use the `@provider` suffix:

```
middlewareName@provider
```

| Provider | Suffix | Example |
|---|---|---|
| File | `@file` | `security-headers@file` |
| Docker | `@docker` | `my-mw@docker` |
| Kubernetes CRD | `@kubernetescrd` | `my-mw@kubernetescrd` |
| Internal | `@internal` | `noop@internal` |

### Middleware Chain Pattern

Use Docker Compose labels for service-level global patterns (not true global, but a reusable chain):

```yaml
services:
  traefik:
    image: traefik:v3
    command:
      - "--entrypoints.websecure.http.middlewares=global-security@file"
    # ...

  # Services inherit global middlewares automatically,
  # and can layer additional ones:
  myapp:
    labels:
      - "traefik.http.routers.myapp.middlewares=rate-limit@file"  # additional only
```

---

## 8. Error Pages

The `errors` middleware intercepts responses with configured status codes and replaces them with custom error pages served by a dedicated error service.

### Basic Setup

```yaml
## Dynamic configuration
http:
  middlewares:
    error-pages:
      errors:
        # Which status codes trigger custom error pages
        status:
          - "404"
          - "500"
          - "502"
          - "503"
          - "504"
          # Or ranges:
          # - "400-499"
          # - "500-599"

        # Service that serves the error pages
        service: error-page-service

        # URL path on the error service — {status} is replaced with HTTP code
        query: "/{status}.html"

  services:
    error-page-service:
      loadBalancer:
        servers:
          - url: "http://error-pages:80"
```

### Advanced: Status Rewrites & Variables

```yaml
http:
  middlewares:
    advanced-errors:
      errors:
        status:
          - "500"
          - "501"
          - "503"
          - "505-599"

        # Rewrite specific codes before serving the error page
        # (affects what {status} shows in the query, not the HTTP response code sent to client)
        statusRewrites:
          "418": 404            # Teapot → Not Found page
          "502-504": 500        # Gateway errors → generic 500 page

        service: error-handler-service

        # Available query variables:
        # {status}         — the (possibly rewritten) response status code
        # {originalStatus} — original status before any rewrite
        # {url}            — URL-escaped request URL
        query: "/errors/{status}?from={originalStatus}&url={url}"
```

```toml
[http.middlewares]
  [http.middlewares.advanced-errors.errors]
    status = ["500", "501", "503", "505-599"]
    service = "error-handler-service"
    query = "/{status}.html"
    [http.middlewares.advanced-errors.errors.statusRewrites]
      "418" = "404"
      "502-504" = "500"
```

```yaml
# Docker labels
labels:
  - "traefik.http.middlewares.errors.errors.status=404,500,502,503"
  - "traefik.http.middlewares.errors.errors.service=error-page-service"
  - "traefik.http.middlewares.errors.errors.query=/{status}.html"
  - "traefik.http.middlewares.errors.errors.statusRewrites.418=404"
```

```yaml
# Kubernetes CRD
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: error-pages
spec:
  errors:
    status:
      - "404"
      - "500-599"
    statusRewrites:
      "418": "404"
      "502-504": "500"
    query: /{status}.html
    service:
      name: error-handler-service
      port: 80
```

### Complete Docker Compose Pattern with Error Pages

```yaml
services:
  traefik:
    image: traefik:v3
    # ...

  # Your app
  myapp:
    image: myapp:latest
    labels:
      - "traefik.http.routers.myapp.rule=Host(`example.com`)"
      - "traefik.http.routers.myapp.middlewares=error-pages@file"

  # Dedicated error page service
  error-pages:
    image: nginx:alpine
    volumes:
      - ./error-pages:/usr/share/nginx/html:ro
    # Serves static files: /usr/share/nginx/html/404.html, 500.html, etc.
    labels:
      - "traefik.http.services.error-page-service.loadbalancer.server.port=80"
      # Don't expose this service directly
      - "traefik.http.routers.error-pages.rule=Host(`errors.internal`)"
```

> **Host header**: By default, the client's `Host` header is forwarded to the error service. To forward the error service's own host, set `passHostHeader: false` on the error service.

---

## 9. Access Logs

Access logs track every request handled by Traefik. Configured in the **static/install configuration** (`traefik.yml`).

### Enable JSON Access Logs with Filtering

```yaml
# traefik.yml (static configuration)
accessLog:
  # File path (omit for stdout)
  filePath: "/var/log/traefik/access.log"

  # Format: common (Traefik CLF), genericCLF (standard CLF), json
  format: json

  # Async buffering — number of log lines held in memory before writing
  bufferingSize: 100

  # Include logs for internal Traefik resources (ping, metrics, etc.)
  addInternals: false

  # Filtering — only log requests matching these criteria
  filters:
    # Only log these status code ranges
    statusCodes:
      - "400-499"       # all 4xx
      - "500-599"       # all 5xx
      # Remove to log all status codes

    # Log if at least one retry occurred
    retryAttempts: true

    # Log only slow requests (useful for performance debugging)
    minDuration: "100ms"

  # Field selection — control which fields appear in JSON output
  fields:
    defaultMode: keep    # keep, redact, or drop

    names:
      # Drop specific fields:
      ClientUsername: drop
      # Redact specific fields:
      # RequestAddr: redact

    headers:
      defaultMode: drop  # Headers are dropped by default — must opt-in

      names:
        # Selectively keep/redact specific headers:
        User-Agent: keep
        Authorization: drop     # never log auth tokens
        X-API-Key: redact       # log that it exists but not the value
        X-Request-ID: keep
        X-Forwarded-For: keep
```

```toml
# TOML equivalent
[accessLog]
  filePath = "/var/log/traefik/access.log"
  format = "json"
  bufferingSize = 100

  [accessLog.filters]
    statusCodes = ["400-499", "500-599"]
    retryAttempts = true
    minDuration = "100ms"

  [accessLog.fields]
    defaultMode = "keep"
    [accessLog.fields.names]
      ClientUsername = "drop"
    [accessLog.fields.headers]
      defaultMode = "drop"
      [accessLog.fields.headers.names]
        User-Agent = "keep"
        Authorization = "drop"
        X-Request-ID = "keep"
```

```bash
# CLI flags
--accesslog=true
--accesslog.format=json
--accesslog.filepath=/var/log/traefik/access.log
--accesslog.bufferingsize=100
--accesslog.filters.statuscodes=400-499,500-599
--accesslog.filters.retryattempts=true
--accesslog.filters.minduration=100ms
--accesslog.fields.defaultmode=keep
--accesslog.fields.names.ClientUsername=drop
--accesslog.fields.headers.defaultmode=drop
--accesslog.fields.headers.names.User-Agent=keep
--accesslog.fields.headers.names.Authorization=drop
```

### JSON Log Format Fields

All fields available in `json` format:

| Field | Description |
|---|---|
| `StartUTC` | Request start time (UTC) |
| `StartLocal` | Request start time (local TZ) |
| `Duration` | Total processing time (nanoseconds) |
| `RouterName` | Traefik router name |
| `ServiceName` | Backend service name |
| `ServiceURL` | Backend service URL |
| `ServiceAddr` | Backend IP:port |
| `ClientAddr` | Client remote address |
| `ClientHost` | Client IP |
| `ClientPort` | Client port |
| `ClientUsername` | URL username (if present) |
| `RequestAddr` | HTTP Host header |
| `RequestHost` | Host without port |
| `RequestPort` | Port from Host header |
| `RequestMethod` | HTTP method |
| `RequestPath` | URI path |
| `RequestProtocol` | HTTP version |
| `RequestScheme` | http or https |
| `RequestContentSize` | Request body bytes |
| `OriginDuration` | Backend response time (ns) |
| `OriginContentSize` | Backend response size |
| `OriginStatus` | Backend HTTP status code |
| `DownstreamStatus` | Status code sent to client |
| `DownstreamContentSize` | Response bytes sent to client |
| `RequestCount` | Total requests since start |
| `GzipRatio` | Compression ratio achieved |
| `Overhead` | Traefik processing overhead (ns) |
| `RetryAttempts` | Number of retries |
| `TLSVersion` | TLS version (e.g., `1.3`) |
| `TLSCipher` | TLS cipher suite |
| `TLSClientSubject` | mTLS client cert subject |

### Timezone Configuration

```yaml
# docker-compose.yml
services:
  traefik:
    image: traefik:v3
    environment:
      - TZ=Europe/Berlin
    command:
      - "--accesslog.fields.names.StartUTC=drop"   # use local time instead
      - "--accesslog.format=json"
```

### Log Rotation

Traefik reopens log files on `SIGUSR1` (Linux only):

```bash
kill -USR1 $(pidof traefik)
```

Or use `logrotate`:

```
/var/log/traefik/access.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    postrotate
        kill -USR1 $(cat /var/run/traefik.pid)
    endscript
}
```

Static log file rotation options:

```yaml
log:
  filePath: "/var/log/traefik/traefik.log"
  maxSize: 100        # MB before rotation
  maxAge: 30          # days to retain old files
  maxBackups: 5       # number of old files to keep
  compress: true      # gzip rotated files
```

### OpenTelemetry Access Logs (Experimental)

```yaml
# traefik.yml
experimental:
  otlpLogs: true

accesslog:
  otlp:
    http:
      endpoint: https://collector:4318/v1/logs
      headers:
        Authorization: "Bearer your-token"
```

---

## 10. Metrics — Prometheus

Prometheus metrics are exposed via Traefik's built-in metrics endpoint (default: `traefik` entrypoint, path `/metrics`).

### Enable Prometheus Metrics

```yaml
# traefik.yml (static configuration)
metrics:
  prometheus:
    # Custom histogram buckets (seconds)
    buckets:
      - 0.05    # 50ms
      - 0.1     # 100ms
      - 0.25    # 250ms
      - 0.5     # 500ms
      - 1.0     # 1s
      - 2.5     # 2.5s
      - 5.0     # 5s
      - 10.0    # 10s

    # Enable metrics labeled by entrypoint (default: true)
    addEntryPointsLabels: true

    # Enable metrics labeled by router (default: false — can be high cardinality)
    addRoutersLabels: true

    # Enable metrics labeled by service (default: true)
    addServicesLabels: true

    # Expose on a specific entrypoint (default: "traefik")
    entryPoint: traefik

    # Disable the auto-created /metrics router (for custom routing)
    manualRouting: false

    # Enable internal resource metrics (ping, etc.)
    addInternals: false

    # Extra labels extracted from request headers
    headerLabels:
      useragent: User-Agent
      host: X-Forwarded-Host    # Use X-Forwarded-Host instead of Host
```

```toml
[metrics]
  [metrics.prometheus]
    buckets = [0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
    addEntryPointsLabels = true
    addRoutersLabels = true
    addServicesLabels = true
    entryPoint = "traefik"
```

```bash
# CLI
--metrics.prometheus=true
--metrics.prometheus.addRoutersLabels=true
--metrics.prometheus.buckets=0.05,0.1,0.25,0.5,1.0,2.5,5.0,10.0
```

### Prometheus Metrics Reference

#### Global Metrics

| Metric | Type | Description |
|---|---|---|
| `traefik_config_reloads_total` | Counter | Total configuration reloads |
| `traefik_config_last_reload_success` | Gauge | Timestamp of last successful reload |
| `traefik_open_connections` | Gauge | Open connections by entrypoint+protocol |
| `traefik_tls_certs_not_after` | Gauge | TLS cert expiry timestamps |

#### EntryPoint Metrics

| Metric | Type | Labels |
|---|---|---|
| `traefik_entrypoint_requests_total` | Counter | `code, method, protocol, entrypoint` |
| `traefik_entrypoint_requests_tls_total` | Counter | `tls_version, tls_cipher, entrypoint` |
| `traefik_entrypoint_request_duration_seconds` | Histogram | `code, method, protocol, entrypoint` |
| `traefik_entrypoint_requests_bytes_total` | Counter | `code, method, protocol, entrypoint` |
| `traefik_entrypoint_responses_bytes_total` | Counter | `code, method, protocol, entrypoint` |

#### Router Metrics (when `addRoutersLabels: true`)

| Metric | Type | Labels |
|---|---|---|
| `traefik_router_requests_total` | Counter | `code, method, protocol, router, service` |
| `traefik_router_requests_tls_total` | Counter | `tls_version, tls_cipher, router, service` |
| `traefik_router_request_duration_seconds` | Histogram | `code, method, protocol, router, service` |

#### Service Metrics

| Metric | Type | Labels |
|---|---|---|
| `traefik_service_requests_total` | Counter | `code, method, protocol, service` |
| `traefik_service_request_duration_seconds` | Histogram | `code, method, protocol, service` |
| `traefik_service_retries_total` | Counter | `service` |
| `traefik_service_server_up` | Gauge | `service, url` |

### Expose Metrics on a Secure Separate Port

```yaml
# traefik.yml
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
  metrics-port:
    address: ":9100"    # internal-only metrics port

metrics:
  prometheus:
    entryPoint: metrics-port    # metrics only on port 9100
    addRoutersLabels: true
```

### Manual Routing for Custom /metrics Path

```yaml
# traefik.yml
metrics:
  prometheus:
    manualRouting: true    # disable auto-router

# dynamic/metrics-router.yaml
http:
  routers:
    custom-metrics:
      rule: "Host(`monitoring.internal`) && Path(`/metrics`)"
      entryPoints:
        - metrics-port
      service: prometheus@internal
      middlewares:
        - metrics-basic-auth

  middlewares:
    metrics-basic-auth:
      basicAuth:
        users:
          - "admin:$apr1$H6uskkkW$IgXLP6ewTrSuBkTrqE8wj/"
```

### Prometheus Scrape Config

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik:8080']   # traefik entrypoint
    metrics_path: /metrics
    scrape_interval: 15s

    # If using manualRouting on a different port:
    # static_configs:
    #   - targets: ['traefik:9100']
```

### Grafana Dashboards

Official dashboards from Grafana.com:
- **On-Premises**: Dashboard ID `17346`
- **Kubernetes**: Dashboard ID `17347`

### Header Labels Example

```yaml
# traefik.yml
metrics:
  prometheus:
    headerLabels:
      useragent: User-Agent

# This creates metrics like:
# traefik_entrypoint_requests_total{...,useragent="curl/7.68.0"} 1
# traefik_entrypoint_requests_total{...,useragent="Mozilla/5.0..."} 42
```

---

## 11. Traefik Hub

### What Is Traefik Hub?

**Traefik Hub** is the **commercial SaaS platform** built on top of Traefik OSS. It adds enterprise-grade features that extend — not replace — your existing Traefik configuration.

> ⚠️ "Traefik Pilot" was the predecessor, now discontinued and replaced by Traefik Hub.

### Core Capabilities

| Feature | Description |
|---|---|
| **API Gateway** | Full API management layer (rate limiting, auth, versioning, monetization) |
| **Secure Tunneling** | Expose local/on-prem services to the internet without port-forwarding |
| **API Portal** | Developer portal for API documentation and self-service access |
| **Access Control** | JWT validation, OAuth2, OIDC, API key management |
| **AI Gateway** | Route and manage traffic to LLM providers (OpenAI, Anthropic, etc.) |
| **Observability** | Centralized dashboard, alerts, SLA monitoring |

### How It Works

```
┌─────────────────────────────────────────┐
│  Your Infrastructure                    │
│                                         │
│  ┌────────────────┐    ┌─────────────┐  │
│  │  Traefik OSS   │◄──►│  Traefik    │  │
│  │  (unchanged)   │    │  Hub Agent  │  │
│  └────────────────┘    └──────┬──────┘  │
└─────────────────────────────┼──────────┘
                               │ HTTPS tunnel
                               ▼
                    ┌─────────────────────┐
                    │  Traefik Hub SaaS   │
                    │  (traefik.io/hub)   │
                    └─────────────────────┘
```

1. You run the Hub Agent alongside Traefik (or enable it in Traefik)
2. The agent connects outbound to Hub SaaS — no inbound firewall changes needed
3. Hub extends Traefik with additional CRDs (API, APIAccess, APIGateway, etc.)

### Enabling Hub (in Traefik static config)

```yaml
# traefik.yml
hub:
  token: "${TRAEFIK_HUB_TOKEN}"   # from hub.traefik.io
```

### Difference: OSS vs Hub

| Feature | Traefik OSS | Traefik Hub |
|---|---|---|
| Reverse proxy routing | ✅ | ✅ |
| TLS/Let's Encrypt | ✅ | ✅ |
| Basic middlewares | ✅ | ✅ |
| Rate limiting (in-memory) | ✅ | ✅ |
| Rate limiting (Redis distributed) | ✅ | ✅ |
| API key management | ❌ | ✅ |
| OAuth2/OIDC middleware | ❌ | ✅ |
| API portal/docs | ❌ | ✅ |
| AI Gateway | ❌ | ✅ |
| Secure tunneling | ❌ | ✅ |
| Centralized SaaS dashboard | ❌ | ✅ |
| Commercial support SLA | Optional | Included |

---

## 12. Production Hardening Checklist

### Docker Compose Hardened Traefik Template

```yaml
services:
  traefik:
    image: traefik:v3.6          # pin exact version
    container_name: traefik
    restart: unless-stopped

    security_opt:
      - no-new-privileges:true   # prevent privilege escalation

    read_only: true               # read-only root filesystem

    tmpfs:
      - /tmp                      # allow temp file writes

    cap_drop:
      - ALL                       # drop all Linux capabilities

    cap_add:
      - NET_BIND_SERVICE          # only if binding to ports < 1024 directly
                                  # (not needed if using Docker port mapping)

    user: "1000:1000"             # run as non-root user

    ports:
      - "80:80"
      - "443:443"
      # Do NOT expose 8080 (dashboard) publicly

    volumes:
      # Read-only Docker socket (use socket proxy instead — see below)
      - /var/run/docker.sock:/var/run/docker.sock:ro

      # Read-only config
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./dynamic:/etc/traefik/dynamic:ro

      # Writable only for certs — use named volume
      - traefik-certs:/etc/traefik/certs

    environment:
      # Pass secrets as environment variables, never hardcode
      - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
      - TRAEFIK_HUB_TOKEN=${TRAEFIK_HUB_TOKEN}

    networks:
      - traefik-public
    
    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s

volumes:
  traefik-certs:

networks:
  traefik-public:
    external: true
```

### Docker Socket Proxy Pattern (Recommended)

Instead of mounting the Docker socket directly into Traefik, use a socket proxy to limit what Traefik can read:

```yaml
services:
  # Privileged socket proxy — isolated
  docker-proxy:
    image: tecnativa/docker-socket-proxy:latest
    restart: unless-stopped
    environment:
      CONTAINERS: 1    # allow read container info
      SERVICES: 0
      SWARM: 0
      NETWORKS: 0
      TASKS: 0
      INFO: 0
      IMAGES: 0
      VOLUMES: 0
      BUILD: 0
      COMMIT: 0
      CONFIGS: 0
      DISTRIBUTION: 0
      EXEC: 0
      GRPC: 0
      NODES: 0
      PLUGINS: 0
      POST: 0          # critical: deny all POST (write) operations
      SECRETS: 0
      SESSION: 0
      SYSTEM: 0
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - docker-proxy-net
    security_opt:
      - no-new-privileges:true

  traefik:
    image: traefik:v3
    # NO Docker socket volume mount!
    environment:
      - DOCKER_HOST=tcp://docker-proxy:2375  # use proxy instead
    networks:
      - traefik-public
      - docker-proxy-net
    # ... rest of config
```

```yaml
# traefik.yml — use socket proxy endpoint
providers:
  docker:
    endpoint: "tcp://docker-proxy:2375"
    exposedByDefault: false    # require explicit opt-in per container
    network: traefik-public
```

### Static Configuration Hardening (`traefik.yml`)

```yaml
# traefik.yml
global:
  checkNewVersion: false        # disable version check (outbound request)
  sendAnonymousUsage: false     # disable telemetry

api:
  dashboard: true
  # insecure: false             # NEVER enable insecure dashboard in prod
  # dashboard is protected by router + auth middleware below

ping:
  entryPoint: ping-internal     # dedicated internal-only entrypoint

entryPoints:
  ping-internal:
    address: "127.0.0.1:8081"   # bind to loopback only (not exposed)

  web:
    address: ":80"
    http:
      middlewares:
        - redirect-to-https@file
    # Limit incoming connections
    transport:
      respondingTimeouts:
        readTimeout: 60s
        writeTimeout: 60s
        idleTimeout: 180s

  websecure:
    address: ":443"
    http:
      middlewares:
        - security-headers@file
        - compress@file
      tls:
        options: modern-tls      # references TLS options below
        certResolver: letsencrypt
    forwardedHeaders:
      trustedIPs:
        - "172.16.0.0/12"        # trust Docker network
        - "10.0.0.0/8"
        - "192.168.0.0/16"

tls:
  options:
    modern-tls:
      minVersion: VersionTLS12
      maxVersion: VersionTLS13
      cipherSuites:
        - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
        - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
      sniStrict: true            # reject connections without SNI

providers:
  docker:
    exposedByDefault: false      # NEVER auto-expose all containers
    network: traefik-public
  file:
    directory: /etc/traefik/dynamic
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: "admin@example.com"
      storage: "/etc/traefik/certs/acme.json"
      # Use DNS challenge for wildcard certs (recommended):
      dnsChallenge:
        provider: cloudflare
        resolvers:
          - "1.1.1.1:53"
          - "8.8.8.8:53"
      # Or HTTP challenge for simple single-domain:
      # httpChallenge:
      #   entryPoint: web

log:
  level: WARN           # reduce log noise in prod
  format: json

accessLog:
  format: json
  bufferingSize: 100
  filters:
    statusCodes:
      - "400-599"       # only log errors in prod

metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true
    addRoutersLabels: false     # careful: high cardinality
```

### Dashboard Security (Dynamic Config)

```yaml
# dynamic/dashboard.yaml
http:
  routers:
    dashboard:
      rule: "Host(`traefik.internal.example.com`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))"
      entryPoints:
        - websecure
      service: api@internal
      middlewares:
        - dashboard-auth
        - whitelist-internal
      tls: {}

  middlewares:
    dashboard-auth:
      basicAuth:
        users:
          - "admin:$apr1$H6uskkkW$IgXLP6ewTrSuBkTrqE8wj/"
          # Generate with: echo $(htpasswd -nb admin yourpassword)

    whitelist-internal:
      ipAllowList:
        sourceRange:
          - "10.0.0.0/8"
          - "172.16.0.0/12"
          - "192.168.0.0/16"
```

### Production Hardening Checklist Summary

```
Security
────────
[ ] Pin exact Traefik image version (traefik:v3.6, not traefik:latest)
[ ] no-new-privileges:true in security_opt
[ ] Drop ALL capabilities; only add NET_BIND_SERVICE if needed
[ ] Run as non-root user (user: "1000:1000")
[ ] Read-only root filesystem (read_only: true) + tmpfs for /tmp
[ ] Docker socket mounted :ro, or use socket proxy (recommended)
[ ] exposedByDefault: false in docker provider
[ ] Dashboard NOT on public entrypoint; secured with auth + IP whitelist
[ ] Disable insecure API (api.insecure never true in prod)
[ ] TLS 1.2+ only; disable weak cipher suites; enable sniStrict
[ ] Enforce HTTPS redirect on port 80 entrypoint
[ ] forwardedHeaders.trustedIPs set to known upstream proxy ranges only
[ ] Secrets via environment variables, never hardcoded in config

Observability
─────────────
[ ] accessLog enabled in JSON format
[ ] Prometheus metrics enabled
[ ] Log level WARN or ERROR in production
[ ] TLS cert expiry tracked via traefik_tls_certs_not_after metric
[ ] Alert on traefik_service_server_up = 0

Reliability
───────────
[ ] restart: unless-stopped
[ ] healthcheck configured (traefik healthcheck --ping)
[ ] Rate limiting on public-facing routes
[ ] Circuit breaker on critical upstream services
[ ] Retry middleware with exponential backoff
[ ] Global error pages middleware
[ ] Request size limits via buffering middleware

Operations
──────────
[ ] sendAnonymousUsage: false
[ ] checkNewVersion: false
[ ] Log rotation configured (logrotate + SIGUSR1, or maxSize/maxAge/maxBackups)
[ ] cert storage on named Docker volume (persists across restarts)
[ ] Dynamic config in file provider with watch: true (hot-reload)
[ ] Separate traefik-public network; services only join this network explicitly
```

---

## 13. Automation-Friendly Patterns

### Environment Variable Substitution in Config Files

Traefik's **static configuration** (`traefik.yml`) does **not** natively support `${VAR}` substitution. However, you can use several patterns:

#### Pattern 1: Docker Compose `env_file` + Inline Expansion

Docker Compose does variable interpolation in `command:` and `labels:` but **not** in mounted config files:

```yaml
# .env file
CF_DNS_API_TOKEN=abc123
ACME_EMAIL=ops@example.com
TRAEFIK_LOG_LEVEL=WARN

# docker-compose.yml
services:
  traefik:
    env_file: .env
    environment:
      # These reach Traefik as actual env vars — usable by CLI args
      - CF_DNS_API_TOKEN
      - ACME_EMAIL
    command:
      # CLI args DO support direct shell expansion in compose
      - "--certificatesresolvers.le.acme.email=${ACME_EMAIL}"
      - "--log.level=${TRAEFIK_LOG_LEVEL}"
      - "--certificatesresolvers.le.acme.dnschallenge.provider=cloudflare"
```

#### Pattern 2: envsubst — Template File to Final Config

```bash
# traefik.yml.tmpl — use ${VAR} syntax
log:
  level: ${TRAEFIK_LOG_LEVEL:-WARN}
  format: json

certificatesResolvers:
  letsencrypt:
    acme:
      email: "${ACME_EMAIL}"
      storage: "/etc/traefik/certs/acme.json"
      dnsChallenge:
        provider: cloudflare
```

```bash
# deploy.sh
export TRAEFIK_LOG_LEVEL=WARN
export ACME_EMAIL=ops@example.com

# Generate final config from template
envsubst < traefik.yml.tmpl > /etc/traefik/traefik.yml

# Validate before applying
docker run --rm -v /etc/traefik:/etc/traefik traefik:v3 \
  --configfile=/etc/traefik/traefik.yml \
  --log.level=DEBUG 2>&1 | grep -i "error\|warn"
```

#### Pattern 3: Environment Variables in CLI Arguments (Recommended for Secrets)

Traefik CLI arguments support environment variable expansion by some providers. Sensitive values (API tokens, passwords) should **always** come from environment variables:

```yaml
# docker-compose.yml
services:
  traefik:
    image: traefik:v3
    environment:
      # These are used by Traefik's DNS challenge providers directly
      - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
      - CF_ZONE_API_TOKEN=${CF_ZONE_API_TOKEN}
      # Or AWS:
      # - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      # - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      # Redis password for rate limiting
      - REDIS_PASSWORD=${REDIS_PASSWORD}
```

#### Pattern 4: Docker Secrets (Swarm Mode)

```yaml
# docker-compose.yml (swarm)
services:
  traefik:
    image: traefik:v3
    secrets:
      - cf_api_token
      - redis_password
    environment:
      # Some providers read from file path
      CF_DNS_API_TOKEN_FILE: /run/secrets/cf_api_token

secrets:
  cf_api_token:
    external: true
  redis_password:
    external: true
```

#### Pattern 5: Dynamic Config via File Provider (Hot Reload)

Unlike static config, **dynamic config supports live updates** without restart:

```yaml
# traefik.yml
providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true    # hot reload on file changes
```

```bash
# Update middleware config — takes effect immediately, no restart
cat > /etc/traefik/dynamic/middlewares.yaml << EOF
http:
  middlewares:
    rate-limit:
      rateLimit:
        average: ${NEW_RATE_LIMIT:-100}
        burst: ${NEW_BURST:-200}
EOF
```

### Ansible / IaC Pattern

```yaml
# ansible task
- name: Render Traefik static config
  template:
    src: traefik.yml.j2
    dest: /etc/traefik/traefik.yml
    owner: root
    group: root
    mode: '0644'
  notify: reload traefik

- name: Render dynamic middlewares config
  template:
    src: middlewares.yml.j2
    dest: /etc/traefik/dynamic/middlewares.yaml
    mode: '0644'
  # No restart needed — file provider watches for changes

# traefik.yml.j2 (Jinja2)
log:
  level: {{ traefik_log_level | default('WARN') }}

certificatesResolvers:
  letsencrypt:
    acme:
      email: "{{ acme_email }}"
      storage: "/etc/traefik/certs/acme.json"
```

### Complete Reference: Config Format Priority

Traefik resolves install configuration in this order (later overrides earlier):

```
1. traefik.yml / traefik.yaml / traefik.toml   (file)
2. CLI arguments                                (--flag=value)
3. Environment variables                        (TRAEFIK_LOG_LEVEL=DEBUG)
```

Environment variable naming convention: `TRAEFIK_` prefix + uppercase option path with `_` separating levels:

| CLI Flag | Environment Variable |
|---|---|
| `--log.level=DEBUG` | `TRAEFIK_LOG_LEVEL=DEBUG` |
| `--api.dashboard=true` | `TRAEFIK_API_DASHBOARD=true` |
| `--providers.docker.exposedbydefault=false` | `TRAEFIK_PROVIDERS_DOCKER_EXPOSEDBYDEFAULT=false` |
| `--entrypoints.web.address=:80` | `TRAEFIK_ENTRYPOINTS_WEB_ADDRESS=:80` |
| `--metrics.prometheus=true` | `TRAEFIK_METRICS_PROMETHEUS=true` |
| `--accesslog=true` | `TRAEFIK_ACCESSLOG=true` |
| `--accesslog.format=json` | `TRAEFIK_ACCESSLOG_FORMAT=json` |
| `--certificatesresolvers.le.acme.email=x` | `TRAEFIK_CERTIFICATESRESOLVERS_LE_ACME_EMAIL=x` |

### Full-Stack Example: docker-compose.yml

```yaml
# Complete production-ready Traefik v3 setup
version: "3.8"

services:
  docker-proxy:
    image: tecnativa/docker-socket-proxy:latest
    restart: unless-stopped
    environment:
      CONTAINERS: 1
      POST: 0
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - docker-proxy

  traefik:
    image: traefik:v3.6
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    user: "0:0"   # root needed for port 80/443 in this config; use non-root with CAP_NET_BIND_SERVICE or high ports + iptables REDIRECT
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./dynamic:/etc/traefik/dynamic:ro
      - traefik-certs:/etc/traefik/certs
    environment:
      - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
      - TRAEFIK_LOG_LEVEL=${TRAEFIK_LOG_LEVEL:-WARN}
    networks:
      - traefik-public
      - docker-proxy
    depends_on:
      - docker-proxy
    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 30s
      timeout: 5s
      retries: 3

volumes:
  traefik-certs:

networks:
  traefik-public:
    external: true
  docker-proxy:
    internal: true   # no external access to proxy network
```

---

## Quick Reference Card

### Middleware Syntax Summary

```yaml
# File provider dynamic config — all middlewares in one file
http:
  middlewares:
    # HTTPS redirect
    https-redirect:
      redirectScheme:
        scheme: https
        permanent: true

    # Security headers (production)
    secure-headers:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        frameDeny: true
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: "strict-origin-when-cross-origin"
        customResponseHeaders:
          Server: ""
          X-Powered-By: ""

    # Rate limiting
    rate-limit:
      rateLimit:
        average: 100
        burst: 200
        period: 1s

    # Compression
    compress:
      compress:
        encodings: [zstd, br, gzip]

    # Retry
    retry:
      retry:
        attempts: 3
        initialInterval: 100ms

    # Circuit breaker
    circuit-breaker:
      circuitBreaker:
        expression: "ResponseCodeRatio(500, 600, 0, 600) > 0.25 || LatencyAtQuantileMS(99.0) > 5000"
        fallbackDuration: 30s
        recoveryDuration: 10s

    # Error pages
    error-pages:
      errors:
        status: ["400-599"]
        service: error-page-service
        query: "/{status}.html"

    # Strip prefix
    strip-api:
      stripPrefix:
        prefixes: ["/api/v1"]

    # Add prefix
    add-prefix:
      addPrefix:
        prefix: "/app"

    # Buffering / request size limit
    body-limit:
      buffering:
        maxRequestBodyBytes: 10000000   # 10MB
```

### Attach Middlewares to a Router

```yaml
# File provider
http:
  routers:
    my-service:
      rule: "Host(`app.example.com`)"
      entryPoints: [websecure]
      middlewares:
        - secure-headers
        - rate-limit
        - compress
      service: my-service-backend
      tls: {}
```

```yaml
# Docker labels
labels:
  - "traefik.http.routers.myapp.rule=Host(`app.example.com`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.middlewares=secure-headers@file,rate-limit@file,compress@file"
  - "traefik.http.routers.myapp.tls=true"
  - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
  - "traefik.http.services.myapp.loadbalancer.server.port=8080"
```
