# RW Planner Loop

2-에이전트 오케스트레이션 스킬. 계획(`rw-planner`) → 구현(`rw-loop`).

- **rw-planner**: 인터뷰 → feature 승인 → DAG 태스크 분해
- **rw-loop**: 태스크 디스패치 → TDD coder → 검증 게이트 → 리뷰

## 설치

Copilot Chat에서 다음과 같이 말하세요:

```
Fetch and follow instructions from https://raw.githubusercontent.com/jihunheodev-lab/rw-planner-loop/main/INSTALL.md
```

AI가 자동으로 12개 스킬 파일을 다운로드하여 프로젝트의 `.github/skills/`에 배치합니다.

수동 설치 방법은 [INSTALL.md](INSTALL.md)를 참고하세요.

## 사용법

```
1. @rw-planner "기능 요청"     # 인터뷰 → feature → plan → tasks
2. @rw-loop                    # 구현 시작
3. @rw-loop                    # 완료될 때까지 반복
```

### 모드 옵션

| 플래그 | 효과 |
|---|---|
| `--auto` / `--no-hitl` | 중간 확인 질문 최소화 |
| `--hitl` | 사람 확인 유지 |
| `--parallel` | 독립 태스크 병렬 디스패치 |
| `--max-parallel=N` | 최대 N개 병렬 (기본 4) |

## 동작 흐름

```mermaid
flowchart TD
    A[사용자 요청] --> B[@rw-planner: 인터뷰 + feature + plan]
    B --> C[NEXT_COMMAND=rw-loop]
    C --> D[@rw-loop: task → coder → 검증]
    D --> E{게이트 통과?}
    E -- 실패 --> D
    E -- 통과 --> F{모든 Task 완료?}
    F -- 아니오 --> D
    F -- 예 --> G[Review → NEXT_COMMAND=done]
```

## 핵심 메커니즘

| 메커니즘 | 설명 |
|---|---|
| **Step 0 가드** | 모든 에이전트 시작 시 `.ai/CONTEXT.md` + 필수 파일 검증. 실패 시 오류 토큰 출력 후 중단 |
| **Feature 승인 게이트** | feature 문서에 `Approval: APPROVED` 없으면 태스크 생성 불가 |
| **모호도 자동 점수화** | 요청 모호도를 0-100으로 평가, 40+ 이면 후보안 4개 자동 생성 |
| **TDD 강제** | coder는 테스트 먼저 → 실패 확인 → 최소 구현 → 통과 확인 순서 필수 |
| **4단계 검증 게이트** | Task Inspector → Security → Phase Inspector → Review |
| **3-strike 규칙** | 3회 실패 시 blocked → `rw-planner` 재진입 |

> 각 메커니즘의 상세 규칙은 계약 문서를 참조하세요.

## 구조

```text
rw-planner-loop/
├─ .github/skills/
│  ├─ rw-planner/
│  │  ├─ SKILL.md                    # planner 정의
│  │  ├─ assets/                     # feature-template, memory-contract
│  │  └─ references/planner-contract.md
│  └─ rw-loop/
│     ├─ SKILL.md                    # loop 정의
│     ├─ assets/                     # 5개 서브에이전트 프롬프트
│     └─ references/                 # loop-contract, subagent-contracts
├─ .gitignore
└─ README.md
```

런타임 `.ai/` 디렉토리는 planner 첫 실행 시 대상 워크스페이스에 자동 생성됩니다.

## 계약 문서 참조

| 문서 | 내용 |
|---|---|
| [planner-contract.md](.github/skills/rw-planner/references/planner-contract.md) | Step 0, 인터뷰 정책, 모호도 점수화, Feature 관리, 실패 토큰 |
| [loop-contract.md](.github/skills/rw-loop/references/loop-contract.md) | Step 0, 모드 해석, 메인 루프, 디스패치, 검증 게이트 |
| [subagent-contracts.md](.github/skills/rw-loop/references/subagent-contracts.md) | Coder, Task Inspector, Security, Phase Inspector, Review 계약 |
