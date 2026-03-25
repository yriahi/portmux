---
phase: quick
plan: 260325-qnw
subsystem: documentation
tags: [readme, docker, buildx, ci-cd]
dependency_graph:
  requires: []
  provides: [readme-building-pushing-section]
  affects: []
tech_stack:
  added: []
  patterns: []
key_files:
  created: []
  modified:
    - README.md
decisions:
  - "Building & Pushing section placed before Quick Start — image must exist in registry before pull commands in Quick Start are useful"
metrics:
  duration: "~1 min"
  completed: "2026-03-25"
  tasks_completed: 1
  files_changed: 1
---

# Quick Task 260325-qnw: Add Building & Pushing Section to README Summary

**One-liner:** Added "Building & Pushing" section to README before Quick Start, covering CI/CD automated path and manual docker buildx command for first-time setup.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Add Building & Pushing section to README.md | f925654 | README.md |

## What Was Done

Inserted a new `## Building & Pushing` section immediately before `## Quick Start` in README.md. The section covers:

- **Automated (CI/CD):** GitHub Actions workflow triggered on push to `main` or `v*.*.*` tags; lists `NEXUS_USERNAME` and `NEXUS_PASSWORD` repo secrets required.
- **Manual (first-time or local):** `docker login` + `docker buildx build` command with `--platform linux/amd64,linux/arm64 --push`; note about creating a multi-platform builder with `docker buildx create --use`.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

- [x] README.md modified with Building & Pushing section before Quick Start
- [x] Commit f925654 exists
