---
name: rw-planner
description: "Lite+Contract planner: hybrid askQuestions + subagent planning + DAG/task-graph generation with approval integrity. Bootstraps .ai/ workspace on first run. Input: feature request — resolves required fields first, asks only missing fields, then deep-dive if ambiguous."
---

# RW Planner Skill

Bootstrap workspace + hybrid interview → feature normalization → task decomposition → DAG/task-graph generation.

## When to Use

- Starting a new feature that needs structured decomposition
- Re-planning after loop escalation (`NEXT_COMMAND=rw-planner`)
- Reviewing or revising an existing plan

## Procedure Overview

```
Phase 1: Bootstrap   → scaffold .ai/ dirs and templates (first run only)
Phase 2: Plan        → interview → feature → plan artifacts → atomic tasks
Output:  NEXT_COMMAND=rw-loop
```

## Phase 1: Bootstrap

Scaffold the workspace for first-time use. Skip items that already exist.

1. Create directories:
   - `.ai/features`, `.ai/tasks`, `.ai/notes`, `.ai/runtime`, `.ai/plans`, `.ai/memory`
2. Create `.ai/CONTEXT.md` with the following default language policy:
   ```markdown
   # CONTEXT
   - Response language: 한국어
   - Machine tokens: English (pending, in-progress, completed, blocked, VERIFICATION_EVIDENCE, etc.)
   - Section headers: English (unless overridden below)
   ```
3. Create `.ai/memory/shared-memory.md` (see [memory-contract.md](./assets/memory-contract.md)).
4. Copy [feature-template.md](./assets/feature-template.md) to `.ai/features/FEATURE-TEMPLATE.md`.
5. Create `.ai/PROGRESS.md` with initial format:
   ```markdown
   # Progress

   ## Task Status
   | Task | Title | Status | Commit |
   |------|-------|--------|--------|

   ## Phase Status
   Current Phase: Phase 1

   ## Log
   ```
6. Create `.ai/PLAN.md` with initial format:
   ```markdown
   # Plan
   - PLAN_ID: (none)
   - Feature Key: (none)
   - Strategy: (none)
   - Task Range: (none)
   ```
7. Validate `runSubagent` is available. If not, print `RW_ENV_UNSUPPORTED` and stop.
8. Validate `askQuestions` is available. If not, print `INTERVIEW_REQUIRED` and stop.

## Phase 2: Plan

Load full planner contract: [planner-contract.md](./references/planner-contract.md)

### Quick Reference

1. **Step 0 Guard**: Validate `.ai/CONTEXT.md`, check for `.ai/PAUSE.md`, verify `runSubagent` + `askQuestions`.
2. **Hybrid Intake** (via `askQuestions`):
   - Phase A: Resolve `TARGET_KIND`, `USER_PATH`, `SCOPE_BOUNDARY`, `ACCEPTANCE_SIGNAL` from request. Ask only for missing fields.
   - Phase B: Deep-dive (6–10 questions) if ambiguity remains.
   - Phase C: Confirmation gate (one yes/no).
   - Phase D: Ambiguity scoring (0–100 rubric) → select `PLAN_STRATEGY` (SINGLE or PARALLEL_AUTO).
   - Phase E: Subagent planning — generate plan candidates via `runSubagent`, confirm selection.
3. **Feature File**: Create/update under `.ai/features/` with approval metadata + SHA-256 hash integrity.
4. **Approval Gate**: Feature must have `Approval: APPROVED`. Hash mismatch resets approval.
5. **Plan Artifacts**: `plan-summary.yaml`, `task-graph.yaml`, `research_findings_*.yaml` under `.ai/plans/<PLAN_ID>/` (`task-graph` nodes must start with `status: pending`).
6. **Task Decomposition**: Create 2–6 atomic `TASK-XX-*.md` in `.ai/tasks/` with frontmatter `status: pending`, acceptance criteria, user path, and fast task-scoped verification commands. Same-phase tasks must be independent by default; add dependency edges only with explicit rationale. Put full regression commands in `TASK-00` phase/final gate policy.
7. **Update Progress**: Append task rows to `.ai/PROGRESS.md` as `pending`.

### Planner Output Contract (success)

```
FEATURE_FILE=<path>
FEATURE_KEY=<JIRA-123|FEATURE-XX>
FEATURE_STATUS=PLANNED
PLAN_ID=<id>
PLAN_STRATEGY=<SINGLE|PARALLEL_AUTO>
AMBIGUITY_SCORE=<0-100>
AMBIGUITY_REASONS=<comma-separated-codes>
PLAN_MODE=<INITIAL|REPLAN|EXTENSION>
PLAN_TASK_RANGE=<TASK-XX~TASK-YY>
TASK_BOOTSTRAP_FILE=<path>
TASK_GRAPH_FILE=<path>
PLAN_RISK_LEVEL=<LOW|MEDIUM|HIGH>
PLAN_CONFIDENCE=<HIGH|MEDIUM|LOW>
OPEN_QUESTIONS_COUNT=<n>
NEXT_COMMAND=rw-loop
```

After emitting the success output contract, stop planner execution immediately.
Do not start implementation, do not dispatch rw-loop internally, and do not modify product code.

## Failure Handling

| Token | Meaning | Next |
|-------|---------|------|
| `RW_ENV_UNSUPPORTED` | `runSubagent` unavailable | stop |
| `TARGET_ROOT_INVALID` | workspace not writable | stop |
| `LANG_POLICY_MISSING` | `.ai/CONTEXT.md` unreadable after bootstrap | stop |
| `INTERVIEW_REQUIRED` | `askQuestions` unavailable | stop |
| `INTERVIEW_ABORTED` | user declined confirmation | stop |
| `INTERVIEW_DEEP_REQUIRED` | deep dive still unresolved | retry |
| `FEATURE_NEED_INSUFFICIENT` | scope still insufficient after confirmation | stop |
| `FEATURE_REVIEW_REQUIRED` | approval missing or hash changed | re-approve |
| `PLAN_ARTIFACTS_INCOMPLETE` | required plan artifacts missing | retry |
| `PAUSE_DETECTED` | `.ai/PAUSE.md` exists | remove pause file |

## Language Policy

- `.ai/CONTEXT.md` 부트스트랩 기본값: prose는 한국어, 머신 토큰은 영어.
- 모든 `.ai/**` 아티팩트 작성 전 `.ai/CONTEXT.md`를 먼저 읽을 것.
