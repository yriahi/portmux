<!-- GSD:project-start source:PROJECT.md -->
## Project

**Swiss Knife Image**

A lightweight Docker image that acts as a universal stub for testing containerized service scaffolding. It listens simultaneously on all common framework ports (80, 8080, 8181, 8081, 3000, 5000) and returns HTTP 200 with JSON request info on every path, regardless of method or URL. Designed to drop in wherever a real Node.js, React, Next.js, Java, or Spring Boot container would run.

**Core Value:** Any containerized scaffolding can be validated end-to-end — networking, routing, proxies, load balancers, probes — without needing real application code running.

### Constraints

- **HTTP only**: No TLS — simplifies deployment and certificate management
- **Multi-port**: Must bind all 6 ports in a single container process or via supervisor
- **Stateless**: No filesystem writes, no database, purely in-memory request handling
- **Portability**: Must run on linux/amd64 and linux/arm64 (Apple Silicon + CI/CD environments)
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Core Technologies
| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Go | 1.26.1 (latest stable) | HTTP server binary | net/http stdlib handles multi-port goroutines trivially; static binary compiles to ~5 MB with no runtime dependencies; single Dockerfile handles amd64 + arm64 via GOARCH |
| Docker multi-stage build | Dockerfile syntax 1.x | Build and package | Builder stage uses golang:1.26-alpine; final stage uses `FROM scratch`; keeps image to ~5 MB with zero OS attack surface |
| `FROM scratch` | — | Final base image | Zero additional layers; no shell, no package manager, no OS overhead; only the binary lands in the image; supported by all OCI runtimes (Docker, containerd, ECS, k8s) |
### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `encoding/json` (stdlib) | included in Go 1.26 | JSON serialization of response body | Always — no external dep needed for this use case |
| `net/http` (stdlib) | included in Go 1.26 | HTTP listener per port | Always — goroutine-per-port pattern; `http.ListenAndServe` blocks, so each port runs in its own goroutine with `sync.WaitGroup` |
| `log` (stdlib) | included in Go 1.26 | Stdout request logging | Always — writes port/method/path/timestamp to stdout for Docker log capture |
### Development Tools
| Tool | Purpose | Notes |
|------|---------|-------|
| `golang:1.26-alpine` | Builder image in multi-stage Dockerfile | Alpine keeps builder layer fast; only artifact (static binary) is copied to scratch |
| `docker buildx` | Multi-arch image build | Use `--platform linux/amd64,linux/arm64` to produce a single manifest list; required for Apple Silicon dev + CI/CD |
| `CGO_ENABLED=0` build flag | Forces pure Go static binary | Without this, the binary links glibc and cannot run on `FROM scratch`; must be set at `go build` time |
| `GOOS=linux GOARCH=...` | Cross-compilation in builder stage | Docker buildx injects `TARGETARCH`; pass through to `go build` for correct arch |
## Installation
# No npm. The build is entirely within Docker.
# Example build command (local):
## Alternatives Considered
| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Go static binary on `FROM scratch` | `nginx:1.28-alpine-slim` | Use nginx only if the response body can be a static string — nginx `return 200` with variable interpolation (`$server_port`, `$request_method`, `$request_uri`, `$time_iso8601`) handles port/method/path/time, but query param extraction into JSON requires `$args` string manipulation and becomes unreadable config; nginx is 8-10 MB vs 5 MB and requires a maintained nginx.conf |
| Go static binary on `FROM scratch` | `caddy:2.11.2-alpine` | Use Caddy only if you need HTTPS, automatic cert management, or a richer reverse proxy — Caddy alpine is ~35-45 MB, massive overkill for a stub that returns 200; the `respond` directive returns static bodies only, no dynamic request metadata |
| Go static binary on `FROM scratch` | Python `http.server` | Use Python only for a throwaway local dev prototype — the base image is 50+ MB, `http.server` is single-port (multi-port would require multiple processes + supervisord), and there is no JSON metadata control |
| Go static binary on `FROM scratch` | `gcr.io/distroless/static-debian12` | Use distroless instead of scratch if you need TLS CA certificates or a non-root UID at runtime — for plain HTTP with no TLS this adds ~2 MB of unnecessary baggage; scratch is correct for HTTP-only stub |
| `golang:1.26-alpine` (builder) | `golang:1.26` (Debian builder) | Use Debian builder only if build tools require glibc — alpine builder is ~50% smaller and identical for pure Go |
## What NOT to Use
| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `socat` / `ncat` | These are Layer 4 (TCP) tools, not HTTP servers — they cannot parse HTTP requests, cannot read port/method/path/query, cannot return structured JSON; they pipe raw bytes | Go net/http |
| OpenResty (nginx + Lua) | Adds Lua scripting to nginx to enable dynamic JSON responses, but the image is ~80-100 MB and requires learning a Lua embedding just to replicate what 50 lines of Go stdlib does | Go net/http |
| `supervisord` + multiple single-port servers | Spawning one HTTP process per port via supervisord is the wrong abstraction — adds a supervisor daemon, complex config, and extra image layers; Go goroutines handle multi-port in one process with zero overhead | Single Go binary with goroutine-per-port |
| `FROM node:alpine` + `http.createServer` | Node with a tiny script would work for single-port but the node:alpine image is ~70 MB; requires a package manager present; goroutine-per-port is simpler in Go and the binary is 10x smaller | Go static binary |
| Multi-stage build ending on `alpine` (not `scratch`) | Alpine adds ~5 MB of shell, pkg manager, and libc that are never used at runtime for a statically-linked binary — increases attack surface with no benefit | `FROM scratch` as final stage |
| `golang:1.26` as final image (not multi-stage) | The full Go toolchain image is ~800 MB; shipping it as the runtime image is a critical size mistake | Multi-stage: build in `golang:1.26-alpine`, copy binary to `FROM scratch` |
## Stack Patterns by Variant
- Use `FROM gcr.io/distroless/static-debian12:nonroot` as the final stage instead of `FROM scratch`
- Because scratch has no /etc/passwd so you cannot reference a named user; distroless-nonroot ships with UID 65532 pre-defined
- Add `gcr.io/distroless/static-debian12` instead of `FROM scratch` to get CA certificates
- The Go binary uses `crypto/tls` from stdlib — no new external dependencies
- No change needed — the catch-all handler on every port already returns 200 on `GET /`, which is the default probe path; no dedicated `/healthz` route is required
## Version Compatibility
| Package | Compatible With | Notes |
|---------|-----------------|-------|
| `golang:1.26-alpine` (builder) | `alpine:3.23` (embedded in the alpine tag) | Compatible; golang alpine images track the current alpine release |
| Go 1.26.1 static binary | `FROM scratch` | Compatible only when built with `CGO_ENABLED=0`; this must be explicit in the Dockerfile `RUN` step |
| Docker buildx multi-arch | `FROM scratch` final stage | Compatible; scratch is architecture-agnostic; the binary inside must match `TARGETARCH` which buildx injects |
## Sources
- https://github.com/golang/go/tags — Go 1.26.1 confirmed as latest stable (March 6, 2026), HIGH confidence
- https://github.com/nginx/nginx/tags — nginx 1.28.3 confirmed as latest stable release (March 24, 2026), HIGH confidence
- https://github.com/docker-library/official-images/blob/master/library/nginx — nginx:1.28-alpine-slim confirmed, alpine:3.23 base, HIGH confidence
- https://github.com/caddyserver/caddy/releases — Caddy v2.11.2 confirmed latest stable (March 6, 2026), HIGH confidence
- https://github.com/GoogleContainerTools/distroless — distroless/static-debian12 ~2 MB confirmed, HIGH confidence
- docs.nginx.com — nginx `return` directive with variable interpolation (`$server_port`, `$request_method`, `$request_uri`) confirmed, MEDIUM confidence (SSL cert issue prevented direct verification; behavior is well-documented and stable across nginx versions)
- Training data (Go multi-port goroutine pattern, CGO_ENABLED=0 scratch compatibility) — MEDIUM confidence, standard Go Docker patterns widely validated
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
