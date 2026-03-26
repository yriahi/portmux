# Pitfalls Research

**Domain:** Docker stub/mock HTTP server image (multi-port, multi-arch)
**Researched:** 2026-03-25
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Shell Form CMD/ENTRYPOINT Breaks Signal Handling

**What goes wrong:**
Using shell form (`CMD my-server`) instead of exec form (`CMD ["my-server"]`) causes the process to run as a child of `/bin/sh -c` rather than as PID 1. When `docker stop` sends SIGTERM, the shell process receives it — not the server. The shell ignores it. Docker waits 10 seconds, then force-kills with SIGKILL. No graceful shutdown. In Kubernetes, this causes pod termination to take the full `terminationGracePeriodSeconds` every time, and liveness probes may miss the shutdown window.

**Why it happens:**
Developers write `CMD go run main.go` or `CMD node server.js` without knowing the shell form wraps the command in `/bin/sh -c`. The container appears to work because requests are served — the failure only appears at shutdown.

**How to avoid:**
Always use exec form: `CMD ["./server"]` or `ENTRYPOINT ["./server"]`. If a shell wrapper script is needed for setup, end the script with `exec "$@"` or `exec ./server` — the `exec` replaces the shell process so the binary becomes PID 1 directly.

**Warning signs:**
- `docker stop` takes 10 seconds instead of less than 1 second
- Container logs show no graceful shutdown message before termination
- `docker inspect` shows `ExitCode: 137` (SIGKILL) instead of `143` (SIGTERM)

**Phase to address:** Dockerfile authoring phase (core image build)

---

### Pitfall 2: Multi-Arch Build Silently Produces Single-Arch Image

**What goes wrong:**
Running `docker build` without `docker buildx build --platform linux/amd64,linux/arm64` produces an image for only the host architecture. The image pushes to a registry with no error. On CI (amd64) or Apple Silicon (arm64), the image either fails to pull or runs under QEMU emulation with a silent performance penalty. AWS ECS Fargate on Graviton (arm64) and GitHub Actions runners (amd64) hit this at deploy time.

**Why it happens:**
The default `docker build` command does not use BuildKit's multi-platform support. Developers test locally (arm64 on Apple Silicon), push the image, and it fails in amd64 CI/CD pipelines — or vice versa. The `--platform` flag is easy to omit.

**How to avoid:**
Use `docker buildx build --platform linux/amd64,linux/arm64 --push -t image:tag .` in all CI/CD pipelines. Never use `docker build` for published images. Validate after push with `docker buildx imagetools inspect image:tag` — output must list both `linux/amd64` and `linux/arm64` manifests. For Go: set `GOOS` and `GOARCH` via `ARG TARGETARCH` in the Dockerfile to cross-compile rather than relying on QEMU emulation.

**Warning signs:**
- `docker inspect image:tag | grep Architecture` returns only one value
- `docker buildx imagetools inspect image:tag` shows a single manifest, not a manifest list
- CI pipeline uses `docker build` not `docker buildx build`
- Image works on developer machine but fails to start on CI runner

**Phase to address:** CI/CD pipeline phase; validate immediately after first push

---

### Pitfall 3: EXPOSE Does Not Bind Ports — Runtime `-p` Flag Still Required

**What goes wrong:**
Adding `EXPOSE 80 8080 3000 5000 8181 8081` to the Dockerfile does not make those ports accessible from outside the container. `EXPOSE` is documentation only. If a consumer runs `docker run swiss-knife-image` without `-p` flags, all ports are unreachable from the host. The container is healthy internally, but nothing can connect to it. This is especially confusing during testing when the container reports "listening on :8080" but `curl localhost:8080` times out.

**Why it happens:**
`EXPOSE` looks like a port-publishing directive. New Docker users assume it functions like a firewall rule or port binding. The actual binding only happens at `docker run -p 8080:8080` or via docker-compose `ports:` entries.

**How to avoid:**
Document the required `docker run` invocation explicitly in the README and as a Dockerfile `LABEL`. Use `docker run -p 80:80 -p 8080:8080 -p 8181:8181 -p 8081:8081 -p 3000:3000 -p 5000:5000 swiss-knife-image` in all examples. In docker-compose, `ports:` must enumerate every port. Do not rely on `-P` (publish all exposed ports) as it maps to random high-numbered host ports, breaking consumers that hardcode port numbers.

**Warning signs:**
- `curl localhost:8080` returns `Connection refused` when container is running
- Container logs show "listening on :8080" but host cannot connect
- `docker ps` shows `PORTS` column as empty or only internal addresses

**Phase to address:** Dockerfile authoring phase; verify in smoke-test phase

---

### Pitfall 4: Zombie Processes When Using a Supervisor to Bind Multiple Ports

**What goes wrong:**
To bind 6 ports simultaneously, the natural approach is to run 6 server instances managed by a supervisor (supervisord, s6, runit). If the supervisor is not designed to act as a proper init process, child processes that exit leave zombie entries in the process table. Long-running containers accumulate zombies. On resource-constrained environments (ECS Fargate with small task sizes), this can eventually exhaust the PID namespace.

**Why it happens:**
Unix requires that a process's parent call `wait()` to reap its exit status, or PID 1 must act as the adoptive parent and reap orphaned processes. Many supervisors handle this correctly, but minimalist approaches (bash background jobs, `&` separated commands) do not. Running multiple `go run` or `node` processes in a bash script with `&` and `wait` is brittle.

**How to avoid:**
Either: (a) write a single binary that binds all 6 ports in goroutines/threads — no supervisor needed, the binary is PID 1 directly via exec form; or (b) use `--init` flag at runtime (`docker run --init`) or add `init: true` in docker-compose to insert `tini` as PID 1. If using supervisord, use the `nodaemon=true` and configure `pidfile` correctly. Preferred: single-binary approach eliminates the entire pitfall class.

**Warning signs:**
- `docker exec container ps aux` shows `<defunct>` processes
- Container memory/PID usage grows over time under load
- `docker stop` hangs or takes full grace period
- Supervisor process is PID 1 but shows no child reaping in logs

**Phase to address:** Core architecture decision (single binary vs supervisor) — must be resolved before Dockerfile authoring

---

### Pitfall 5: Kubernetes Probe Failures Due to Missing or Wrong Content-Type

**What goes wrong:**
Kubernetes HTTP liveness and readiness probes use `GET /` by default and succeed on any 2xx response — but some probe configurations or proxy layers inspect the `Content-Type` header. Returning a body without `Content-Type: application/json` causes certain ingress controllers (NGINX, Envoy) and health check aggregators to mark the response as an error. Additionally, if the JSON body contains a syntax error (truncated response during high load), any probe using response body validation will flip from healthy to unhealthy, triggering pod restarts.

**Why it happens:**
Developers focus on the HTTP status code and ignore headers. HTTP 200 with no `Content-Type` is technically valid but practically problematic with tools that auto-parse JSON.

**How to avoid:**
Always set `Content-Type: application/json` on every response. Ensure the JSON response is flushed atomically — write the complete response body before closing the connection. For the stub specifically, the response body (port, method, path, timestamp, query params) is small enough to buffer entirely in memory before writing; avoid streaming.

**Warning signs:**
- `curl -I localhost:8080/` shows no `Content-Type` header
- Ingress controller logs show unexpected content-type mismatches
- Health check aggregators report "unexpected content type"
- Pod restart loop even though `curl` returns HTTP 200

**Phase to address:** HTTP handler implementation phase

---

### Pitfall 6: Large Image Size From Wrong Base Image

**What goes wrong:**
Using `node:18`, `openjdk:17`, or `golang:1.22` as the final base image for a stub server adds 300–900MB of runtime tooling that serves no purpose. The stub does not need a language runtime in the final image if it compiles to a static binary, or can use a minimal runtime image. A 900MB image takes 30–90 seconds to pull in ECS cold starts, breaking SLA targets for infrastructure bootstrap.

**Why it happens:**
Developers copy a base image from the application they are stubbing. If stubbing a Spring Boot app, they reach for `openjdk`. The `FROM golang:1.22` image includes the full Go toolchain — appropriate for building, not for running.

**How to avoid:**
Use multi-stage builds: compile in a full SDK image, copy the binary to `scratch` (for fully static Go binaries) or `alpine:3` (if libc is needed). A Go static binary in `scratch` produces images under 10MB. If using a scripting language without compilation (Python, Node), use `-alpine` or `-slim` variants. Target image size: under 20MB.

**Warning signs:**
- `docker images swiss-knife-image` shows size over 100MB
- `FROM` line is a full SDK image (`golang:`, `node:`, `openjdk:`)
- No multi-stage build in Dockerfile
- ECS task launch takes over 30 seconds on cold start

**Phase to address:** Dockerfile authoring phase (base image selection)

---

### Pitfall 7: Port 80 Binding Requires Root or Kernel Capability

**What goes wrong:**
On Linux, binding to ports below 1024 (including port 80) requires `CAP_NET_BIND_SERVICE` or running as root. If the container runs as a non-root user (security best practice) without this capability, the server fails to bind port 80 at startup with `permission denied`, while all other ports (8080, 8081, 3000, 5000, 8181) bind successfully. This is silent in logs unless the error is explicitly handled — the container may appear to start normally.

**Why it happens:**
Developers test on Docker Desktop (Mac/Windows) where port binding restrictions are relaxed compared to Linux hosts. The container appears to work in local dev, then fails on Linux CI or ECS.

**How to avoid:**
Either: (a) run the container as root (acceptable for a stub/testing tool with no sensitive data); or (b) grant `CAP_NET_BIND_SERVICE` via `docker run --cap-add NET_BIND_SERVICE`; or (c) use `setcap cap_net_bind_service=+ep /server` in the Dockerfile. For a testing stub that poses no security risk, running as root is the pragmatic choice — document it explicitly. Do not silently omit port 80.

**Warning signs:**
- `curl localhost:80` fails but `curl localhost:8080` succeeds
- Container logs show `bind: permission denied` for port 80 only
- `docker run --user 1000:1000` causes port 80 to fail

**Phase to address:** Dockerfile authoring phase; verify in smoke-test phase

---

### Pitfall 8: docker-compose `ports` Short Syntax Binds to 0.0.0.0 (Unintended Host Exposure)

**What goes wrong:**
In docker-compose, `ports: - "8080:8080"` binds the host port to `0.0.0.0`, making it accessible on all network interfaces — including any externally reachable interface. On developer laptops connected to shared networks, or on cloud VMs without firewall rules, the stub server becomes publicly accessible. While a stub returning HTTP 200 is low-risk, this surprises teams and may trigger security scanners.

**Why it happens:**
The short port syntax is the most commonly documented form. The `127.0.0.1:8080:8080` form that binds only localhost is rarely shown in introductory examples.

**How to avoid:**
For local development use `127.0.0.1:8080:8080` (or `127.0.0.1` for each port) in docker-compose to restrict binding to localhost. For Kubernetes and ECS, this is irrelevant — port mapping is controlled by the orchestrator. Document both forms in the README: open binding for compose scenarios where the stub must be reachable from a connected device, localhost binding for isolated dev testing.

**Warning signs:**
- `netstat -an | grep LISTEN` shows `0.0.0.0:8080` on host
- Network scanner reports unexpected open ports on developer machine
- Colleagues on same network can reach the stub server

**Phase to address:** docker-compose integration phase

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Run multiple server processes with bash `&` | Simple to implement, no dependencies | No zombie reaping, fragile shutdown, hard to restart individual ports | Never — use a single binary instead |
| `FROM golang:1.22` as final image | Skips multi-stage build complexity | 900MB+ image, slow cold starts | Never for a published image |
| Shell form `CMD node server.js` | Familiar syntax | Breaks signal handling, 10s shutdown delay | Never |
| Omit `Content-Type: application/json` header | One fewer line of code | Breaks clients that auto-parse JSON, ingress validation failures | Never |
| Use `:latest` tag for base image | Always pulls newest | Non-reproducible builds, unexpected breakage after base image updates | Never for pinned production builds |
| Single-arch image build | Faster CI | Fails on arm64 (Apple Silicon) or amd64 (most CI) depending on where built | Only acceptable for local-only testing images |
| Pin to single static port instead of 6 | Simpler server code | Fails to replicate multi-port scaffolding patterns | Never — multi-port is the core requirement |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Kubernetes liveness probe | Probe path set to `/healthz` but server returns 404 on that path | Stub returns 200 on ALL paths; probe can use any path, but `/` is simplest |
| Kubernetes readiness probe | `initialDelaySeconds` too short; probe fires before server binds all 6 ports | Use `startupProbe` or set `initialDelaySeconds: 3` to give all ports time to bind |
| ECS health check | `command` array uses `curl` but `curl` is not installed in minimal image (`scratch`/`alpine`) | Either install `wget`/`curl` in image, or use TCP health check: `["CMD", "nc", "-z", "localhost", "8080"]` |
| ECS health check | `interval` default (30s) + `startPeriod` not set causes initial unhealthy state during cold start | Set `startPeriod: 10` to give the task time to start before health checks count against it |
| docker-compose service dependency | Another service uses `depends_on: swiss-knife-image` expecting it to be "ready" | Add `healthcheck` to the stub service in compose so `depends_on: condition: service_healthy` works |
| NGINX upstream proxy | NGINX `proxy_pass` to stub container fails if stub returns no `Content-Length` | Ensure server sets `Content-Length` or uses chunked transfer encoding; Go/Node HTTP servers do this automatically |
| CI/CD image push | `docker build && docker push` produces single-arch manifest | Use `docker buildx build --platform linux/amd64,linux/arm64 --push` in one command |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Logging every request to stdout synchronously | High-throughput load testing causes CPU bottleneck in logger, not server | Use buffered/async logging, or accept the limitation for a stub (load testing is not the use case) | Above ~10k req/s in load tests |
| Allocating new JSON encoder per request | Memory allocation spikes under test load | Use `json.Marshal` once with a fixed struct, or precompute static template with dynamic fields injected | Above ~1k req/s |
| Binding all ports in sequential blocking calls | First `Listen()` blocks; ports 2-6 never bind | Use goroutines per port (Go) or `Promise.all` (Node) to bind all ports concurrently | Immediately if server code is sequential |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Reflecting full request headers back in JSON response | Leaks internal proxy headers, auth tokens passed by mistake | Only reflect safe fields: port, method, path, timestamp, query params — never reflect headers |
| Running as root with no justification | Unnecessary privilege escalation; violates least-privilege | Run as root only if required for port 80 binding; document reason; consider `--cap-add NET_BIND_SERVICE` as alternative |
| No resource limits in docker-compose or ECS task definition | Stub gets starved under load or consumes host resources | Set `mem_limit: 64m` and `cpus: 0.25` in compose; set ECS task CPU/memory to minimal values (256 CPU units, 512MB) |
| Image published without digest pinning in consumer configs | Consumers silently pull updated image with different behavior | Publish with both `:latest` and a semver tag; consumers should pin to semver tag |

---

## "Looks Done But Isn't" Checklist

- [ ] **Multi-arch:** `docker buildx imagetools inspect` shows BOTH `linux/amd64` and `linux/arm64` manifests — not just one
- [ ] **All 6 ports:** `docker run` then `curl localhost:80`, `curl localhost:8080`, `curl localhost:8081`, `curl localhost:8181`, `curl localhost:3000`, `curl localhost:5000` all return HTTP 200
- [ ] **Deep paths:** `curl localhost:8080/.magnolia/admincentral` returns HTTP 200, not 404
- [ ] **Exec form:** `docker inspect image --format '{{json .Config.Cmd}}'` shows JSON array, not string
- [ ] **Signal handling:** `docker stop` completes in under 2 seconds (not 10s timeout)
- [ ] **Content-Type:** `curl -I localhost:8080/` shows `Content-Type: application/json`
- [ ] **JSON body:** Response body parses as valid JSON with keys: `port`, `method`, `path`, `timestamp`, `query`
- [ ] **Image size:** `docker images swiss-knife-image` shows under 20MB
- [ ] **Stdout logging:** `docker logs container` shows one log line per request
- [ ] **No zombies:** `docker exec container ps aux` shows no `<defunct>` processes after 60 seconds of operation
- [ ] **ECS health check:** Task reaches HEALTHY state, not UNHEALTHY, within 30 seconds of launch
- [ ] **Kubernetes probe:** Pod reaches Running/Ready state; no CrashLoopBackOff

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Published single-arch image | LOW | Rebuild with `docker buildx build --platform linux/amd64,linux/arm64 --push`; retag |
| Signal handling broken (shell form) | LOW | Change CMD/ENTRYPOINT to exec form; rebuild and push |
| Port 80 permission denied | LOW | Add `--cap-add NET_BIND_SERVICE` to run command, or accept root user in Dockerfile; rebuild |
| Image too large (wrong base) | MEDIUM | Rewrite Dockerfile with multi-stage build; rebuild and push; update all consumer references |
| Zombie process accumulation | MEDIUM | Switch to single-binary architecture (eliminates supervisor); rebuild; rolling restart in Kubernetes/ECS |
| Missing Content-Type header | LOW | Add header in HTTP handler; rebuild and push |
| Kubernetes probe CrashLoopBackOff | LOW | Verify all 6 ports bind before probe fires; add `initialDelaySeconds: 3`; check logs for bind errors |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Shell form CMD breaks signal handling | Phase 1: Dockerfile authoring | `docker stop` completes under 2s |
| Single-arch image | Phase 2: CI/CD pipeline setup | `docker buildx imagetools inspect` shows both archs |
| EXPOSE misconception / missing `-p` flags | Phase 1: Dockerfile authoring + README | All 6 ports reachable via `curl` after `docker run` |
| Zombie processes from multi-process design | Phase 1: Architecture decision (single binary) | `ps aux` shows no defunct processes |
| Missing Content-Type header | Phase 1: HTTP handler implementation | `curl -I` shows `Content-Type: application/json` |
| Wrong base image / large image | Phase 1: Dockerfile base image selection | `docker images` shows under 20MB |
| Port 80 CAP_NET_BIND_SERVICE | Phase 1: Dockerfile authoring | `curl localhost:80` returns 200 |
| docker-compose 0.0.0.0 exposure | Phase 3: docker-compose integration | `netstat` shows expected binding scope |
| ECS health check misconfiguration | Phase 4: ECS integration | ECS task reaches HEALTHY within 30s |
| Kubernetes probe failures | Phase 4: Kubernetes integration | Pod reaches Ready state; no CrashLoopBackOff |

---

## Sources

- Docker documentation — ENTRYPOINT exec vs shell form: https://docs.docker.com/reference/dockerfile/#entrypoint
- Docker documentation — EXPOSE instruction: https://docs.docker.com/reference/dockerfile/#expose
- Docker documentation — Multi-service containers and PID 1: https://docs.docker.com/engine/containers/multi-service_container/
- Docker documentation — Multi-platform builds: https://docs.docker.com/build/building/multi-platform/
- Docker documentation — Compose networking and port mapping: https://docs.docker.com/compose/how-tos/networking/
- Linux kernel documentation — CAP_NET_BIND_SERVICE for ports below 1024
- Domain expertise: ECS health check startPeriod, Kubernetes probe initialDelaySeconds, Content-Type header requirements for proxy compatibility

---
*Pitfalls research for: Docker stub/mock HTTP server image (swiss-knife-image)*
*Researched: 2026-03-25*
