# Swiss Army Image

## What This Is

A lightweight Docker image that acts as a universal stub for testing containerized service scaffolding. It listens simultaneously on all common framework ports (80, 8080, 8181, 8081, 3000, 5000) and returns HTTP 200 with JSON request info on every path, regardless of method or URL. Designed to drop in wherever a real Node.js, React, Next.js, Java, or Spring Boot container would run.

## Core Value

Any containerized scaffolding can be validated end-to-end — networking, routing, proxies, load balancers, probes — without needing real application code running.

## Requirements

### Validated

- [x] Container listens simultaneously on ports 80, 8080, 8181, 8081, 3000, and 5000 — Validated in Phase 1: Core Server Binary
- [x] Any HTTP request on any path returns HTTP 200 — Validated in Phase 1: Core Server Binary
- [x] Response body is JSON containing: port, method, path, timestamp, and any query params — Validated in Phase 1: Core Server Binary
- [x] All requests are logged to stdout (port, method, path, timestamp) — Validated in Phase 1: Core Server Binary

### Active

- [ ] Works in docker run, docker-compose, Kubernetes, and AWS ECS contexts
- [ ] Dockerfile published and runnable with a single `docker run` command

### Out of Scope

- HTTPS/TLS — HTTP only; no cert management complexity needed
- Dedicated health/readiness endpoints — catch-all 200 is sufficient for probes
- Actual framework code (Node.js, Java, etc.) — the stub is framework-agnostic
- Request body parsing or persistence — stateless, no storage needed

## Current State

Phase 1 complete — Go binary delivers all server requirements (SRVR-01 through LOG-02). Binary compiles with CGO_ENABLED=0 using stdlib-only, ready for Phase 2 multi-stage Dockerfile with FROM scratch.

## Context

- Target deployment platforms: local Docker, docker-compose, Kubernetes (liveness/readiness probes), AWS ECS
- Target app types being scaffolded: Node.js, React (CRA/Vite), Next.js, Java, Spring Boot
- Common ports chosen to match default dev/prod ports for these frameworks
- Path /.magnolia/admincentral and all other deep/arbitrary paths must respond 200 — no 404s, no routing rules

## Constraints

- **HTTP only**: No TLS — simplifies deployment and certificate management
- **Multi-port**: Must bind all 6 ports in a single container process or via supervisor
- **Stateless**: No filesystem writes, no database, purely in-memory request handling
- **Portability**: Must run on linux/amd64 and linux/arm64 (Apple Silicon + CI/CD environments)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Single image, multiple ports | Matches real scaffolding patterns where one container owns its ports | — Pending |
| JSON response body with request metadata | Easier to debug which port/path was hit vs. empty 200 | — Pending |
| HTTP 200 for all paths | Removes routing complexity; the goal is scaffolding validation not app behavior | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-25 after Phase 1: Core Server Binary*
