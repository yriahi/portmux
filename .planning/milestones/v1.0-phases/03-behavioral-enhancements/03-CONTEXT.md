# Phase 3: Behavioral Enhancements - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Add `?delay=<ms>` latency injection and `?status=<code>` HTTP status code override to the existing catch-all handler. All 6 ports, any path, any method. No new ports, no new routes, no structural changes to the binary — only handler.go is modified.

</domain>

<decisions>
## Implementation Decisions

### Delay Injection (ENH-01)
- **D-01:** `?delay=<ms>` pauses the handler for the specified number of milliseconds before writing the response
- **D-02:** Maximum allowed delay: **30,000 ms (30 seconds)**. Values above 30,000 are silently clamped to 30,000.
- **D-03:** Invalid delay values (non-numeric, negative) are silently ignored — handler proceeds with no delay

### Status Code Override (ENH-02)
- **D-04:** `?status=<code>` causes the handler to return the specified HTTP status code instead of 200
- **D-05:** Invalid status values (non-numeric, out of valid range) are silently ignored — handler returns 200 as default

### Parameter Visibility in Response Body
- **D-06:** `delay` and `status` are echoed in `query_params` in the JSON response body — no filtering. Consistent with Phase 1 design (all query params included as-is).

Example response with both params:
```json
{
  "port": 8080,
  "method": "GET",
  "path": "/",
  "timestamp": "2026-03-25T12:00:00Z",
  "query_params": {
    "delay": "500",
    "status": "503",
    "foo": "bar"
  }
}
```

### Logging (LOG-01, LOG-02)
- **D-07:** The request log line gains a `status` field recording the actual HTTP status code returned. Always logged (200 for normal requests, injected code when `?status` is used).

Example log line with injected status:
```json
{"level":"info","msg":"request","port":8080,"method":"GET","path":"/","remote":"172.17.0.1:12345","status":503,"time":"2026-03-25T12:00:00Z"}
```

### Claude's Discretion
- Where exactly to place the `time.Sleep` call within `makeHandler` (before or after building the response struct — before writing the response is all that's required)
- Whether to parse delay/status into a small helper or inline in the handler closure
- Go idiom for clamping: `min()` builtin (Go 1.21+) or explicit if-guard

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` — Phase 3 requirement IDs: ENH-01, ENH-02

### Project Constraints
- `.planning/PROJECT.md` — Constraints (stateless, no filesystem writes, HTTP only)
- `CLAUDE.md` — Prescribed stack: Go 1.26.1, stdlib only (`net/http`, `encoding/json`, `log/slog`, `time`). No external dependencies.

### Prior Phases
- `.planning/phases/01-core-server-binary/01-CONTEXT.md` — D-01 to D-03: Response body shape (flat snake_case, `query_params` as map), D-06 to D-08: structured log fields
- `.planning/phases/02-container-and-distribution/02-CONTEXT.md` — Registry and image path (no changes needed for Phase 3)

No external ADRs or specs — all decisions captured above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `handler.go:makeHandler()` — The only file that needs modification. Currently reads all query params into a `map[string]string`, builds `Response` struct, and writes 200 with JSON. Both enhancements insert into this closure.
- `main.go` — No changes needed. Port binding, goroutine-per-port, and graceful shutdown are unaffected.

### Established Patterns
- `w.WriteHeader(http.StatusOK)` at handler.go:49 — parameterize this with the resolved status code
- `slog.Info("request", ...)` at handler.go:41 — extend with `"status", resolvedStatus` field
- `time` package already imported in handler.go — `time.Sleep(duration)` requires no new import
- `strconv.Atoi` from stdlib for parsing string → int (no new import needed beyond adding `"strconv"`)

### Integration Points
- `handler.go` only — planner should scope all changes to this single file
- No changes to `main.go`, `Dockerfile`, `docker-compose.yml`, or GitHub Actions workflow

</code_context>

<specifics>
## Specific Ideas

- Delay is applied before writing the response (sleep then respond) — this is the natural interpretation of latency injection
- Status override uses the same JSON body shape regardless of status code — `{"port":..., "method":..., "path":..., "timestamp":..., "query_params":{...}}` is always returned
- Max delay of 30s chosen to prevent accidental connection exhaustion in load tests or probe storms without being overly restrictive for legitimate timeout testing scenarios

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 03-behavioral-enhancements*
*Context gathered: 2026-03-25*
