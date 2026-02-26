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
- `.github/prompts/subagents/` — 5 subagent prompt files

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
5. Ensure `.github/prompts/subagents/` directory exists. Create if missing.
6. Verify required subagent prompt files exist. If any are missing, copy from skill assets:
   - [rw-loop-coder.subagent.md](./assets/rw-loop-coder.subagent.md)
   - [rw-loop-task-inspector.subagent.md](./assets/rw-loop-task-inspector.subagent.md)
   - [rw-loop-security-review.subagent.md](./assets/rw-loop-security-review.subagent.md)
   - [rw-loop-phase-inspector.subagent.md](./assets/rw-loop-phase-inspector.subagent.md)
   - [rw-loop-review.subagent.md](./assets/rw-loop-review.subagent.md)
   - If copy fails: print `RW_SUBAGENT_PROMPT_MISSING`, stop.
6. If `.ai/memory/shared-memory.md` exists, read it before loop start.
7. If `.ai/runtime/rw-active-plan-id.txt` exists, read matching `.ai/plans/<PLAN_ID>/task-graph.yaml` as primary dependency graph.

## Mode Resolution

| Flag | HITL_MODE | PARALLEL_MODE |
|------|-----------|---------------|
| (default) | ON | OFF |
| `--auto` or `--no-hitl` | OFF | OFF |
| `--hitl` | ON | OFF |
| `--parallel` | (unchanged) | ON |
| `--max-parallel=<n>` | (unchanged) | ON, clamped 1..4 |

## Main Loop

Load full loop contract: [loop-contract.md](./references/loop-contract.md)

### Quick Reference

1. Check `.ai/PAUSE.md`. If exists: print `PAUSE_DETECTED`, stop.
2. **Select dispatchable task(s)** from DAG (`in-progress` first, then `pending`, never `blocked`).
   - Single mode: 1 task. Parallel mode: up to `MAX_PARALLEL` independent tasks.
3. **Dispatch** to coder subagent via `runSubagent`.
4. **Validate**: completion delta (exactly N tasks), correct task IDs, evidence count increased.
5. **Task Inspector Gate**: `TASK_INSPECTION=PASS|FAIL`, `USER_PATH_GATE=PASS|FAIL`.
6. **Security Gate**: `SECURITY_GATE=PASS|FAIL`.
7. **Phase Inspector** (when phase complete): `PHASE_REVIEW_STATUS=APPROVED|NEEDS_REVISION|FAILED`.
   - If `HITL_MODE=ON`: ask phase approval confirmation.
8. **3-strike rule**: same task fails 3× → blocked + escalate to planner. Strike history is written to `.ai/runtime/strikes/<TASK-XX>-strikes.md`.
9. **Review Gate** (all tasks complete): `REVIEW_STATUS=OK|FAIL|ESCALATE`.

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
| `TARGET_ROOT_INVALID` | `.ai/PROGRESS.md` or tasks missing | run rw-planner |
| `LANG_POLICY_MISSING` | `.ai/CONTEXT.md` missing | run rw-planner |
| `TASK_DEPENDENCY_BLOCKED` | no dispatchable task | replan |
| `SECURITY_GATE_FAILED` | security regression found | fix + re-run |
| `PAUSE_DETECTED` | `.ai/PAUSE.md` exists | remove pause file |

## Language Policy

- 모든 `.ai/**` 아티팩트 작성 전 `.ai/CONTEXT.md`를 먼저 읽을 것.
