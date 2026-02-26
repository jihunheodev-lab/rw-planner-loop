# RW Plan Loop Lite (Skill Edition)

실사용 기준으로 최소 구성만 남긴 plan/loop 오케스트레이션 **스킬 패키지**입니다.

- `rw-planner`: 하이브리드 인터뷰(askQuestions) + 요구사항 정리 + 태스크 분해
- `rw-loop`: 구현 위임 + 검증 + 리뷰 게이트

핵심 의도:
- 사용은 쉽게 (`@rw-planner` -> `@rw-loop`)
- 동작은 견고하게 (Step 0 가드, 상태 토큰 계약, 검증 증거 강제)

`rw-auto`는 제거했습니다. 이유는 planner 인터뷰(`askQuestions`) 안정성과 nested subagent 호출 리스크를 줄이기 위함입니다.

## 스킬 설치 방법

이 저장소를 사용자 스킬 디렉토리에 클론하세요:

```bash
# Windows
git clone <repo-url> "%USERPROFILE%\.copilot\skills\rw-planner-loop"

# macOS / Linux
git clone <repo-url> "$HOME/.copilot/skills/rw-planner-loop"
```

설치 후 VS Code에서 `@rw-planner`, `@rw-loop` 에이전트가 자동으로 등록됩니다.

## 한눈에 보는 구조

```text
rw-planner-loop/           # 스킬 루트
├─ .github/skills/
│  ├─ rw-planner/
│  │  ├─ SKILL.md          # planner 에이전트 정의
│  │  ├─ assets/
│  │  │  ├─ feature-template.md
│  │  │  └─ memory-contract.md
│  │  └─ references/
│  │     └─ planner-contract.md
│  └─ rw-loop/
│     ├─ SKILL.md          # loop 에이전트 정의
│     ├─ assets/
│     │  ├─ rw-loop-coder.subagent.md
│     │  ├─ rw-loop-task-inspector.subagent.md
│     │  ├─ rw-loop-security-review.subagent.md
│     │  ├─ rw-loop-phase-inspector.subagent.md
│     │  └─ rw-loop-review.subagent.md
│     └─ references/
│        ├─ loop-contract.md
│        └─ subagent-contracts.md
└─ README.md               # 이 파일
```

런타임 디렉토리(`.ai/`)는 planner 첫 실행 시 대상 워크스페이스에 자동 bootstrap됩니다:

```text
workspace/                  # 대상 프로젝트
├─ .ai/
│  ├─ CONTEXT.md           # Step 0 필수 참조
│  ├─ PLAN.md
│  ├─ PROGRESS.md
│  ├─ features/
│  ├─ tasks/
│  ├─ plans/
│  ├─ runtime/
│  └─ memory/shared-memory.md
└─ ...
```

## 동작 흐름 (시각화)

### 1) 전체 플로우

```mermaid
flowchart TD
    A[사용자 요청] --> C[@rw-planner: Step 0 + 인터뷰]
    C --> D[@rw-planner: feature -> plan -> tasks]
    D --> E[NEXT_COMMAND=rw-loop]
    E --> F[@rw-loop: task lock -> coder 위임]
    F --> G[검증: completion delta + VERIFICATION_EVIDENCE]
    G --> H[Task Inspector + USER_PATH_GATE]
    H --> H2[Security Gate]
    H2 --> I{Phase 완료?}
    I -- 예 --> J[Phase Inspector]
    I -- 아니오 --> F
    J --> K{모든 Task 완료?}
    K -- 아니오 --> F
    K -- 예 --> L[Review Subagent]
    L --> M{REVIEW_STATUS}
    M -- OK --> N[NEXT_COMMAND=done]
    M -- FAIL/ESCALATE --> O[NEXT_COMMAND=rw-loop 또는 rw-planner]
```

### 2) 상태 전이(태스크 단위)

```text
pending -> in-progress -> completed
                |            ^
                v            |
              blocked --------

규칙:
- 단일 모드: rw-loop 1회 dispatch는 정확히 1개 task만 completed 가능
- 병렬 모드: dispatch한 N개 task가 같은 실행에서 정확히 N개 completed 되어야 함
- completed로 바뀌려면 VERIFICATION_EVIDENCE 증가가 필수
- 3-strike 실패 시 blocked + REVIEW-ESCALATE + rw-planner 재진입
```

## 에이전트별 책임 분리

| Agent | 하는 일 | 하지 않는 일 | 종료 토큰 |
|---|---|---|---|
| `rw-planner` | feature 수집, `PLAN_ID` 생성, `TASK-XX` 분해, `PROGRESS` 동기화 | 제품 코드 직접 구현 | `NEXT_COMMAND=rw-loop` |
| `rw-loop` | task 선택/락, coder 위임, 증거 검증, user-path/security/phase/review 게이트 | planner 역할(요구사항 재정의) | `NEXT_COMMAND=done/rw-loop/rw-planner` |

## Step 0 가드 (견고성 핵심)

모든 에이전트는 시작 시 아래를 먼저 확인합니다.

1. `.ai/CONTEXT.md` 읽기
2. 필수 파일/디렉토리 존재 확인
3. 조건 미충족 시 표준 오류 토큰 출력 후 중단

주요 오류 토큰:
- `LANG_POLICY_MISSING`: auto-recovery 이후에도 CONTEXT 복구 실패
- `TARGET_ROOT_INVALID`: 필수 경로/권한 문제
- `RW_ENV_UNSUPPORTED`: `runSubagent` 사용 불가
- `RW_SUBAGENT_PROMPT_MISSING`: loop 하위 프롬프트 누락
- `PAUSE_DETECTED`: 긴급 정지 파일(`.ai/PAUSE.md`) 감지
- `SECURITY_GATE_FAILED`: 보안 게이트 실패

## 실제 사용 방법

### 기본 사용 (권장)

1. VS Code에서 워크스페이스 열기
2. `@rw-planner "원라인 기능 요청"`
3. `@rw-loop`
4. 완료될 때까지 `@rw-loop` 반복

`rw-planner`에는 handoff(`Start Implementation`)가 설정되어 있어, UI에서 바로 `rw-loop`로 넘길 수 있습니다.

### 사용자 직접 테스트 (권장)

`rw-loop`는 모든 task 완료 + review 통과 시, 사용자 수동 점검용 체크리스트를 만들 수 있습니다.

- 경로: `.ai/plans/<PLAN_ID>/user-acceptance-checklist.md`
- 포함 내용: 실행 명령, 기대 결과, 실패 시 빠른 확인 포인트
- 성격: advisory only (참고용)
  - task 상태/게이트/NEXT_COMMAND에는 영향 없음
  - 파일 생성 실패/누락으로 실행이 실패하지 않음

### Planner 질문 정책 (Hybrid)

`rw-planner`는 필수 필드를 항상 채우되, 질문은 누락/모호한 항목에만 수행합니다.

1. 1차 Need-Gate(최대 4개): 입력에서 먼저 필드 추출 후 필요한 질문만 배치
2. 필수 확인 항목:
   `TARGET_KIND` (`PRODUCT_CODE` / `AGENT_WORKFLOW`), `USER_PATH`,
   범위 경계(`in-scope` / `out-of-scope`), `ACCEPTANCE_SIGNAL`
3. `TARGET_KIND` 기본값:
   - 기본 `PRODUCT_CODE`
   - `.github/agents/**`, `.github/prompts/**`, `.ai/**`, `scripts/health/**`, `scripts/validation/**` 등
     에이전트/오케스트레이션 자산 수정 요청일 때만 `AGENT_WORKFLOW`
4. 2차 Deep-Dive(조건부): 애매하거나 리스크가 크면 6~10개 추가 질문
5. 최종 확인(항상): 요약 확인 질문에 동의해야 태스크 생성

### Planner 문서 언어 정책

- 계획/feature/task 본문(prose)은 `.ai/CONTEXT.md`의 `Response language`를 따름
- 헤더와 machine token은 영어 유지 (컨텍스트에서 별도 지시가 있으면 따름)

### Planner 서브에이전트 계획 단계

`rw-planner`는 계획 생성 시 `runSubagent`를 사용합니다.

1. `PLAN_STRATEGY=SINGLE`: Plan 서브에이전트 1회 실행
2. `PLAN_STRATEGY=PARALLEL_AUTO`: Plan 서브에이전트 4회 실행(후보안 생성)
3. 후보 계획 텍스트는 메인 채팅에 그대로 표시
4. `askQuestions`는 승인 질문에만 사용 (계획 본문 삽입 금지)
5. 승인 전에는 task/progress를 기록하지 않음

### 모호도 점수화와 자동 전략 선택

`rw-planner`는 별도 명령어 없이 모호도를 점수화하고 계획 전략을 자동 선택합니다.

점수 규칙(최대 100):
- `TARGET_KIND` 기본 추론 후에도 충돌: +5
- `USER_PATH` 불명확: +25
- `SCOPE_BOUNDARY` 불명확: +20
- `ACCEPTANCE_SIGNAL` 불명확: +20
- 대상 경로/파일 미지정: +10
- 범용 표현 위주 요청: +10
- 광범위 표현 사용: +5
- 3개 이상 디렉토리 영향 예상: +10
- 보안/데이터/권한 이슈 미해결: +15

전략 규칙:
1. 필수 필드가 하나라도 불명확하면 `PLAN_STRATEGY=PARALLEL_AUTO`
2. 아니면 `AMBIGUITY_SCORE >= 40`일 때 `PLAN_STRATEGY=PARALLEL_AUTO`
3. 나머지는 `PLAN_STRATEGY=SINGLE`

출력 토큰:
- `AMBIGUITY_SCORE=<0-100>`
- `AMBIGUITY_REASONS=<comma-separated-codes>`
- `PLAN_STRATEGY=<SINGLE|PARALLEL_AUTO>`

`PARALLEL_AUTO`일 때 동작:
- 후보안 4개를 `.ai/plans/<PLAN_ID>/candidate-plan-{1..4}.md`로 생성
- 비교표 `.ai/plans/<PLAN_ID>/candidate-selection.md` 작성
- 각 후보는 고정 섹션 + `## Candidate JSON` 블록을 포함
- 최종 task/progress 쓰기는 선택된 1개 안만 반영

### Planner 산출물 강화 (DAG + 연구 근거)

`rw-planner`는 task 분해 시 아래 파일을 추가로 생성/갱신합니다.

- `.ai/plans/<PLAN_ID>/task-graph.yaml`
  - `nodes`, `edges`, `parallel_groups` 포함
  - `rw-loop --parallel`에서 독립 태스크 선별 기준으로 사용
- `.ai/plans/<PLAN_ID>/research_findings_<focus_area>.yaml`
  - `focus_area`, `summary`, `citations(file:line)`, `assumptions` 포함
  - 근거 없는 단정 최소화 목적

### Feature 승인 게이트 (필수)

`rw-planner`는 feature 문서 승인이 없으면 태스크를 만들지 않습니다.

필수 메타데이터(Feature 파일):
- `Approval: PENDING|APPROVED`
- `Approved By: <name-or-id>`
- `Approved At: <YYYY-MM-DD>`
- `Feature Hash: <sha256>`

동작:
1. 인터뷰 후 feature 초안을 만들거나 갱신
2. `Approval != APPROVED`이면 아래 토큰을 출력하고 중단
   - `FEATURE_REVIEW_REQUIRED`
   - `FEATURE_REVIEW_REASON=<APPROVAL_MISSING|APPROVAL_RESET_SCOPE_CHANGED>`
   - `FEATURE_FILE=<path>`
   - `FEATURE_REVIEW_HINT=<what_to_edit>`
3. 사용자가 feature 내용을 리뷰/수정 후 `Approval: APPROVED`로 확정
4. 그 다음 실행에서만 planner가 task 생성
5. 승인 후 scope가 바뀌면 승인 상태를 `PENDING`으로 되돌리고 다시 리뷰 요구

템플릿 참고: `rw-planner/assets/feature-template.md`

### Feature 파일 네이밍

planner는 feature 파일명을 아래 순서로 선택합니다.

1. 이슈 키가 있으면: `JIRA-123-<slug>.md`
2. 없으면: `FEATURE-XX-<slug>.md`

예시:
- `.ai/features/JIRA-123-add-search-command.md`
- `.ai/features/FEATURE-04-add-search-command.md`

### 모드 옵션

- `@rw-loop --auto` 또는 `@rw-loop --no-hitl`: 중간 확인 질문 최소화
- `@rw-loop --hitl`: 사람 확인 유지
- `@rw-loop --parallel`: 독립 태스크 병렬 시도
- `@rw-loop --parallel --max-parallel=4`: 최대 4개까지 병렬 디스패치

### Coder TDD 규칙 (강제)

`rw-loop-coder`는 아래 순서를 강제합니다.

1. 테스트 먼저 작성/수정
2. 실패 테스트 확인
3. 최소 구현
4. 재테스트 통과 확인
5. 사용자 진입점(UI/CLI/API) 실제 연결 여부 확인

증거는 `VERIFICATION_EVIDENCE`로 남기며, 실패 테스트/성공 테스트/진입점 확인 항목이 모두 필요합니다.

## 첫 실행 시 생성되는 산출물

`rw-planner`가 없으면 대상 워크스페이스에 bootstrap합니다.

- `.ai/CONTEXT.md`
- `.ai/PLAN.md`
- `.ai/PROGRESS.md`
- `.ai/memory/shared-memory.md`
- `.ai/plans/*/task-graph.yaml`
- `.ai/features/*`, `.ai/tasks/*`, `.ai/plans/*`

## 어떤 파일이 "필수"인가?

스킬 패키지(필수):
- `.github/skills/rw-planner/SKILL.md`
- `.github/skills/rw-loop/SKILL.md`
- `.github/skills/rw-loop/assets/rw-loop-*.subagent.md`

참조 문서:
- `.github/skills/rw-planner/assets/feature-template.md` — Feature 파일 양식
- `.github/skills/rw-planner/assets/memory-contract.md` — 메모리 계약 양식
- `.github/skills/rw-loop/references/loop-contract.md` — Loop 계약 상세
- `.github/skills/rw-loop/references/subagent-contracts.md` — 서브에이전트 계약 상세
- `.github/skills/rw-planner/references/planner-contract.md` — Planner 계약 상세

## 메모리 계약

- 계약 문서: `rw-planner/assets/memory-contract.md`
- 런타임 파일: `.ai/memory/shared-memory.md`
- planner/loop는 짧은 의사결정 기록만 남깁니다.
- 비밀/개인정보 저장 금지.
