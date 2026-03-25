# Project Research Summary

**Project:** Swiss Army Image
**Domain:** Minimal multi-port catch-all HTTP stub Docker image
**Researched:** 2026-03-25
**Confidence:** HIGH

## Executive Summary

Swiss Army Image is a drop-in Docker stub that replaces real application containers during infrastructure scaffolding and topology validation. The core contract is simple: bind six well-known framework ports simultaneously (80, 8080, 8181, 8081, 3000, 5000), respond HTTP 200 with structured JSON metadata to any request on any path via any method, and publish a multi-arch manifest covering linux/amd64 and linux/arm64. No existing tool does this — traefik/whoami, mendhak/http-https-echo, hashicorp/http-echo, and nicholasjackson/fake-service all bind a single port. Multi-port is both the unique selling point and the entire design constraint.

The recommended implementation is a single statically-linked Go binary running in a `FROM scratch` container built via a multi-stage Dockerfile. Go's `net/http` stdlib handles six concurrent goroutines trivially with `golang.org/x/sync/errgroup`, produces a ~5 MB binary with `CGO_ENABLED=0`, and requires zero external dependencies. The multi-stage build uses `golang:1.26-alpine` as the builder and `FROM scratch` as the runtime stage, producing a final image well under 10 MB. `docker buildx build --platform linux/amd64,linux/arm64` covers both Apple Silicon dev and amd64 CI with no QEMU overhead.

The primary risks are operational, not architectural. The most dangerous pitfall is a single-arch image that silently ships for only one platform — it must be caught immediately after first push via `docker buildx imagetools inspect`. The second highest risk is using shell-form `ENTRYPOINT`/`CMD`, which breaks signal handling and causes `docker stop` to hang for 10 seconds. Both are avoided by committing to the correct patterns from day one. Port 80 binding on Linux requires either running as root or granting `CAP_NET_BIND_SERVICE`; for a testing-only stub with no sensitive data, running as root is the pragmatic and documentable choice.

## Key Findings

### Recommended Stack

All research converges on a single, clear technology choice with no ambiguity. Go 1.26.1 with `FROM scratch` produces the smallest possible image (~5-8 MB) with the fewest moving parts. Every alternative — nginx, Caddy, Node, Python — is ruled out by size, complexity, or inability to handle multi-port in a single process. The Go stdlib alone (`net/http`, `encoding/json`, `log`) covers all required functionality; there are no external runtime dependencies.

**Core technologies:**
- **Go 1.26.1** — HTTP server binary — `net/http` goroutine-per-port pattern handles multi-port in a single process; static binary with `CGO_ENABLED=0` runs on `FROM scratch`
- **`FROM scratch`** — Final runtime base — zero OS overhead, no shell, no package manager, ~5 MB image; only the compiled binary is present
- **`golang:1.26-alpine`** — Builder stage only — alpine keeps the builder layer fast; only the compiled binary crosses to the runtime stage
- **`docker buildx`** — Multi-arch build — `--platform linux/amd64,linux/arm64` produces a single manifest list; `BUILDPLATFORM`/`TARGETARCH` args enable cross-compilation without QEMU

### Expected Features

Research cross-referenced five established stub tools (traefik/whoami, mendhak/http-https-echo, nicholasjackson/fake-service, hashicorp/http-echo, WireMock). The MVP feature set is narrow and well-defined.

**Must have (table stakes):**
- Simultaneous binding on ports 80, 8080, 8181, 8081, 3000, 5000 — core contract; without this the image is identical to existing single-port stubs
- Catch-all routing (any path, any HTTP method returns HTTP 200) — the entire value proposition
- JSON response body containing port, method, path, timestamp, and query params — makes the stub debuggable and distinguishable from a blank 200
- Stdout request logging per request — required for `docker logs` workflow
- Multi-arch image (linux/amd64 + linux/arm64) — Apple Silicon dev + amd64 CI are both required targets
- Single `docker run` zero-config invocation — no volume mounts, no env vars required
- Docker Compose example in README — minimum viable documentation

**Should have (competitive):**
- `?delay=` query param for timeout testing — low complexity, high value for proxy/LB validation
- CORS headers on all responses — enables browser-based scaffold testing
- `?status=` query param for error path testing — low complexity, confirms error propagation through scaffolding
- Kubernetes/ECS probe compatibility documentation — the catch-all already provides this; needs explicit docs

**Defer (v2+):**
- Configurable port list via environment variable — complicates the drop-in stub contract
- Additional framework ports beyond the core 6 — add only with evidence of specific demand
- Response body size configuration (`?size=`) — niche use case for bandwidth testing

### Architecture Approach

The architecture is a single Go binary owning all six ports through goroutines, with no supervisor process. `main.go` fans out one `http.ListenAndServe` goroutine per port using `errgroup`; `handler.go` provides a shared stateless catch-all `HandlerFunc` that builds the JSON response and writes to stdout. `errgroup` propagates the first bind error to `main()` and exits cleanly — the correct behavior when a stub must present all ports or nothing. The Dockerfile is a two-stage build: builder stage cross-compiles with `GOOS`/`GOARCH` from `TARGETOS`/`TARGETARCH` build args, runtime stage copies the binary to `FROM scratch`. GitHub Actions runs `docker buildx build --push` on tag push.

**Major components:**
1. `main.go` — Port list as single source of truth; goroutine fan-out via `errgroup`; signal handler wiring `http.Server.Shutdown()` on SIGTERM
2. `handler.go` — Stateless catch-all `HandlerFunc`; extracts port (via closure capture), method, path, query params, timestamp; writes JSON response and stdout log line
3. `Dockerfile` — Multi-stage: `golang:1.26-alpine` builder with `CGO_ENABLED=0` cross-compilation; `FROM scratch` runtime with exec-form `ENTRYPOINT ["/server"]`
4. `.github/workflows/docker-publish.yml` — `docker buildx build --platform linux/amd64,linux/arm64 --push`; Docker Metadata Action for semver + SHA tags

### Critical Pitfalls

1. **Shell-form ENTRYPOINT/CMD breaks signal handling** — Always use exec form: `ENTRYPOINT ["/server"]`. Shell form makes `/bin/sh` PID 1; SIGTERM never reaches the server; `docker stop` takes 10 seconds and exits with code 137. Verify with `docker stop` completing in under 2 seconds.

2. **Multi-arch build silently produces single-arch image** — Never use `docker build` for published images. Use `docker buildx build --platform linux/amd64,linux/arm64 --push` exclusively. Validate immediately after push with `docker buildx imagetools inspect` — must list both manifests.

3. **Port 80 binding requires root or CAP_NET_BIND_SERVICE on Linux** — Docker Desktop (Mac/Windows) relaxes this restriction, masking the problem in local dev. For a testing stub, running as root is the documented pragmatic choice. Alternatively, `setcap cap_net_bind_service=+ep /server` in the Dockerfile grants the capability without full root.

4. **Missing `Content-Type: application/json` header breaks proxy compatibility** — Kubernetes ingress controllers and health check aggregators inspect `Content-Type`. Always set the header on every response. Write the complete JSON body atomically before closing the connection.

5. **`EXPOSE` does not bind ports — `-p` flags are required at runtime** — `EXPOSE` is documentation only. All six ports must be listed in `docker run -p` or docker-compose `ports:` entries. Document the full invocation prominently; do not rely on `-P` (maps to random high ports, breaks consumers with hardcoded port numbers).

## Implications for Roadmap

The architecture research defines a strict linear build dependency: the Go binary must work locally before containerizing, and a correct single-arch container must be validated before adding multi-arch complexity. This maps directly to three phases.

### Phase 1: Core Go Binary

**Rationale:** All downstream work depends on a correct, working binary. The handler logic and multi-port listener are the entire product in code form. No Dockerfile complexity until this is right.

**Delivers:** A runnable Go binary that binds all 6 ports, responds HTTP 200 JSON with port/method/path/timestamp/query on any request, and logs to stdout. Verifiable locally with `go run .` and six `curl` calls.

**Addresses:** Multi-port binding, catch-all routing, JSON response body, stdout logging (all P1 features).

**Avoids:** Sequential port binding anti-pattern (use `errgroup` goroutines, not blocking sequential `ListenAndServe` calls).

**Research flag:** Standard Go patterns — no deeper research needed. The goroutine-per-port + `errgroup` pattern is well-documented and confirmed.

---

### Phase 2: Container Packaging

**Rationale:** Containerize the confirmed-working binary. Address all Dockerfile pitfalls before adding multi-arch complexity. Single-arch smoke test first.

**Delivers:** A working single-arch Docker image. All 6 ports accessible via `docker run -p ...`. Exec-form `ENTRYPOINT`. Image under 10 MB. Correct `Content-Type` header. Clean `docker stop` in under 2 seconds.

**Uses:** `golang:1.26-alpine` builder, `FROM scratch` runtime, `CGO_ENABLED=0`, multi-stage build, `.dockerignore`.

**Implements:** Multi-stage Dockerfile with cross-compilation structure (even for single arch, set up `TARGETOS`/`TARGETARCH` args now so multi-arch is a single flag addition in Phase 3).

**Avoids:** Shell-form ENTRYPOINT; large base image; `COPY . .` before `go mod download` (breaks layer caching); wrong base image; port 80 CAP_NET_BIND_SERVICE issue (resolve in this phase).

**Research flag:** Standard Docker multi-stage patterns — no deeper research needed.

---

### Phase 3: Multi-Arch CI/CD

**Rationale:** Multi-arch is a CI/CD concern, not a code concern. The binary already cross-compiles correctly; this phase adds `buildx`, the GitHub Actions workflow, and registry publishing. Depends entirely on Phase 2 Dockerfile being correct.

**Delivers:** Published multi-arch manifest on GHCR (or Docker Hub) covering linux/amd64 and linux/arm64. Semver + SHA tagging strategy. GitHub Actions workflow triggered on tag push.

**Uses:** `docker buildx`, `BUILDPLATFORM`/`TARGETOS`/`TARGETARCH` Dockerfile build args, `docker/metadata-action`, `docker/build-push-action`.

**Avoids:** Single-arch publish mistake (validate with `docker buildx imagetools inspect` as CI step); `latest`-only tagging.

**Research flag:** Standard GitHub Actions multi-platform Docker patterns — no deeper research needed. Official Docker docs cover this exactly.

---

### Phase 4: Documentation and Integration Examples

**Rationale:** The image is only valuable if users can configure it correctly. EXPOSE misconception and docker-compose port binding scope are documentation problems, not code problems. Kubernetes and ECS integration notes prevent support burden.

**Delivers:** README with zero-config `docker run` invocation showing all 6 `-p` flags; docker-compose example with correct `ports:` entries and localhost-binding note; Kubernetes probe compatibility explanation; ECS health check guidance; a "Looks Done But Isn't" smoke test checklist.

**Addresses:** EXPOSE misconception, docker-compose 0.0.0.0 exposure, Kubernetes probe documentation (P2 feature), ECS health check guidance.

**Research flag:** No deeper research needed — all integration patterns documented in PITFALLS.md.

---

### Phase 5: v1.x Enhancements

**Rationale:** Add the P2 differentiators once core is validated and users confirm the use cases. These are all low-complexity additions to the existing handler.

**Delivers:** `?delay=` for timeout testing; `?status=` for error path testing; CORS headers on all responses.

**Implements:** Query parameter parsing additions to `handler.go`; `time.Sleep` for delay; status code override; `Access-Control-Allow-Origin: *` default header.

**Research flag:** Standard HTTP handler patterns — no deeper research needed.

---

### Phase Ordering Rationale

- **Binary before container:** The goroutine-per-port architecture must be validated locally before adding Dockerfile complexity. Mixing debugging layers slows delivery.
- **Single-arch before multi-arch:** Multi-arch is strictly additive to a correct single-arch Dockerfile. Attempting multi-arch before the Dockerfile is right introduces two simultaneous unknowns.
- **Code before docs:** Documentation cannot be written accurately before integration behavior is confirmed.
- **Core before enhancements:** The `?delay=`/`?status=`/CORS additions are stateless handler changes that cannot break core behavior, but should wait until the primary use case is validated.

### Research Flags

Phases with standard patterns (skip `/gsd:research-phase`):
- **Phase 1** — Go goroutine-per-port pattern with `errgroup` is well-documented and confirmed at HIGH confidence
- **Phase 2** — Docker multi-stage build with `FROM scratch` and `CGO_ENABLED=0` is a standard, well-documented pattern
- **Phase 3** — GitHub Actions multi-platform Docker build is covered by official Docker CI docs with working examples
- **Phase 4** — All integration patterns are documented in PITFALLS.md; no new research needed
- **Phase 5** — HTTP handler query param additions are trivial Go stdlib patterns

No phase requires deeper research. All five phases have HIGH-confidence patterns available.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Go 1.26.1 confirmed latest stable; `FROM scratch` + `CGO_ENABLED=0` pattern is universally validated; all alternatives evaluated and dismissed with clear rationale |
| Features | HIGH | Five established stub tools cross-referenced; feature set derived from observed industry patterns; competitor matrix confirms multi-port as unique differentiator |
| Architecture | HIGH | Official Docker multi-platform docs, Dockerfile best practices, Go stdlib patterns; code examples provided and validated; build dependency order is unambiguous |
| Pitfalls | HIGH | Each pitfall backed by official Docker docs or confirmed observed behavior; warning signs and recovery steps are specific and actionable |

**Overall confidence:** HIGH

### Gaps to Address

- **Port 80 root vs. capability choice:** The research documents both options (run as root, or `setcap`/`--cap-add NET_BIND_SERVICE`). The Dockerfile author must make the explicit call during Phase 2. Recommendation: run as root for this testing-only stub, document the reason in the Dockerfile with a comment.

- **tini vs. signal handler in Go:** Research notes that `FROM scratch` cannot use tini without copying the tini binary, and recommends wiring Go's `net/http.Server.Shutdown()` to SIGTERM directly as the cleaner approach. This is a Phase 2 implementation decision. The pattern is well-understood; no gap in knowledge, only a code authoring choice.

- **Registry target (GHCR vs. Docker Hub):** Not determined by research. Needs a project decision before Phase 3. Both are supported identically by `docker/build-push-action`.

## Sources

### Primary (HIGH confidence)
- https://github.com/golang/go/tags — Go 1.26.1 confirmed latest stable (March 6, 2026)
- https://docs.docker.com/build/building/multi-platform/ — Multi-platform build patterns
- https://docs.docker.com/build/building/best-practices/ — Dockerfile best practices including layer caching
- https://docs.docker.com/build/building/variables/ — BUILDPLATFORM, TARGETOS, TARGETARCH build args
- https://docs.docker.com/build/ci/github-actions/multi-platform/ — GitHub Actions multi-arch CI
- https://docs.docker.com/reference/dockerfile/#entrypoint — Exec vs shell form behavior
- https://docs.docker.com/reference/dockerfile/#expose — EXPOSE is documentation only
- https://github.com/GoogleContainerTools/distroless — distroless/static-debian12 ~2 MB
- https://github.com/traefik/whoami — Single-port catch-all stub, feature reference
- https://github.com/mendhak/docker-http-https-echo — Feature reference, CORS patterns
- https://github.com/nicholasjackson/fake-service — Feature reference
- https://github.com/hashicorp/http-echo — Feature reference, zero-config startup model
- https://github.com/wiremock/wiremock-docker — Feature reference, scoping anti-features

### Secondary (MEDIUM confidence)
- docs.nginx.com — nginx `return` directive with variable interpolation; behavior documented but SSL prevented direct verification
- Training data — Go multi-port goroutine pattern, CGO_ENABLED=0 scratch compatibility; standard patterns widely validated across sources

---
*Research completed: 2026-03-25*
*Ready for roadmap: yes*
