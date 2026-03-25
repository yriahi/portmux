# Phase 3: Behavioral Enhancements - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 03-behavioral-enhancements
**Areas discussed:** Invalid param handling, Delay safety cap, Control params in response body, Log line for injected status

---

## Invalid Param Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Silently ignore, use defaults | Invalid delay → no delay. Invalid status → 200. Clean for a stub. | ✓ |
| Return 400 Bad Request | Invalid param values return HTTP 400 with JSON error body. | |
| Clamp to safe range | Negative delay → 0. Status outside 100–599 → 200. Silent correction. | |

**User's choice:** Silently ignore and use defaults
**Notes:** Keeps the stub clean — callers with bad params still get a valid 200 response, consistent with the "no 404s, no errors" philosophy of the image.

---

## Delay Safety Cap

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — 30 seconds | Cap at 30,000 ms, anything higher silently clamped. | ✓ |
| Yes — 60 seconds | More generous cap for long timeout scenarios. | |
| No cap — Claude decides | No ceiling enforced. | |

**User's choice:** 30 second cap
**Notes:** Prevents accidental connection exhaustion in load tests or probe storms.

---

## Control Params in Response Body

| Option | Description | Selected |
|--------|-------------|----------|
| Echo as-is | delay and status appear in query_params like any other param. | ✓ |
| Filter them out | delay and status stripped; only business params appear. | |

**User's choice:** Echo as-is — no filtering
**Notes:** Consistent with Phase 1 design where all query params are echoed. Keeps the handler simple with no special-case filtering logic.

---

## Log Line for Injected Status

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — add status to log line | Log includes "status": 503 when injected. | ✓ |
| No — keep log fields unchanged | Log stays as-is: port, method, path, remote, time. | |

**User's choice:** Add status field to every request log line
**Notes:** Makes injected error scenarios visible in CloudWatch/Datadog without needing to correlate with response bodies.

---

## Claude's Discretion

- Where to place `time.Sleep` within the handler closure
- Whether to extract delay/status parsing to a helper function or inline it
- Go idiom for clamping the delay value

## Deferred Ideas

None — discussion stayed within phase scope.
