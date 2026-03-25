# Architecture Research

**Domain:** Multi-port Docker stub/mock HTTP server (Go-based, multi-arch)
**Researched:** 2026-03-25
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Docker Image                                 │
│                    (linux/amd64 + linux/arm64)                       │
├─────────────────────────────────────────────────────────────────────┤
│  Entrypoint: /server  (static Go binary, PID 1 via tini)            │
├─────────────────────────────────────────────────────────────────────┤
│  HTTP Listener Layer (single process, 6 goroutines)                 │
│                                                                      │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ │
│  │ :80    │ │ :8080  │ │ :8181  │ │ :8081  │ │ :3000  │ │ :5000  │ │
│  └───┬────┘ └───┬────┘ └───┬────┘ └───┬────┘ └───┬────┘ └───┬────┘ │
│      └──────────┴──────────┴──────────┴──────────┴──────────┘      │
│                              │                                       │
│                    ┌─────────▼─────────┐                            │
│                    │  Shared Handler   │                            │
│                    │  (catch-all mux)  │                            │
│                    └─────────┬─────────┘                            │
│                              │                                       │
│                    ┌─────────▼─────────┐                            │
│                    │  Response Builder │                            │
│                    │  JSON + stdout log│                            │
│                    └───────────────────┘                            │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| `tini` | PID 1, zombie reaping, signal forwarding to server binary | `tini` binary in image, `ENTRYPOINT ["/sbin/tini", "--", "/server"]` |
| `server` binary | Bind all 6 ports, serve HTTP, log to stdout | Single static Go binary with goroutines per port |
| Shared handler | Accept any method + path, extract request metadata | `http.HandlerFunc` registered on `http.NewServeMux()` |
| Response builder | Construct JSON response with port/method/path/timestamp/query | Pure function, no state |
| Stdout logger | Emit one log line per request | `log.Printf` or `fmt.Fprintf(os.Stdout, ...)` |

## Recommended Project Structure

```
swiss-army-image/
├── main.go                   # Entry point: port list, goroutine fan-out, errgroup
├── handler.go                # Shared catch-all HTTP handler + JSON builder
├── go.mod                    # Module: single dependency (errgroup or none)
├── go.sum
├── Dockerfile                # Multi-stage: builder + scratch/distroless final
├── .dockerignore             # Exclude .git, .planning, *.md from build context
└── .github/
    └── workflows/
        └── docker-publish.yml  # buildx multi-arch build + push on tag/push
```

### Structure Rationale

- **`main.go`:** Owns port configuration and goroutine lifecycle. Separating it from handler logic means the port list is a single source of truth.
- **`handler.go`:** Isolated catch-all handler that can be unit-tested without starting listeners.
- **`Dockerfile`:** Single file covers both build and runtime stages — no separate `docker-compose.yml` needed for the image itself.

## Architectural Patterns

### Pattern 1: Single Process, Multiple Goroutines Per Port

**What:** One Go binary calls `http.ListenAndServe` once per target port, each in its own goroutine. A shared handler function is registered on each server. `golang.org/x/sync/errgroup` propagates the first fatal listen error back to main, causing a clean exit.

**When to use:** Always — for a pure HTTP listener stub with no inter-port state this is the correct model. Supervisors (s6, supervisord) add complexity with zero benefit when a single binary can own all ports natively.

**Trade-offs:** Simple, minimal image size, single log stream. No automatic restart of individual ports if one bind fails (but a bind failure on startup is fatal anyway — correct behavior for a stub).

**Example:**
```go
// main.go
var ports = []string{":80", ":8080", ":8181", ":8081", ":3000", ":5000"}

func main() {
    g, ctx := errgroup.WithContext(context.Background())
    _ = ctx
    for _, port := range ports {
        port := port // capture
        g.Go(func() error {
            log.Printf("listening on %s", port)
            return http.ListenAndServe(port, newHandler(port))
        })
    }
    if err := g.Wait(); err != nil {
        log.Fatal(err)
    }
}
```

### Pattern 2: Multi-Stage Dockerfile with Cross-Compilation

**What:** Stage 1 pins to `--platform=$BUILDPLATFORM` (builder's native arch) and cross-compiles with `GOOS`/`GOARCH` set from `TARGETOS`/`TARGETARCH` build args. Stage 2 copies the static binary into a minimal base (`scratch` or `gcr.io/distroless/static-debian12`). `CGO_ENABLED=0` ensures a fully static binary with zero shared-library deps.

**When to use:** Always for multi-arch Go images. Cross-compilation is faster than QEMU emulation and produces identical binaries.

**Trade-offs:** Requires Go's cross-compilation support (trivially available). `scratch` gives the smallest image (~5-8 MB for the binary) but has no shell — distroless adds ~2 MB and includes TZ data and CA certs (not needed here, so `scratch` is preferred).

**Example:**
```dockerfile
# Stage 1: build (always runs on builder's native arch)
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG TARGETOS
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -ldflags="-s -w" -trimpath -o /server .

# Stage 2: minimal runtime
FROM scratch
COPY --from=builder /server /server
EXPOSE 80 8080 8181 8081 3000 5000
ENTRYPOINT ["/server"]
```

> Note: `scratch` has no shell, so `ENTRYPOINT` must use exec form (JSON array). tini cannot be used with scratch unless the tini binary is also copied in. For scratch, let Go handle signals directly — Go's `net/http` handles SIGTERM cleanly. If tini is needed, use `gcr.io/distroless/static-debian12` or Alpine and install tini.

### Pattern 3: tini as PID 1 (when not using scratch)

**What:** Add `tini` as the image's init process so it properly reaps zombies and forwards signals (SIGTERM on `docker stop`) to the Go binary.

**When to use:** When using Alpine or distroless as the final base. Not needed with `scratch` if the Go binary itself handles SIGTERM — Go's `net/http.Server.Shutdown` can be wired to a signal handler.

**Trade-offs:** Tini adds ~20 KB and removes a class of PID 1 bugs. For this project, a clean `scratch` image with a signal-handling Go binary achieves the same result. Tini is the safer default for teams unfamiliar with Go signal handling.

**Example (Alpine base with tini):**
```dockerfile
FROM alpine:3.21
RUN apk add --no-cache tini
COPY --from=builder /server /server
EXPOSE 80 8080 8181 8081 3000 5000
ENTRYPOINT ["/sbin/tini", "--", "/server"]
```

### Pattern 4: Image Tagging Strategy

**What:** Apply multiple tags to each published image: semantic version (full + major.minor), `latest` on main branch, and a short Git SHA for traceability. Use Docker Metadata Action in GitHub Actions to compute tags automatically.

**When to use:** All production image releases.

**Trade-offs:** Semver tags are immutable references for dependents. `latest` is mutable — acceptable for a test stub where "always newest" is fine. SHA tags enable exact reproducibility for CI pipelines that pin by digest.

**Recommended tag set per release:**
```
ghcr.io/org/swiss-army-image:1.2.3         # exact version
ghcr.io/org/swiss-army-image:1.2           # minor stream
ghcr.io/org/swiss-army-image:1             # major stream
ghcr.io/org/swiss-army-image:latest        # mutable, main branch only
ghcr.io/org/swiss-army-image:sha-abc1234   # immutable, exact build
```

## Data Flow

### Request Flow

```
External HTTP client
    │
    │  TCP connect to port (80/8080/8181/8081/3000/5000)
    ▼
http.ListenAndServe (goroutine per port)
    │
    │  passes *http.Request to handler
    ▼
Shared catch-all HandlerFunc
    │
    ├─── Extract: port (from server context), method, path, query params, timestamp
    │
    ├─── Write log line to stdout
    │         format: "port=8080 method=GET path=/foo/bar ts=2026-03-25T12:00:00Z"
    │
    └─── Write HTTP 200 response
              Content-Type: application/json
              Body: {"port":8080,"method":"GET","path":"/foo/bar",
                     "timestamp":"2026-03-25T12:00:00Z","query":{"k":["v"]}}
```

### Startup Flow

```
Container start
    │
    ├── tini (PID 1) starts /server
    │
    └── main() fans out goroutines
            │
            ├── goroutine → http.ListenAndServe(":80", handler)
            ├── goroutine → http.ListenAndServe(":8080", handler)
            ├── goroutine → http.ListenAndServe(":8181", handler)
            ├── goroutine → http.ListenAndServe(":8081", handler)
            ├── goroutine → http.ListenAndServe(":3000", handler)
            └── goroutine → http.ListenAndServe(":5000", handler)

errgroup.Wait() blocks main — container stays alive
```

### Shutdown Flow

```
SIGTERM (docker stop / k8s pod termination)
    │
    ▼
tini forwards SIGTERM to /server PID
    │
    ▼
Go signal handler triggers http.Server.Shutdown() on all servers
    │
    ▼
In-flight requests drain (with configurable timeout, e.g. 5s)
    │
    ▼
All goroutines return → errgroup.Wait() returns → main() exits 0
    │
    ▼
tini exits with child's exit code → container exits cleanly
```

### Key Data Flows

1. **Port identity propagation:** Each goroutine captures its port string at launch and passes it into the handler via closure or server context. The handler reads it to include in JSON and logs — no global state.
2. **Log stream:** All 6 listeners write to the same `os.Stdout`. Docker collects this as the container's log stream. No log aggregation needed; `docker logs` and k8s log collectors pick it up natively.
3. **Build-time arch selection:** `TARGETOS`/`TARGETARCH` flow from `docker buildx build --platform linux/amd64,linux/arm64` into Go compiler env vars. The output binary is architecture-specific; the manifest ties both together.

## Component Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Client ↔ Listener | TCP/HTTP (no TLS) | One goroutine per port; Go's net/http handles concurrency internally |
| Listener ↔ Handler | `http.Request` + `http.ResponseWriter` | Standard Go HTTP interface; handler is stateless |
| Handler ↔ Stdout | `fmt.Fprintf(os.Stdout, ...)` | Single shared stream; Go's stdlib is goroutine-safe for os.Stdout writes |
| Builder stage ↔ Runtime stage | Binary via `COPY --from=builder` | Only the compiled binary crosses the stage boundary |
| CI ↔ Registry | `docker buildx build --push` | Pushes manifest list + per-arch blobs atomically |

## Build Order (Phase Dependencies)

```
Phase 1: Core binary
    └── Go handler function (catch-all, JSON response, port extraction)
    └── Multi-port listener (goroutines, errgroup)
    └── Stdout logging

Phase 2: Container packaging
    └── Depends on: Phase 1 binary works locally
    └── Dockerfile (multi-stage, scratch or Alpine+tini)
    └── .dockerignore
    └── docker run smoke test on single arch

Phase 3: Multi-arch + CI
    └── Depends on: Phase 2 Dockerfile is correct
    └── Buildx cross-compilation (BUILDPLATFORM/TARGETOS/TARGETARCH)
    └── GitHub Actions workflow (metadata-action tags + buildx push)
    └── GHCR or Docker Hub publishing
```

Dependencies are strictly linear: the binary must work before containerizing; single-arch container must work before adding multi-arch complexity.

## Anti-Patterns

### Anti-Pattern 1: Using supervisord or s6 for Multi-Port

**What people do:** Reach for supervisord or s6-overlay to run six separate server processes, one per port.

**Why it's wrong:** Supervisors add 10-50 MB to the image, require configuration files, introduce a multi-stage supervision tree, and add restart semantics that are not needed. For a stub image, a single Go binary binding six ports via goroutines is architecturally correct — it is genuinely one process doing one thing.

**Do this instead:** Use `errgroup` with one `ListenAndServe` goroutine per port. If any port bind fails, the whole binary exits — which is the right behavior for a container that must present all ports.

### Anti-Pattern 2: Running One Container Per Port

**What people do:** Run six separate containers, each bound to one port, fronted by a compose service.

**Why it's wrong:** This defeats the purpose of a drop-in stub. Real application containers (Spring Boot on 8080, Next.js on 3000) own multiple ports from a single container. The stub must match that topology for scaffolding validation to be meaningful.

**Do this instead:** Single container, all ports bound, as specified in PROJECT.md.

### Anti-Pattern 3: Shell-Form ENTRYPOINT

**What people do:** `ENTRYPOINT /server` or `CMD /server` without exec form.

**Why it's wrong:** Shell form spawns a `/bin/sh -c` wrapper as PID 1. SIGTERM goes to the shell, not to `/server`. On `docker stop`, the shell may not forward the signal, forcing a SIGKILL after the 10s grace period — unclean container shutdown, bad for Kubernetes probe races.

**Do this instead:** Always use exec form: `ENTRYPOINT ["/server"]` or `ENTRYPOINT ["/sbin/tini", "--", "/server"]`.

### Anti-Pattern 4: Using `latest` as a Build Cache Tag

**What people do:** Tag images only as `latest`, relying on registry to cache layers.

**Why it's wrong:** `latest` is overwritten on every push, making rollbacks require a full rebuild. CI pipelines cannot pin a known-good version.

**Do this instead:** Tag with semver + SHA on every release. Use `latest` as an alias that also gets published, but never as the only tag.

### Anti-Pattern 5: COPY . . Before go mod download

**What people do:**
```dockerfile
COPY . .
RUN go mod download
RUN go build ...
```

**Why it's wrong:** Any source change invalidates the `go mod download` cache layer, re-downloading all dependencies on every build.

**Do this instead:**
```dockerfile
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build ...
```

## Scaling Considerations

This is a stateless stub — "scaling" means multi-arch portability and image pull speed, not horizontal scaling.

| Concern | Approach |
|---------|----------|
| Apple Silicon dev machines (arm64) | Multi-arch manifest via buildx; `docker run` auto-selects correct variant |
| CI runners (amd64, mostly) | Cross-compiled amd64 binary; no QEMU needed on standard GitHub runners |
| AWS ECS Graviton (arm64) | Multi-arch manifest covers this transparently |
| Image pull time in k8s | Scratch base keeps image under 10 MB; pulls in under 2s on typical cluster |
| Concurrent test traffic | Go net/http handles thousands of concurrent requests natively; no tuning needed for a stub |

## Sources

- Docker multi-platform build docs: https://docs.docker.com/build/building/multi-platform/
- Dockerfile best practices: https://docs.docker.com/build/building/best-practices/
- Pre-defined build args (BUILDPLATFORM etc.): https://docs.docker.com/build/building/variables/
- GitHub Actions multi-platform CI: https://docs.docker.com/build/ci/github-actions/multi-platform/
- Docker image tagging with metadata-action: https://docs.docker.com/build/ci/github-actions/manage-tags-labels/
- Distroless static base image: https://github.com/GoogleContainerTools/distroless
- tini init system: https://github.com/krallin/tini
- s6-overlay process supervisor: https://github.com/just-containers/s6-overlay
- Docker multi-service container guidance: https://docs.docker.com/engine/containers/multi-service_container/
- OCI image annotations spec: https://github.com/opencontainers/image-spec/blob/main/annotations.md

---
*Architecture research for: Multi-port Docker stub/mock HTTP server*
*Researched: 2026-03-25*
