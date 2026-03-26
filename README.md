# Swiss Knife Image

![Swiss Knife Image](swiss-knife-image.png)

A lightweight Docker image that acts as a universal HTTP stub for testing containerized service scaffolding. It listens simultaneously on ports 80, 3000, 3306, 4040, 5000, 5432, 5601, 6379, 8000, 8080, 8081, 8181, 8888, 9090, 9200, and 27017, and returns HTTP 200 with JSON request metadata on every path regardless of method or URL. Drop it in wherever a real Node.js, React, Next.js, Java, or Spring Boot container would run to validate networking, routing, proxies, load balancers, and health probes — without needing real application code.

## Building & Pushing

The image must be built and pushed to the registry before it can be pulled. Two paths are supported:

### Automated (CI/CD)

Pushing to `main` or tagging `v*.*.*` triggers the GitHub Actions workflow (`.github/workflows/build-push.yml`), which builds a multi-arch image (`linux/amd64`, `linux/arm64`) and pushes it to Nexus automatically.

**Required repo secrets:**

| Secret | Description |
|--------|-------------|
| `NEXUS_USERNAME` | Nexus registry username |
| `NEXUS_PASSWORD` | Nexus registry password |

### Manual (first-time or local)

For first-time setup before CI runs, or for local testing:

```bash
docker login nexus.cainc.com:5001
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push \
  -t nexus.cainc.com:5001/cainc/ops/yriahi/swiss-knife-image:latest \
  .
```

> **Note:** Requires `docker buildx` with a multi-platform builder. If you haven't set one up, run `docker buildx create --use` first.

## Quick Start

### docker run

```bash
docker run \
  -p 80:80 \
  -p 8080:8080 \
  -p 8181:8181 \
  -p 8081:8081 \
  -p 3000:3000 \
  -p 5000:5000 \
  -p 3306:3306 \
  -p 5601:5601 \
  -p 4040:4040 \
  -p 5432:5432 \
  -p 6379:6379 \
  -p 8000:8000 \
  -p 8888:8888 \
  -p 9090:9090 \
  -p 9200:9200 \
  -p 27017:27017 \
  nexus.cainc.com:5001/cainc/ops/yriahi/swiss-knife-image:latest
```

### docker compose

Save the following as `docker-compose.yml` (or use the one included in this repo):

```yaml
services:
  stub:
    image: nexus.cainc.com:5001/cainc/ops/yriahi/swiss-knife-image:latest
    ports:
      - "80:80"
      - "8080:8080"
      - "8181:8181"
      - "8081:8081"
      - "3000:3000"
      - "5000:5000"
      - "3306:3306"
      - "4040:4040"
      - "5601:5601"
      - "5432:5432"
      - "6379:6379"
      - "8000:8000"
      - "8888:8888"
      - "9090:9090"
      - "9200:9200"
      - "27017:27017"
```

Then start it:

```bash
docker compose up
```

## Sample Response

Every request — any path, any HTTP method — returns HTTP 200 with a JSON body:

```json
{
  "port": 8080,
  "method": "GET",
  "path": "/",
  "timestamp": "2026-03-25T12:00:00Z",
  "query_params": {}
}
```

**Field reference:**

| Field | Type | Description |
|-------|------|-------------|
| `port` | int | The port that received the request |
| `method` | string | HTTP method (GET, POST, PUT, etc.) |
| `path` | string | Request path |
| `timestamp` | string | ISO 8601 UTC timestamp of the request |
| `query_params` | object | Key-value pairs from the query string |

## Ports

| Port | Common Framework |
|------|----------------|
| 80 | nginx, Apache, generic HTTP |
| 3000 | Node.js (Express, Next.js, React dev) |
| 3306 | MySQL, MariaDB |
| 4040 | Spark UI |
| 5000 | Flask, Python dev servers |
| 5432 | PostgreSQL |
| 5601 | Kibana |
| 6379 | Redis |
| 8000 | Django, uvicorn, generic HTTP alt |
| 8080 | Spring Boot, Tomcat, generic app server |
| 8081 | Alternative app server port |
| 8181 | Karaf, some microservice frameworks |
| 8888 | Jupyter Notebook, secondary proxy |
| 9090 | Prometheus, management dashboards |
| 9200 | Elasticsearch HTTP |
| 27017 | MongoDB |

> **Note:** Port 80 requires root or `CAP_NET_BIND_SERVICE`. If it fails to bind, the other 15 ports still work.

## Image Details

| Property | Value |
|----------|-------|
| Base image | `FROM scratch` (~5 MB, zero OS overhead) |
| Architectures | `linux/amd64`, `linux/arm64` |
| Registry | `nexus.cainc.com:5001/cainc/ops/yriahi/swiss-knife-image` |
| Tags | `:latest`, `:main`, semver (e.g., `:v1.0.0`) |
