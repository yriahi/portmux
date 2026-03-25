# Phase 2: Container and Distribution - Research

**Researched:** 2026-03-25
**Domain:** Docker multi-stage build, docker buildx multi-arch, GitHub Actions CI/CD, private Nexus registry push
**Confidence:** HIGH

## Summary

Phase 2 wraps the Phase 1 Go binary in a production-ready multi-stage Dockerfile, builds a manifest list covering `linux/amd64` and `linux/arm64` using `docker buildx`, and publishes to a private Nexus registry at `nexus.cainc.com:5000` via GitHub Actions. The stack is fully prescribed by CLAUDE.md and the locked CONTEXT.md decisions — no alternatives need evaluation. The primary research questions are the exact GitHub Actions action versions, correct cross-compilation pattern in the Dockerfile, registry login for a private Nexus host, exec-form ENTRYPOINT requirement, and the `docker/metadata-action` tag generation pattern.

The Go binary is already scratch-compatible (`CGO_ENABLED=0`, pure stdlib, no `go.sum`). The Dockerfile is the main new artifact. The GHA workflow is the second major artifact. Supporting files are `docker-compose.yml` and README additions.

**Primary recommendation:** Use `FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS build` with `ARG TARGETARCH` passed through to `go build` for native-speed cross-compilation. This avoids QEMU emulation entirely during the build step — the compiler runs natively on the GHA runner's AMD64 host and cross-compiles to ARM64 without emulation.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Registry: `nexus.cainc.com:5000` — private internal Nexus registry (not GHCR or Docker Hub)
- **D-02:** Image path: `nexus.cainc.com:5000/cainc/yriahi/swiss-army-image`
- **D-03:** CI authenticates via `NEXUS_USERNAME` and `NEXUS_PASSWORD` GitHub Actions secrets using `docker login`
- **D-04:** Tags: semver pushes produce `:v1.0.0` + `:latest`; push to `main` produces `:main`
- **D-05:** GitHub Actions builds and pushes on **both** push to `main` branch (`:main` tag) AND semver tags (`:v1.0.0` + `:latest`)
- **D-06:** Pull requests against `main` run the build step only — no push to Nexus
- **D-07:** Single-service topology in docker-compose — just the stub with all 6 ports mapped
- **D-08:** README scope: what the image does, `docker run` command with all 6 port flags, docker-compose snippet, sample JSON response body
- Dockerfile: Multi-stage `golang:1.26-alpine` builder → `FROM scratch` final stage
- Dockerfile: `CGO_ENABLED=0 GOOS=linux` static binary
- Dockerfile: `docker buildx` with `--platform linux/amd64,linux/arm64`
- Dockerfile: `TARGETARCH` injected by buildx, passed through to `go build`

### Claude's Discretion

- Exact GitHub Actions job/step structure (single job vs. separate build/push jobs)
- Whether to use `docker/build-push-action` or raw docker buildx commands in the workflow
- Dockerfile layer ordering and cache optimization

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CONT-01 | Dockerfile uses multi-stage build — Go binary compiled with CGO_ENABLED=0, final stage is FROM scratch (~5-8 MB image) | Multi-stage Dockerfile pattern with `FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS build` and `FROM scratch` final stage is documented and verified |
| CONT-02 | Image is built and published for both linux/amd64 and linux/arm64 architectures | `docker/build-push-action@v7` with `platforms: linux/amd64,linux/arm64` plus `docker/setup-buildx-action@v4` and `docker/setup-qemu-action@v4` is the current standard |
| CONT-03 | README includes a `docker run` command that maps all 6 ports in a single invocation | Straightforward documentation task; pattern is `docker run -p 80:80 -p 8080:8080 -p 8181:8181 -p 8081:8081 -p 3000:3000 -p 5000:5000` |
| DIST-01 | GitHub Actions workflow builds and pushes the image to a registry on push to main and on semver tags | GHA `on.push.branches` + `on.push.tags` with `v*.*.*` pattern; `push: true` in build-push-action only when not a PR |
| DIST-02 | Published image is tagged with semver (e.g., v1.0.0) and a mutable `latest` alias | `docker/metadata-action@v6` with `type=semver,pattern={{version}}` + `type=raw,value=latest,enable={{is_default_branch}}` + `type=ref,event=branch` |
| DIST-03 | Repository includes a `docker-compose.yml` example showing the image wired into a typical service stack | Single-service compose file with all 6 port mappings; confirmed shape in CONTEXT.md D-07 |
</phase_requirements>

## Standard Stack

### Core GitHub Actions

| Action | Version | Purpose | Why Standard |
|--------|---------|---------|--------------|
| `actions/checkout` | v4 | Checkout source code | Official; v4 is current stable (v6.0.2 also exists but v4 is widely used and stable) |
| `docker/login-action` | v4 | Authenticate to registry | Official Docker action; v4 is latest (released March 2025, Node 24 runtime) |
| `docker/setup-buildx-action` | v4 | Configure buildx builder | Official Docker action; v4 is latest (released March 2025) |
| `docker/setup-qemu-action` | v4 | Install QEMU for ARM emulation | Required for multi-arch builds on AMD64 runners — even with cross-compilation, buildx uses QEMU for the final image assembly step |
| `docker/build-push-action` | v7 | Build and push multi-arch image | Official Docker action; v7 is latest (released March 2025, Node 24 runtime) |
| `docker/metadata-action` | v6 | Generate Docker tags from git metadata | Official Docker action; v6 is latest; handles semver + latest + branch tagging automatically |

### Dockerfile Components

| Component | Value | Purpose |
|-----------|-------|---------|
| Builder base | `golang:1.26-alpine` | Go toolchain for compilation; alpine keeps builder layer fast |
| `--platform=$BUILDPLATFORM` | On builder stage | Pins builder to runner's native arch (AMD64); prevents emulation during compilation |
| `ARG TARGETARCH` | In builder stage | BuildKit injects the target arch; passed to `go build` as `GOARCH` |
| `CGO_ENABLED=0` | In `go build` | Forces fully static binary; required for `FROM scratch` compatibility |
| `GOOS=linux` | In `go build` | Ensures Linux binary from potentially non-Linux builder |
| Final base | `FROM scratch` | Zero OS overhead; only the binary lands in the final image (~5 MB total) |
| `ENTRYPOINT` form | Exec-form: `["./swiss-army-image"]` | Process becomes PID 1 and receives SIGTERM directly; shell-form wraps in `/bin/sh -c` and signals are NOT forwarded |

### Version Note

Action versions confirmed via GitHub releases pages (March 2026 check): `docker/login-action@v4`, `docker/setup-buildx-action@v4`, `docker/setup-qemu-action@v4`, `docker/build-push-action@v7`, `docker/metadata-action@v6`, `actions/checkout@v4` are all current stable.

## Architecture Patterns

### Recommended Project Structure

```
swiss-army-image/
├── Dockerfile                        # Multi-stage build
├── docker-compose.yml                # Usage example
├── README.md                         # Usage documentation
├── .github/
│   └── workflows/
│       └── build-push.yml            # CI/CD workflow
├── main.go                           # Existing
├── handler.go                        # Existing
└── go.mod                            # Existing
```

### Pattern 1: Dockerfile — Cross-Compilation with FROM scratch

**What:** Two-stage Dockerfile. Builder stage uses `FROM --platform=$BUILDPLATFORM` to run natively on the GHA runner, cross-compiles via `GOARCH=${TARGETARCH}`. Final stage copies only the binary into `FROM scratch`.

**When to use:** Always for this project. This is the only correct pattern when targeting `FROM scratch` with multi-arch.

**Example:**
```dockerfile
# Source: https://docs.docker.com/build/building/multi-platform/ (cross-compilation pattern)
FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS build

WORKDIR /src

# Copy go.mod first for layer caching — only invalidated when dependencies change.
# This project has no external dependencies so go.sum does not exist.
COPY go.mod ./
RUN go mod download

COPY *.go ./

ARG TARGETOS
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -o /swiss-army-image .

# ---

FROM scratch

COPY --from=build /swiss-army-image /swiss-army-image

# Exec-form: process is PID 1 and receives SIGTERM directly.
ENTRYPOINT ["/swiss-army-image"]
```

**Key details:**
- `go mod download` before `COPY *.go` — layer cache is reused if `go.mod` is unchanged
- `-trimpath` removes absolute build paths from the binary (reproducibility, smaller binary)
- No `EXPOSE` instruction is strictly required, but adding all 6 ports documents intent and is conventional
- No `USER` instruction — `FROM scratch` has no `/etc/passwd`; container runs as UID 0 inside the namespace, which is standard for scratch-based images with no privilege escalation risk at HTTP-only workloads

### Pattern 2: GitHub Actions Workflow — Single Job with Conditional Push

**What:** One job handles build and push. The `push` input to `build-push-action` is gated on `github.event_name != 'pull_request'`. PRs build only; main and tag pushes also push.

**When to use:** This is preferred over separate build/push jobs because it avoids pushing a build artifact between jobs and keeps the workflow simple. For this project's scale, a single job is correct.

**Example:**
```yaml
# Source: https://docs.docker.com/build/ci/github-actions/multi-platform/ (adapted)
name: Build and Push

on:
  push:
    branches:
      - main
    tags:
      - 'v*.*.*'
  pull_request:
    branches:
      - main

jobs:
  build-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Docker metadata
        id: meta
        uses: docker/metadata-action@v6
        with:
          images: nexus.cainc.com:5000/cainc/yriahi/swiss-army-image
          tags: |
            type=semver,pattern={{version}}
            type=raw,value=latest,enable={{is_default_branch}}
            type=ref,event=branch

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v4

      - name: Log in to Nexus
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v4
        with:
          registry: nexus.cainc.com:5000
          username: ${{ secrets.NEXUS_USERNAME }}
          password: ${{ secrets.NEXUS_PASSWORD }}

      - name: Build and push
        uses: docker/build-push-action@v7
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

**Tag behavior produced by `metadata-action`:**
- Push to `main` → `:main` + `:latest` (because `main` is the default branch)
- Push of `v1.0.0` tag → `:v1.0.0` + `:latest`
- Pull request → tags computed but `push: false` so nothing is pushed

**Cache note:** `cache-from/cache-to: type=gha` uses GitHub Actions cache for buildx layer caching. This significantly speeds up subsequent builds when only Go source files change (the `go mod download` layer is reused). This is the standard recommended approach for GHA workflows — no external cache registry needed.

### Pattern 3: docker-compose.yml

**What:** Single-service compose file per D-07. Uses the `latest` mutable tag.

```yaml
# Source: CONTEXT.md D-07 confirmed shape
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

### Anti-Patterns to Avoid

- **Shell-form ENTRYPOINT:** `ENTRYPOINT ./swiss-army-image` wraps in `/bin/sh -c` which is NOT present in `FROM scratch`. This will cause container startup to fail with "exec: no such file". Exec-form is the only valid form for scratch images.
- **Omitting `--platform=$BUILDPLATFORM` on builder stage:** Without this, buildx will run the builder stage under QEMU emulation for the ARM64 pass, making `go build` 5-10x slower. The cross-compilation pattern is always faster.
- **`go mod download` after source copy:** Copying all source before `go mod download` defeats layer caching — any source change invalidates the download layer. Copy `go.mod` (and `go.sum` if it existed) first.
- **`CGO_ENABLED=0` omitted:** The Go toolchain may link glibc by default on some paths. Without this flag, the binary will fail at runtime on `FROM scratch` with a missing library error.
- **Pushing on PRs from forks:** The `docker login` step must be conditional. Forks do not have access to `NEXUS_USERNAME`/`NEXUS_PASSWORD` secrets, and attempting login will fail the workflow. The `if: github.event_name != 'pull_request'` guard handles this.
- **Using `latest` as `TARGETARCH` source:** `TARGETARCH` is injected by buildx as `amd64` or `arm64` (not `linux/amd64`). Pass it directly as `GOARCH=${TARGETARCH}` — no parsing needed.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-arch tag generation | Custom bash to produce tag strings | `docker/metadata-action@v6` | Handles semver parsing, `latest` conditional on default branch, branch tags, and OCI labels automatically |
| Registry login in workflow | `run: echo $PASSWORD \| docker login` | `docker/login-action@v4` | Handles credential masking, registry URL, and logout on workflow completion |
| Buildx setup | `run: docker buildx create --use` | `docker/setup-buildx-action@v4` | Manages builder lifecycle, caching, and cleanup; raw commands leave dangling builders |
| Layer caching | None or S3/registry cache | `cache-from/cache-to: type=gha` | GHA cache is zero-config, free, and integrated; avoids needing a separate cache registry |
| QEMU installation | `run: apt-get install qemu-user-static` | `docker/setup-qemu-action@v4` | Official action handles binfmt registration correctly across runner environments |

**Key insight:** All five common CI/CD plumbing problems have official Docker GitHub Actions with maintained implementations. The workflow should be thin orchestration calling these actions — no custom shell scripts.

## Common Pitfalls

### Pitfall 1: Shell-Form ENTRYPOINT on FROM scratch

**What goes wrong:** Container fails to start with "exec format error" or "no such file or directory" for `/bin/sh`.
**Why it happens:** `FROM scratch` contains no shell. Shell-form `ENTRYPOINT app` expands to `["/bin/sh", "-c", "app"]`. There is no `/bin/sh` in scratch.
**How to avoid:** Always use exec-form: `ENTRYPOINT ["/swiss-army-image"]`. Verify in the Dockerfile — the JSON array syntax is the visual indicator.
**Warning signs:** `docker run` immediately exits with a non-zero code and "exec" error in `docker logs`.

### Pitfall 2: SIGTERM Not Received (2-second stop requirement fails)

**What goes wrong:** `docker stop` waits the full 10-second (default) timeout before sending SIGKILL, so the container takes 10+ seconds to stop rather than < 2 seconds.
**Why it happens:** Either (a) shell-form ENTRYPOINT wraps the binary in sh which does not forward signals, or (b) the Go binary is not PID 1. Both prevent SIGTERM from reaching `signal.NotifyContext`.
**How to avoid:** Exec-form ENTRYPOINT ensures the binary is PID 1. The existing `main.go` already uses `signal.NotifyContext` with `syscall.SIGTERM` and a 5-second shutdown timeout — the wiring is correct as long as ENTRYPOINT is exec-form.
**Warning signs:** `time docker stop <container>` takes > 2 seconds; container exits with code 137 (SIGKILL) rather than 0 or 143 (SIGTERM).

### Pitfall 3: Private Registry Requires Explicit `registry:` in login-action

**What goes wrong:** `docker/login-action` without a `registry:` input defaults to Docker Hub. The push fails with "unauthorized" against `nexus.cainc.com:5000`.
**Why it happens:** The action's default registry is `index.docker.io`.
**How to avoid:** Always specify `registry: nexus.cainc.com:5000` in the login step.
**Warning signs:** Login step succeeds (because it logged into Docker Hub) but the push step fails with 401/403 from Nexus.

### Pitfall 4: Nexus Registry Requires HTTP (not HTTPS)

**What goes wrong:** `docker push nexus.cainc.com:5000/...` fails with TLS handshake error or "http: server gave HTTP response to HTTPS client".
**Why it happens:** Nexus registries on port 5000 are often HTTP-only. Docker daemon defaults to HTTPS for all non-localhost registries.
**How to avoid:** If Nexus is HTTP-only, the GHA runner's Docker daemon must be configured to allow insecure registries. Add a daemon configuration step before the build, or confirm with the Nexus admin whether the registry uses HTTP or HTTPS.
**Warning signs:** Push fails during the workflow with TLS-related errors. This is a MEDIUM confidence concern — the actual Nexus configuration at `nexus.cainc.com:5000` is unknown and must be verified by the team.
**Mitigation in plan:** Include a step to verify Nexus HTTP vs HTTPS before finalizing the workflow.

### Pitfall 5: go.mod Download Layer Cache Miss

**What goes wrong:** Every source file change rebuilds the `go mod download` layer, adding unnecessary download time (even though this project has no external dependencies, the pattern matters for correctness).
**Why it happens:** `COPY . .` before `RUN go mod download` means any file change invalidates the download cache.
**How to avoid:** Copy `go.mod` first, run `go mod download`, then copy source files. Since this project has zero external dependencies, `go mod download` is a no-op — but the layer ordering is still correct practice.

### Pitfall 6: `TARGETARCH` vs `BUILDPLATFORM` Confusion

**What goes wrong:** Binary is compiled for the wrong architecture, producing a manifest where both platforms contain the amd64 binary.
**Why it happens:** Omitting `ARG TARGETARCH` in the builder stage means the variable is not available to the `RUN` command, so `GOARCH=${TARGETARCH}` silently evaluates to `GOARCH=` (empty), defaulting to the builder's native arch (amd64) for both passes.
**How to avoid:** Always declare `ARG TARGETOS` and `ARG TARGETARCH` after the `FROM` line in the builder stage. BuildKit injects these only after they are declared.
**Warning signs:** `docker buildx imagetools inspect` shows both manifests but both report the same architecture binary (verifiable with `file` on an extracted binary).

## Code Examples

Verified patterns from official sources:

### Complete Dockerfile
```dockerfile
# Source: https://docs.docker.com/build/building/multi-platform/ (cross-compilation)
# and CLAUDE.md stack specification
FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS build

WORKDIR /src

COPY go.mod ./
RUN go mod download

COPY *.go ./

ARG TARGETOS
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -o /swiss-army-image .

FROM scratch

EXPOSE 80 8080 8181 8081 3000 5000

COPY --from=build /swiss-army-image /swiss-army-image

ENTRYPOINT ["/swiss-army-image"]
```

### GitHub Actions on: trigger block
```yaml
# Source: https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow
on:
  push:
    branches:
      - main
    tags:
      - 'v*.*.*'
  pull_request:
    branches:
      - main
```

### metadata-action tags producing semver + latest + branch
```yaml
# Source: https://github.com/docker/metadata-action#tags-input
- name: Docker metadata
  id: meta
  uses: docker/metadata-action@v6
  with:
    images: nexus.cainc.com:5000/cainc/yriahi/swiss-army-image
    tags: |
      type=semver,pattern={{version}}
      type=raw,value=latest,enable={{is_default_branch}}
      type=ref,event=branch
```

Produces on semver tag push (`v1.0.0`):
- `nexus.cainc.com:5000/cainc/yriahi/swiss-army-image:v1.0.0`
- `nexus.cainc.com:5000/cainc/yriahi/swiss-army-image:latest`

Produces on push to `main`:
- `nexus.cainc.com:5000/cainc/yriahi/swiss-army-image:main`
- `nexus.cainc.com:5000/cainc/yriahi/swiss-army-image:latest`

### Conditional push (no push on PRs)
```yaml
# Source: https://docs.docker.com/build/ci/github-actions/multi-platform/
- name: Build and push
  uses: docker/build-push-action@v7
  with:
    context: .
    platforms: linux/amd64,linux/arm64
    push: ${{ github.event_name != 'pull_request' }}
    tags: ${{ steps.meta.outputs.tags }}
    labels: ${{ steps.meta.outputs.labels }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

### docker run command (README content)
```bash
docker run \
  -p 80:80 \
  -p 8080:8080 \
  -p 8181:8181 \
  -p 8081:8081 \
  -p 3000:3000 \
  -p 5000:5000 \
  nexus.cainc.com:5000/cainc/yriahi/swiss-army-image:latest
```

### Sample JSON response body (README content, from Phase 1 D-01 to D-03)
```json
{
  "port": 8080,
  "method": "GET",
  "path": "/",
  "timestamp": "2026-03-25T12:00:00Z",
  "query_params": {}
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `docker/build-push-action@v5/v6` | `v7` | March 2025 | Node 24 runtime; v3-era deprecated env vars removed; ESM |
| `docker/login-action@v3` | `v4` | March 2025 | Node 24 runtime; ESM |
| `docker/setup-buildx-action@v3` | `v4` | March 2025 | Node 24 runtime; deprecated inputs removed |
| `docker/metadata-action@v5` | `v6` | March 2025 | Node 24 runtime; ESM |
| Raw `docker buildx build` in workflow | `docker/build-push-action@v7` | Ongoing standard | Official action handles provenance attestations, SBOM, caching automatically |
| `FROM golang:1.26-alpine` (single-stage) | Multi-stage with `FROM scratch` | Established pattern | ~800 MB builder → ~5 MB final image |

**Deprecated/outdated:**
- `docker/build-push-action@v5` and earlier: Use v7. The Node 20 → 24 upgrade broke backward compat for some deprecated inputs. Pin to v7 for all new workflows.
- Shell-form `ENTRYPOINT`: Functionally incorrect for `FROM scratch` images. Always exec-form.

## Open Questions

1. **Nexus HTTP vs HTTPS**
   - What we know: Registry is `nexus.cainc.com:5000`; port 5000 is commonly HTTP for internal Nexus instances
   - What's unclear: Whether this Nexus instance uses a self-signed TLS cert, a CA-signed cert, or plain HTTP
   - Recommendation: The plan should include a verification step (e.g., `curl -v https://nexus.cainc.com:5000/v2/` locally before the workflow runs). If HTTP-only, the GHA workflow needs a daemon.json step to add `nexus.cainc.com:5000` to `insecure-registries`. This is a LOW confidence area — requires human verification.

2. **Port 80 in container vs. host mapping**
   - What we know: The Go binary attempts port 80 bind non-fatally; Docker `-p 80:80` maps host:container — root is NOT required on the host
   - What's unclear: Whether the GHA workflow should include a smoke test (`docker run` + `curl`) to verify the image before pushing
   - Recommendation: A simple smoke test (run image locally in the CI job, curl port 8080, check for HTTP 200) is a low-cost quality gate. Leave to planner's discretion since this was not discussed.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Docker | Dockerfile build + compose | Yes | 29.3.0 (local) | — |
| docker buildx | Multi-arch build | Yes | 0.32.1 (local) | — |
| GitHub Actions runners (ubuntu-latest) | CI/CD workflow | Assumed available | ubuntu-latest (GitHub managed) | — |
| Nexus registry at nexus.cainc.com:5000 | Push target | Unknown | Unknown | Cannot push; blocks DIST-01, DIST-02 |
| `NEXUS_USERNAME` / `NEXUS_PASSWORD` secrets | GHA auth | Unknown | — | Cannot push without credentials |
| git | Repo tagging, GHA trigger | Yes | 2.51.1 (local) | — |

**Missing dependencies with no fallback:**
- Nexus registry accessibility from GHA runners — must be confirmed by the team (is the registry reachable from the public internet or only via VPN/private network?)
- GitHub Actions secrets `NEXUS_USERNAME` / `NEXUS_PASSWORD` — must be configured in the repository settings before the push workflow can function

**Missing dependencies with fallback:**
- None identified

## Sources

### Primary (HIGH confidence)
- https://docs.docker.com/build/building/multi-platform/ — Cross-compilation pattern with `$BUILDPLATFORM` / `$TARGETARCH`; `FROM scratch` compatibility
- https://docs.docker.com/build/ci/github-actions/multi-platform/ — Full GHA workflow with `setup-qemu-action`, `setup-buildx-action`, `build-push-action`
- https://docs.docker.com/reference/dockerfile/#entrypoint — Exec-form vs shell-form signal handling; PID 1 behavior
- https://github.com/docker/build-push-action/releases — v7 confirmed latest (March 2025)
- https://github.com/docker/login-action/releases — v4 confirmed latest (March 2025)
- https://github.com/docker/setup-buildx-action/releases — v4 confirmed latest (March 2025)
- https://github.com/docker/metadata-action/releases — v6 confirmed latest (March 2025); tag type=semver, type=raw, type=ref patterns verified
- https://github.com/actions/checkout/releases — v4 current stable (v6.0.2 also available)
- CLAUDE.md — Prescribed stack (Go 1.26.1, FROM scratch, CGO_ENABLED=0, docker buildx, golang:1.26-alpine builder); verified against existing source

### Secondary (MEDIUM confidence)
- https://github.com/docker/metadata-action#tags-input — `type=semver,pattern={{version}}` + `type=raw,value=latest,enable={{is_default_branch}}` + `type=ref,event=branch` tag pattern; verified against releases page
- https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow — `on.push.tags: v*.*.*` semver pattern; branches + tags combination

### Tertiary (LOW confidence)
- Nexus HTTP/HTTPS behavior — inferred from common port 5000 conventions; unverified against actual nexus.cainc.com:5000 instance; requires team confirmation

## Metadata

**Confidence breakdown:**
- Standard stack (actions versions): HIGH — verified against GitHub releases pages March 2026
- Dockerfile patterns: HIGH — verified against official Docker multi-platform docs
- GHA workflow structure: HIGH — verified against official Docker GHA docs
- metadata-action tag generation: HIGH — verified against action README and releases
- Nexus HTTP/HTTPS: LOW — unverified; blocking concern if HTTP-only

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (stable tooling; action major versions rarely change within 30 days)
