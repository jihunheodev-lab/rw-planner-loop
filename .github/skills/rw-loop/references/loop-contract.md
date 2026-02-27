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
6. If `.ai/memory/shared-memory.md` exists, read it before loop start.
7. If `.ai/runtime/rw-active-plan-id.txt` exists, read matching `.ai/plans/<PLAN_ID>/task-graph.yaml` as primary dependency graph.
8. Load `.ai/runtime/rw-strike-state.yaml` if present. If missing, initialize counters in memory and create it on first strike/security record. Use this state as the source of truth for `dispatch_id` generation across reruns/restarts.

## Mode Resolution

| Flag | HITL_MODE | PARALLEL_MODE |
|------|-----------|---------------|
| (default) | ON | OFF |
| `--auto` or `--no-hitl` | OFF | OFF |
| `--hitl` | ON | OFF |
| `--parallel` | (unchanged) | ON |
| `--max-parallel=<n>` | (unchanged) | ON, clamped 1..4 |

## Loop Policy

- Task priority: `in-progress` first, then `pending`. Never auto-select `blocked`.
- Single mode: one dispatch = exactly one task completed.
- Parallel mode: N dispatched = exactly N completed. Only independent tasks (no dependency relation).
- Every completed task must increase verification evidence count.
- State transitions:
  - `pending → in-progress` before dispatch
  - `in-progress → completed` only if delta/evidence invariants pass
  - `in-progress → blocked` after 3-strike threshold (Task Inspector FAIL only; Security CRITICAL uses immediate block path)
  - `completed → pending` forbidden unless explicit review rollback

## Main Loop

1. Check `.ai/PAUSE.md`. If exists: print `PAUSE_DETECTED`, stop.
2. Resolve locked task set from PROGRESS:
   - `PARALLEL_MODE=OFF`: one `LOCKED_TASK_ID`
   - `PARALLEL_MODE=ON`: up to `MAX_PARALLEL` independent tasks via `task-graph.yaml`
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
4. On count/set mismatch: print `RW_SUBAGENT_COMPLETION_DELTA_INVALID`, stop.
5. On wrong task: print `RW_SUBAGENT_COMPLETED_WRONG_TASK`, stop.
6. On missing evidence: print `RW_SUBAGENT_VERIFICATION_EVIDENCE_MISSING`, stop.
7. Print `RUNSUBAGENT_DISPATCH_OK <TASK-XX>` per task on success.

## Mandatory Gates (after every dispatch)

### Task Inspector Gate

- Load `.github/skills/rw-loop/assets/rw-loop-task-inspector.subagent.md`.
- Call `runSubagent` per locked task.
- Require: `TASK_INSPECTION=PASS|FAIL`, `USER_PATH_GATE=PASS|FAIL`.
- On fail: keep `in-progress` or set `blocked` per retry threshold.
- Strike counting: only `TASK_INSPECTION=FAIL` increments strike count.
- On each `TASK_INSPECTION=FAIL`:
  1. Collect tokens produced after Main Loop step 5 from the current dispatch cycle only, scoped to the current `LOCKED_TASK_ID` response (never global log): `REVIEW_FINDING`, `VERIFICATION_EVIDENCE` with `exit_code != 0`, and `APPROACH_SUMMARY`.
  2. Do not re-collect tokens from prior dispatches.
  3. Allocate `dispatch_id=<LOCKED_TASK_ID>-S<N>`, where `N` is the task's cumulative strike count from `.ai/runtime/rw-strike-state.yaml` (never from strike-file entry count).
  4. If an entry with the same `dispatch_id` already exists in `.ai/runtime/strikes/<LOCKED_TASK_ID>-strikes.md`, skip write (idempotency guard).
  5. Ensure `.ai/runtime/strikes/` exists, then append one strike entry to `.ai/runtime/strikes/<LOCKED_TASK_ID>-strikes.md`.
- 3-strike rule: same task fails 3× → blocked + `REVIEW-ESCALATE` + stop with `NEXT_COMMAND=rw-planner`.
- On 3rd strike (blocked):
  1. Write summary + recommended alternatives to `.ai/runtime/strikes/<LOCKED_TASK_ID>-strikes.md`.
  2. Append to `.ai/PROGRESS.md`: `<LOCKED_TASK_ID> blocked (3-strike). See .ai/runtime/strikes/<LOCKED_TASK_ID>-strikes.md`.
  3. Append one concise pattern entry to `.ai/memory/shared-memory.md`.

### Security Gate

- Load `.github/skills/rw-loop/assets/rw-loop-security-review.subagent.md`.
- Call `runSubagent` with locked task IDs.
- Require: `SECURITY_GATE=PASS|FAIL`.
- On `SECURITY_GATE=FAIL`:
  - Non-critical findings: print `SECURITY_GATE_FAILED`, keep `in-progress`, stop.
  - Critical findings: block immediately (does not increment strike count), then:
    1. Collect current-cycle `SECURITY_FINDING` tokens scoped to `LOCKED_TASK_ID`.
    2. Allocate `dispatch_id=<LOCKED_TASK_ID>-SEC<N>`, where `N` is the task's cumulative security-block count from `.ai/runtime/rw-strike-state.yaml`.
    3. If an entry with the same `dispatch_id` already exists in `.ai/runtime/strikes/<LOCKED_TASK_ID>-strikes.md`, skip write; otherwise append one security entry.
    4. Append to `.ai/PROGRESS.md`: `<LOCKED_TASK_ID> blocked (security-critical). See .ai/runtime/strikes/<LOCKED_TASK_ID>-strikes.md`.
    5. Append one concise security pattern entry to `.ai/memory/shared-memory.md`.
    6. Print `SECURITY_GATE_FAILED`, stop.

### Phase Inspector (when current phase tasks all completed)

- Load `.github/skills/rw-loop/assets/rw-loop-phase-inspector.subagent.md`.
- Call `runSubagent`.
- Require: `PHASE_INSPECTION=PASS|FAIL`, `PHASE_REVIEW_STATUS=APPROVED|NEEDS_REVISION|FAILED`.
- On `NEEDS_REVISION`: stop with `NEXT_COMMAND=rw-loop`.
- On `FAILED`: stop with `NEXT_COMMAND=rw-planner`.
- If `HITL_MODE=ON`: ask one explicit yes/no via `askQuestions`:
  - "현재 phase를 완료로 승인하고 다음 phase로 진행할까요?"
  - If user declines: stop with `NEXT_COMMAND=rw-loop`.

### Review Gate (when all tasks completed)

- Load `.github/skills/rw-loop/assets/rw-loop-review.subagent.md`.
- Call `runSubagent`.
- Require: `REVIEW_STATUS=OK|FAIL|ESCALATE`.
- On `OK`: proceed to success output.
- On `FAIL`/`ESCALATE`: stop with appropriate `NEXT_COMMAND`.

## Optional User Acceptance Checklist

- Trigger when all tasks completed and `REVIEW_STATUS=OK`.
- Create `.ai/plans/<PLAN_ID>/user-acceptance-checklist.md`.
- Content: how-to-run commands, expected results, failure hints.
- Advisory only — never blocks `NEXT_COMMAND`.

## Contract Tokens

```
RUNSUBAGENT_DISPATCH_BEGIN <TASK-XX>
RUNSUBAGENT_DISPATCH_OK <TASK-XX>
VERIFICATION_EVIDENCE <LOCKED_TASK_ID>
TASK_INSPECTION=PASS|FAIL
USER_PATH_GATE=PASS|FAIL
SECURITY_GATE=PASS|FAIL
PHASE_INSPECTION=PASS|FAIL
PHASE_REVIEW_STATUS=APPROVED|NEEDS_REVISION|FAILED
REVIEW_STATUS=OK|FAIL|ESCALATE
```

## Success Output

Emit in exact order:
```
HITL_MODE=<ON|OFF>
PARALLEL_MODE=<ON|OFF>
PARALLEL_BATCH_SIZE=<1-4>
RUNSUBAGENT_DISPATCH_COUNT=<n>
RUN_PHASE_NOTE_FILE=<path|none>
PHASE_REVIEW_STATUS=<APPROVED|NEEDS_REVISION|FAILED|NA>
REVIEW_STATUS=<OK|FAIL|ESCALATE>
ARCHIVE_RESULT=<SKIPPED|DONE|LOCKED>
NEXT_COMMAND=<done|rw-planner|rw-loop>
```

Append one short reflection entry to `.ai/memory/shared-memory.md` when run completes or escalates.
