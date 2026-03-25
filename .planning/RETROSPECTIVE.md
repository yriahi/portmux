# Retrospective: Swiss Army Image

Living retrospective — one section per milestone.

---

## Milestone: v1.0 — MVP

**Shipped:** 2026-03-25
**Phases:** 3 | **Plans:** 4 | **Tasks:** 8

### What Was Built

- Go binary binding 12 ports simultaneously via goroutine-per-port with net/http stdlib, slog JSON logging, graceful SIGTERM shutdown
- Multi-stage Dockerfile (golang:1.26-alpine → FROM scratch, ~5 MB) with linux/amd64 + linux/arm64 support
- GitHub Actions CI/CD pipeline publishing to Nexus on push to main and semver tags
- docker-compose.yml and README with complete usage documentation
- Delay injection (?delay=<ms>) and status code override (?status=<code>) with 40-test integration suite

### What Worked

- **goroutine-per-port pattern** — net.Listen pre-flight + srv.Serve(ln) in goroutine was clean and handled port 80 non-fatal bind failures elegantly
- **Go stdlib only** — no external deps meant zero go.sum, no module issues, trivial cross-compilation
- **FROM scratch final stage** — forced clarity on exec-form ENTRYPOINT requirement; once understood, straightforward
- **inline parse-and-validate** — ~10 lines each for delay and status params, readable without abstraction
- **Integration tests in test.sh** — fast feedback, caught curl -sf gotcha before it could hide issues in CI

### What Was Inefficient

- Phase 1 ROADMAP.md checkbox was not updated to `[x]` after completion (tooling gap — disk_status was correct but roadmap_complete=false)
- No milestone audit performed before completion — gaps check was skipped

### Patterns Established

- `curl -s` (not `-sf`) for non-2xx HTTP status assertions — `-f` exit code interferes with `%{http_code}` capture
- `PASS=$((PASS + 1))` pattern over `((PASS++))` in bash `set -e` scripts — arithmetic increment is falsy at 0
- `resolvedStatus` variable pattern for parameterized `WriteHeader` calls
- `FROM --platform=$BUILDPLATFORM` on builder stage for native-speed cross-compilation in GHA

### Key Lessons

- Port 80 bind failure on non-root dev machines is expected — design for non-fatal from the start
- exec-form ENTRYPOINT is not optional for FROM scratch images — document this prominently
- `docker-compose.yml` with no `version:` key is correct for Docker Compose v2+ — avoid adding it

### Cost Observations

- Model mix: sonnet (primary)
- Sessions: 1 day, multiple quick tasks
- Notable: All 3 phases + 2 quick tasks completed in a single day; Go stdlib approach minimized research overhead

---

## Cross-Milestone Trends

| Metric | v1.0 |
|--------|------|
| Phases | 3 |
| Plans | 4 |
| Timeline | 1 day |
| Test coverage | 40 integration tests |
| Image size | ~5 MB |
| External deps | 0 |
