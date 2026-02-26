# Memory Contract (Lite+Memory)

Path:
- `.ai/memory/shared-memory.md`

Purpose:
- Keep durable decisions, conventions, and recurring failure patterns.

Write rules:
1) Keep entries concise and verifiable.
2) Prefer one entry per meaningful decision/failure pattern.
3) Avoid long narrative logs.

Entry format:

```markdown
## [Topic]
- Fact: <short statement>
- Reason: <why this matters>
- Evidence: <file path or command output summary>
- Updated: <YYYY-MM-DD>
```

Safety:
- Never store secrets.
- Never store personal data.
