# Subagent Contracts

Five mandatory subagents used by the loop phase. Each is dispatched via `runSubagent` with the corresponding prompt file from `.github/skills/rw-loop/assets/`.

---

## 1. Coder (`rw-loop-coder.subagent.md`)

**Purpose**: Implement exactly one locked task using TDD discipline.

**Inputs**: `LOCKED_TASK_ID`, `.ai/PROGRESS.md`, `.ai/tasks/TASK-*.md`, `.ai/runtime/rw-active-plan-id.txt`, `.ai/plans/<PLAN_ID>/task-graph.yaml`

**Mandatory Workflow**:
1. Read task fully (User Path, Acceptance Criteria, Accessibility Criteria, Verification).
2. Write tests first for requested behavior.
3. Run tests → confirm at least one targeted failure.
4. Implement minimum code to pass tests.
5. Re-run tests → confirm pass.
6. Run task-level verification commands from task file (scoped/fast checks for this task only).
7. Verify user entry wiring: feature reachable from existing navigation (UI/CLI/API).
8. For runtime-visible behavior tasks, run runtime scenario command(s) from Verification and capture artifact path(s).
9. Transition `LOCKED_TASK_ID` status from `in-progress` to `completed` in all synchronized state artifacts in the same dispatch cycle:
   - `.ai/PROGRESS.md` task row `Status`
   - task file frontmatter `status`
   - `task-graph.yaml` node `status`
10. Append evidence log:
   ```
   VERIFICATION_EVIDENCE <LOCKED_TASK_ID> <UNIT|INTEGRATION|ACCEPTANCE>: command="<cmd>" exit_code=<code> key_output="<summary>"
   ```

**Evidence Requirements**:
- One failing test evidence (exit_code != 0) before implementation
- One passing test evidence (exit_code = 0) after implementation
- One user-path verification evidence entry
- For runtime-visible behavior tasks: one runtime evidence entry with artifact path(s)

**Rules**: Complete only the locked task. Update status for exactly one locked task across synchronized state artifacts. Do not mutate `.ai/runtime/rw-strike-state.yaml`. Commit with conventional message. Never call `runSubagent`. Always append one line:
`APPROACH_SUMMARY <LOCKED_TASK_ID>: "<single-line summary>"` (max 200 chars, no newlines, escape inner `"` as `\"`).

---

## 2. Task Inspector (`rw-loop-task-inspector.subagent.md`)

**Purpose**: Skeptically verify task completion against acceptance criteria + user path.

**Inputs**: `LOCKED_TASK_ID`, task file, progress file, latest commit

**Workflow**:
1. Verify preflight using task-level verification commands from task verification section (scoped/fast checks).
2. Validate all acceptance + accessibility criteria.
3. Validate user accessibility path (feature reachable by user flow).
4. Validate runtime behavior gate:
   - runtime-visible behavior tasks must include runtime evidence artifact(s)
   - if acceptance includes error handling, verify error state is user-visible in UI/UX path

**Output** (always emit all three tokens):
- Pass: `TASK_INSPECTION=PASS`, `USER_PATH_GATE=PASS`, `RUNTIME_GATE=PASS`, append `REVIEW_OK`
- Fail: `TASK_INSPECTION=FAIL`, `USER_PATH_GATE=PASS` if user path intact / `USER_PATH_GATE=FAIL` if broken, `RUNTIME_GATE=PASS|FAIL` by runtime evidence status, append `REVIEW_FAIL` + `REVIEW_FINDING <LOCKED_TASK_ID> <P0|P1|P2>|<file>|<line>|<rule>|<fix>`

---

## 3. Security Review (`rw-loop-security-review.subagent.md`)

**Purpose**: Catch critical security regressions before task completion.

**Triggers**: Always run for auth, tokens, secrets, credentials, permissions, roles, payment, user data, external APIs.

**Checks**:
- Hardcoded secrets/tokens
- Missing authorization checks on privileged paths
- Unsafe input handling (injection vectors)
- Sensitive data leakage in logs/errors

**Output**:
- Pass: `SECURITY_GATE=PASS`, `SECURITY_FINDINGS=0`
- Fail: `SECURITY_GATE=FAIL`, `SECURITY_FINDINGS=<n>`, append `SECURITY_FINDING <LOCKED_TASK_ID> <CRITICAL|HIGH|MEDIUM>|<file>|<line>|<rule>|<fix>`

---

## 4. Phase Inspector (`rw-loop-phase-inspector.subagent.md`)

**Purpose**: Verify phase-level integration when all phase tasks complete.

**Inputs**: `.ai/PROGRESS.md`, `.ai/tasks/TASK-*.md`, `.ai/tasks/TASK-00-READBEFORE.md`, `.ai/runtime/rw-active-plan-id.txt`, `.ai/plans/<PLAN_ID>/task-graph.yaml`, `.ai/runtime/rw-strike-state.yaml` (if exists), recent commits for current phase

**Checks**:
1. Status consistency for every phase task across:
   - `.ai/PROGRESS.md` row `Status`
   - task frontmatter `status`
   - `task-graph.yaml` node `status`
2. Phase-level coverage and integration between tasks.
3. No unresolved `REVIEW-ESCALATE` lines.
4. No task marked `blocked` in current phase.
5. Completed tasks must have `strike.active=0` and `security.active=0` in `.ai/runtime/rw-strike-state.yaml` (if file exists).
6. Run every command listed under `Phase Gate Verification Commands` in `TASK-00-READBEFORE.md`.
   - If section is missing/empty (legacy plan), infer best available full regression set (project-wide build + full test + key user-path smoke) and run those.
   - Any non-zero exit must fail phase approval.

**Output**:
- Pass: `PHASE_INSPECTION=PASS`, `PHASE_REVIEW_STATUS=APPROVED`
- Fail (fixable): `PHASE_INSPECTION=FAIL`, `PHASE_REVIEW_STATUS=NEEDS_REVISION`
- Fail (critical): `PHASE_INSPECTION=FAIL`, `PHASE_REVIEW_STATUS=FAILED`, append `REVIEW-ESCALATE`

---

## 5. Review (`rw-loop-review.subagent.md`)

**Purpose**: Final completion/escalation decision when all tasks are done.

**Inputs**: `.ai/tasks/TASK-00-READBEFORE.md`, all task-inspection results for current run

**Output**:
- `REVIEW_STATUS=OK` → success
- `REVIEW_STATUS=FAIL` → fixable issue
- `REVIEW_STATUS=ESCALATE` → critical blocker (3+ failures same task), append `REVIEW-ESCALATE`

**Rule**: Before emitting `REVIEW_STATUS=OK`, run every command listed under `Final Gate Verification Commands` in `TASK-00-READBEFORE.md`.
- If section is missing/empty (legacy plan), infer best available full regression set (project-wide build + full test + key user-path smoke) and run those.
- Any non-zero exit must emit `REVIEW_STATUS=FAIL`.

---

## Common Rules for All Subagents

- Loop orchestrator must run both before dispatch (preflight):
  - `python .github/skills/rw-loop/scripts/check_state_sync.py`
  - `python .github/skills/rw-loop/scripts/env_preflight.py`
- Never call `runSubagent` from within a subagent.
- Keep findings factual and actionable.
- Use exact token format for machine-readable output.
- `APPROACH_SUMMARY` is orchestrator-consumed only and is not a contract token.
- Strike state ownership stays in loop orchestrator:
  - `rw-strike-state.yaml` uses `total` (lifetime) and `active` (current unresolved) counters.
  - Subagents must not directly increment/decrement strike counters.
