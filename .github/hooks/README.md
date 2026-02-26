# Copilot Chat Agent Notification Hook

VS Code Copilot Chat 에이전트 세션에서 주요 이벤트 발생 시 알림을 보내는 Hook입니다.

## 알림 트리거

| 이벤트 | 알림 내용 |
|--------|----------|
| 작업 완료/실패 | `Stop` 이벤트 — "작업 완료!" / "작업 실패!" / "세션 종료" |
| 질문 대기 | `PreToolUse` + askQuestions — "질문을 기다리고 있어요!" |
| 승인 대기 | `PreToolUse` + terminal/bash 등 — "승인 대기 중!" |

## 알림 채널

| 채널 | 설정값 | 비고 |
|------|--------|------|
| OS 네이티브 | `os` (기본값) | Windows Toast, macOS 알림센터, Linux notify-send |
| Telegram | `telegram` | 핸드폰 푸시 알림 |
| 둘 다 | `telegram,os` | |

## 사전조건

1. **VS Code hooks 활성화** (Preview 기능):
   - `Ctrl+,` → 검색: `chat.hooks.enabled` → 체크 활성화
   - 또는 `settings.json`에 추가: `"chat.hooks.enabled": true`

2. (선택) **Bash 환경에서 `jq` 설치** — 없어도 fallback 파싱 동작하지만, `jq`가 있으면 더 안정적

## 설치

### 이 프로젝트에서 사용

이미 `.github/hooks/notify.json`이 포함되어 있으므로 추가 설치 불필요.

### 다른 프로젝트에 복사

```bash
# 대상 프로젝트의 .github/hooks/ 디렉토리에 복사
cp -r .github/hooks/notify.json .github/hooks/notify.sh .github/hooks/notify.ps1 .github/hooks/.env.example <대상프로젝트>/.github/hooks/

# (macOS/Linux) 실행 권한 부여
chmod +x <대상프로젝트>/.github/hooks/notify.sh
```

## 환경변수 설정

### `.env` 파일 (권장)

프로젝트별 설정을 `.env` 파일로 관리할 수 있습니다:

```bash
# .env.example을 복사하여 .env 파일 생성
cp .github/hooks/.env.example .github/hooks/.env

# .env 파일을 편집하여 값 설정
```

> **우선순위**: 셸 환경 변수가 항상 `.env` 파일보다 우선합니다. `.env` 파일은 미설정 변수에 대한 fallback으로만 동작합니다.

> **보안**: `.github/hooks/.env`는 `.gitignore`에 포함되어 있어 커밋되지 않습니다.

### OS 알림만 (기본)

추가 설정 없이 바로 동작합니다.

### Telegram 연동

1. **Telegram 봇 생성**:
   - Telegram에서 [@BotFather](https://t.me/BotFather) 검색
   - `/newbot` 명령 → 이름/유저네임 설정
   - 발급된 **토큰** 복사

2. **Chat ID 확인**:
   - 생성한 봇에게 아무 메시지 전송
   - 브라우저에서 `https://api.telegram.org/bot<토큰>/getUpdates` 접속
   - `result[0].message.chat.id` 값이 Chat ID

3. **환경변수 설정** (사용하는 셸 프로필에 추가):

   ```bash
   # Bash (~/.bashrc 또는 ~/.zshrc)
   export TELEGRAM_BOT_TOKEN="your-bot-token"
   export TELEGRAM_CHAT_ID="your-chat-id"
   export COPILOT_NOTIFY_CHANNELS="telegram,os"
   ```

   ```powershell
   # PowerShell ($PROFILE)
   $env:TELEGRAM_BOT_TOKEN = "your-bot-token"
   $env:TELEGRAM_CHAT_ID = "your-chat-id"
   $env:COPILOT_NOTIFY_CHANNELS = "telegram,os"
   ```

### 환경변수 목록

| 변수 | 필수 | 기본값 | 설명 |
|------|------|--------|------|
| `COPILOT_NOTIFY_CHANNELS` | X | `os` | 활성 채널: `os`, `telegram`, `telegram,os` |
| `COPILOT_NOTIFY_EVENTS` | X | `all` | 알림 이벤트: `all`, `stop`, `pretooluse`, `stop,pretooluse`, `none` |
| `TELEGRAM_BOT_TOKEN` | Telegram 시 | - | Telegram 봇 토큰 |
| `TELEGRAM_CHAT_ID` | Telegram 시 | - | Telegram 채팅 ID |
| `COPILOT_NOTIFY_DEBUG` | X | `0` | `1`로 설정 시 모든 tool_name을 stderr에 로그 |
| `COPILOT_NOTIFY_DETAIL` | X | `normal` | 알림 상세도: `short`, `normal`, `verbose` |

## 알림 상세도

`COPILOT_NOTIFY_DETAIL` 값에 따라 알림에 포함되는 정보가 달라집니다:

| 레벨 | 내용 | 예시 |
|------|------|------|
| `short` | 상태만 | `Copilot: 작업 완료!` |
| `normal` | + 프로젝트명, 첫 질문 요약 | `Copilot: 작업 완료!`<br>`📂 my-project`<br>`💬 "hooks 알림이 안 오는데"` |
| `verbose` | + 세션 ID, 마지막 질문 | 위 내용 +<br>`🏷 ea620ff9`<br>`📝 "현재 까지 내용 커밋하고..."` |

## 디버그 모드

실제 `tool_name` 값을 확인하여 필터를 튜닝하고 싶을 때:

```bash
export COPILOT_NOTIFY_DEBUG=1
```

VS Code Output 패널 → "GitHub Copilot Chat Hooks" 채널에서 로그를 확인할 수 있습니다.

## 보안 주의사항

### Hook 스크립트 편집 보호

에이전트가 hook 스크립트를 수정하면 자기 자신을 실행하는 위험이 있습니다. VS Code 설정에서 hook 파일의 자동 승인을 제외하세요:

```json
// settings.json
{
  "chat.tools.edits.autoApprove": {
    "exclude": [".github/hooks/**"]
  }
}
```

### 알림 본문

알림에는 이벤트 유형과 도구명만 포함됩니다. 프롬프트, 명령어, 파일 경로, 토큰 등 민감 정보는 전송되지 않습니다.

## 알려진 제한사항

- **중복 알림 억제**: 같은 이벤트 유형이 30초 내 재발생하면 알림을 스킵합니다. 이로 인해 PreToolUse 내에서 "질문 대기"와 "승인 대기"가 30초 내 서로 가릴 수 있습니다.
- **에러 감지**: VS Code의 `PostToolUse`는 성공 시에만 발생하므로, 에러 감지는 세션 종료(`Stop`) 시점에 transcript 기반으로 판별합니다. transcript 스키마 변경 시 "세션 종료"로 폴백됩니다.
- **tool_name 변동성**: VS Code 업데이트에 따라 도구명이 바뀔 수 있습니다. 디버그 모드로 주기적으로 확인하세요.

## 테스트

```bash
# Bash 테스트
bash .github/hooks/test-notify.sh

# PowerShell 테스트
pwsh .github/hooks/test-notify.ps1
```
