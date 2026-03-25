# Swiss Army Image

## What This Is

A lightweight Docker image that acts as a universal stub for testing containerized service scaffolding. It listens simultaneously on all common framework ports (80, 8080, 8181, 8081, 3000, 5000, 8000, 8888, 3306, 5432, 6379, 9090) and returns HTTP 200 with JSON request info on every path, regardless of method or URL. Designed to drop in wherever a real Node.js, React, Next.js, Java, Spring Boot, or database-backed container would run.

## Core Value

Any containerized scaffolding can be validated end-to-end — networking, routing, proxies, load balancers, probes — without needing real application code running.

## Requirements

### Validated

- ✓ Container listens simultaneously on all 12 ports — v1.0
- ✓ Any HTTP request on any path returns HTTP 200 — v1.0
- ✓ Response body is JSON containing: port, method, path, timestamp, and query params — v1.0
- ✓ All requests logged to stdout (port, method, path, timestamp, status) — v1.0
- ✓ SIGTERM triggers graceful shutdown within 5 seconds — v1.0
- ✓ Response includes Content-Type: application/json header — v1.0
- ✓ Delay injection via `?delay=<ms>` query param (clamped to 30s, invalid ignored) — v1.0
- ✓ Status code override via `?status=<code>` query param (100-999 range, invalid ignored) — v1.0
- ✓ Multi-stage Dockerfile: CGO_ENABLED=0 static binary, FROM scratch final (~5 MB) — v1.0
- ✓ Multi-arch image: linux/amd64 + linux/arm64 — v1.0
- ✓ GitHub Actions CI/CD: builds and pushes on main push and semver tags — v1.0
- ✓ docker-compose.yml example with all ports mapped — v1.0
- ✓ README with docker run command and usage documentation — v1.0

### Active

- [ ] Works end-to-end in AWS ECS and Kubernetes (liveness/readiness probes verified)
- [ ] Prometheus-compatible `/metrics` endpoint exposing request counts per port
- [ ] Optional request body echo in response JSON (configurable via env var)
- [ ] `runAsNonRoot` compatible image variant (distroless/static-debian12:nonroot base)

### Out of Scope

- HTTPS/TLS — HTTP only; no cert management complexity needed
- Dedicated health/readiness endpoints — catch-all 200 is sufficient for probes
- Actual framework code (Node.js, Java, etc.) — the stub is framework-agnostic
- Request body parsing or persistence — stateless, no storage needed
- Scriptable response rules — that is WireMock's job

## Current State

v1.0 shipped 2026-03-25. Go binary (161 LOC) binds 12 ports simultaneously, returns JSON request metadata on every path, logs structured JSON to stdout, supports delay injection and status code override. Published as multi-arch Docker image (~5 MB) to Nexus via GitHub Actions. 40 integration tests passing.

## Context

- Target deployment platforms: local Docker, docker-compose, Kubernetes (liveness/readiness probes), AWS ECS
- Target app types being scaffolded: Node.js, React (CRA/Vite), Next.js, Java, Spring Boot, databases (MySQL, Postgres, Redis), monitoring (Prometheus)
- Common ports chosen to match default dev/prod ports for these frameworks and services
- Path /.magnolia/admincentral and all other deep/arbitrary paths must respond 200 — no 404s, no routing rules

## Constraints

- **HTTP only**: No TLS — simplifies deployment and certificate management
- **Multi-port**: Must bind all ports in a single container process
- **Stateless**: No filesystem writes, no database, purely in-memory request handling
- **Portability**: Must run on linux/amd64 and linux/arm64 (Apple Silicon + CI/CD environments)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Single image, multiple ports | Matches real scaffolding patterns where one container owns its ports | ✓ Good — goroutine-per-port trivial in Go |
| JSON response body with request metadata | Easier to debug which port/path was hit vs. empty 200 | ✓ Good — validated in testing |
| HTTP 200 for all paths by default | Removes routing complexity; goal is scaffolding validation not app behavior | ✓ Good — catches all probe patterns |
| Go static binary on FROM scratch | ~5 MB image, no OS overhead, no runtime deps | ✓ Good — CGO_ENABLED=0 compiles clean |
| goroutine-per-port with net.Listen pre-flight | Accurate startup banner, non-fatal port bind failures | ✓ Good — port 80 non-fatal per D-04 |
| exec-form ENTRYPOINT | Only valid form for FROM scratch; shell-form fails without /bin/sh | ✓ Good — mandatory for scratch |
| Inline parse-and-validate for query params | ~10 lines each, no abstraction needed at current scale | ✓ Good — readable without helper |
| delay clamped to 30s, invalid silently ignored | Prevents abuse/hangs, clean UX for typos | ✓ Good — 30s sufficient for timeout testing |

---
*Last updated: 2026-03-25 after v1.0 milestone*
