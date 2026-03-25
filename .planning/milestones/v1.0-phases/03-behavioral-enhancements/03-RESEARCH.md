# Phase 3: Behavioral Enhancements - Research

**Researched:** 2026-03-25
**Domain:** Go stdlib — `net/http`, `time`, `strconv`; single-file handler modification
**Confidence:** HIGH

## Summary

Phase 3 adds two query-parameter-driven behaviors to the existing catch-all handler in `handler.go`: artificial latency injection via `?delay=<ms>` and HTTP status code override via `?status=<code>`. Both enhancements are confined to the `makeHandler` closure. No other files change.

The implementation is entirely stdlib. No new imports are needed for `time` (already imported). One new import is required: `strconv` for `strconv.Atoi` to parse query parameter strings to integers. The `min()` builtin (available since Go 1.21, which matches the go.mod minimum) is usable for clamping the delay value.

A critical safety constraint was verified against Go source: `w.WriteHeader(code)` panics if `code < 100` or `code > 999`. The status validation guard MUST reject codes outside 100–999 before calling WriteHeader. The CONTEXT.md decision D-05 says "invalid status values (non-numeric, out of valid range) are silently ignored — handler returns 200 as default," which maps exactly to this range check.

**Primary recommendation:** Modify only `handler.go`. Parse delay and status params with `strconv.Atoi`, apply `time.Sleep` before writing the response, call `w.WriteHeader(resolvedStatus)` with a validated code, and extend the `slog.Info` log line with a `"status"` field.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Delay Injection (ENH-01)
- **D-01:** `?delay=<ms>` pauses the handler for the specified number of milliseconds before writing the response
- **D-02:** Maximum allowed delay: **30,000 ms (30 seconds)**. Values above 30,000 are silently clamped to 30,000.
- **D-03:** Invalid delay values (non-numeric, negative) are silently ignored — handler proceeds with no delay

#### Status Code Override (ENH-02)
- **D-04:** `?status=<code>` causes the handler to return the specified HTTP status code instead of 200
- **D-05:** Invalid status values (non-numeric, out of valid range) are silently ignored — handler returns 200 as default

#### Parameter Visibility in Response Body
- **D-06:** `delay` and `status` are echoed in `query_params` in the JSON response body — no filtering. Consistent with Phase 1 design (all query params included as-is).

#### Logging (LOG-01, LOG-02)
- **D-07:** The request log line gains a `status` field recording the actual HTTP status code returned. Always logged (200 for normal requests, injected code when `?status` is used).

#### Integration Points
- `handler.go` only — planner should scope all changes to this single file
- No changes to `main.go`, `Dockerfile`, `docker-compose.yml`, or GitHub Actions workflow

### Claude's Discretion
- Where exactly to place the `time.Sleep` call within `makeHandler` (before or after building the response struct — before writing the response is all that's required)
- Whether to parse delay/status into a small helper or inline in the handler closure
- Go idiom for clamping: `min()` builtin (Go 1.21+) or explicit if-guard

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ENH-01 | Request with `?delay=<ms>` query parameter waits the specified number of milliseconds before responding (latency injection) | `time.Sleep(time.Duration(delayMs) * time.Millisecond)` in handler closure; `strconv.Atoi` for parsing; `min()` for clamping to 30,000; ignore negatives |
| ENH-02 | Request with `?status=<code>` query parameter returns the specified HTTP status code instead of 200 (error simulation) | `strconv.Atoi` for parsing; validate 100 ≤ code ≤ 999 (Go panics outside this range); pass validated code to `w.WriteHeader(resolvedStatus)` |
</phase_requirements>

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `time` (stdlib) | Go 1.21 | `time.Sleep` for delay injection | Already imported in handler.go; zero-cost addition |
| `strconv` (stdlib) | Go 1.21 | `strconv.Atoi` to parse query param strings to int | Stdlib; the canonical Go int-parse idiom |
| `net/http` (stdlib) | Go 1.21 | `w.WriteHeader(code)` with validated status | Already in use; no change |
| `log/slog` (stdlib) | Go 1.21 | Extend existing log line with `"status"` field | Already in use; no change |

### Supporting
None — no additional libraries needed.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `strconv.Atoi` | `strconv.ParseInt` | ParseInt offers base/bitsize control — unnecessary here; Atoi is idiomatic for decimal int parsing |
| `min()` builtin | explicit `if delayMs > 30000 { delayMs = 30000 }` | Both are correct; `min()` is more concise; explicit if-guard is equally readable; either works |

**Installation:** No new packages. All stdlib.

---

## Architecture Patterns

### Recommended Handler Structure

The entire change fits inside `makeHandler`. The sequence within the closure becomes:

```
1. Parse all query params into map[string]string (existing)
2. Parse ?status param → resolvedStatus (new)
3. Parse ?delay param → delayMs (new)
4. Build Response struct (existing)
5. Marshal JSON (existing)
6. time.Sleep(delay) ← NEW: before writing response
7. Log with status field (modified)
8. Set Content-Type header (existing)
9. w.WriteHeader(resolvedStatus) ← modified: was hardcoded 200
10. w.Write(body) (existing)
```

### Pattern 1: Inline Parse-and-Validate

**What:** Parse and validate both params inline within the closure, no helper functions.
**When to use:** When logic is simple enough to read without abstraction (this case: ~10 lines each).

```go
// Source: Go stdlib strconv documentation + direct verification
import (
    "encoding/json"
    "log/slog"
    "net/http"
    "strconv"   // NEW
    "time"
)

func makeHandler(port int) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        params := make(map[string]string)
        for k, v := range r.URL.Query() {
            params[k] = v[0]
        }

        // Resolve status code (ENH-02)
        resolvedStatus := http.StatusOK
        if s, ok := params["status"]; ok {
            if code, err := strconv.Atoi(s); err == nil && code >= 100 && code <= 999 {
                resolvedStatus = code
            }
        }

        // Resolve delay in ms (ENH-01)
        var delayMs int
        if d, ok := params["delay"]; ok {
            if ms, err := strconv.Atoi(d); err == nil && ms > 0 {
                delayMs = min(ms, 30000)
            }
        }

        body, err := json.Marshal(Response{
            Port:        port,
            Method:      r.Method,
            Path:        r.URL.Path,
            Timestamp:   time.Now().UTC().Format(time.RFC3339),
            QueryParams: params,
        })
        if err != nil {
            slog.Error("marshal error", "error", err)
            return
        }

        if delayMs > 0 {
            time.Sleep(time.Duration(delayMs) * time.Millisecond)
        }

        slog.Info("request",
            "port",   port,
            "method", r.Method,
            "path",   r.URL.Path,
            "remote", r.RemoteAddr,
            "status", resolvedStatus,   // NEW
        )

        w.Header().Set("Content-Type", "application/json")
        w.WriteHeader(resolvedStatus)
        w.Write(body) //nolint:errcheck
    }
}
```

### Pattern 2: Small Helper Functions

**What:** Extract `parseStatus` and `parseDelay` into package-level helpers.
**When to use:** If the handler body becomes difficult to read, or if tests are added for the parse logic specifically.
**Tradeoff:** Slightly more files/lines, but each piece is independently testable.

### Anti-Patterns to Avoid
- **Calling `w.WriteHeader` with out-of-range code:** Go panics at runtime on codes < 100 or > 999. The guard `code >= 100 && code <= 999` is mandatory, not optional.
- **Sleeping after `w.Write`:** The sleep must occur before writing headers/body. If sleep happens after `w.Write`, the response has already been sent — the client receives it immediately and the delay has no effect.
- **Sleeping before JSON marshal:** Delays the timestamp capture slightly but is functionally fine. Preferred order: parse → build → marshal → sleep → log → write.
- **Filtering `delay`/`status` from `query_params`:** Decision D-06 explicitly keeps them in the response body. Do not filter.
- **Using `time.After` channel instead of `time.Sleep`:** Adds unnecessary complexity; `time.Sleep` is correct for this synchronous handler.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Integer parsing from string | Custom digit loop | `strconv.Atoi` | Handles sign, overflow, non-numeric; returns error |
| Delay clamping | Manual bounds check repeated in multiple places | `min(ms, 30000)` builtin | Single expression, no off-by-one |
| Status code validation | Regex on the string | `strconv.Atoi` + range check `100 <= code <= 999` | Numeric range check is correct and sufficient |

**Key insight:** The validation rules here are deliberate "silent ignore" semantics (per D-03, D-05). The pattern `if parsed, err := strconv.Atoi(s); err == nil && <range check> { use it }` perfectly encodes "ignore if invalid" with no extra code path needed.

---

## Common Pitfalls

### Pitfall 1: WriteHeader Panic on Out-of-Range Code
**What goes wrong:** If `?status=50` or `?status=0` or `?status=1000` is passed and the handler calls `w.WriteHeader(50)`, Go's `net/http` server calls `checkWriteHeaderCode` internally which panics with `"invalid WriteHeader code 50"`. This crashes the goroutine serving that request (Go's HTTP server recovers panics per-connection, but it logs a 500 to the client and logs noise to stdout).
**Why it happens:** Go RFC compliance — HTTP status codes are 3-digit (100–999). The implementation in `server.go` line 1161: `if code < 100 || code > 999 { panic(...) }`.
**How to avoid:** Validate `code >= 100 && code <= 999` before calling `w.WriteHeader`. Reject anything outside this range per D-05 (silently return 200).
**Warning signs:** `panic: invalid WriteHeader code N` in container logs.

### Pitfall 2: Sleep Positioned After Write
**What goes wrong:** Placing `time.Sleep` after `w.Write(body)` sends the response immediately (the client receives HTTP 200 right away), then sleeps — the delay is invisible to the client.
**Why it happens:** HTTP response is sent as soon as headers + body are written to the connection. Sleep afterward has no effect on round-trip latency.
**How to avoid:** Sleep must occur before `w.Header().Set(...)` / `w.WriteHeader(...)` / `w.Write(...)`.

### Pitfall 3: Negative Delay Passed to time.Sleep
**What goes wrong:** `time.Sleep` with a negative duration returns immediately (no-op in Go). This is safe, but the intent per D-03 is to also treat negative values as "no delay." The guard `ms > 0` ensures negative inputs are never passed to `time.Sleep`.
**Why it happens:** `strconv.Atoi("-500")` succeeds and returns -500. Without a `> 0` guard, `-500` would pass the numeric check but `time.Sleep(-500ms)` would be a no-op.
**How to avoid:** Guard: `if ms, err := strconv.Atoi(d); err == nil && ms > 0 { delayMs = min(ms, 30000) }`.

### Pitfall 4: Import Not Added for strconv
**What goes wrong:** `strconv` is not currently imported in `handler.go`. Adding `strconv.Atoi` without adding the import causes a compile error.
**Why it happens:** `handler.go` currently imports only `encoding/json`, `log/slog`, `net/http`, `time`. `strconv` is not in that list.
**How to avoid:** Add `"strconv"` to the import block in `handler.go`.

### Pitfall 5: Log Line Order — Status Logged Before Sleep
**What goes wrong:** If `slog.Info("request", ...)` is called before `time.Sleep`, the log timestamp precedes the response timestamp — useful for measuring latency but potentially confusing. D-07 just says the `status` field is added; order relative to sleep is not specified.
**Why it happens:** Logging before sleep is common but means the log line appears before the response is sent.
**How to avoid:** Log after sleep (and before write) so the log line aligns with when the response is actually written. This matches the existing code's natural position (log → set headers → write).

---

## Code Examples

### strconv.Atoi Idiom
```go
// Source: Go stdlib strconv package
if ms, err := strconv.Atoi(params["delay"]); err == nil && ms > 0 {
    delayMs = min(ms, 30000)
}
```

### time.Sleep with Millisecond Conversion
```go
// Source: Go stdlib time package — time.Duration is int64 nanoseconds
// time.Millisecond is a constant equal to 1,000,000 nanoseconds
time.Sleep(time.Duration(delayMs) * time.Millisecond)
```

### WriteHeader with Validated Status
```go
// Source: Go net/http server.go — checkWriteHeaderCode enforces 100-999
resolvedStatus := http.StatusOK
if s, ok := params["status"]; ok {
    if code, err := strconv.Atoi(s); err == nil && code >= 100 && code <= 999 {
        resolvedStatus = code
    }
}
// ... later ...
w.WriteHeader(resolvedStatus)
```

### Extending the slog.Info Log Line (D-07)
```go
// Source: Existing handler.go pattern — extend with "status" field
slog.Info("request",
    "port",   port,
    "method", r.Method,
    "path",   r.URL.Path,
    "remote", r.RemoteAddr,
    "status", resolvedStatus,
)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual range check with if-else | `min()` builtin for clamping | Go 1.21 (2023-08) | Cleaner clamp expressions |
| `log.Printf` | `log/slog` structured JSON | Go 1.21 (2023-08) | Machine-parseable log fields |

**Deprecated/outdated:**
- `log.Printf`: Still valid but this project uses `log/slog` per CLAUDE.md. Do not introduce `log.Printf`.

---

## Open Questions

1. **Timing of `time.Now()` in Response struct vs. sleep**
   - What we know: `time.Now().UTC().Format(time.RFC3339)` in the Response struct captures the time the handler entered, before the sleep.
   - What's unclear: Should the timestamp reflect when the handler started processing, or when the response was sent?
   - Recommendation: Keep existing behavior (timestamp captured before sleep). The timestamp documents when the request arrived, not when it was answered. This is the natural reading and requires no change to the Response struct.

2. **`?status=1xx` informational responses**
   - What we know: Go's WriteHeader accepts 100–999; 1xx codes are "informational" and the HTTP spec treats them specially (they can be sent multiple times before a final 2xx-5xx header).
   - What's unclear: Passing `?status=100` would send an informational-only response with no final status. In practice, `w.Write(body)` after `w.WriteHeader(100)` may cause the server to implicitly add a 200 before the body.
   - Recommendation: The guard `code >= 100 && code <= 999` allows 1xx. This is unlikely to be tested or cause real problems. If the planner wants to restrict to 200–599 (the practical test-scaffolding range), that is also valid and safe. D-05 says "out of valid range" — the planner should decide whether "valid range" means 100–999 (RFC) or 200–599 (practical). The research recommends 100–999 as it matches Go's own validation boundary.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 3 is a pure Go source code change with no external dependencies beyond the Go toolchain already used in Phase 1 and 2. No new CLIs, services, databases, or runtimes are introduced.

---

## Sources

### Primary (HIGH confidence)
- `/opt/homebrew/Cellar/go/1.25.0/libexec/src/net/http/server.go` lines 1150–1162 — `checkWriteHeaderCode` confirms panic boundary at `code < 100 || code > 999`, verified by direct source read
- `/opt/homebrew/Cellar/go/1.25.0/libexec/src/net/http/server.go` — `ResponseWriter.WriteHeader` doc: "The provided code must be a valid HTTP 1xx-5xx status code"
- `go run /tmp/statustest3.go` — Live verification that `httptest.ResponseRecorder` panics on codes 0, 99, -1; accepts 100, 200, 503, 600, 999
- `go run /tmp/mintest.go` — Live verification that `min()` builtin is available and functional with `go 1.21` module
- `/Users/yriahi/Development/swiss-army-image/handler.go` — Direct read: `strconv` not yet imported; `time` already imported; `w.WriteHeader(http.StatusOK)` at line 49; `slog.Info("request", ...)` at line 41
- `/Users/yriahi/Development/swiss-army-image/go.mod` — `go 1.21` minimum confirmed

### Secondary (MEDIUM confidence)
- Go stdlib docs (`go doc strconv.Atoi`, `go doc net/http ResponseWriter`) — confirmed via local Go installation (1.25.0 — higher than 1.21 minimum, fully compatible)

### Tertiary (LOW confidence)
- None.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all stdlib, verified against local Go installation
- Architecture: HIGH — pattern derived directly from existing `handler.go` code read at research time
- Pitfalls: HIGH — WriteHeader panic boundary verified by running Go source + live test; sleep ordering is first-principles Go HTTP behavior

**Research date:** 2026-03-25
**Valid until:** 2026-09-25 (Go stdlib is stable; panic boundary behavior has been unchanged for years)
