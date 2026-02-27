# Planner Contract

Full deterministic contract for the planning phase of rw-planner-loop skill.

## Step 0 (Mandatory)

1. Validate workspace root is writable and resolvable.
2. If path cannot be resolved or is not writable: print `TARGET_ROOT_INVALID`, stop.
3. Ensure `.ai/CONTEXT.md` exists. If missing, create minimal policy file.
4. Read `.ai/CONTEXT.md` first.
5. If `.ai/CONTEXT.md` is missing/unreadable after bootstrap: print `LANG_POLICY_MISSING`, stop.
6. If `.ai/PAUSE.md` exists: print `PAUSE_DETECTED`, stop.
7. Ensure `runSubagent` is available. If unavailable: print `RW_ENV_UNSUPPORTED`, stop.
8. Do not write product code. Allowed writes: `.ai/**` only.
9. If `askQuestions` is unavailable: print `INTERVIEW_REQUIRED`, stop.
10. If `.ai/runtime/strikes/` contains strike history files, read relevant files before intake to inform replan context.

## Failure Output Tokens

One primary error token + `NEXT_COMMAND=rw-planner`:

| Token | Meaning |
|-------|---------|
| `TARGET_ROOT_INVALID` | Workspace not writable/resolvable |
| `FEATURE_NEED_INSUFFICIENT` | Scope still insufficient after confirmation |
| `FEATURE_REVIEW_REQUIRED` | Approval missing or hash mismatch (with `FEATURE_REVIEW_REASON`, `FEATURE_FILE`, `FEATURE_REVIEW_HINT`) |
| `INTERVIEW_REQUIRED` | `askQuestions` unavailable |
| `INTERVIEW_DEEP_REQUIRED` | Deep dive still unresolved |
| `INTERVIEW_ABORTED` | User declined confirmation |
| `PAUSE_DETECTED` | `.ai/PAUSE.md` exists |
| `LANG_POLICY_MISSING` | `.ai/CONTEXT.md` unreadable after bootstrap |
| `FEATURES_DIR_MISSING` | `.ai/features/` directory not found |
| `FEATURE_FILE_MISSING` | Expected feature file not found |
| `FEATURE_NOT_READY` | Feature status not `READY_FOR_PLAN` |
| `PLAN_ARTIFACTS_INCOMPLETE` | Required plan artifacts missing/empty |
| `RW_ENV_UNSUPPORTED` | `runSubagent` unavailable |

## Hybrid Intake

### Phase A — Mandatory Need-Gate

1. Resolve required fields from user request/context before asking questions.
2. Collect:
   - `TARGET_KIND`: `PRODUCT_CODE` (default) or `AGENT_WORKFLOW`
   - `USER_PATH`: how end user reaches/uses the feature
   - `SCOPE_BOUNDARY`: explicit in-scope and out-of-scope
   - `ACCEPTANCE_SIGNAL`: observable behavior + verification command
3. Defaulting rule for `TARGET_KIND`:
   - Default to `PRODUCT_CODE`.
   - Use `AGENT_WORKFLOW` only when request explicitly targets agent/prompt/orchestration assets.
4. Ask questions only for missing/uncertain required fields (batch unresolved items).

### Phase B — Deep Dive (conditional)

Trigger when:
- Target is ambiguous
- User path is missing
- Acceptance signal is weak/non-testable
- Request affects 3+ directories or has security/data risk

Ask 6–10 clarifying questions in one or two batches.
If still unresolved: print `INTERVIEW_DEEP_REQUIRED`, stop.

### Phase C — Confirmation Gate

1. Summarize normalized scope in 4 lines: target kind, user path, in-scope, out-of-scope.
2. Ask one explicit yes/no confirmation via `askQuestions`.
3. If not confirmed: print `INTERVIEW_ABORTED`, stop.

### Phase D — Ambiguity Scoring

Compute `AMBIGUITY_SCORE` (cap at 100):

| Condition | Score |
|-----------|-------|
| `TARGET_KIND` conflicting signals | +5 |
| `USER_PATH` missing/uncertain | +25 |
| `SCOPE_BOUNDARY` missing/uncertain | +20 |
| `ACCEPTANCE_SIGNAL` missing/non-testable | +20 |
| Target path/file not specified | +10 |
| Generic verbs only (improve/add/fix without scope) | +10 |
| Broad expressions (overall, global, optimize all) | +5 |
| Impact spans 3+ directories | +10 |
| Security/data concern unresolved | +15 |

Ambiguity reason codes: `TARGET_KIND_UNCLEAR`, `USER_PATH_UNCLEAR`, `SCOPE_UNCLEAR`, `ACCEPTANCE_UNCLEAR`, `TARGET_PATH_MISSING`, `GENERIC_VERB_REQUEST`, `BROAD_SCOPE_WORDING`, `CROSS_DIR_IMPACT`, `SECURITY_DATA_UNCLEAR`.

Strategy selection:
- Hard trigger → `PARALLEL_AUTO` when any required field remains unclear.
- `AMBIGUITY_SCORE >= 40` → `PARALLEL_AUTO`.
- Else → `SINGLE`.

### Phase E — Subagent Planning

1. Generate plan candidates via `runSubagent` only.
2. If `SINGLE`: dispatch one plan subagent.
3. If `PARALLEL_AUTO`: dispatch four plan subagents.
4. Each plan subagent prompt must include:
   - **Inputs**: `TARGET_KIND`, `USER_PATH`, `SCOPE_BOUNDARY`, `ACCEPTANCE_SIGNAL`, relevant codebase context.
   - **Required output keys**: `assumptions`, `user_path`, `acceptance_strategy`, `risk_level`, `complexity`, `estimated_tasks`, `candidate_score`.
   - **Output format**: Markdown with embedded JSON block containing the required keys.
   - **Constraint**: Subagent must not call `runSubagent` or `askQuestions`.
5. Show candidate plan text in main chat.
6. Ask one confirmation question via `askQuestions` before writing tasks.
7. If not confirmed: print `INTERVIEW_ABORTED`, stop.

## Feature File Management

1. Create/select feature file under `.ai/features/`.
   - Naming: `<ISSUE_KEY>-<slug>.md` or `FEATURE-XX-<slug>.md`.
   - Set `Status: READY_FOR_PLAN`.
2. Approval metadata:
   - `Approval: PENDING|APPROVED`
   - `Approved By: <name-or-id>`
   - `Approved At: <YYYY-MM-DD>`
   - `Feature Hash: <sha256>` (from normalized scope: TARGET_KIND + USER_PATH + SCOPE_BOUNDARY + ACCEPTANCE_SIGNAL)
3. Approval gate:
   - If `Approval` not `APPROVED`: print `FEATURE_REVIEW_REQUIRED` with `APPROVAL_MISSING`.
   - If approved but hash differs: reset approval, print `FEATURE_REVIEW_REQUIRED` with `APPROVAL_RESET_SCOPE_CHANGED`.

## Plan Artifacts

1. Scope guard from `TARGET_KIND`:
   - `PRODUCT_CODE` → out-of-scope: `.github/agents/**`, `.github/prompts/**`
   - `AGENT_WORKFLOW` → out-of-scope: `src/**`, `app/**`, runtime product code
2. Generate `PLAN_ID=YYYYMMDD-HHMM-<slug>`.
3. Determine plan mode:
   - `REPLAN` if `.ai/runtime/rw-plan-replan.flag` exists.
   - `EXTENSION` if existing task rows already exist in PROGRESS.
   - Else `INITIAL`.
4. If `PARALLEL_AUTO`, create candidate artifacts:
   - `.ai/plans/<PLAN_ID>/candidate-plan-{1..4}.md`
   - `.ai/plans/<PLAN_ID>/candidate-selection.md` (winner + reasons)
   - Each candidate schema: Assumptions, User Path, Scope, Acceptance/Test Strategy, Risk Notes, Candidate Score, Candidate JSON.
   - Candidate JSON required keys:
     - `candidate_id`
     - `assumptions`
     - `user_path`
     - `acceptance_strategy`
     - `risk_level`
     - `complexity`
     - `estimated_tasks`
   - Selection file must include: `winner_candidate_id`, `winner_reason`, `rejected_reasons`.
5. Write artifacts:
   - `.ai/plans/<PLAN_ID>/research_findings_<focus>.yaml` (focus_area, summary, citations, assumptions)
   - `.ai/plans/<PLAN_ID>/plan-summary.yaml`
   - `.ai/plans/<PLAN_ID>/task-graph.yaml` (plan_id, nodes, edges, parallel_groups). Each node must include `task_id`, `status: pending`, and declared dependencies.
   - `.ai/runtime/rw-active-plan-id.txt`
   - `.ai/PLAN.md`
6. Verify artifact completeness: `plan-summary.yaml`, `task-graph.yaml`, at least one `research_findings_*.yaml` must exist and be non-empty.
   - If incomplete: print `PLAN_ARTIFACTS_INCOMPLETE`, stop.

## Task Decomposition

1. Create/update `.ai/tasks/TASK-00-READBEFORE.md`.
2. Create 2–6 atomic tasks `TASK-XX-*.md`. Each must contain:
   - YAML frontmatter with `task_id`, `phase`, `status: pending`, `dependencies`
   - Phase, Title, Dependencies, Dependency Rationale
   - User Path, Description
   - Acceptance Criteria, Accessibility Criteria
   - Files to Create/Modify
   - Test Strategy, Verification
   - Strike History Reference (optional): path to prior `.ai/runtime/strikes/<TASK-XX>-strikes.md` when replanning a previously blocked task
3. Update `.ai/PROGRESS.md`:
   - Append new task rows as `pending`.
   - Create/update `## Phase Status` section.
   - Append log entry with task range.
4. PROGRESS.md minimum format:
   - `## Task Status` with table: `| Task | Title | Status | Commit |`
   - `## Log`
   - `## Phase Status`

## Rules

- Keep machine tokens unchanged: `pending`, `in-progress`, `completed`, `blocked`, `VERIFICATION_EVIDENCE`.
- Do not renumber existing tasks.
- Planner must never mark tasks as `completed`.
- Planner must not create tasks before Phase C + Phase E confirmations.
- Planner must not create tasks before `Approval: APPROVED`.
- Planner must treat `Feature Hash` as approval integrity guard.
- Write `task-graph.yaml` before emitting success output.
- Update `.ai/memory/shared-memory.md` with one short planning decision entry.
