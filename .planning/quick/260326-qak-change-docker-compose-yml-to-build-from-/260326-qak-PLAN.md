---
phase: quick
plan: 260326-qak
type: execute
wave: 1
depends_on: []
files_modified: [docker-compose.yml]
autonomous: true
requirements: []
must_haves:
  truths:
    - "docker-compose.yml builds from local Dockerfile instead of pulling remote image"
    - "All existing port mappings are preserved"
  artifacts:
    - path: "docker-compose.yml"
      provides: "Local build configuration"
      contains: "build:"
  key_links:
    - from: "docker-compose.yml"
      to: "Dockerfile"
      via: "build context"
      pattern: "build:\\s*\\."
---

<objective>
Change docker-compose.yml to build from the local Dockerfile instead of pulling the remote Nexus image.

Purpose: Enable local development builds without depending on the remote Nexus registry.
Output: Updated docker-compose.yml with `build: .` replacing the `image:` directive.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@docker-compose.yml
@Dockerfile
</context>

<tasks>

<task type="auto">
  <name>Task 1: Switch docker-compose.yml from remote image to local build</name>
  <files>docker-compose.yml</files>
  <action>
    In docker-compose.yml, replace the `image: nexus.cainc.com:5001/cainc/ops/yriahi/portmux:latest` line with `build: .` so the service builds from the local Dockerfile. Keep the `image:` line as well but move it after `build:` so that `docker compose build` tags the locally-built image with that name. Preserve all existing port mappings exactly as they are.

    The result should look like:
    ```yaml
    services:
      stub:
        build: .
        image: nexus.cainc.com:5001/cainc/ops/yriahi/portmux:latest
        ports:
          - "80:80"
          ...
    ```

    Having both `build` and `image` means: compose builds from the local Dockerfile and tags the result with the image name, which is useful for subsequent pushes.
  </action>
  <verify>
    <automated>grep -q "build:" docker-compose.yml && grep -q "image:" docker-compose.yml && echo "PASS" || echo "FAIL"</automated>
  </verify>
  <done>docker-compose.yml has `build: .` directive and retains the image tag and all port mappings unchanged</done>
</task>

</tasks>

<verification>
- `docker-compose.yml` contains `build: .`
- `docker-compose.yml` retains the image name for tagging
- All port mappings (80, 8080, 8181, 8081, 3000, 5000, 3306, 5432, 6379, 8000, 8888, 9090, 4040, 5601, 9200, 27017) are present
</verification>

<success_criteria>
Running `docker compose config` shows a build context of `.` and all 16 port mappings.
</success_criteria>

<output>
After completion, create `.planning/quick/260326-qak-change-docker-compose-yml-to-build-from-/260326-qak-SUMMARY.md`
</output>
