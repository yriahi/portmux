---
phase: 01-core-server-binary
plan: 01
subsystem: infra
tags: [go, net/http, slog, multi-port, graceful-shutdown, json]

# Dependency graph
requires: []
provides:
  - Go module (go.mod) with no external dependencies
  - handler.go: Response struct with json tags, makeHandler closure-based HTTP handler factory
  - main.go: net.Listen pre-flight, goroutine-per-port HTTP servers, slog JSON logging, SIGTERM graceful shutdown
  - test.sh: integration smoke test (24 assertions, all passing)
affects: [02-docker-image]

# Tech tracking
tech-stack:
  added:
    - Go 1.21 stdlib (net/http, log/slog, encoding/json, os/signal, sync, net)
  patterns:
    - goroutine-per-port via net.Listen pre-flight + srv.Serve(ln)
    - makeHandler closure captures port int — avoids runtime port parsing
    - signal.NotifyContext + sync.WaitGroup for SIGTERM graceful shutdown with 5s timeout
    - slog.NewJSONHandler(os.Stdout, nil) as default structured JSON logger

key-files:
  created:
    - go.mod
    - main.go
    - handler.go
    - test.sh
  modified: []

key-decisions:
  - "net.Listen pre-flight used for accurate startup banner (activePorts only lists ports that actually bound)"
  - "go 1.21 minimum in go.mod for log/slog availability; local toolchain is 1.25.0"
  - "Port 80 bind failure is non-fatal and logged as 'bind failed (non-fatal)'; other ports also non-fatal but logged differently"
  - "makeHandler closure-based factory avoids runtime port parsing from r.Host"
  - "Content-Type set before WriteHeader to prevent silent header suppression"

patterns-established:
  - "goroutine-per-port: net.Listen pre-flight then srv.Serve(ln) in goroutine"
  - "All server goroutines avoid log.Fatal/os.Exit — errors are logged, not fatal"
  - "Per-server http.NewServeMux() isolates handlers across ports"

requirements-completed: [SRVR-01, SRVR-02, SRVR-03, RESP-01, RESP-02, RESP-03, LOG-01, LOG-02]

# Metrics
duration: 8min
completed: 2026-03-25
---

# Phase 1 Plan 01: Core Server Binary Summary

**Go binary binding 6 ports simultaneously via goroutine-per-port with net/http stdlib, slog JSON logging, and graceful SIGTERM shutdown — 24 integration tests passing**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-03-25T20:45:13Z
- **Completed:** 2026-03-25T20:53:00Z
- **Tasks:** 2 of 2
- **Files modified:** 4

## Accomplishments

- Multi-port Go binary binds ports 80, 8080, 8181, 8081, 3000, and 5000 simultaneously in a single process using goroutine-per-port pattern
- Every HTTP request on any path and any method returns HTTP 200 with Content-Type: application/json and a JSON body containing port (int), method, path, timestamp (RFC3339), and query_params (map)
- Structured JSON logging via log/slog: startup banner listing bound ports + per-request log with port/method/path/remote
- SIGTERM triggers clean shutdown within 5 seconds via signal.NotifyContext + sync.WaitGroup
- Integration smoke test (test.sh) validates all requirements with 24 assertions, all passing

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Go module and implement server binary** - `798f253` (feat)
2. **Task 2: Create automated integration smoke test** - `39e8ff9` (feat)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `go.mod` - Module declaration: `module swiss-army-image`, `go 1.21`, no external deps
- `handler.go` - Response struct with json tags, makeHandler closure factory, correct header-before-WriteHeader ordering
- `main.go` - Entry point: logger init, net.Listen pre-flight per port, goroutine-per-port, startup banner, SIGTERM shutdown
- `test.sh` - Executable integration smoke test: 24 assertions across 6 test categories

## Decisions Made

- Used net.Listen pre-flight (not ListenAndServe in goroutine) so the startup banner only lists ports that actually bound — this is the recommended approach from research
- Set go 1.21 in go.mod as minimum (log/slog availability); local toolchain is 1.25.0 — no conflict
- Port 80 bind failure is non-fatal per D-04, logged with distinct "bind failed (non-fatal)" message; other port failures are also non-fatal but logged without the "(non-fatal)" qualifier
- makeHandler uses closure over `port int` — avoids runtime parsing of r.Host per the "Don't Hand-Roll" research guidance

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed bash arithmetic increment causing set -e abort in test.sh**
- **Found during:** Task 2 (running test.sh)
- **Issue:** `((PASS++))` and `((FAIL++))` in bash with `set -e` abort the script when PASS=0 because `((0))` returns exit code 1 (false in arithmetic context)
- **Fix:** Changed to `PASS=$((PASS + 1))` and `FAIL=$((FAIL + 1))` — safe arithmetic assignment pattern
- **Files modified:** test.sh
- **Verification:** bash test.sh exits 0 with 24/24 tests passing
- **Committed in:** 39e8ff9 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug in test script arithmetic)
**Impact on plan:** Required for test.sh to run at all. Fix is idiomatic bash. No scope creep.

## Issues Encountered

- First test.sh run aborted after first PASS assertion due to `((PASS++))` bash `set -e` interaction — diagnosed immediately and fixed inline per Rule 1

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Go binary is complete and all 8 requirements (SRVR-01 through LOG-02) are satisfied
- Binary uses only stdlib, compiles with CGO_ENABLED=0 for scratch image compatibility (Phase 2)
- Phase 2 can wrap this binary in a multi-stage Dockerfile using golang:1.26-alpine builder + FROM scratch final stage

---
*Phase: 01-core-server-binary*
*Completed: 2026-03-25*

## Self-Check: PASSED

- FOUND: go.mod
- FOUND: main.go
- FOUND: handler.go
- FOUND: test.sh
- FOUND: .planning/phases/01-core-server-binary/01-01-SUMMARY.md
- FOUND commit: 798f253 (Task 1)
- FOUND commit: 39e8ff9 (Task 2)
- FOUND commit: 70f4a76 (Plan metadata)
