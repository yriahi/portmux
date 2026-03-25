# Roadmap: Swiss Army Image

## Overview

Build a minimal multi-port HTTP stub Docker image in three phases: first make the Go binary work correctly locally (all six ports, catch-all routing, JSON responses, structured logging), then containerize and publish it as a multi-arch image with CI/CD automation, then add behavioral enhancements (delay injection, status code override) once the core is validated in production.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Core Server Binary** - Go binary binding all 6 ports with catch-all HTTP 200 JSON responses and structured stdout logging
- [ ] **Phase 2: Container and Distribution** - Multi-stage Dockerfile, multi-arch image, GitHub Actions CI/CD, and usage documentation
- [ ] **Phase 3: Behavioral Enhancements** - Delay injection and status code override via query parameters

## Phase Details

### Phase 1: Core Server Binary
**Goal**: A runnable Go binary that binds all 6 ports simultaneously, returns HTTP 200 JSON with request metadata on any path via any method, logs every request to stdout as structured JSON, and shuts down cleanly on SIGTERM
**Depends on**: Nothing (first phase)
**Requirements**: SRVR-01, SRVR-02, SRVR-03, RESP-01, RESP-02, RESP-03, LOG-01, LOG-02
**Success Criteria** (what must be TRUE):
  1. Running `go run .` binds all six ports (80, 8080, 8181, 8081, 3000, 5000) simultaneously and a `curl` to each returns HTTP 200
  2. Any path and any HTTP method on any port returns a JSON body containing port, method, path, ISO timestamp, and query parameters
  3. Every request produces a structured JSON log line on stdout with port, method, path, and timestamp
  4. Sending SIGTERM causes the process to exit cleanly within 5 seconds (in-flight requests drain, no hanging)
  5. Response includes `Content-Type: application/json` header on every request
**Plans:** 1 plan
Plans:
- [x] 01-01-PLAN.md — Implement Go server binary with multi-port binding, JSON responses, structured logging, SIGTERM shutdown, and integration tests

### Phase 2: Container and Distribution
**Goal**: A published multi-arch Docker image runnable with a single `docker run` command, built and pushed automatically by GitHub Actions on semver tags, with a docker-compose example and README usage instructions
**Depends on**: Phase 1
**Requirements**: CONT-01, CONT-02, CONT-03, DIST-01, DIST-02, DIST-03
**Success Criteria** (what must be TRUE):
  1. `docker run` with all six `-p` port flags starts the container and all six ports respond HTTP 200 JSON
  2. `docker buildx imagetools inspect` confirms both linux/amd64 and linux/arm64 manifests are present in the published image
  3. `docker stop` on a running container completes in under 2 seconds (exec-form ENTRYPOINT, clean SIGTERM handling)
  4. Pushing a semver tag triggers GitHub Actions, builds the multi-arch image, and publishes it tagged with both the semver version and `latest`
  5. Repository includes a `docker-compose.yml` showing the image wired into a service stack with all ports mapped
**Plans:** 2 plans
Plans:
- [ ] 02-01-PLAN.md — Create multi-stage Dockerfile and GitHub Actions CI/CD workflow for multi-arch image build and push to Nexus
- [ ] 02-02-PLAN.md — Create docker-compose.yml usage example and README.md documentation

### Phase 3: Behavioral Enhancements
**Goal**: Users can inject artificial latency and force specific HTTP status codes via query parameters to test timeout handling and error propagation through their scaffolding
**Depends on**: Phase 2
**Requirements**: ENH-01, ENH-02
**Success Criteria** (what must be TRUE):
  1. A request with `?delay=500` causes the response to arrive after at least 500 milliseconds
  2. A request with `?status=503` returns HTTP 503 instead of 200 (with the same JSON body)
  3. Requests without delay or status query params are unaffected and continue returning HTTP 200 immediately
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Core Server Binary | 0/1 | Planning complete | - |
| 2. Container and Distribution | 0/2 | Planning complete | - |
| 3. Behavioral Enhancements | 0/? | Not started | - |
