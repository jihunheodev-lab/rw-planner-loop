# Feature Template (Lite)

Use this structure for `.ai/features/<key>-<slug>.md`.
Write prose in the `Response language` defined by `.ai/CONTEXT.md`.

Naming:
- Preferred: `<ISSUE_KEY>-<slug>.md` (example: `JIRA-123-add-search-command.md`)
- Fallback: `FEATURE-XX-<slug>.md` (example: `FEATURE-04-add-search-command.md`)

```markdown
# [feature-slug]

## Summary
- One-line objective

## Trigger / Situation
- Why this feature is needed now

## User Path
- Entry point
- Main interaction flow
- Exit/expected end state

## Scope Boundary
- In Scope:
  - ...
- Out of Scope:
  - ...

## Acceptance Signal
- Observable behavior:
  - ...
- Verification command(s):
  - ...

## Planning Profile
- STANDARD | FAST_TEST

## Status
- READY_FOR_PLAN | PLANNED

## Approval
- Approval: PENDING | APPROVED
- Approved By: <name-or-id>
- Approved At: <YYYY-MM-DD>
- Feature Hash: <sha256>

## Approval Checklist
- [ ] User path is concrete and testable
- [ ] In/Out scope boundaries are explicit
- [ ] Acceptance signal includes executable verification
- [ ] Approver identity and date are filled
```

Notes:
- If scope changes after approval, reset `Approval` to `PENDING`.
- Keep machine-readable tokens in English.
- Keep headers in English if needed, and follow `.ai/CONTEXT.md` for prose language.
