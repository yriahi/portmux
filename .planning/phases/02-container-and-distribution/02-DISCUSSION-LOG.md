# Phase 2: Container and Distribution - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 02-container-and-distribution
**Areas discussed:** Registry target, docker-compose shape, README scope, CI/CD build triggers

---

## Registry Target

| Option | Description | Selected |
|--------|-------------|----------|
| GHCR | GitHub Container Registry — public, free, tied to GitHub account | |
| Docker Hub | Public registry — most discoverable, rate-limited pulls | |
| Private Nexus | Internal Nexus registry at nexus.cainc.com:5000 | ✓ |

**User's choice:** Private Nexus registry — `nexus.cainc.com:5000/cainc/yriahi/swiss-army-image`
**Notes:** User specified image path format `cainc/yriahi/swiss-army-image:1.0.0` and hostname `nexus.cainc.com:5000`. CI auth via `NEXUS_USERNAME` + `NEXUS_PASSWORD` secrets.

---

## docker-compose Shape

| Option | Description | Selected |
|--------|-------------|----------|
| Single stub, all ports mapped | Just the swiss-army-image service with all 6 ports | ✓ |
| Multi-service: stub + real app | Stub wired alongside a frontend or backend service | |

**User's choice:** Single-service, all 6 ports mapped
**Notes:** Keeps the example universal — no assumptions about what the stub is replacing.

---

## README Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal — just docker run | Single docker run command with all 6 port flags | |
| Standard — run + compose + what it does | What-it-does section, docker run, compose snippet, sample JSON response | ✓ |

**User's choice:** Standard scope
**Notes:** README should include: what the image does, docker run command, docker-compose snippet, and a sample curl/response showing the JSON body.

---

## CI/CD Build Triggers

| Option | Description | Selected |
|--------|-------------|----------|
| Tags only | Build + push only on semver tags; PRs run tests only | |
| Main branch + tags | Push on every commit to main (:main tag) AND semver tags (:v1.0.0 + :latest) | ✓ |

**User's choice:** Main branch + tags
**Notes:** Push to main produces `:main` tag in Nexus. Semver tags produce `:v1.0.0` + `:latest`. PRs build but do not push.

---

## Claude's Discretion

- GitHub Actions job/step structure (single job vs. separate build/push jobs)
- Whether to use `docker/build-push-action` or raw `docker buildx` commands
- Dockerfile layer ordering and build cache optimization

## Deferred Ideas

None — discussion stayed within phase scope.
