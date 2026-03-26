---
name: add-port
description: >
  Add one or more ports to the swiss-knife-image multiport HTTP stub server.
  Use this skill whenever the user says "add port", "add ports", mentions a
  port number they want added, or says something like "also listen on 9200" or
  "support port 4000". Triggers on single ports and comma/space-separated lists.
  After adding, this skill runs the full test suite to confirm nothing broke.
---

# add-port skill

Add one or more ports to the swiss-knife-image multiport HTTP stub server.

## What this skill does

For each port number provided, update **4 files (7 edit points)** consistently:

1. `main.go` — `var ports = []int{...}` slice
2. `test.sh` — `for port in ...` test loop
3. `docker-compose.yml` — `ports:` section (4 edit points total in README below)
4. `README.md` — description line, `docker run` block, compose example block, and Ports table

> `handler.go` exists in this repo but contains no port config — do not edit it.

Then run `bash test.sh` to verify all ports respond correctly.

## Arguments

The skill accepts one or more port numbers as arguments:
- Single port: `add-port 9200`
- Multiple ports (space-separated): `add-port 9200 4040`
- Multiple ports (comma-separated): `add-port 9200, 4040`

If the user provides a description for the port (e.g., "add port 9200 for Elasticsearch"), capture it for the README ports table. Otherwise, use a known default from the table below, or use "custom" if unknown.

## Common port descriptions (use as defaults)

| Port | Framework/Service |
|------|------------------|
| 443  | HTTPS |
| 2181 | ZooKeeper |
| 2375 | Docker daemon (unencrypted) |
| 2376 | Docker daemon (TLS) |
| 4000 | Generic dev server |
| 4040 | Spark UI |
| 4200 | Angular dev server |
| 4567 | Sinatra (Ruby) |
| 5601 | Kibana |
| 7000 | Cassandra inter-node |
| 7001 | Cassandra TLS inter-node |
| 8161 | ActiveMQ admin |
| 8443 | HTTPS alt / Tomcat TLS |
| 8500 | Consul |
| 8600 | Consul DNS |
| 9000 | SonarQube, MinIO |
| 9092 | Kafka broker |
| 9200 | Elasticsearch HTTP |
| 9300 | Elasticsearch transport |
| 9411 | Zipkin |
| 11211| Memcached |
| 15672| RabbitMQ management UI |
| 27017| MongoDB |
| 61616| ActiveMQ broker |

If the port is not in this table and the user gave no description, use `"custom port ${PORT}"`.

## Step-by-step process

### Step 1: Parse and validate

- Extract all port numbers from the arguments (strip commas, spaces)
- Validate: each must be an integer 1–65535
- Check which ports already exist in `main.go`'s `var ports` slice — skip any that are already there and tell the user
- If all ports already exist, report and stop

### Step 2: Read current state

Read all 4 files to get their exact current content:
- `main.go`
- `test.sh`
- `docker-compose.yml`
- `README.md`

### Step 3: Update main.go

In the `var ports = []int{...}` line, append the new port(s) to the slice. Keep the existing order; append new ports at the end.

Example — adding 9200:
```go
// before
var ports = []int{80, 8080, 8181, 8081, 3000, 5000, 8000, 8888, 3306, 5432, 6379, 9090}

// after
var ports = []int{80, 8080, 8181, 8081, 3000, 5000, 8000, 8888, 3306, 5432, 6379, 9090, 9200}
```

### Step 4: Update test.sh

Add the new port(s) to the test loop. The loop looks like:
```bash
for port in 8080 8181 8081 3000 5000 8000 8888 3306 5432 6379 9090; do
```
Note: port 80 is intentionally excluded from the test loop (requires root). Only add ports that are NOT 80.

### Step 5: Update docker-compose.yml

Add `"PORT:PORT"` entries to the `ports:` section for each new port. Insert in numerically sorted position relative to existing entries.

### Step 6: Update README.md — 4 spots

**Spot 1:** Description line at the top. Find the sentence listing all ports (e.g., "It listens simultaneously on ports 80, 3000, 3306, ..."). Update it to include the new port(s), keeping the list **numerically sorted**.

**Spot 2:** `docker run` block. Add `-p PORT:PORT \` lines. The existing flags are in insertion order (not numerically sorted) — append new ports at the end, before the image name line.

**Spot 3:** Compose example block inside README. Add `"PORT:PORT"` entry in numerically sorted position.

**Spot 4:** Ports table (`## Ports` section). Add a new row `| PORT | DESCRIPTION |` in numerically sorted order.

Also update the count in the "Note" line at the bottom of the Ports section. It matches the pattern:
```
> **Note:** Port 80 requires root or `CAP_NET_BIND_SERVICE`. If it fails to bind, the other N ports still work.
```
Increment N by the number of ports successfully added.

### Step 7: Commit

Commit all 4 files atomically:
```
feat: add port(s) PORT1[, PORT2, ...] to swiss-knife-image
```

### Step 8: Run tests

```bash
bash test.sh
```

If tests pass: report success with the port count.
If tests fail: show the failure output. The port was added to the code — tell the user tests failed and what to check (port conflict, privileged port, etc.).

## Edge cases

- **Port 80**: Add to `main.go` and all docs, but skip in `test.sh` (requires root — the existing note about port 80 applies)
- **Port already in list**: Skip silently with a note to the user
- **Privileged ports < 1024 (except 80)**: Add them but warn the user they require root or `CAP_NET_BIND_SERVICE`
- **Invalid input** (non-numeric, out of range): Report clearly and skip
