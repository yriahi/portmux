# Phase 1: Core Server Binary - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 01-core-server-binary
**Areas discussed:** JSON response shape, Port 80 bind failure, Log field richness, Startup output

---

## JSON Response Shape

| Option | Description | Selected |
|--------|-------------|----------|
| Flat snake_case | Simple, consistent with Go conventions and most API tooling | ✓ |
| Flat camelCase | Matches JavaScript/JSON conventions if consumers are JS-heavy | |
| Nested request object | Groups metadata under a 'request' key, leaves room for future fields at top level | |

**User's choice:** Flat snake_case
**Notes:** Confirmed with explicit JSON preview — `port`, `method`, `path`, `timestamp`, `query_params`

---

## Port 80 Bind Failure

| Option | Description | Selected |
|--------|-------------|----------|
| Fail fast — exit immediately | Consistent and predictable: any required port fails, whole process exits | |
| Continue without port 80 | Log the error and keep the other 5 ports running | ✓ |
| Log warning, keep going | Same as continue but with a loud WARNING on startup | |

**User's choice:** Continue without port 80
**Notes:** Non-fatal bind failure — log the error clearly but keep serving remaining ports

---

## Log Field Richness

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal — required fields only | Exactly what REQUIREMENTS say: port, method, path, timestamp | |
| Add remote IP | Include client IP address | ✓ |
| Add remote IP + duration | Include client IP and response duration in ms | |

**User's choice:** Add remote IP
**Notes:** `remote` field (IP:port) helps identify which service/pod is hitting the stub

---

## Startup Output

| Option | Description | Selected |
|--------|-------------|----------|
| Startup banner | Single JSON log line listing all successfully bound ports | ✓ |
| Silent start | No startup output; first log line is the first request | |
| Port-by-port lines | One log line per port as it binds | |

**User's choice:** Startup banner
**Notes:** Confirmed with explicit JSON preview — `{"level":"info","msg":"listening","ports":[...],"time":"..."}`

---

## Claude's Discretion

- Code structure (single file vs. multiple files)
- goroutine coordination mechanism
- JSON serialization approach (encoding/json per stack)
- Error handling for non-port-80 bind failures

## Deferred Ideas

None.
