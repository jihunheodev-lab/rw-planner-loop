# Session Notify Hook

Copilot Chat 에이전트 세션의 주요 이벤트(작업 완료, 질문 대기 등)를 OS 알림 또는 Telegram으로 통보합니다.

## 파일 구조

```
.github/hooks/
├── session-notify.json     # VS Code hook 등록 (고유 이름으로 충돌 방지)
└── session-notify/
    ├── notify.ps1        # Windows 알림 스크립트
├── notify.sh         # macOS/Linux 알림 스크립트
├── .env.example      # 환경변수 템플릿
    ├── .env              # 사용자 설정 (gitignore 대상)
    ├── test-notify.ps1   # PowerShell 테스트
    ├── test-notify.sh    # Bash 테스트
    └── README.md         # 이 파일
```

## 알림 트리거

| 이벤트 | 알림 내용 |
|--------|----------|
| 작업 완료/실패 | `Stop` — "작업 완료!" / "작업 실패!" / "세션 종료" |
| 질문 대기 | `PreToolUse` + askQuestions — "질문을 기다리고 있어요!" |

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

2. (선택) **Bash 환경에서 `jq` 설치** — 없어도 fallback 파싱 동작

## 설치

이 레포의 다른 프로젝트 설치는 [HOOKS-INSTALL.md](../../../HOOKS-INSTALL.md)를 참고하세요.

### 이 프로젝트에서 사용

이미 `session-notify.json`이 포함되어 있으므로 추가 설치 불필요.
`.env.example`을 복사하여 `.env`를 만들고 값을 설정하세요:

```bash
cp .github/hooks/session-notify/.env.example .github/hooks/session-notify/.env
```

## 환경변수 설정

### `.env` 파일 (권장)

> **우선순위**: 셸 환경 변수 > `.env` 파일. `.env`는 미설정 변수의 fallback입니다.

> **보안**: `.env`는 `.gitignore`로 커밋되지 않습니다.

### OS 알림만 (기본)

추가 설정 없이 바로 동작합니다.

### Telegram 연동

1. **Telegram 봇 생성**: [@BotFather](https://t.me/BotFather) → `/newbot` → 토큰 복사
2. **Chat ID 확인**: 봇에 메시지 전송 → `https://api.telegram.org/bot<토큰>/getUpdates` → `result[0].message.chat.id`
3. **설정**: `.env`에 입력하거나 셸 프로필에 추가:

   ```bash
   TELEGRAM_BOT_TOKEN="your-bot-token"
   TELEGRAM_CHAT_ID="your-chat-id"
   COPILOT_NOTIFY_CHANNELS="telegram,os"
   ```

### 환경변수 목록

| 변수 | 필수 | 기본값 | 설명 |
|------|------|--------|------|
| `COPILOT_NOTIFY_CHANNELS` | X | `os` | `os`, `telegram`, `telegram,os` |
| `COPILOT_NOTIFY_EVENTS` | X | `all` | `all`, `stop`, `pretooluse`, `none` |
| `COPILOT_NOTIFY_DETAIL` | X | `normal` | `short`, `normal`, `verbose` |
| `TELEGRAM_BOT_TOKEN` | Telegram 시 | - | Telegram 봇 토큰 |
| `TELEGRAM_CHAT_ID` | Telegram 시 | - | Telegram 채팅 ID |
| `COPILOT_NOTIFY_DEBUG` | X | `0` | `1`: stderr에 디버그 로그 |

## 알림 상세도

`COPILOT_NOTIFY_DETAIL` 값에 따라 알림에 포함되는 정보가 달라집니다:

| 레벨 | 내용 | 예시 |
|------|------|------|
| `short` | 상태만 | `Copilot: 작업 완료!` |
| `normal` | + 프로젝트명, 세션 제목 | `Copilot: 작업 완료!`<br>`📂 my-project`<br>`💬 Chat ID 확인 방법 문의` |
| `verbose` | + 세션 ID, 마지막 질문 | 위 내용 +<br>`🏷 ea620ff9`<br>`📝 "현재 까지 내용 커밋하고..."` |

### 세션 제목 자동 추출

`normal`/`verbose` 레벨에서 VS Code가 AI로 생성한 채팅 세션 제목을 자동 표시합니다.
- `state.vscdb`에서 직접 추출 (외부 도구 의존 없음)
- 세션 제목을 찾지 못하면 첫 번째 사용자 메시지로 fallback

## 보안 주의사항

- **Hook 편집 보호**: 에이전트가 hook 스크립트를 수정하지 못하도록 설정:
  ```json
  {
    "chat.tools.edits.autoApprove": { "exclude": [".github/hooks/**"] }
  }
  ```
- **알림 본문**: 이벤트 유형, 프로젝트명, 세션 제목만 포함. 프롬프트·명령어·토큰 등 민감 정보 미전송.

## 알려진 제한사항

- **중복 억제**: 같은 이벤트 30초 내 재발생 시 스킵
- **에러 감지**: `Stop` 시점에 transcript 기반 판별. 스키마 변경 시 "세션 종료" fallback
- **tool_name 변동**: VS Code 업데이트에 따라 도구명 변경 가능. 디버그 모드로 확인

## 테스트

```bash
# Bash
bash .github/hooks/session-notify/test-notify.sh

# PowerShell
pwsh .github/hooks/session-notify/test-notify.ps1
```
