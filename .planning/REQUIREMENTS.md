# Requirements: Swiss Army Image

**Defined:** 2026-03-25
**Core Value:** Any containerized scaffolding can be validated end-to-end — networking, routing, proxies, load balancers, probes — without needing real application code running.

## v1 Requirements

### Server

- [x] **SRVR-01**: Container binds ports 80, 8080, 8181, 8081, 3000, and 5000 simultaneously in a single running instance
- [x] **SRVR-02**: Any HTTP request on any path and any method returns a response — no 404s, no routing errors, no path restrictions
- [x] **SRVR-03**: Container exits cleanly on SIGTERM with graceful shutdown (drains in-flight requests, exits within 5 seconds)

### Response

- [x] **RESP-01**: All HTTP responses return status code 200 by default
- [x] **RESP-02**: Response body is JSON containing: port number, HTTP method, request path, ISO timestamp, and query parameters
- [x] **RESP-03**: Response includes `Content-Type: application/json` header on every request

### Logging

- [x] **LOG-01**: Each incoming request is logged to stdout with port, method, path, and timestamp
- [x] **LOG-02**: Log output is structured JSON (machine-parseable for CloudWatch, Datadog, etc.)

### Container

- [x] **CONT-01**: Dockerfile uses multi-stage build — Go binary compiled with CGO_ENABLED=0, final stage is FROM scratch (~5-8 MB image)
- [x] **CONT-02**: Image is built and published for both linux/amd64 and linux/arm64 architectures
- [x] **CONT-03**: README includes a `docker run` command that maps all 6 ports in a single invocation

### Distribution

- [x] **DIST-01**: GitHub Actions workflow builds and pushes the image to a registry on push to main and on semver tags
- [x] **DIST-02**: Published image is tagged with semver (e.g., v1.0.0) and a mutable `latest` alias
- [x] **DIST-03**: Repository includes a `docker-compose.yml` example showing the image wired into a typical service stack

### Enhancements

- [x] **ENH-01**: Request with `?delay=<ms>` query parameter waits the specified number of milliseconds before responding (latency injection)
- [x] **ENH-02**: Request with `?status=<code>` query parameter returns the specified HTTP status code instead of 200 (error simulation)

## v2 Requirements

### Observability

- **OBS-01**: Prometheus-compatible `/metrics` endpoint exposing request counts per port
- **OBS-02**: Optional request body echo in response JSON (configurable via env var)

### Security

- **SEC-01**: `runAsNonRoot` compatible image variant (distroless/static-debian12:nonroot base)

## Out of Scope

| Feature | Reason |
|---------|--------|
| HTTPS/TLS | Belongs at the ingress/load balancer layer; adds cert complexity with no stub value |
| Dedicated /health endpoint | Catch-all 200 on any path is sufficient for Kubernetes/ECS probes |
| Request body storage or persistence | Stateless by design; no database, no filesystem writes |
| Scriptable response rules | That is WireMock's job; out of scope prevents feature creep |
| Default CORS headers | Not needed for scaffolding validation; can be added at ingress |
| Web UI or dashboard | CLI/logs are the interface |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SRVR-01 | Phase 1 | Complete |
| SRVR-02 | Phase 1 | Complete |
| SRVR-03 | Phase 1 | Complete |
| RESP-01 | Phase 1 | Complete |
| RESP-02 | Phase 1 | Complete |
| RESP-03 | Phase 1 | Complete |
| LOG-01 | Phase 1 | Complete |
| LOG-02 | Phase 1 | Complete |
| CONT-01 | Phase 2 | Complete |
| CONT-02 | Phase 2 | Complete |
| CONT-03 | Phase 2 | Complete |
| DIST-01 | Phase 2 | Complete |
| DIST-02 | Phase 2 | Complete |
| DIST-03 | Phase 2 | Complete |
| ENH-01 | Phase 3 | Complete |
| ENH-02 | Phase 3 | Complete |

**Coverage:**
- v1 requirements: 16 total
- Mapped to phases: 16
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-25*
*Last updated: 2026-03-25 after roadmap creation*
