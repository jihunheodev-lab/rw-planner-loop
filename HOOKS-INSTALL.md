# Installing Session Notify Hook for GitHub Copilot

Copilot Chat 에이전트의 작업 완료/질문 대기 이벤트를 OS 알림 또는 Telegram으로 통보하는 Hook입니다.

## Automated Installation (Recommended)

AI agent reading this document: follow the steps below in order.

### Step 1: Create Directory

Create the following directory relative to the project root:

```
.github/hooks/session-notify/
```

### Step 2: Download Files

Download each file from the URLs below and save them to the corresponding paths.
Base URL: `https://raw.githubusercontent.com/jihunheodev-lab/rw-planner-loop/main`

| URL Path | Save To |
|---|---|
| `/.github/hooks/session-notify.json` | `.github/hooks/session-notify.json` |
| `/.github/hooks/session-notify/notify.ps1` | `.github/hooks/session-notify/notify.ps1` |
| `/.github/hooks/session-notify/notify.sh` | `.github/hooks/session-notify/notify.sh` |
| `/.github/hooks/session-notify/.env.example` | `.github/hooks/session-notify/.env.example` |
| `/.github/hooks/session-notify/.gitignore` | `.github/hooks/session-notify/.gitignore` |
| `/.github/hooks/session-notify/README.md` | `.github/hooks/session-notify/README.md` |

### Step 3: Make Executable (macOS/Linux)

```bash
chmod +x .github/hooks/session-notify/notify.sh
```

### Step 4: Enable VS Code Hooks

Add to `.vscode/settings.json` (or user settings):

```json
{
  "chat.hooks.enabled": true
}
```

### Step 5: Configure (Optional)

```bash
cp .github/hooks/session-notify/.env.example .github/hooks/session-notify/.env
```

Edit `.env` to set notification channels and Telegram credentials if needed.
See [README.md](.github/hooks/session-notify/README.md) for all options.

### Step 6: Verify

Confirm that 6 files were downloaded:
- `.github/hooks/session-notify.json` (hook registration)
- `.github/hooks/session-notify/`: `notify.ps1` + `notify.sh` + `.env.example` + `.gitignore` + `README.md`

> **Note**: `session-notify.json`은 고유한 파일명을 사용하므로 기존 hooks와 충돌 없이 공존합니다.

### Step 7: Report

Report the installation result to the user:
- On success: "session-notify hook installed (6 files). Configure `.env` for Telegram, or use OS notifications out of the box."
- On failure: report which files failed and why.

## Manual Installation

```bash
git clone https://github.com/jihunheodev-lab/rw-planner-loop.git /tmp/rw-planner-loop
mkdir -p .github/hooks
cp /tmp/rw-planner-loop/.github/hooks/session-notify.json .github/hooks/
cp -r /tmp/rw-planner-loop/.github/hooks/session-notify .github/hooks/
chmod +x .github/hooks/session-notify/notify.sh
rm -rf /tmp/rw-planner-loop
```

## Updating

Ask the AI to fetch this URL again to overwrite with the latest version.

## Uninstalling

```bash
rm -f .github/hooks/session-notify.json
rm -rf .github/hooks/session-notify
```
