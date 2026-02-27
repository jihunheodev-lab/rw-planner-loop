---
name: rw-loop
description: "Lite+Contract loop: DAG-aware dispatch, TDD evidence checks, user-path/security gates, and phase review contracts. Optional flags: --auto, --no-hitl, --hitl, --parallel, --max-parallel=<1..4>"
---

# RW Loop Skill

DAG-aware task dispatch → TDD coder subagent → mandatory verification gates → phase/review contracts.

## When to Use

- Implementing tasks from an existing plan (`NEXT_COMMAND=rw-loop`)
- Resuming implementation after a gate failure or pause
- Re-running loop after fixing a blocked task

## Prerequisites

The following must exist before running this skill (created by `rw-planner`):
- `.ai/CONTEXT.md` — language policy
- `.ai/PROGRESS.md` — task status table
- `.ai/tasks/` — atomic task files (`TASK-XX-*.md`)
- `.ai/runtime/rw-active-plan-id.txt` + `.ai/plans/<PLAN_ID>/task-graph.yaml` — DAG + node status source
- `.github/skills/rw-loop/assets/` — 5 subagent prompt files

If any prerequisite is missing, the skill prints a failure token and stops.

## Procedure Overview

```
Step 0: Guard     → verify prerequisites, resolve HITL/parallel mode
Loop:   Dispatch  → lock task → coder subagent → validate → gates → next
End:    Review    → final review gate → success output
```

## Step 0: Guard

1. Read `.ai/CONTEXT.md`. If missing: print `LANG_POLICY_MISSING`, stop.
2. Verify `.ai/PROGRESS.md` and `.ai/tasks/` exist. If missing: print `TARGET_ROOT_INVALID`, stop.
3. Verify `runSubagent` is available. If not: print `RW_ENV_UNSUPPORTED`, stop.
4. This mode never writes product code directly.
5. Verify required subagent prompt files exist in skill assets:
   - [rw-loop-coder.subagent.md](./assets/rw-loop-coder.subagent.md)
   - [rw-loop-task-inspector.subagent.md](./assets/rw-loop-task-inspector.subagent.md)
   - [rw-loop-security-review.subagent.md](./assets/rw-loop-security-review.subagent.md)
   - [rw-loop-phase-inspector.subagent.md](./assets/rw-loop-phase-inspector.subagent.md)
   - [rw-loop-review.subagent.md](./assets/rw-loop-review.subagent.md)
   - If any file is missing: print `RW_SUBAGENT_PROMPT_MISSING`, stop.
6. If `.ai/memory/shared-memory.md` exists, read it before loop start.
7. Read `.ai/runtime/rw-active-plan-id.txt`, then read matching `.ai/plans/<PLAN_ID>/task-graph.yaml` as primary dependency graph. If missing/unreadable: print `TARGET_ROOT_INVALID`, stop.

## Mode Resolution

| Flag | HITL_MODE | PARALLEL_MODE |
|------|-----------|---------------|
| (default) | ON | ON |
| `--auto` or `--no-hitl` | OFF | ON |
| `--hitl` | ON | ON |
| `--parallel` | (unchanged) | ON |
| `--max-parallel=<n>` | (unchanged) | ON, clamped 1..4 |

When `PARALLEL_MODE=ON` and `--max-parallel` is omitted, `MAX_PARALLEL=4`.

## Main Loop

Load full loop contract: [loop-contract.md](./references/loop-contract.md)

### Quick Reference

1. Check `.ai/PAUSE.md`. If exists: print `PAUSE_DETECTED`, stop.
1a. Run state sync checker before dispatch:
   - `python .github/skills/rw-loop/scripts/check_state_sync.py`
   - If checker returns fail tokens, stop and fix state artifacts first.
2. **Select dispatchable task(s)** from DAG (`in-progress` first, then `pending`, never `blocked`).
   - Single mode: 1 task. Parallel mode: up to `MAX_PARALLEL` independent tasks (default `4`).
3. **Dispatch** to coder subagent via `runSubagent`.
4. **Validate**: completion delta (exactly N tasks), correct task IDs, evidence count increased, and state sync across `PROGRESS` + task frontmatter + `task-graph`.
   - Task-level verification should stay scoped/fast. Full regression belongs to Phase/Review gates via `TASK-00` policy.
5. **Task Inspector Gate**: `TASK_INSPECTION=PASS|FAIL`, `USER_PATH_GATE=PASS|FAIL`.
6. **Security Gate**: `SECURITY_GATE=PASS|FAIL`.
7. **Phase Inspector** (when phase complete): run `TASK-00` phase-gate full verification commands, then require `PHASE_REVIEW_STATUS=APPROVED|NEEDS_REVISION|FAILED`.
   - **[HITL MANDATORY]** If `HITL_MODE=ON`: output structured phase summary (completed tasks + evidence + inspector findings + 직접 확인 방법) THEN call `askQuestions` — unconditionally, never skip.
8. **3-strike rule**: same task `strike.active` reaches 3 → blocked + escalate to planner. `strike.total`/`security.total` stay cumulative for history IDs, and `active` counters reset on successful completion.
9. **Review Gate** (all tasks complete): run `TASK-00` final-gate full verification commands, then require `REVIEW_STATUS=OK|FAIL|ESCALATE`.

## State Transitions

```
pending → in-progress → completed
               |
               v
            blocked (3-strike or security critical)
```

- Single mode: 1 dispatch = exactly 1 task completed.
- Parallel mode: N dispatched = exactly N completed.
- `completed` requires `VERIFICATION_EVIDENCE` count increase.
- `completed → pending` forbidden unless explicit review rollback.

## Loop Output Contract (success)

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

## Failure Handling

| Token | Meaning | Next |
|-------|---------|------|
| `RW_ENV_UNSUPPORTED` | `runSubagent` unavailable | stop |
| `RW_SUBAGENT_PROMPT_MISSING` | subagent prompt file missing | run rw-planner |
| `TARGET_ROOT_INVALID` | required state files missing (`PROGRESS`, tasks, active-plan graph) | run rw-planner |
| `RW_SUBAGENT_STATE_SYNC_INVALID` | status mismatch across state artifacts | fix sync + re-run |
| `LANG_POLICY_MISSING` | `.ai/CONTEXT.md` missing | run rw-planner |
| `TASK_DEPENDENCY_BLOCKED` | no dispatchable task | replan |
| `SECURITY_GATE_FAILED` | security regression found | fix + re-run |
| `PAUSE_DETECTED` | `.ai/PAUSE.md` exists | remove pause file |

## Language Policy

- 모든 `.ai/**` 아티팩트 작성 전 `.ai/CONTEXT.md`를 먼저 읽을 것.
