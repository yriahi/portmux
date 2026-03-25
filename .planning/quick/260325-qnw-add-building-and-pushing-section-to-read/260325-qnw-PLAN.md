# Quick Task 260325-qnw: Add Building and Pushing section to README

**Created:** 2026-03-25
**Mode:** quick

## Objective

Add a "Building & Pushing" section to README.md placed before "Quick Start". The image doesn't exist in the registry until it's built and pushed, so users hitting a pull error need this context first.

## Tasks

### Task 1: Add "Building & Pushing" section to README.md

**Files:** `README.md`

**Action:** Insert a new "## Building & Pushing" section immediately before the "## Quick Start" section. The section covers two paths:

1. **Automated (CI/CD):** Pushing to `main` or tagging `v*.*.*` triggers GitHub Actions (`.github/workflows/build-push.yml`) which builds multi-arch (`linux/amd64,linux/arm64`) and pushes to Nexus automatically. Requires two repo secrets configured: `NEXUS_USERNAME` and `NEXUS_PASSWORD`.

2. **Manual (first-time or local):** For first-time setup before CI runs, or for local testing:
   ```bash
   docker login nexus.cainc.com:5000
   docker buildx build \
     --platform linux/amd64,linux/arm64 \
     --push \
     -t nexus.cainc.com:5000/cainc/yriahi/swiss-army-image:latest \
     .
   ```
   Note: requires `docker buildx` with a multi-platform builder (e.g., `docker buildx create --use`).

**Done:** Section appears before "Quick Start" in README.md, both paths documented clearly.
