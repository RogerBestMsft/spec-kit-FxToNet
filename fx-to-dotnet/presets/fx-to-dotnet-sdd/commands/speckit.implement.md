---
description: "Execute the implementation plan by processing all tasks, with automatic .NET Framework migration execution before user-story tasks and post-migration verification"
scripts:
  sh: scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks
  ps: scripts/powershell/check-prerequisites.ps1 -Json -RequireTasks -IncludeTasks
commands:
  - "speckit.fx-to-dotnet.convert"
  - "speckit.fx-to-dotnet.update-packages"
  - "speckit.fx-to-dotnet.multitarget-migrate"
  - "speckit.fx-to-dotnet.web-migrate"
  - "speckit.fx-to-dotnet.fix"
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution: Migration Task Execution (fx-to-dotnet integration)

**Before starting the core implementation workflow**, execute all pending migration tasks.

Invoke `speckit.fx-to-dotnet.implement-hook` — this command:
- Reads `tasks.md` for `[MIG]`-tagged migration tasks
- If `[MIG]` tasks exist:
  - Executes them in order by dispatching to FxToNet commands (`speckit.fx-to-dotnet.convert`, `speckit.fx-to-dotnet.update-packages`, `speckit.fx-to-dotnet.multitarget-migrate`, `speckit.fx-to-dotnet.web-migrate`)
  - Marks each task `[X]` as it completes
  - Provides layer checkpoints and phase transition prompts
  - Updates `.fx-to-dotnet/plan.md` with completion status
  - Appends a "Migration Execution Summary" to the SDD plan.md
  - Inserts a "Migration Complete" checkpoint above remaining user-story tasks
- If no `[MIG]` tasks are found, exits silently and control falls through immediately

Wait for the implement-hook command to complete before proceeding to the core implementation workflow below.

---

## Outline

1. Run `{SCRIPT}` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Check checklists status** (if FEATURE_DIR/checklists/ exists):
   - Scan all checklist files in the checklists/ directory
   - For each checklist, count:
     - Total items: All lines matching `- [ ]` or `- [X]` or `- [x]`
     - Completed items: Lines matching `- [X]` or `- [x]`
     - Incomplete items: Lines matching `- [ ]`
   - Create a status table:

     ```text
     | Checklist | Total | Completed | Incomplete | Status |
     |-----------|-------|-----------|------------|--------|
     | ux.md     | 12    | 12        | 0          | ✓ PASS |
     | test.md   | 8     | 5         | 3          | ✗ FAIL |
     ```

   - **If any checklist is incomplete**:
     - Display the table with incomplete item counts
     - **STOP** and ask: "Some checklists are incomplete. Do you want to proceed with implementation anyway? (yes/no)"
     - Wait for user response before continuing

   - **If all checklists are complete**: Proceed automatically

3. Load and analyze the implementation context:
   - **REQUIRED**: Read tasks.md for the complete task list and execution plan
   - **REQUIRED**: Read plan.md for tech stack, architecture, and file structure
   - **IF EXISTS**: Read data-model.md for entities and relationships
   - **IF EXISTS**: Read contracts/ for API specifications and test requirements
   - **IF EXISTS**: Read research.md for technical decisions and constraints
   - **IF EXISTS**: Read quickstart.md for integration scenarios

4. **Project Setup Verification**:
   - **REQUIRED**: Create/verify ignore files based on actual project setup:

   **Detection & Creation Logic**:
   - Check if the repository is a git repo (create/verify .gitignore if so)
   - Check if Dockerfile* exists or Docker in plan.md → create/verify .dockerignore
   - Check for other tool-specific ignore files as needed

   **Common Patterns by Technology** (from plan.md tech stack):
   - **C#/.NET**: `bin/`, `obj/`, `*.user`, `*.suo`, `packages/`
   - **Node.js/JavaScript/TypeScript**: `node_modules/`, `dist/`, `build/`, `*.log`, `.env*`
   - **Python**: `__pycache__/`, `*.pyc`, `.venv/`, `venv/`, `dist/`, `*.egg-info/`
   - **Universal**: `.DS_Store`, `Thumbs.db`, `*.tmp`, `*.swp`, `.vscode/`, `.idea/`

5. Parse tasks.md structure and extract:
   - **Task phases**: Setup, Tests, Core, Integration, Polish
   - **Task dependencies**: Sequential vs parallel execution rules
   - **Task details**: ID, description, file paths, parallel markers [P]
   - **Execution flow**: Order and dependency requirements
   - **Note**: Skip any `[MIG]`-tagged tasks that were already completed by the implement-hook in the Pre-Execution step above. Only process remaining non-`[MIG]` tasks (or any `[MIG]` tasks that were skipped).

6. Execute implementation following the task plan:
   - **Phase-by-phase execution**: Complete each phase before moving to the next
   - **Respect dependencies**: Run sequential tasks in order, parallel tasks [P] can run together
   - **Follow TDD approach**: Execute test tasks before their corresponding implementation tasks
   - **File-based coordination**: Tasks affecting the same files must run sequentially
   - **Validation checkpoints**: Verify each phase completion before proceeding

7. Implementation execution rules:
   - **Setup first**: Initialize project structure, dependencies, configuration
   - **Tests before code**: If you need to write tests for contracts, entities, and integration scenarios
   - **Core development**: Implement models, services, CLI commands, endpoints
   - **Integration work**: Database connections, middleware, logging, external services
   - **Polish and validation**: Unit tests, performance optimization, documentation

8. Progress tracking and error handling:
   - Report progress after each completed task
   - Halt execution if any non-parallel task fails
   - For parallel tasks [P], continue with successful tasks, report failed ones
   - Provide clear error messages with context for debugging
   - Suggest next steps if implementation cannot proceed
   - **IMPORTANT** For completed tasks, make sure to mark the task off as [X] in the tasks file.

9. Completion validation:
   - Verify all required tasks are completed
   - Check that implemented features match the original specification
   - Validate that tests pass and coverage meets requirements
   - Confirm the implementation follows the technical plan
   - Report final status with summary of completed work

Note: This command assumes a complete task breakdown exists in tasks.md. If tasks are incomplete or missing, suggest running `/speckit.tasks` first to regenerate the task list.

10. **Post-Migration Verification (fx-to-dotnet integration)**: After completion validation, run migration verification.

    Invoke `speckit.fx-to-dotnet.verify-hook` — this command:
    - Checks if `.fx-to-dotnet/plan.md` exists (migration context)
    - If migration context is found:
      - Audits `[MIG]` task completion status in tasks.md
      - Runs a full solution build to verify compilation
      - Generates `.fx-to-dotnet/completion.md` with build results, task summary, and remaining work
      - Appends "Migration Verification" sections to SDD plan.md and tasks.md
      - Reports build status and any incomplete migration tasks
    - If no migration context is found, exits silently

    Wait for the verify-hook command to complete before finishing.
