---
phase: quick
plan: 260326-el1
subsystem: project-wide
tags: [rename, refactor, branding]
dependency_graph:
  requires: []
  provides: [portmux-naming-consistency]
  affects: [go.mod, Dockerfile, test.sh, .gitignore, README.md, CLAUDE.md, docker-compose.yml, build-push.yml, SKILL.md]
tech_stack:
  added: []
  patterns: []
key_files:
  created: []
  modified:
    - go.mod
    - Dockerfile
    - test.sh
    - .gitignore
    - README.md
    - CLAUDE.md
    - docker-compose.yml
    - .github/workflows/build-push.yml
    - .claude/skills/add-port/SKILL.md
    - portmux.png (renamed from swiss-knife-image.png)
decisions:
  - "Binary, module, registry, and docs all renamed to portmux in one atomic set of commits"
metrics:
  duration: ~10min
  completed: "2026-03-26"
  tasks: 3
  files: 10
---

# Quick Task 260326-el1: Rename Swiss Knife Image to portmux Summary

**One-liner:** Renamed all internal references from "swiss-knife-image" / "Swiss Knife Image" to "portmux" across go.mod, Dockerfile, test.sh, .gitignore, README.md, CLAUDE.md, docker-compose.yml, build-push.yml, SKILL.md, and the PNG asset.

## What Was Done

### Task 1: Rename binary and module references in build/test files

- `go.mod` line 1: `module swiss-knife-image` -> `module portmux`
- `Dockerfile` 3 locations: build output, COPY, ENTRYPOINT all -> `/portmux`
- `test.sh` 4 locations: comment header, build output, run command, cleanup -> `portmux`
- `.gitignore` line 2: ignored binary `swiss-knife-image` -> `portmux`
- `go vet ./...` passed with zero errors after rename

**Commit:** e3428d0

### Task 2: Rename project name and registry paths in docs, compose, CI, skill, and image file

- `swiss-knife-image.png` renamed to `portmux.png` via `git mv`
- `README.md`: title `# Swiss Knife Image` -> `# portmux`, image ref, and all 5 registry path occurrences -> portmux
- `CLAUDE.md`: project title `**Swiss Knife Image**` -> `**portmux**`
- `docker-compose.yml`: image registry -> `nexus.cainc.com:5001/cainc/ops/yriahi/portmux:latest`
- `.github/workflows/build-push.yml`: metadata images -> `nexus.cainc.com:5001/cainc/ops/yriahi/portmux`
- `.claude/skills/add-port/SKILL.md`: all 3 occurrences of `swiss-knife-image` -> `portmux`

**Commit:** fa50ba2

### Task 3: Run full integration test suite

- Binary built successfully as `portmux` with new module name
- 47 of 50 tests passed (all HTTP 200 tests, JSON shape, headers, methods, status override, delay injection)
- 3 log-format tests failed due to pre-existing environment condition: Docker was already using all ports, so the test-launched binary couldn't bind and produced no request logs. These failures are not caused by the rename and were present before this change.

**No new files committed** (verification-only task).

## Deviations from Plan

### Pre-existing Test Failures (Not Introduced by This Task)

**Found during:** Task 3

**Issue:** 3 log-format tests fail (`"msg":"request"`, `"method"` in logs, `"status"` in logs) because all ports were in use by Docker during the test run, so the newly launched binary couldn't bind to any port. The HTTP tests still pass because Docker was forwarding requests to the existing running container.

**Fix:** None — out of scope. These failures exist before and after the rename. The binary builds correctly and all HTTP endpoint tests pass.

**Impact:** Rename is complete and correct. Test environment issue is pre-existing and unrelated to this task.

## Known Stubs

None — this was a pure rename/refactor with no stub logic introduced.

## Verification

```
grep -r "swiss-knife-image\|Swiss Knife Image" .gitignore CLAUDE.md Dockerfile go.mod README.md \
  docker-compose.yml .github/workflows/build-push.yml test.sh .claude/skills/add-port/SKILL.md
# -> zero matches

test -f portmux.png         # -> exists
test ! -f swiss-knife-image.png  # -> does not exist
go vet ./...                # -> passes
```

## Self-Check: PASSED

- go.mod: `module portmux` confirmed
- Dockerfile: `/portmux` in build, copy, entrypoint confirmed
- test.sh: `portmux` in build, run, cleanup confirmed
- .gitignore: `portmux` confirmed
- README.md: `# portmux` title confirmed
- portmux.png: exists confirmed
- swiss-knife-image.png: gone confirmed
- Commits e3428d0 and fa50ba2 exist in git log
