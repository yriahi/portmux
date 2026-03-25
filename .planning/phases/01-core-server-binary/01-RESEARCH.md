# Phase 1: Core Server Binary - Research

**Researched:** 2026-03-25
**Domain:** Go stdlib HTTP server — multi-port, structured logging, graceful shutdown
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** JSON response body uses flat `snake_case` structure: `port`, `method`, `path`, `timestamp`, `query_params`
- **D-02:** `query_params` is a JSON object (key/value map), not a string or array
- **D-03:** `timestamp` is ISO 8601 / RFC3339 format (e.g., `2026-03-25T12:00:00Z`)
- **D-04:** If port 80 fails to bind, log the error and continue serving the other 5 ports — do not exit
- **D-05:** Port 80 bind failure must be logged clearly (visible in docker logs), but is non-fatal
- **D-06:** Required log fields per request: `port`, `method`, `path`, `timestamp`
- **D-07:** Also include `remote` (client IP:port) in every request log line
- **D-08:** Log format is structured JSON (machine-parseable for CloudWatch, Datadog, etc.)
- **D-09:** On startup emit a single JSON log line listing all ports that successfully bound
- **D-10:** Startup log line uses the same structured JSON format as request logs
- **D-11:** SIGTERM triggers graceful shutdown — drain in-flight requests, exit within 5 seconds

### Claude's Discretion

- Code structure: single `main.go` vs. multiple files — Claude decides based on readability
- Error handling patterns for port bind errors beyond port 80
- goroutine coordination mechanism (errgroup, sync.WaitGroup, etc.)
- JSON serialization approach (stdlib `encoding/json` per CLAUDE.md stack)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SRVR-01 | Container binds ports 80, 8080, 8181, 8081, 3000, and 5000 simultaneously in a single running instance | goroutine-per-port with `http.Server` per port; D-04 handles port 80 failures non-fatally |
| SRVR-02 | Any HTTP request on any path and any method returns a response — no 404s, no routing errors | Single catch-all handler registered on `http.NewServeMux()` via `mux.HandleFunc("/", handler)` or `http.HandlerFunc` |
| SRVR-03 | Container exits cleanly on SIGTERM with graceful shutdown (drains in-flight requests, exits within 5 seconds) | `signal.NotifyContext` + `http.Server.Shutdown(ctx)` with 5s timeout context per server |
| RESP-01 | All HTTP responses return status code 200 by default | `w.WriteHeader(http.StatusOK)` in catch-all handler |
| RESP-02 | Response body is JSON containing: port number, HTTP method, request path, ISO timestamp, and query parameters | `encoding/json` marshal of struct with fields matching D-01 through D-03; query params from `r.URL.Query()` |
| RESP-03 | Response includes `Content-Type: application/json` header on every request | `w.Header().Set("Content-Type", "application/json")` before WriteHeader |
| LOG-01 | Each incoming request is logged to stdout with port, method, path, and timestamp | `log/slog` JSONHandler on `os.Stdout` with fields per D-06 and D-07 |
| LOG-02 | Log output is structured JSON (machine-parseable for CloudWatch, Datadog, etc.) | `slog.NewJSONHandler(os.Stdout, nil)` produces line-delimited JSON; matches example in D-08 |
</phase_requirements>

---

## Summary

Phase 1 creates the sole Go source file(s) for a multi-port HTTP stub binary. All required functionality lives entirely in the Go standard library: `net/http` for the HTTP servers, `log/slog` (added in Go 1.21) for structured JSON logging, `encoding/json` for response serialization, and `os/signal` for SIGTERM handling. No external dependencies are needed or permitted.

The goroutine-per-port pattern is straightforward: create one `http.Server` per port, launch each via a goroutine calling `srv.ListenAndServe()`, coordinate shutdown using `signal.NotifyContext` + `srv.Shutdown(ctx)`. The only non-trivial concern is the port 80 bind error: it must be handled per D-04 so the binary continues running on the other 5 ports rather than exiting. All other port bind failures should be treated as fatal (they indicate a configuration problem).

The local Go version is 1.25.0, which is one minor version behind CLAUDE.md's prescribed 1.26.1. This matters for the build stage in Phase 2 (the Dockerfile uses `golang:1.26-alpine`) but is irrelevant for Phase 1 local development — the code uses only stdlib APIs available since Go 1.21 (`log/slog`) and Go 1.0 (`net/http`). No go.sum or module proxy issues arise from this gap.

**Primary recommendation:** Single `main.go` (or `main.go` + `handler.go` split if > ~120 lines) using `log/slog` JSONHandler, one `http.Server` per port in a goroutine, `signal.NotifyContext` for SIGTERM, and `sync.WaitGroup` for shutdown coordination.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `net/http` | Go stdlib (1.0+) | HTTP listener, request handling | Standard Go HTTP server; `http.Server.Shutdown` supports graceful drain |
| `log/slog` | Go stdlib (1.21+) | Structured JSON logging to stdout | `slog.NewJSONHandler` produces line-delimited JSON natively; no external logger needed |
| `encoding/json` | Go stdlib (1.0+) | JSON response body serialization | CLAUDE.md mandates stdlib; `json.Marshal` on a struct handles D-01 through D-03 |
| `os/signal` | Go stdlib (1.0+) | SIGTERM interception for graceful shutdown | `signal.NotifyContext` (Go 1.16+) cleanly integrates signal handling with context cancellation |
| `sync` | Go stdlib (1.0+) | WaitGroup for goroutine coordination | Ensures main waits for all servers to finish shutdown before os.Exit |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `time` | Go stdlib | RFC3339 timestamp formatting | `time.Now().UTC().Format(time.RFC3339)` for D-03 |
| `fmt` | Go stdlib | Port address string construction | `fmt.Sprintf(":%d", port)` for server Addr |
| `strconv` | Go stdlib | Port int → string in log attrs | `strconv.Itoa(port)` if needed for slog integer attr |
| `net/url` | Go stdlib | Query param extraction | `r.URL.Query()` returns `url.Values` (map[string][]string); flatten to map[string]string for D-02 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `log/slog` JSONHandler | `zerolog` or `zap` | External deps for no benefit; slog JSONHandler is native and its output matches the D-08 example exactly |
| `signal.NotifyContext` | `signal.Notify` with manual channel | NotifyContext is cleaner (Go 1.16+); both work, NotifyContext reduces boilerplate |
| `sync.WaitGroup` | `golang.org/x/sync/errgroup` | errgroup not available as module in this project (no go.mod yet); WaitGroup is sufficient since error handling per goroutine is intentionally non-fatal for port 80 |

**Installation:** No `go get` required. All packages are stdlib. Phase 1 requires only:
```bash
go mod init swiss-army-image
# No additional dependencies
```

---

## Architecture Patterns

### Recommended Project Structure

```
swiss-army-image/
├── main.go          # entry point: signal setup, server launch, shutdown coordination
├── handler.go       # HTTP handler: builds response JSON, writes Content-Type header
├── go.mod           # module declaration, Go version 1.21+ (slog availability)
└── go.sum           # empty (no external deps)
```

Single-file `main.go` is acceptable if total line count stays below ~120 lines. Split into `main.go` + `handler.go` if the handler + response struct adds significant length — keeps each file focused on one concern.

### Pattern 1: Goroutine-per-Port with Named Servers

**What:** Create one `http.Server` per port, each with its own `ServeMux` and catch-all handler. Launch each via `go srv.ListenAndServe()`. Track all servers in a slice for shutdown.

**When to use:** Always for this project — enables independent shutdown of each server and clean error handling per port.

```go
// Source: net/http stdlib docs + Go 1.16+ signal.NotifyContext
ports := []int{80, 8080, 8181, 8081, 3000, 5000}
var servers []*http.Server

for _, port := range ports {
    mux := http.NewServeMux()
    mux.HandleFunc("/", makeHandler(port))
    srv := &http.Server{
        Addr:    fmt.Sprintf(":%d", port),
        Handler: mux,
    }
    servers = append(servers, srv)
    go func(s *http.Server, p int) {
        if err := s.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            slog.Error("listen error", "port", p, "error", err)
            // For port 80: non-fatal per D-04. For others: log and continue.
        }
    }(srv, port)
}
```

### Pattern 2: SIGTERM Graceful Shutdown via NotifyContext

**What:** Use `signal.NotifyContext` to get a context that cancels on SIGTERM (or SIGINT). When cancelled, call `Shutdown` on every server with a 5-second deadline.

**When to use:** Always — satisfies SRVR-03.

```go
// Source: os/signal stdlib docs (Go 1.16+)
ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
defer stop()

<-ctx.Done() // blocks until signal received

shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
defer cancel()

var wg sync.WaitGroup
for _, srv := range servers {
    wg.Add(1)
    go func(s *http.Server) {
        defer wg.Done()
        s.Shutdown(shutdownCtx)
    }(srv)
}
wg.Wait()
```

### Pattern 3: Structured JSON Logging with slog

**What:** Initialize a single `slog.Logger` with `slog.NewJSONHandler(os.Stdout, nil)` at startup. Pass it (or use the default) for all log output including startup banner and per-request logs.

**When to use:** Always — satisfies LOG-01, LOG-02, D-06 through D-10.

```go
// Source: log/slog stdlib docs (Go 1.21+)
logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
slog.SetDefault(logger)

// Startup banner (D-09, D-10)
slog.Info("listening", "ports", successfulPorts)

// Per-request (D-06, D-07)
slog.Info("request",
    "port",      port,
    "method",    r.Method,
    "path",      r.URL.Path,
    "remote",    r.RemoteAddr,
    "time",      time.Now().UTC().Format(time.RFC3339),
)
```

Note: `slog` automatically adds a `"time"` key in RFC3339Nano format. To match the D-08 example format exactly (`"time":"2026-03-25T12:00:00Z"`), the default slog time is sufficient — it uses RFC3339Nano which includes the Z suffix for UTC times.

### Pattern 4: Catch-All Handler Registration

**What:** Register a single handler on `"/"` path — Go's `ServeMux` treats `"/"` as a catch-all that matches all paths not matched by more-specific patterns.

**When to use:** Always — satisfies SRVR-02 (no 404s on any path or method).

```go
// Source: net/http stdlib docs
mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
    // This matches ALL paths: /foo, /bar/baz, /anything
})
```

**Warning:** Go 1.22 changed ServeMux pattern syntax. The `"/"` catch-all still works in 1.22+ but new method-prefixed patterns (e.g., `"GET /"`) are available. Do not use method-prefixed patterns since SRVR-02 requires all methods to be handled.

### Pattern 5: Query Params as JSON Object (D-02)

**What:** `r.URL.Query()` returns `url.Values` which is `map[string][]string`. For D-02 (key/value map, not array), flatten to `map[string]string` using the first value per key, or use `map[string][]string` directly for full fidelity. Decision: use `map[string][]string` to avoid data loss with multi-value params, but document this in the response struct.

**When to use:** In the response handler.

```go
// Source: net/url stdlib docs
queryParams := make(map[string][]string)
for k, v := range r.URL.Query() {
    queryParams[k] = v
}
// OR for simple single-value map as shown in D-02 example:
queryParams := make(map[string]string)
for k, v := range r.URL.Query() {
    queryParams[k] = v[0] // first value only
}
```

Given D-02's example shows `{"foo": "bar"}` (string values, not arrays), use `map[string]string` with first-value extraction. This matches the spec example.

### Pattern 6: Response Struct and JSON Serialization

**What:** Define a struct with `json` tags matching D-01. Serialize with `encoding/json.Marshal`. Set `Content-Type` header before writing status.

```go
// Source: encoding/json stdlib
type Response struct {
    Port        int               `json:"port"`
    Method      string            `json:"method"`
    Path        string            `json:"path"`
    Timestamp   string            `json:"timestamp"`
    QueryParams map[string]string `json:"query_params"`
}

func makeHandler(port int) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        params := make(map[string]string)
        for k, v := range r.URL.Query() {
            params[k] = v[0]
        }
        body, _ := json.Marshal(Response{
            Port:        port,
            Method:      r.Method,
            Path:        r.URL.Path,
            Timestamp:   time.Now().UTC().Format(time.RFC3339),
            QueryParams: params,
        })
        w.Header().Set("Content-Type", "application/json")
        w.WriteHeader(http.StatusOK)
        w.Write(body)
    }
}
```

### Anti-Patterns to Avoid

- **Using `http.ListenAndServe` (package-level function) instead of `http.Server` struct:** The package-level function returns no handle for graceful shutdown. Always use `http.Server` struct so `srv.Shutdown()` can be called.
- **Calling `w.WriteHeader` before `w.Header().Set`:** Headers must be set before WriteHeader; setting them after is silently ignored.
- **Using `log.Fatal` or `os.Exit` in port bind goroutines:** This kills the entire process. Errors on port 80 must be non-fatal per D-04.
- **Registering `"/"` on DefaultServeMux:** Use per-server `http.NewServeMux()` instances to avoid cross-port handler pollution.
- **`json.Marshal` error ignored silently:** For a static struct with known types, marshal errors cannot happen in practice, but for production code wrap in error check and return 500 — not applicable here since we always return 200, so log the error and return an empty body rather than panicking.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Structured JSON log output | Custom JSON string formatting | `log/slog` JSONHandler | slog handles time format, escaping, level normalization; custom formatting will have edge cases |
| Query param parsing | Manual `strings.Split` on `r.URL.RawQuery` | `r.URL.Query()` | stdlib handles percent-encoding, duplicate keys, empty values |
| Signal handling | `os.Signal` channel + select loop | `signal.NotifyContext` | NotifyContext integrates directly with context cancellation; less boilerplate |
| Graceful shutdown timeout | Custom timer + force-kill loop | `context.WithTimeout` + `srv.Shutdown` | `Shutdown` respects context deadline natively |
| Port-number extraction | Parsing `r.Host` or `r.URL.Host` | Closure over `port int` in handler factory | Port is known at server construction time; pass via closure, not runtime parsing |

**Key insight:** This phase touches 4-5 stdlib packages in their most straightforward use cases. Every component has a clean stdlib solution. Adding any external dependency would be net-negative for image size and complexity.

---

## Common Pitfalls

### Pitfall 1: Port 80 Bind Failure Kills the Process

**What goes wrong:** If a goroutine calls `log.Fatal` or lets a panic propagate when port 80 bind fails, the entire binary exits — the other 5 ports never serve.

**Why it happens:** Default error handling instinct is to exit on any listen error. Port 80 requires root or `CAP_NET_BIND_SERVICE` locally, so it will routinely fail in development.

**How to avoid:** In the goroutine for each server, check `if err != nil && err != http.ErrServerClosed` and for port 80 specifically log with `slog.Error` and continue. Track which ports successfully started and use that list for the D-09 startup banner.

**Warning signs:** `curl localhost:8080` returns `connection refused` when run without root — means the whole binary exited on port 80 failure.

### Pitfall 2: Headers Set After WriteHeader

**What goes wrong:** `Content-Type: application/json` is missing from the response even though the code calls `w.Header().Set(...)`.

**Why it happens:** `w.WriteHeader(http.StatusOK)` flushes and locks the header map. Any `w.Header().Set` after that call is silently ignored.

**How to avoid:** Always call `w.Header().Set("Content-Type", "application/json")` BEFORE `w.WriteHeader(http.StatusOK)`. Order: Set headers → WriteHeader → Write body.

**Warning signs:** `curl -I localhost:8080` shows no `Content-Type` header in response.

### Pitfall 3: Shutdown Race — Main Exits Before Servers Drain

**What goes wrong:** After receiving SIGTERM, main proceeds to `os.Exit(0)` before in-flight requests complete, violating SRVR-03.

**Why it happens:** `srv.Shutdown()` is non-blocking unless you `Wait()` on all goroutines.

**How to avoid:** Use `sync.WaitGroup` — `wg.Add(1)` per server before launching shutdown goroutines, `wg.Done()` in each, `wg.Wait()` in main before returning.

**Warning signs:** Load test with concurrent requests during shutdown shows truncated responses.

### Pitfall 4: slog Default Time Format Mismatch

**What goes wrong:** Log timestamps use `time.RFC3339Nano` (e.g., `2026-03-25T12:00:00.000000000Z`) instead of the cleaner RFC3339 format shown in D-08 example (`2026-03-25T12:00:00Z`).

**Why it happens:** `slog.NewJSONHandler` uses `time.RFC3339Nano` for its built-in `time` field by default. This is still valid ISO 8601 and machine-parseable, so it meets LOG-01 and LOG-02 requirements. The D-08 example is illustrative, not a byte-for-byte contract.

**How to avoid:** Accept the default nano-precision format — it satisfies all requirements. If exact format match is required, use `HandlerOptions.ReplaceAttr` to reformat the time key. This is unnecessary complexity for a stub server.

**Warning signs:** Test comparing exact log output fails due to nanosecond precision in timestamp.

### Pitfall 5: go.mod Missing or Wrong Go Version

**What goes wrong:** `go run .` fails with "cannot find module" or slog is unavailable.

**Why it happens:** `log/slog` was added in Go 1.21. If `go.mod` declares `go 1.19`, the build may fail or use a compatibility shim.

**How to avoid:** `go mod init swiss-army-image` then manually set `go 1.21` minimum in `go.mod`. Given the local toolchain is Go 1.25.0, declare `go 1.21` as minimum (slog availability) for broadest compatibility, or `go 1.25` to match local toolchain exactly.

### Pitfall 6: `r.URL.Path` vs `r.URL.RawPath`

**What goes wrong:** Percent-encoded paths (e.g., `/foo%2Fbar`) are decoded in `r.URL.Path` but preserved raw in `r.URL.RawPath`. For a stub that returns the path as-is, `r.URL.Path` is correct and preferred (decoded form).

**How to avoid:** Always use `r.URL.Path`. Only use `r.URL.RawPath` when the raw encoded form matters (never for this stub).

---

## Code Examples

Verified patterns from stdlib documentation (Go 1.25.0 local, APIs stable since noted versions):

### Minimal Multi-Port Server Skeleton

```go
// Source: net/http stdlib (Go 1.0+), os/signal stdlib (Go 1.16+ for NotifyContext)
package main

import (
    "context"
    "encoding/json"
    "fmt"
    "log/slog"
    "net/http"
    "os"
    "os/signal"
    "sync"
    "syscall"
    "time"
)

var ports = []int{80, 8080, 8181, 8081, 3000, 5000}

type Response struct {
    Port        int               `json:"port"`
    Method      string            `json:"method"`
    Path        string            `json:"path"`
    Timestamp   string            `json:"timestamp"`
    QueryParams map[string]string `json:"query_params"`
}

func makeHandler(port int) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        params := make(map[string]string)
        for k, v := range r.URL.Query() {
            params[k] = v[0]
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
        slog.Info("request",
            "port",   port,
            "method", r.Method,
            "path",   r.URL.Path,
            "remote", r.RemoteAddr,
        )
        w.Header().Set("Content-Type", "application/json")
        w.WriteHeader(http.StatusOK)
        w.Write(body)
    }
}

func main() {
    logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
    slog.SetDefault(logger)

    var servers []*http.Server
    var activePorts []int

    for _, port := range ports {
        mux := http.NewServeMux()
        mux.HandleFunc("/", makeHandler(port))
        srv := &http.Server{
            Addr:    fmt.Sprintf(":%d", port),
            Handler: mux,
        }
        // Test bind before adding to active list
        // (actual ListenAndServe in goroutine below)
        servers = append(servers, srv)
        activePorts = append(activePorts, port)
    }

    var startWg sync.WaitGroup
    var mu sync.Mutex
    var started []int

    for i, srv := range servers {
        port := ports[i]
        startWg.Add(1)
        go func(s *http.Server, p int) {
            // Signal started (optimistic — bind error reported separately)
            mu.Lock()
            started = append(started, p)
            mu.Unlock()
            startWg.Done()
            if err := s.ListenAndServe(); err != nil && err != http.ErrServerClosed {
                if p == 80 {
                    slog.Error("listen error (non-fatal)", "port", p, "error", err)
                } else {
                    slog.Error("listen error", "port", p, "error", err)
                }
            }
        }(srv, port)
    }

    // Give goroutines a moment to start, then log banner
    // Better approach: use net.Listen() first to verify bind, then srv.Serve(l)
    startWg.Wait()
    slog.Info("listening", "ports", started)

    // Graceful shutdown
    ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
    defer stop()
    <-ctx.Done()

    shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    var wg sync.WaitGroup
    for _, srv := range servers {
        wg.Add(1)
        go func(s *http.Server) {
            defer wg.Done()
            s.Shutdown(shutdownCtx)
        }(srv)
    }
    wg.Wait()
}
```

### Accurate Startup Banner with net.Listen Pre-flight

For D-09 (list only successfully bound ports), use `net.Listen` before `srv.Serve` to detect bind failure before launching the goroutine:

```go
// Source: net stdlib (Go 1.0+)
import "net"

for _, port := range ports {
    ln, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
    if err != nil {
        if port == 80 {
            slog.Error("bind failed (non-fatal)", "port", port, "error", err)
            continue  // D-04: non-fatal for port 80
        }
        slog.Error("bind failed", "port", port, "error", err)
        continue
    }
    activePorts = append(activePorts, port)
    // pass ln to srv.Serve(ln) instead of srv.ListenAndServe()
    go srv.Serve(ln)
}
slog.Info("listening", "ports", activePorts)  // D-09: only successful ports
```

This is the **recommended approach** for the startup banner — it guarantees `activePorts` only contains ports that actually bound before the banner is emitted.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `log` package with manual JSON string formatting | `log/slog` with `NewJSONHandler` | Go 1.21 (Aug 2023) | Native structured logging; no external dep like zerolog or zap needed |
| `signal.Notify` + manual channel | `signal.NotifyContext` | Go 1.16 (Feb 2021) | Cleaner context-based signal handling; integrates with `context.WithTimeout` |
| `gorilla/mux` catch-all | `net/http` ServeMux `"/"` pattern | Always available | For catch-all routing, stdlib ServeMux is sufficient; gorilla/mux adds deps with no benefit |
| Single global `http.DefaultServeMux` | Per-server `http.NewServeMux()` | Always available | Required for multi-port to avoid cross-port handler registration |

**Deprecated/outdated:**
- `log.Fatal` in server goroutines: causes whole-process exit; never use for per-port errors in this binary
- `ioutil.ReadAll` / `ioutil.WriteAll`: deprecated in Go 1.16, replaced by `io.ReadAll` / `io.WriteAll` (not needed for this phase)

---

## Open Questions

1. **go.mod minimum Go version**
   - What we know: Local toolchain is Go 1.25.0; CLAUDE.md references Go 1.26.1 for the Docker builder
   - What's unclear: Whether to declare `go 1.21` (minimum for slog) or `go 1.25` (local toolchain) in go.mod
   - Recommendation: Declare `go 1.21` as minimum — enables slog, is correct for the feature set used, and avoids pinning to a higher version than strictly necessary. The Docker builder uses 1.26.1 per CLAUDE.md.

2. **Startup banner timing accuracy**
   - What we know: The `net.Listen` pre-flight approach (above) gives accurate per-port bind results before the banner is emitted
   - What's unclear: Whether a naive `startWg.Wait()` after goroutine launch is acceptable (it cannot detect bind failures at startup time)
   - Recommendation: Use `net.Listen` + `srv.Serve(ln)` pattern — it is the only way to accurately know which ports bound before emitting the D-09 startup log line.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Go toolchain | Build binary, `go run .` | Yes | 1.25.0 (local) / 1.26.1 (Docker) | None needed |
| Docker | Phase 2 (not this phase) | Yes | 29.3.0 | N/A |
| docker buildx | Phase 2 (not this phase) | Yes | 0.32.1-desktop.1 | N/A |
| curl | Manual testing / verification | Yes | 8.7.1 | wget or browser |

**Go version note:** CLAUDE.md prescribes Go 1.26.1 for the Docker build stage. Local toolchain is Go 1.25.0. For Phase 1 (local `go run .`), 1.25.0 is fully capable — all APIs used (`log/slog`, `signal.NotifyContext`, `http.Server.Shutdown`) are available since Go 1.21 or earlier. No version-related blockers.

**Missing dependencies with no fallback:** None — all Phase 1 dependencies are present.

---

## Project Constraints (from CLAUDE.md)

| Constraint | Impact on Phase 1 |
|------------|-------------------|
| Go 1.26.1 as prescribed version | Local dev uses 1.25.0 (no issue); Docker builder uses 1.26.1 (Phase 2) |
| `net/http` stdlib only (no gorilla/mux, no chi, no fiber) | Catch-all via `"/"` on `http.NewServeMux()` |
| `encoding/json` stdlib only (no sonic, no jsoniter) | `json.Marshal` on Response struct |
| `CGO_ENABLED=0` required for scratch image | Must set at build time; irrelevant for `go run .` in Phase 1 |
| Stateless — no filesystem writes | All output goes to stdout via slog; no log files |
| Multi-port — all 6 ports in one process | goroutine-per-port, not supervisord or multiple binaries |
| No supervisord, no socat, no Node, no nginx | Go stdlib only |

---

## Sources

### Primary (HIGH confidence)
- `net/http` stdlib — verified locally with `go doc net/http Server`, `go doc net/http Server.Shutdown`
- `log/slog` stdlib — verified locally with `go doc log/slog`, `go doc log/slog NewJSONHandler`, `go doc log/slog HandlerOptions`
- `os/signal` stdlib — verified locally with `go doc os/signal NotifyContext`, `go doc os/signal Notify`
- `encoding/json` stdlib — verified locally
- `net/url` stdlib — verified locally with `go doc net/url Values`
- CLAUDE.md — project-mandated stack, constraints, and what NOT to use

### Secondary (MEDIUM confidence)
- CONTEXT.md — user decisions D-01 through D-11 (gathered 2026-03-25 from /gsd:discuss-phase)
- REQUIREMENTS.md — requirement IDs SRVR-01 through LOG-02

### Tertiary (LOW confidence)
- None — all research verified against local stdlib docs

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages verified against local Go 1.25.0 stdlib docs
- Architecture: HIGH — goroutine-per-port + slog JSONHandler are standard, well-documented patterns
- Pitfalls: HIGH — each pitfall derived from explicit API behavior (WriteHeader ordering, signal handling, etc.) verified in stdlib docs

**Research date:** 2026-03-25
**Valid until:** 2026-09-25 (stable stdlib APIs; `log/slog` is mature since Go 1.21)
