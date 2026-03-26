#!/usr/bin/env bash
set -euo pipefail

# portmux — Integration smoke test
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
  rm -f portmux
}
trap cleanup EXIT

# ----- build -----------------------------------------------------------------

echo "=== Building binary ==="
go build -o portmux .
echo "Build OK"

# ----- start server ----------------------------------------------------------

echo ""
echo "=== Starting server ==="
./portmux > /tmp/sai-test-stdout.log 2>&1 &
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

for port in 8080 8181 8081 3000 5000 8000 8888 3306 5432 6379 9090 4040 9200 5601 27017; do
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

# ----- test g: status code override (?status=) --------------------------------

# Valid status override
HTTP_503=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/?status=503" 2>/dev/null || echo "000")
assert_eq "?status=503 returns HTTP 503" "503" "$HTTP_503"

HTTP_404=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/?status=404" 2>/dev/null || echo "000")
assert_eq "?status=404 returns HTTP 404" "404" "$HTTP_404"

# Response body still has correct JSON shape with status override
RESP_503=$(curl -s -o - -w "" "http://localhost:8080/test?status=503&foo=bar" 2>/dev/null)
assert_contains "status=503 response has port"         "$RESP_503" '"port":8080'
assert_contains "status=503 response has method"       "$RESP_503" '"method":"GET"'
assert_contains "status=503 response has path"         "$RESP_503" '"path":"/test"'
assert_contains "status=503 response has query_params" "$RESP_503" '"query_params"'
assert_contains "status=503 response has status param" "$RESP_503" '"status":"503"'
assert_contains "status=503 response has foo param"    "$RESP_503" '"foo":"bar"'

# Invalid status values silently ignored -> HTTP 200
HTTP_INVALID_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" "http://localhost:8080/?status=abc" 2>/dev/null || echo "000")
assert_eq "?status=abc returns HTTP 200 (invalid ignored)" "200" "$HTTP_INVALID_STATUS"

HTTP_OOR_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" "http://localhost:8080/?status=50" 2>/dev/null || echo "000")
assert_eq "?status=50 returns HTTP 200 (out-of-range ignored)" "200" "$HTTP_OOR_STATUS"

# ----- test h: delay injection (?delay=) --------------------------------------

# Measurable delay (200ms — long enough to measure, short enough for CI)
START_MS=$(python3 -c "import time; print(int(time.time()*1000))")
curl -sf -o /dev/null "http://localhost:8080/?delay=200" 2>/dev/null
END_MS=$(python3 -c "import time; print(int(time.time()*1000))")
ELAPSED_MS=$(( END_MS - START_MS ))

if [[ "$ELAPSED_MS" -ge 150 ]]; then
  pass "?delay=200 took ${ELAPSED_MS}ms (>= 150ms)"
else
  fail "?delay=200 took only ${ELAPSED_MS}ms (expected >= 150ms)"
fi

# No delay without param — should respond in < 100ms
START_MS2=$(python3 -c "import time; print(int(time.time()*1000))")
curl -sf -o /dev/null "http://localhost:8080/" 2>/dev/null
END_MS2=$(python3 -c "import time; print(int(time.time()*1000))")
ELAPSED_MS2=$(( END_MS2 - START_MS2 ))

if [[ "$ELAPSED_MS2" -lt 100 ]]; then
  pass "No delay param responds in ${ELAPSED_MS2}ms (< 100ms)"
else
  fail "No delay param took ${ELAPSED_MS2}ms (expected < 100ms)"
fi

# Invalid delay values silently ignored
HTTP_BAD_DELAY=$(curl -sf -o /dev/null -w "%{http_code}" "http://localhost:8080/?delay=abc" 2>/dev/null || echo "000")
assert_eq "?delay=abc returns HTTP 200 (invalid ignored)" "200" "$HTTP_BAD_DELAY"

HTTP_NEG_DELAY=$(curl -sf -o /dev/null -w "%{http_code}" "http://localhost:8080/?delay=-100" 2>/dev/null || echo "000")
assert_eq "?delay=-100 returns HTTP 200 (negative ignored)" "200" "$HTTP_NEG_DELAY"

# ----- test i: combined delay + status ----------------------------------------

HTTP_COMBINED=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/?delay=100&status=418" 2>/dev/null || echo "000")
assert_eq "?delay=100&status=418 returns HTTP 418" "418" "$HTTP_COMBINED"

# ----- test j: status field in request logs (D-07) ----------------------------

sleep 1
LOG_CONTENT2=$(cat /tmp/sai-test-stdout.log)
assert_contains "Log contains status field" "$LOG_CONTENT2" '"status"'

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
