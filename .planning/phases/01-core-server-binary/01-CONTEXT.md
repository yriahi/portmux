# Phase 1: Core Server Binary - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

A runnable Go binary that binds all 6 ports (80, 8080, 8181, 8081, 3000, 5000) simultaneously, returns HTTP 200 JSON with request metadata on any path and any method, logs every request to stdout as structured JSON, and shuts down cleanly on SIGTERM. No Dockerfile, no container, no CI/CD — that is Phase 2.

</domain>

<decisions>
## Implementation Decisions

### JSON Response Body (RESP-02)
- **D-01:** Flat `snake_case` structure — `port`, `method`, `path`, `timestamp`, `query_params`
- **D-02:** `query_params` is a JSON object (key/value map), not a string or array
- **D-03:** `timestamp` is ISO 8601 / RFC3339 format (e.g., `2026-03-25T12:00:00Z`)

Example shape:
```json
{
  "port":         8080,
  "method":       "GET",
  "path":         "/some/path",
  "timestamp":    "2026-03-25T12:00:00Z",
  "query_params": {"foo": "bar"}
}
```

### Port 80 Bind Failure (SRVR-01)
- **D-04:** If port 80 fails to bind (e.g., no root/CAP_NET_BIND_SERVICE locally), log the error and continue serving the other 5 ports — do not exit
- **D-05:** The error must be logged clearly so it is visible in docker logs, but it is non-fatal

### Structured Log Fields (LOG-01, LOG-02)
- **D-06:** Required fields per request: `port`, `method`, `path`, `timestamp`
- **D-07:** Also include `remote` (client IP:port) — useful for debugging which service/pod is hitting the stub
- **D-08:** Log format is structured JSON (machine-parseable for CloudWatch, Datadog, etc.)

Example log line:
```json
{"level":"info","msg":"request","port":8080,"method":"GET","path":"/foo","remote":"172.17.0.1:54321","time":"2026-03-25T12:00:00Z"}
```

### Startup Output
- **D-09:** On successful startup, emit a single JSON log line listing all ports that successfully bound
- **D-10:** Log line uses the same structured JSON format as request logs

Example startup line:
```json
{"level":"info","msg":"listening","ports":[80,8080,8181,8081,3000,5000],"time":"2026-03-25T12:00:00Z"}
```
(If port 80 fails: ports array contains only the 5 that succeeded, plus a separate error log line for the failure)

### Graceful Shutdown (SRVR-03)
- **D-11:** SIGTERM triggers graceful shutdown — drain in-flight requests, exit within 5 seconds (per requirements)

### Claude's Discretion
- Code structure: single `main.go` vs. multiple files — Claude decides based on what keeps it readable
- Error handling patterns for port bind errors beyond port 80
- goroutine coordination mechanism (errgroup, sync.WaitGroup, etc.)
- JSON serialization approach (stdlib `encoding/json` per CLAUDE.md stack)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` — Full requirement IDs for Phase 1: SRVR-01, SRVR-02, SRVR-03, RESP-01, RESP-02, RESP-03, LOG-01, LOG-02
- `.planning/PROJECT.md` — Constraints (HTTP only, multi-port, stateless, portability)

### Stack Decisions
- `CLAUDE.md` — Prescribed stack: Go 1.26.1, `net/http` stdlib, `encoding/json` stdlib, `CGO_ENABLED=0`, goroutine-per-port pattern, `FROM scratch` final image (Phase 2). CLAUDE.md explicitly rules out supervisord, socat, Node, Python, nginx for this use case.

No external ADRs or specs — all decisions captured above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — codebase is empty; this phase creates the first source files

### Established Patterns
- None yet — this phase establishes the patterns that Phase 2 will build on

### Integration Points
- Phase 2 will wrap this binary in a multi-stage Dockerfile; the binary must be a static Linux binary (`CGO_ENABLED=0 GOOS=linux`) to run on `FROM scratch`

</code_context>

<specifics>
## Specific Ideas

- JSON response body shape confirmed with explicit example during discussion (see D-01 through D-03)
- Startup banner confirmed with explicit example during discussion (see D-09, D-10)
- Port 80 bind failure is non-fatal by design — caller is expected to run with appropriate permissions in production (Docker with `-p 80:80` does not require root on the host)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 01-core-server-binary*
*Context gathered: 2026-03-25*
