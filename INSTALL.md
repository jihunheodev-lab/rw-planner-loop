# Installing RW Planner Loop for GitHub Copilot

Installation guide for rw-planner + rw-loop skills on GitHub Copilot (VS Code).

## Automated Installation (Recommended)

AI agent reading this document: follow the steps below in order.

### Step 1: Create Directories

Create the following directories relative to the project root:

```
.github/skills/rw-planner/assets/
.github/skills/rw-planner/references/
.github/skills/rw-loop/assets/
.github/skills/rw-loop/references/
.github/skills/rw-loop/scripts/
```

### Step 2: Download Files

Download each file from the URLs below and save them to the corresponding paths.
Base URL: `https://raw.githubusercontent.com/jihunheodev-lab/rw-planner-loop/main`

**rw-planner:**

| URL Path | Save To |
|---|---|
| `/.github/skills/rw-planner/SKILL.md` | `.github/skills/rw-planner/SKILL.md` |
| `/.github/skills/rw-planner/assets/feature-template.md` | `.github/skills/rw-planner/assets/feature-template.md` |
| `/.github/skills/rw-planner/assets/memory-contract.md` | `.github/skills/rw-planner/assets/memory-contract.md` |
| `/.github/skills/rw-planner/references/planner-contract.md` | `.github/skills/rw-planner/references/planner-contract.md` |

**rw-loop:**

| URL Path | Save To |
|---|---|
| `/.github/skills/rw-loop/SKILL.md` | `.github/skills/rw-loop/SKILL.md` |
| `/.github/skills/rw-loop/assets/rw-loop-coder.subagent.md` | `.github/skills/rw-loop/assets/rw-loop-coder.subagent.md` |
| `/.github/skills/rw-loop/assets/rw-loop-phase-inspector.subagent.md` | `.github/skills/rw-loop/assets/rw-loop-phase-inspector.subagent.md` |
| `/.github/skills/rw-loop/assets/rw-loop-review.subagent.md` | `.github/skills/rw-loop/assets/rw-loop-review.subagent.md` |
| `/.github/skills/rw-loop/assets/rw-loop-security-review.subagent.md` | `.github/skills/rw-loop/assets/rw-loop-security-review.subagent.md` |
| `/.github/skills/rw-loop/assets/rw-loop-task-inspector.subagent.md` | `.github/skills/rw-loop/assets/rw-loop-task-inspector.subagent.md` |
| `/.github/skills/rw-loop/references/loop-contract.md` | `.github/skills/rw-loop/references/loop-contract.md` |
| `/.github/skills/rw-loop/references/subagent-contracts.md` | `.github/skills/rw-loop/references/subagent-contracts.md` |
| `/.github/skills/rw-loop/scripts/check_state_sync.py` | `.github/skills/rw-loop/scripts/check_state_sync.py` |
| `/.github/skills/rw-loop/scripts/env_preflight.py` | `.github/skills/rw-loop/scripts/env_preflight.py` |

### Step 3: Verify

Confirm that 14 files were downloaded:
- `rw-planner/`: SKILL.md + 2 assets + 1 reference = 4 files
- `rw-loop/`: SKILL.md + 5 assets + 2 references + 2 scripts = 10 files

### Step 4: Report

Report the installation result to the user:
- On success: "rw-planner-loop skills installed (14 files). Start with `@rw-planner`."
- On failure: report which files failed and why.

## Manual Installation

```bash
git clone https://github.com/jihunheodev-lab/rw-planner-loop.git /tmp/rw-planner-loop
mkdir -p .github/skills
cp -r /tmp/rw-planner-loop/.github/skills/rw-planner .github/skills/
cp -r /tmp/rw-planner-loop/.github/skills/rw-loop .github/skills/
rm -rf /tmp/rw-planner-loop
```

## Updating

Ask the AI to fetch this URL again to overwrite with the latest version.

## Uninstalling

```bash
rm -rf .github/skills/rw-planner .github/skills/rw-loop
```
