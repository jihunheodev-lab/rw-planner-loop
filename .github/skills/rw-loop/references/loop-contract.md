# Loop Contract

Full deterministic contract for the implementation loop phase of rw-planner-loop skill.

## Step 0 (Mandatory)

1. Read `.ai/CONTEXT.md` first. If missing: print `LANG_POLICY_MISSING`, stop.
2. Ensure `.ai/PROGRESS.md` and `.ai/tasks/` exist. If missing: print `TARGET_ROOT_INVALID`, stop.
3. Ensure `runSubagent` is available. If unavailable: print `RW_ENV_UNSUPPORTED`, stop.
4. This mode never writes product code directly.
5. Ensure required subagent prompt files exist:
   - `.github/skills/rw-loop/assets/rw-loop-coder.subagent.md`
   - `.github/skills/rw-loop/assets/rw-loop-task-inspector.subagent.md`
   - `.github/skills/rw-loop/assets/rw-loop-security-review.subagent.md`
   - `.github/skills/rw-loop/assets/rw-loop-phase-inspector.subagent.md`
   - `.github/skills/rw-loop/assets/rw-loop-review.subagent.md`
   - If missing: print `RW_SUBAGENT_PROMPT_MISSING`, stop.
6. Ensure required preflight scripts exist:
   - `.github/skills/rw-loop/scripts/check_state_sync.py`
   - `.github/skills/rw-loop/scripts/env_preflight.py`
   - If missing: print `TARGET_ROOT_INVALID`, stop.
7. If `.ai/memory/shared-memory.md` exists, read it before loop start.
8. Read `.ai/runtime/rw-active-plan-id.txt`, then read matching `.ai/plans/<PLAN_ID>/task-graph.yaml` as primary dependency graph. If either file is missing/unreadable, print `TARGET_ROOT_INVALID`, stop.
9. Load `.ai/runtime/rw-strike-state.yaml` if present. If missing, initialize counters in memory and create it on first strike/security record.
10. Maintain strike state using this schema (per task):
   ```yaml
   tasks:
     TASK-XX:
       strike:
         total: 0
         active: 0
       security:
         total: 0
         active: 0
   ```
11. Counter semantics:
   - `total`: monotonic lifetime counter, never decremented, used for `dispatch_id`.
   - `active`: current unresolved counter, used for block/escalation thresholds.
   - Reset `active` counters to `0` when the task reaches `completed` with passing gates.
12. Resolve `PLANNING_PROFILE` for active feature:
   - source: active feature file linked by `.ai/PLAN.md` / feature key
   - default: `STANDARD` when missing
   - allowed values: `STANDARD`, `FAST_TEST`, `UX_STRICT`

## Mode Resolution

| Flag | HITL_MODE | PARALLEL_MODE |
|------|-----------|---------------|
| (default) | ON | ON |
| `--auto` or `--no-hitl` | OFF | ON |
| `--hitl` | ON | ON |
| `--parallel` | (unchanged) | ON |
| `--max-parallel=<n>` | (unchanged) | ON, clamped 1..4 |

When `PARALLEL_MODE=ON` and `--max-parallel` is omitted, `MAX_PARALLEL=4`.

## State Sync Contract

- Every task status must be synchronized across all state artifacts:
  1. `.ai/PROGRESS.md` task table row `Status`
  2. `.ai/tasks/TASK-XX-*.md` frontmatter `status`
  3. `.ai/plans/<PLAN_ID>/task-graph.yaml` node `status`
- Ownership:
  - Loop orchestrator sets `pending → in-progress` before dispatch and enforces gate-driven fallback (`in-progress`/`blocked`) after failures.
  - Coder subagent performs only `in-progress → completed` for `LOCKED_TASK_ID`, updating all synchronized state artifacts together.
  - Loop orchestrator validates status consistency after dispatch and after each gate.
  - Phase Inspector enforces phase-wide consistency before approval.
- Allowed machine status tokens remain unchanged: `pending`, `in-progress`, `completed`, `blocked`.
- Any mismatch among synchronized state artifacts is a contract violation:
  - print `RW_SUBAGENT_STATE_SYNC_INVALID`
  - stop current loop cycle

## Loop Policy

- Task priority: `in-progress` first, then `pending`. Never auto-select `blocked`.
- Single mode: one dispatch = exactly one task completed.
- Parallel mode: N dispatched = exactly N completed. Only independent tasks (no dependency relation).
- Dual quality gates:
  - Gate A (state contract): completion delta + state sync + evidence count.
  - Gate B (product behavior): runtime scenario evidence for user-observable behavior and error path.
- Every completed task must increase verification evidence count.
- Runtime-visible tasks must include runtime evidence artifact paths (for example screenshot/log/output file paths) in `VERIFICATION_EVIDENCE`.
- Task-level verification is scoped/fast per task. Full project regression checks run at phase/final gates using `TASK-00-READBEFORE.md` policy.
- Every transition for `LOCKED_TASK_ID` must update synchronized state artifacts in the same dispatch cycle.
- State transitions:
  - `pending → in-progress` before dispatch
  - `in-progress → completed` only if delta/evidence invariants pass
  - `in-progress → blocked` after 3-strike threshold (Task Inspector FAIL only; Security CRITICAL uses immediate block path)
  - `completed → pending` forbidden unless explicit review rollback

## Main Loop

1. Check `.ai/PAUSE.md`. If exists: print `PAUSE_DETECTED`, stop.
1a. **[HITL MANDATORY]** If `HITL_MODE=ON`: print `HITL_MODE=ON` and call `askQuestions` with a single confirmation:
   - Header: "HITL 확인"
   - Question: "HITL 모드가 활성화되어 있습니다. 각 Phase 완료 시 진행 여부를 묻습니다. 계속 진행할까요?"
   - Options: "예, 진행합니다" (recommended), "아니요, 중단합니다"
   - If user declines: stop immediately.
   - **This step MUST NOT be skipped. Do not proceed to step 2 until the user answers.**
1b. Run state sync checker before selecting tasks:
   - `python .github/skills/rw-loop/scripts/check_state_sync.py`
   - Require: `STATE_SYNC_CHECK=PASS`.
   - On fail: print checker output and stop current loop cycle.
1c. Run environment preflight before selecting tasks:
   - `python .github/skills/rw-loop/scripts/env_preflight.py`
   - Require: `ENV_PREFLIGHT=PASS`.
   - On fail: print checker output and stop current loop cycle.
2. Resolve locked task set from `task-graph.yaml` (primary), cross-checking `PROGRESS` + task frontmatter:
   - `PARALLEL_MODE=OFF`: one `LOCKED_TASK_ID`
   - `PARALLEL_MODE=ON`: up to `MAX_PARALLEL` independent tasks via `task-graph.yaml` (default `4`)
   - If task status mismatches between artifacts: print `RW_SUBAGENT_STATE_SYNC_INVALID`, stop.
   - If selected task is `pending`, set it to `in-progress` in all synchronized state artifacts before dispatch.
3. If unresolved `REVIEW-ESCALATE` exists: run review first, do not dispatch.
4. If no dispatchable task and unfinished tasks exist: print `TASK_DEPENDENCY_BLOCKED`, `REPLAN_TRIGGERED`, stop with `NEXT_COMMAND=rw-planner`.
5. Capture before-state: completed set, evidence count per locked task.

## Coder Dispatch

- Print `RUNSUBAGENT_DISPATCH_BEGIN <TASK-XX>` per task.
- Load `.github/skills/rw-loop/assets/rw-loop-coder.subagent.md`.
- Call `runSubagent` with coder prompt injecting `LOCKED_TASK_ID`.
- In parallel mode: separate lock and invariant checks per task.

## Post-Dispatch Validation

For each dispatched task:
1. Newly completed count must match dispatched count.
2. Completed task IDs must exactly match locked task IDs.
3. Evidence count for each task must increase.
4. Locked task status must be `completed` in all synchronized state artifacts.
5. For runtime-visible tasks, runtime evidence artifact path must be present in `VERIFICATION_EVIDENCE` key output.
6. On count/set mismatch: print `RW_SUBAGENT_COMPLETION_DELTA_INVALID`, stop.
7. On wrong task: print `RW_SUBAGENT_COMPLETED_WRONG_TASK`, stop.
8. On missing evidence: print `RW_SUBAGENT_VERIFICATION_EVIDENCE_MISSING`, stop.
9. On state mismatch: print `RW_SUBAGENT_STATE_SYNC_INVALID`, stop.
10. On missing runtime evidence for runtime-visible task: print `RW_SUBAGENT_VERIFICATION_EVIDENCE_MISSING`, stop.
11. Print `RUNSUBAGENT_DISPATCH_OK <TASK-XX>` per task on success.

## Mandatory Gates (after every dispatch)

### Task Inspector Gate

- Load `.github/skills/rw-loop/assets/rw-loop-task-inspector.subagent.md`.
- Call `runSubagent` per locked task.
- Require: `TASK_INSPECTION=PASS|FAIL`, `USER_PATH_GATE=PASS|FAIL`, `RUNTIME_GATE=PASS|FAIL`.
- On fail: keep `in-progress` or set `blocked` per retry threshold, always syncing status artifacts.
- Strike counting: only `TASK_INSPECTION=FAIL` increments strike counters.
- On each `TASK_INSPECTION=FAIL`:
  1. Increment `.ai/runtime/rw-strike-state.yaml` for `LOCKED_TASK_ID`: `strike.total += 1`, `strike.active += 1`.
  2. Set task status back to `in-progress` in all synchronized state artifacts before next retry.
  3. Collect tokens produced after Main Loop step 5 from the current dispatch cycle only, scoped to the current `LOCKED_TASK_ID` response (never global log): `REVIEW_FINDING`, `VERIFICATION_EVIDENCE` with `exit_code != 0`, and `APPROACH_SUMMARY`.
  4. Do not re-collect tokens from prior dispatches.
  5. Allocate `dispatch_id=<LOCKED_TASK_ID>-S<N>`, where `N` is `strike.total` from `.ai/runtime/rw-strike-state.yaml` (never from strike-file entry count).
  6. If an entry with the same `dispatch_id` already exists in `.ai/runtime/strikes/<LOCKED_TASK_ID>-strikes.md`, skip write (idempotency guard).
  7. Ensure `.ai/runtime/strikes/` exists, then append one strike entry to `.ai/runtime/strikes/<LOCKED_TASK_ID>-strikes.md`.
- 3-strike rule: same task reaches `strike.active >= 3` → blocked + `REVIEW-ESCALATE` + stop with `NEXT_COMMAND=rw-planner`.
- On 3rd strike (blocked):
  1. Write summary + recommended alternatives to `.ai/runtime/strikes/<LOCKED_TASK_ID>-strikes.md`.
  2. Set task status `blocked` in all synchronized state artifacts.
  3. Append to `.ai/PROGRESS.md`: `<LOCKED_TASK_ID> blocked (3-strike). See .ai/runtime/strikes/<LOCKED_TASK_ID>-strikes.md`.
  4. Append one concise pattern entry to `.ai/memory/shared-memory.md`.
- On `TASK_INSPECTION=PASS`:
  1. Keep `LOCKED_TASK_ID` as `completed` across synchronized state artifacts.
  2. Reset `strike.active=0` for `LOCKED_TASK_ID` in `.ai/runtime/rw-strike-state.yaml`.

### Security Gate

- Load `.github/skills/rw-loop/assets/rw-loop-security-review.subagent.md`.
- Call `runSubagent` with locked task IDs.
- Require: `SECURITY_GATE=PASS|FAIL`.
- On `SECURITY_GATE=FAIL`:
  - Non-critical findings: set task status to `in-progress` across synchronized state artifacts, print `SECURITY_GATE_FAILED`, stop.
  - Critical findings: block immediately (does not increment strike count), then:
    1. Collect current-cycle `SECURITY_FINDING` tokens scoped to `LOCKED_TASK_ID`.
    2. Increment `.ai/runtime/rw-strike-state.yaml` for `LOCKED_TASK_ID`: `security.total += 1`, `security.active += 1`.
    3. Allocate `dispatch_id=<LOCKED_TASK_ID>-SEC<N>`, where `N` is `security.total` from `.ai/runtime/rw-strike-state.yaml`.
    4. If an entry with the same `dispatch_id` already exists in `.ai/runtime/strikes/<LOCKED_TASK_ID>-strikes.md`, skip write; otherwise append one security entry.
    5. Set task status `blocked` in all synchronized state artifacts.
    6. Append to `.ai/PROGRESS.md`: `<LOCKED_TASK_ID> blocked (security-critical). See .ai/runtime/strikes/<LOCKED_TASK_ID>-strikes.md`.
    7. Append one concise security pattern entry to `.ai/memory/shared-memory.md`.
    8. Print `SECURITY_GATE_FAILED`, stop.
- On `SECURITY_GATE=PASS`:
  - If `TASK_INSPECTION=PASS` and task status is `completed`, reset `security.active=0` for `LOCKED_TASK_ID` in `.ai/runtime/rw-strike-state.yaml`.

### Phase Inspector (when current phase tasks all completed)

- Load `.github/skills/rw-loop/assets/rw-loop-phase-inspector.subagent.md`.
- Read `.ai/tasks/TASK-00-READBEFORE.md` and locate `Phase Gate Verification Commands`.
- Run all phase-gate verification commands before approval decision.
  - If section is missing/empty (legacy plan), infer best available full regression set (project-wide build + full test + key user-path smoke) and run those.
- Call `runSubagent`.
- Require: `PHASE_INSPECTION=PASS|FAIL`, `PHASE_REVIEW_STATUS=APPROVED|NEEDS_REVISION|FAILED`.
- Require phase-wide status consistency across `PROGRESS`, task frontmatter, and `task-graph.yaml` before phase approval.
- Require completed tasks in this phase to have `strike.active=0` and `security.active=0`.
- If any phase-gate verification command fails: force `PHASE_REVIEW_STATUS=NEEDS_REVISION` and stop with `NEXT_COMMAND=rw-loop`.
- On `NEEDS_REVISION`: stop with `NEXT_COMMAND=rw-loop`.
- On `FAILED`: stop with `NEXT_COMMAND=rw-planner`.
- **[HITL MANDATORY]** If `HITL_MODE=ON`: BEFORE calling `askQuestions`, output a structured phase summary so the user can make an informed decision:

  ```
  === Phase <N> 완료 요약 ===
  완료된 Tasks:
    - TASK-XX: <task title>
      증거: <핵심 verification evidence 1줄 요약 (예: tests passed 5/5, file created at path/to/file)>
    - TASK-YY: ...

  Phase Inspector 판정: <APPROVED|NEEDS_REVISION|FAILED>
  판정 근거: <Phase Inspector findings 요약 2-3줄>

  직접 확인 방법:
    <사용자가 실행할 수 있는 명령어 또는 확인할 파일 경로. 없으면 "해당 없음">
  ========================
  ```

  Then call `askQuestions` — this is UNCONDITIONAL and CANNOT be skipped:
  - Header: "Phase 승인"
  - Question: "위 요약을 확인하셨나요? 현재 phase를 완료로 승인하고 다음 phase로 진행할까요?"
  - Options: "예, 다음 phase로 진행합니다" (recommended), "아니요, 현재 phase를 재검토합니다"
  - If user declines: stop with `NEXT_COMMAND=rw-loop`.
  - **Do NOT call this inside a conditional branch. The summary + askQuestions MUST always execute when HITL_MODE=ON. Never infer approval without asking.**

### Review Gate (when all tasks completed)

- Load `.github/skills/rw-loop/assets/rw-loop-review.subagent.md`.
- Read `.ai/tasks/TASK-00-READBEFORE.md` and locate `Final Gate Verification Commands`.
- Run all final-gate verification commands before allowing `REVIEW_STATUS=OK`.
  - If section is missing/empty (legacy plan), infer best available full regression set (project-wide build + full test + key user-path smoke) and run those.
- Call `runSubagent`.
- Require: `REVIEW_STATUS=OK|FAIL|ESCALATE`.
- If any final-gate verification command fails: force `REVIEW_STATUS=FAIL`.
- On `OK`: proceed to success output.
- On `FAIL`/`ESCALATE`: stop with appropriate `NEXT_COMMAND`.

## User Acceptance Checklist Gate

- Trigger when all tasks completed and `REVIEW_STATUS=OK`.
- Create `.ai/plans/<PLAN_ID>/user-acceptance-checklist.md`.
- Content: how-to-run commands, expected results, failure hints.
- `PLANNING_PROFILE=STANDARD|FAST_TEST`: advisory only (non-blocking), set `USER_ACCEPTANCE_GATE=NA`.
- `PLANNING_PROFILE=UX_STRICT`: blocking gate.
  - Require checklist exists and contains runtime verification steps for main user path + error path.
  - If `HITL_MODE=ON`, call `askQuestions` to confirm checklist run:
    - Header: "사용자 수용 확인"
    - Question: "체크리스트를 실제로 확인했나요? UX_STRICT 게이트를 통과하고 완료할까요?"
    - Options: "예, 통과합니다" (recommended), "아니요, 재검토합니다"
  - If declined or checklist is incomplete: output `USER_ACCEPTANCE_GATE=FAIL`, print `USER_ACCEPTANCE_GATE_FAILED`, stop with `NEXT_COMMAND=rw-loop`.
  - If passed: output `USER_ACCEPTANCE_GATE=PASS`.

## Contract Tokens

```
RUNSUBAGENT_DISPATCH_BEGIN <TASK-XX>
RUNSUBAGENT_DISPATCH_OK <TASK-XX>
VERIFICATION_EVIDENCE <LOCKED_TASK_ID>
STATE_SYNC_CHECK=PASS|FAIL
ENV_PREFLIGHT=PASS|FAIL
TASK_INSPECTION=PASS|FAIL
USER_PATH_GATE=PASS|FAIL
RUNTIME_GATE=PASS|FAIL
SECURITY_GATE=PASS|FAIL
PHASE_INSPECTION=PASS|FAIL
PHASE_REVIEW_STATUS=APPROVED|NEEDS_REVISION|FAILED
REVIEW_STATUS=OK|FAIL|ESCALATE
HITL_PHASE_APPROVED=YES|NO
USER_ACCEPTANCE_GATE=PASS|FAIL|NA
```

## HITL Enforcement Rules

- `HITL_MODE=ON` → `askQuestions` is **MANDATORY** at:
  1. Loop start (step 1a) — one-time confirmation
  2. Phase Inspector completion — every phase, every time
- These calls are **unconditional and non-negotiable**.
- Skipping either call when `HITL_MODE=ON` is a **contract violation**.
- The model MUST NOT auto-advance to the next phase or loop without explicit user confirmation when `HITL_MODE=ON`.

## Success Output

Emit in exact order:
```
HITL_MODE=<ON|OFF>
PARALLEL_MODE=<ON|OFF>
PARALLEL_BATCH_SIZE=<1-4>
PLANNING_PROFILE=<STANDARD|FAST_TEST|UX_STRICT>
RUNSUBAGENT_DISPATCH_COUNT=<n>
RUN_PHASE_NOTE_FILE=<path|none>
PHASE_REVIEW_STATUS=<APPROVED|NEEDS_REVISION|FAILED|NA>
REVIEW_STATUS=<OK|FAIL|ESCALATE>
USER_ACCEPTANCE_GATE=<PASS|FAIL|NA>
ARCHIVE_RESULT=<SKIPPED|DONE|LOCKED>
NEXT_COMMAND=<done|rw-planner|rw-loop>
```

Append one short reflection entry to `.ai/memory/shared-memory.md` when run completes or escalates.
