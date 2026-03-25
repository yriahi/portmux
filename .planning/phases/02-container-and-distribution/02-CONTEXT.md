# Phase 2: Container and Distribution - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

A published multi-arch Docker image (`linux/amd64` + `linux/arm64`) runnable with a single `docker run` command, pushed automatically to an internal Nexus registry by GitHub Actions on push to `main` and on semver tags, with a `docker-compose.yml` example and README usage documentation. No behavioral changes to the Go binary — that is Phase 3.

</domain>

<decisions>
## Implementation Decisions

### Registry (DIST-01, DIST-02)
- **D-01:** Registry: `nexus.cainc.com:5000` — private internal Nexus registry (not GHCR or Docker Hub)
- **D-02:** Image path: `nexus.cainc.com:5000/cainc/yriahi/swiss-army-image`
- **D-03:** CI authenticates via `NEXUS_USERNAME` and `NEXUS_PASSWORD` GitHub Actions secrets using `docker login`
- **D-04:** Tags: semver pushes produce `:v1.0.0` + `:latest`; push to `main` produces `:main`

### CI/CD Triggers (DIST-01)
- **D-05:** GitHub Actions builds and pushes on **both** push to `main` branch (`:main` tag) AND semver tags (`:v1.0.0` + `:latest`)
- **D-06:** Pull requests against `main` run the build step only — no push to Nexus

### docker-compose Example (DIST-03)
- **D-07:** Single-service topology — just the stub with all 6 ports mapped; no assumption about what is being scaffolded

Example shape:
```yaml
services:
  stub:
    image: nexus.cainc.com:5000/cainc/yriahi/swiss-army-image:latest
    ports:
      - "80:80"
      - "8080:8080"
      - "8181:8181"
      - "8081:8081"
      - "3000:3000"
      - "5000:5000"
```

### README (CONT-03)
- **D-08:** Standard scope — includes: what the image does, `docker run` command with all 6 port flags, docker-compose snippet, and a sample JSON response body

### Dockerfile / Build (CONT-01, CONT-02)
- Locked by CLAUDE.md and Phase 1 context:
  - Multi-stage: `golang:1.26-alpine` builder → `FROM scratch` final stage
  - `CGO_ENABLED=0 GOOS=linux` static binary — no glibc, runs on scratch
  - `docker buildx` with `--platform linux/amd64,linux/arm64`
  - `TARGETARCH` injected by buildx, passed through to `go build`

### Claude's Discretion
- Exact GitHub Actions job/step structure (single job vs. separate build/push jobs)
- Whether to use `docker/build-push-action` or raw docker buildx commands in the workflow
- Dockerfile layer ordering and cache optimization

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` — Phase 2 requirement IDs: CONT-01, CONT-02, CONT-03, DIST-01, DIST-02, DIST-03

### Project Constraints
- `.planning/PROJECT.md` — Constraints (HTTP only, multi-port, stateless, portability) + current state summary
- `CLAUDE.md` — Prescribed stack: Go 1.26.1, `FROM scratch`, `CGO_ENABLED=0`, `docker buildx` multi-arch. Explicitly rules out alpine as final stage, full Go toolchain image, supervisord. See "Technology Stack" section.

### Prior Phase
- `.planning/phases/01-core-server-binary/01-CONTEXT.md` — Port 80 non-fatal bind (D-04), structured log fields (D-06 to D-08), static binary requirement for scratch compatibility

No external ADRs or specs — all decisions captured above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `main.go` — Entry point; uses `CGO_ENABLED=0`-compatible stdlib only (`net/http`, `log/slog`, `sync`, `os/signal`). Binary is already scratch-compatible.
- `handler.go` — Catch-all HTTP handler; no changes needed for Phase 2
- `go.mod` — Module `swiss-army-image`, `go 1.21` minimum (for `log/slog` availability)

### Established Patterns
- Static binary with no external dependencies — no `go.sum` entries, pure stdlib
- `CGO_ENABLED=0 GOOS=linux` must be explicit in the Dockerfile `RUN go build` step

### Integration Points
- Dockerfile `COPY` target: the compiled binary from the builder stage
- GitHub Actions: workflow file at `.github/workflows/build-push.yml` (or similar)
- `docker-compose.yml` at repo root

</code_context>

<specifics>
## Specific Ideas

- Image reference confirmed with example: `cainc/yriahi/swiss-army-image:1.0.0` → full path `nexus.cainc.com:5000/cainc/yriahi/swiss-army-image:1.0.0`
- Compose file uses `latest` tag in the example (mutable alias, matches DIST-02)
- README sample response body should reflect the actual JSON shape from Phase 1 (D-01 to D-03 in 01-CONTEXT.md): `{"port":8080,"method":"GET","path":"/","timestamp":"...","query_params":{}}`

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-container-and-distribution*
*Context gathered: 2026-03-25*
