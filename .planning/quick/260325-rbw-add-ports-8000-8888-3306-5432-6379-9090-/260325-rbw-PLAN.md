---
phase: quick
plan: 260325-rbw
type: execute
wave: 1
depends_on: []
files_modified:
  - main.go
  - test.sh
  - README.md
  - docker-compose.yml
autonomous: true
must_haves:
  truths:
    - "Server listens on all 12 ports: 80, 8080, 8181, 8081, 3000, 5000, 8000, 8888, 3306, 5432, 6379, 9090"
    - "Requests to each new port return HTTP 200 with correct JSON response including the port number"
    - "README documents all 12 ports with their common framework descriptions"
    - "docker-compose.yml maps all 12 ports"
  artifacts:
    - path: "main.go"
      provides: "Port list with all 12 ports"
      contains: "8000, 8888, 3306, 5432, 6379, 9090"
    - path: "test.sh"
      provides: "Integration tests for all non-privileged ports"
      contains: "8000 8888 3306 5432 6379 9090"
    - path: "README.md"
      provides: "Port reference table with 12 entries"
    - path: "docker-compose.yml"
      provides: "Port mappings for all 12 ports"
  key_links:
    - from: "main.go"
      to: "handler.go"
      via: "makeHandler(port) called for each port in the slice"
      pattern: "ports = \\[\\]int"
---

<objective>
Add 6 new ports (8000, 8888, 3306, 5432, 6379, 9090) to the swiss-army-image server so it can stub MySQL, PostgreSQL, Redis, Prometheus, Jupyter, and additional web server ports.

Purpose: Expand port coverage to database and monitoring service ports for broader scaffolding validation.
Output: Updated main.go, test.sh, README.md, docker-compose.yml with all 12 ports.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@main.go
@handler.go
@test.sh
@README.md
@docker-compose.yml
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add new ports to server and update tests</name>
  <files>main.go, test.sh</files>
  <action>
In main.go line 16, expand the ports slice to include the 6 new ports:
```go
var ports = []int{80, 8080, 8181, 8081, 3000, 5000, 8000, 8888, 3306, 5432, 6379, 9090}
```

No changes needed to handler.go — makeHandler already works with any port number via closure.

In test.sh, update the port loop on line 83 to include all non-privileged ports:
```bash
for port in 8080 8181 8081 3000 5000 8000 8888 3306 5432 6379 9090; do
```

This adds the 6 new ports to the HTTP 200 smoke test loop. Port 80 remains excluded (requires root/CAP_NET_BIND_SERVICE).
  </action>
  <verify>
    <automated>cd /Users/yriahi/Development/swiss-army-image && bash test.sh</automated>
  </verify>
  <done>Server binds all 12 ports, test.sh passes with HTTP 200 assertions on all 11 non-privileged ports</done>
</task>

<task type="auto">
  <name>Task 2: Update README and docker-compose with new ports</name>
  <files>README.md, docker-compose.yml</files>
  <action>
In README.md, update THREE sections:

1. Opening paragraph (line 1): Update port list text from "ports 80, 8080, 8181, 8081, 3000, and 5000" to "ports 80, 3000, 3306, 5000, 5432, 6379, 8000, 8080, 8081, 8181, 8888, and 9090".

2. docker run example (lines 40-48): Add 6 new -p flags:
```
  -p 3306:3306 \
  -p 5432:5432 \
  -p 6379:6379 \
  -p 8000:8000 \
  -p 8888:8888 \
  -p 9090:9090 \
```

3. docker compose example (lines 55-65): Add 6 new port strings in the ports list.

4. Ports table (lines 99-107): Add 6 new rows:
| 8000 | Django, uvicorn, generic HTTP alt |
| 8888 | Jupyter Notebook, secondary proxy |
| 3306 | MySQL, MariaDB |
| 5432 | PostgreSQL |
| 6379 | Redis |
| 9090 | Prometheus, management dashboards |

5. Port 80 note (line 108): Update "the other 5 ports" to "the other 11 ports".

In docker-compose.yml, add 6 new port mappings after the existing ones:
```yaml
      - "3306:3306"
      - "5432:5432"
      - "6379:6379"
      - "8000:8000"
      - "8888:8888"
      - "9090:9090"
```
  </action>
  <verify>
    <automated>cd /Users/yriahi/Development/swiss-army-image && grep -c "9090" README.md && grep -c "9090" docker-compose.yml && grep "3306" README.md | head -3</automated>
  </verify>
  <done>README.md documents all 12 ports in the table, docker run, and docker compose examples. docker-compose.yml maps all 12 ports. Port 80 note references 11 remaining ports.</done>
</task>

</tasks>

<verification>
- `bash test.sh` passes with all 11 non-privileged port assertions (including 6 new ones)
- `grep -c "9090" README.md` returns at least 3 (table + docker run + docker compose)
- `grep -c "9090" docker-compose.yml` returns 1
- `docker compose config` validates without errors
</verification>

<success_criteria>
- Server listens on all 12 ports and returns correct JSON on each
- Integration tests pass for all non-privileged ports
- README port table has 12 entries with accurate descriptions
- docker run and docker compose examples show all 12 port mappings
- docker-compose.yml has all 12 port mappings
</success_criteria>

<output>
After completion, create `.planning/quick/260325-rbw-add-ports-8000-8888-3306-5432-6379-9090-/260325-rbw-SUMMARY.md`
</output>
