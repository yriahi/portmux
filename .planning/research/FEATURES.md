# Feature Research

**Domain:** Docker stub/catch-all HTTP server image
**Researched:** 2026-03-25
**Confidence:** HIGH (multiple authoritative sources: wiremock-docker, traefik/whoami, mendhak/http-https-echo, nicholasjackson/fake-service, hashicorp/http-echo cross-referenced)

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Catch-all routing (any path returns 200) | Core contract of a stub — no 404s, no routing config required | LOW | Every stub tool surveyed (whoami, http-echo, http-https-echo) defaults to this; any other behavior breaks the use case |
| JSON response body with request metadata | Users need to confirm which port/path was hit; plain-text or empty 200 is not debuggable | LOW | traefik/whoami, mendhak/http-https-echo both echo method, path, headers, IP; json is the de facto format |
| stdout request logging | Scaffolding validation requires `docker logs` to show what hit the container | LOW | All surveyed tools emit per-request logs; absence means no debugging story |
| Multi-architecture image (linux/amd64 + linux/arm64) | Apple Silicon is ubiquitous in dev; CI/CD typically amd64; image unusable on one or the other without this | MEDIUM | WireMock, mendhak/http-https-echo, traefik/whoami all publish multi-arch; Docker Engine 29+ makes buildx/buildkit the standard path; single-arch images are a user friction point in 2025 |
| Single `docker run` invocation | Users expect to be up in one command with no volume mounts or config files | LOW | hashicorp/http-echo, traefik/whoami both prioritize zero-config startup |
| Multiple simultaneous port binding | This project's unique constraint: replaces containers for Node.js (3000, 5000), Java (8080, 8181, 8081), and web (80); single-port stubs can't cover multi-framework scaffolding | HIGH | Most stub tools bind one port; multi-port is the differentiating requirement here but is also table stakes for this project's stated purpose — without it the image doesn't fulfill its core contract |
| Docker Compose example/documentation | Compose is the dominant local multi-service orchestration format; users expect a working `docker-compose.yml` snippet | LOW | mendhak/http-https-echo, WireMock all provide Compose examples; absence creates friction |
| HTTP 200 for all HTTP methods (GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS) | Proxy and load balancer health checks may use HEAD; API scaffolds use all methods | LOW | Standard for catch-all stubs; method-specific routing adds complexity users don't want in a stub |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Response body includes port number | When a container binds multiple ports, knowing which port was hit is uniquely useful; no other multi-port stub tool surfaces this clearly | LOW | Requires the server process to know its own listening port per connection; straightforward in most runtimes |
| Response body includes query parameters | Allows scaffolding tests to assert that query strings pass through proxies and load balancers correctly | LOW | traefik/whoami supports `?wait=` but doesn't echo arbitrary query params back; easy add |
| Named Kubernetes/ECS probe compatibility out of the box | Any path returns 200, so liveness/readiness probes work with zero configuration; worth documenting explicitly | LOW (impl), MEDIUM (docs) | Kubernetes probes accept any 200-399; the catch-all means no `/healthz` endpoint is needed, but this needs to be called out clearly in docs |
| Delay injection via query parameter (`?delay=500ms`) | Allows testing timeout behavior in proxies and clients without modifying the image | LOW | traefik/whoami supports `?wait=` for this; mendhak supports `x-set-response-delay-ms` header; query param is the most discoverable form |
| CORS headers on all responses | Removes friction for browser-based scaffold testing (React/Next.js dev proxies hitting the stub directly) | LOW | fake-service supports CORS config; a single permissive `Access-Control-Allow-Origin: *` default covers most cases |
| Configurable response status code via query parameter (`?status=503`) | Lets scaffold tests verify error-handling paths without a separate image | LOW | mendhak supports this via header; query param is zero-config from the client side |
| Timestamp in response body (ISO 8601) | Allows latency measurement and ordering verification in multi-request scaffolding tests | LOW | Most stubs include timestamps; worth including explicitly |
| Small image size (under 20 MB compressed) | Faster pulls in CI/CD; lower storage cost; signals engineering quality | MEDIUM | Depends on runtime choice (Go or Node Alpine); traefik/whoami is ~10 MB; mendhak/http-https-echo is ~50 MB (Node); Go is the clear winner here |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| HTTPS/TLS support | Real apps serve HTTPS; some probes use HTTPS | Requires certificate management, introduces cert expiry issues, complicates `docker run` UX, and adds no value for scaffolding validation (which is about topology not encryption) | Document that HTTPS termination belongs in the load balancer/ingress layer, not the stub; keep the stub HTTP-only |
| Request body parsing and storage | Users want to inspect POST bodies | Makes the image stateful, complicates memory management, introduces security surface; the JSON response already confirms the request arrived | Echo the `Content-Type` and `Content-Length` headers in the response body — sufficient for scaffolding validation |
| Scriptable/file-based response rules (WireMock-style) | "Can I return different responses per path?" | Scope creep; turns a stub into a mock framework; users who need this should use WireMock or MockServer | Recommend WireMock Docker image for teams needing rule-based mocking; keep this image as a zero-config catch-all |
| Admin API to update responses at runtime | "Can I change the response without restarting?" | Same as above; adds runtime state and HTTP surface area that conflicts with the "drop-in stub" contract | Stateless by design; restart the container to change behavior |
| Request body echoed in response | Users want full round-trip logging | Can expose sensitive data in logs/responses in shared environments; request bodies may be large (file uploads) causing memory pressure | Log `Content-Type` and `Content-Length` only; recommend proper mock frameworks for body inspection |
| Metrics/Prometheus endpoint | "I want to count requests" | Adds ~5-10 MB of dependencies, a separate port, and complexity; the use case is scaffolding not observability | stdout logging provides sufficient signal for scaffolding tests; use a real observability stack for production concerns |
| Authentication simulation | "Can it return 401 for some paths?" | Requires routing logic, which contradicts the catch-all contract | Use a dedicated auth-aware stub (MockServer, WireMock) if auth flow testing is needed |

## Feature Dependencies

```
[Multi-port binding]
    └──enables──> [Per-port metadata in response body]
                      └──requires──> [JSON response body]

[JSON response body]
    └──includes──> [port, method, path, timestamp, query params]

[Delay injection via query param]
    └──enhances──> [Proxy/LB timeout testing]

[Catch-all routing]
    └──enables──> [Kubernetes/ECS probe compatibility]
    └──enables──> [Zero-config startup]

[Multi-arch image]
    └──requires──> [buildx + buildkit in CI]

[CORS headers]
    └──enhances──> [Browser-based scaffold testing]

[Configurable status code via query param]
    └──conflicts──> [Catch-all always returns 200]
        (resolution: catch-all is the default; status override is opt-in per request)
```

### Dependency Notes

- **Multi-port binding requires per-port metadata in response body:** The only reason to bind multiple ports is framework simulation; without the port number in the response, users cannot confirm which port was hit and the multi-port feature loses its debugging value.
- **Catch-all routing enables Kubernetes probe compatibility:** Any path returning 200 means liveness and readiness probes work without configuration. This is a zero-cost benefit that needs explicit documentation.
- **Configurable status code conflicts with catch-all always returns 200:** Resolve by making `?status=` an opt-in override. Default is still 200; the override enables error path testing. This does not break the catch-all contract — the path still matches.
- **Multi-arch image requires buildx in CI:** GitHub Actions' `docker/setup-buildx-action` + `docker/build-push-action` is the standard path. Must be set up early in CI/CD pipeline design.

## MVP Definition

### Launch With (v1)

Minimum viable product — what's needed to validate the concept.

- [ ] Simultaneous binding on ports 80, 8080, 8181, 8081, 3000, 5000 — the core contract; without this the image is not distinct from any single-port stub
- [ ] Any HTTP method on any path returns HTTP 200 JSON — catch-all is the entire value proposition
- [ ] JSON response body containing: port, method, path, timestamp, query params — makes it debuggable and distinguishable from a blank 200
- [ ] stdout request logging (port, method, path, timestamp) — required for `docker logs` workflow; zero value without this
- [ ] linux/amd64 + linux/arm64 multi-arch image published — must work on Apple Silicon dev machines and amd64 CI; a single-arch image will receive immediate friction reports
- [ ] Single `docker run` zero-config invocation — published image, no volume mounts, no environment variables required
- [ ] Docker Compose example in README — minimum documentation for the primary use case

### Add After Validation (v1.x)

Features to add once core is working.

- [ ] Delay injection via `?delay=` query param — add when users report timeout testing needs; LOW complexity, HIGH value
- [ ] CORS headers on all responses — add when browser-based scaffold testing is confirmed as a use case
- [ ] Configurable status code via `?status=` query param — add when error path testing is confirmed as a use case
- [ ] Kubernetes liveness/readiness probe documentation and examples — add after core image validates; LOW complexity, HIGH discoverability value

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] Additional ports beyond the current 6 — defer; add only if specific frameworks are requested with evidence
- [ ] Environment variable to customize which ports are bound — defer; complicates the "drop-in stub" contract; adds configuration surface area
- [ ] Response body size configuration (`?size=`) — defer; traefik/whoami has this; only useful for bandwidth testing which is niche

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Multi-port binding (80, 8080, 8181, 8081, 3000, 5000) | HIGH | MEDIUM | P1 |
| Catch-all routing (any path, any method → 200) | HIGH | LOW | P1 |
| JSON response body (port, method, path, timestamp, query) | HIGH | LOW | P1 |
| stdout request logging | HIGH | LOW | P1 |
| Multi-arch image (amd64 + arm64) | HIGH | MEDIUM | P1 |
| Single `docker run` invocation | HIGH | LOW | P1 |
| Docker Compose example | MEDIUM | LOW | P1 |
| Delay injection via `?delay=` | MEDIUM | LOW | P2 |
| CORS headers on all responses | MEDIUM | LOW | P2 |
| Configurable status code via `?status=` | MEDIUM | LOW | P2 |
| Kubernetes/ECS probe documentation | HIGH | LOW | P2 |
| Small image size (< 20 MB) | MEDIUM | MEDIUM | P2 |
| Additional framework ports | LOW | LOW | P3 |
| Configurable port list via env var | LOW | MEDIUM | P3 |
| Response body size configuration | LOW | LOW | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | traefik/whoami | mendhak/http-https-echo | nicholasjackson/fake-service | hashicorp/http-echo | Swiss Army Image |
|---------|---------------|------------------------|------------------------------|---------------------|-----------------|
| Catch-all routing | Yes | Yes | Yes | Yes (single text response) | Yes |
| Multi-port binding | No (single port) | No (HTTP + HTTPS only) | No (single port) | No (single port) | Yes — core feature |
| JSON response with request metadata | Partial (text + JSON endpoint) | Yes | Yes | No | Yes |
| stdout logging | Yes (verbose flag) | Yes | Yes (structured) | Yes | Yes |
| Delay injection | Yes (`?wait=`) | Yes (header) | Yes (error type) | No | Yes (`?delay=`) |
| CORS headers | No | Yes (env var) | Yes (env var) | No | Yes (default permissive) |
| Multi-arch (amd64 + arm64) | Yes | Yes | No (amd64 only) | No | Yes |
| Health check endpoint | Yes (`/health`) | Yes (`/metrics`) | Yes (`/health`, `/ready`) | No | Not needed (catch-all) |
| Response status override | Via `/health` POST | Yes (header) | Via error rate | No | Yes (`?status=`) |
| Image size | ~10 MB (Go) | ~50 MB (Node) | ~20 MB (Go) | ~5 MB (Go) | Target < 20 MB |
| Zero-config startup | Yes | Yes | Yes | Yes | Yes |

## Sources

- traefik/whoami GitHub repository (HIGH confidence — official source, directly read)
- mendhak/docker-http-https-echo GitHub repository + README (HIGH confidence — directly read)
- nicholasjackson/fake-service GitHub README (HIGH confidence — directly read)
- wiremock/wiremock-docker GitHub repository (HIGH confidence — directly read)
- hashicorp/http-echo GitHub repository (HIGH confidence — directly read)
- mock-server/mockserver GitHub repository (MEDIUM confidence — top-level repo read)
- Docker multi-platform build documentation (HIGH confidence — official Docker docs)
- Kubernetes HTTP probe source code (HIGH confidence — official k8s source)
- PROJECT.md requirements (authoritative for this project's constraints)

---
*Feature research for: Docker stub/catch-all HTTP server image*
*Researched: 2026-03-25*
