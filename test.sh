#!/usr/bin/env bash
set -euo pipefail

# Swiss Army Image — Integration smoke test
# Tests: HTTP 200 on all non-privileged ports, JSON response shape,
# Content-Type header, multiple HTTP methods, structured JSON logs,
# graceful SIGTERM shutdown.

PASS=0
FAIL=0
SERVER_PID=""

# ----- helpers ---------------------------------------------------------------

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$desc"
  else
    fail "$desc (expected='$expected' actual='$actual')"
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    pass "$desc"
  else
    fail "$desc (string '$needle' not found in output)"
  fi
}

# ----- cleanup trap ----------------------------------------------------------

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f swiss-army-image
}
trap cleanup EXIT

# ----- build -----------------------------------------------------------------

echo "=== Building binary ==="
go build -o swiss-army-image .
echo "Build OK"

# ----- start server ----------------------------------------------------------

echo ""
echo "=== Starting server ==="
./swiss-army-image > /tmp/sai-test-stdout.log 2>&1 &
SERVER_PID=$!

# Wait for server to be ready (max 5 attempts)
READY=0
for i in $(seq 1 5); do
  sleep 1
  if curl -sf http://localhost:8080/ > /dev/null 2>&1; then
    READY=1
    echo "Server ready after ${i}s"
    break
  fi
  echo "Waiting for server... attempt $i/5"
done

if [[ "$READY" -eq 0 ]]; then
  echo "ERROR: Server failed to start within 5 seconds"
  cat /tmp/sai-test-stdout.log
  exit 1
fi

echo ""
echo "=== Running tests ==="

# ----- test a: HTTP 200 on all non-privileged ports --------------------------

for port in 8080 8181 8081 3000 5000; do
  HTTP_CODE=$(curl -sf -o /tmp/sai-resp.json -w "%{http_code}" "http://localhost:${port}/test/path" 2>/dev/null || echo "000")
  assert_eq "HTTP 200 on port $port" "200" "$HTTP_CODE"
done

# ----- test b: JSON response body shape --------------------------------------

RESP=$(curl -sf "http://localhost:8080/hello?foo=bar" 2>/dev/null)

assert_contains "Response has 'port' key"          "$RESP" '"port"'
assert_contains "Response has 'method' key"        "$RESP" '"method"'
assert_contains "Response has 'path' key"          "$RESP" '"path"'
assert_contains "Response has 'timestamp' key"     "$RESP" '"timestamp"'
assert_contains "Response has 'query_params' key"  "$RESP" '"query_params"'
assert_contains "Response port is 8080"            "$RESP" '"port":8080'
assert_contains "Response method is GET"           "$RESP" '"method":"GET"'
assert_contains "Response path is /hello"          "$RESP" '"path":"/hello"'
assert_contains "Response query_params contains foo" "$RESP" '"foo"'

# ----- test c: Content-Type header -------------------------------------------

RESP_HEADERS=$(curl -sf -D - -o /dev/null "http://localhost:8080/" 2>/dev/null)
assert_contains "Content-Type: application/json header present" "$RESP_HEADERS" "Content-Type: application/json"

# ----- test d: any HTTP method works -----------------------------------------

POST_RESP=$(curl -sf -X POST "http://localhost:8080/posttest" 2>/dev/null)
assert_contains "POST method reflected"   "$POST_RESP" '"method":"POST"'

PUT_RESP=$(curl -sf -X PUT "http://localhost:8080/puttest" 2>/dev/null)
assert_contains "PUT method reflected"    "$PUT_RESP"  '"method":"PUT"'

DEL_RESP=$(curl -sf -X DELETE "http://localhost:8080/deltest" 2>/dev/null)
assert_contains "DELETE method reflected" "$DEL_RESP"  '"method":"DELETE"'

# ----- test e: structured JSON log output ------------------------------------

# Give server a moment to flush logs
sleep 1
LOG_CONTENT=$(cat /tmp/sai-test-stdout.log)

assert_contains "Startup log contains msg:listening" "$LOG_CONTENT" '"msg":"listening"'
assert_contains "Startup log contains ports"         "$LOG_CONTENT" '"ports"'
assert_contains "Request log contains msg:request"   "$LOG_CONTENT" '"msg":"request"'
assert_contains "Request log contains port"          "$LOG_CONTENT" '"port"'
assert_contains "Request log contains method"        "$LOG_CONTENT" '"method"'

# ----- test f: graceful SIGTERM shutdown ------------------------------------

echo ""
echo "=== Testing graceful shutdown ==="
START=$(date +%s)

kill -TERM "$SERVER_PID"
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""  # already waited; prevent double-wait in cleanup

END=$(date +%s)
ELAPSED=$(( END - START ))

if [[ "$ELAPSED" -lt 5 ]]; then
  pass "Graceful shutdown completed in ${ELAPSED}s (< 5s)"
else
  fail "Graceful shutdown took ${ELAPSED}s (>= 5s)"
fi

# ----- summary ---------------------------------------------------------------

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
