# Installing RW Planner Loop for GitHub Copilot

GitHub Copilot(VS Code)용 rw-planner + rw-loop 스킬 설치 가이드.

## AI 자동 설치 (권장)

이 문서를 읽고 있는 AI 에이전트에게: 아래 절차를 순서대로 실행하세요.

### Step 1: 디렉토리 생성

프로젝트 루트 기준으로 다음 디렉토리를 생성합니다:

```
.github/skills/rw-planner/assets/
.github/skills/rw-planner/references/
.github/skills/rw-loop/assets/
.github/skills/rw-loop/references/
```

### Step 2: 파일 다운로드

아래 URL에서 각 파일을 다운로드하여 해당 경로에 저장합니다.
Base URL: `https://raw.githubusercontent.com/jihunheodev-lab/rw-planner-loop/main`

**rw-planner:**

| URL 경로 | 저장 위치 |
|---|---|
| `/.github/skills/rw-planner/SKILL.md` | `.github/skills/rw-planner/SKILL.md` |
| `/.github/skills/rw-planner/assets/feature-template.md` | `.github/skills/rw-planner/assets/feature-template.md` |
| `/.github/skills/rw-planner/assets/memory-contract.md` | `.github/skills/rw-planner/assets/memory-contract.md` |
| `/.github/skills/rw-planner/references/planner-contract.md` | `.github/skills/rw-planner/references/planner-contract.md` |

**rw-loop:**

| URL 경로 | 저장 위치 |
|---|---|
| `/.github/skills/rw-loop/SKILL.md` | `.github/skills/rw-loop/SKILL.md` |
| `/.github/skills/rw-loop/assets/rw-loop-coder.subagent.md` | `.github/skills/rw-loop/assets/rw-loop-coder.subagent.md` |
| `/.github/skills/rw-loop/assets/rw-loop-phase-inspector.subagent.md` | `.github/skills/rw-loop/assets/rw-loop-phase-inspector.subagent.md` |
| `/.github/skills/rw-loop/assets/rw-loop-review.subagent.md` | `.github/skills/rw-loop/assets/rw-loop-review.subagent.md` |
| `/.github/skills/rw-loop/assets/rw-loop-security-review.subagent.md` | `.github/skills/rw-loop/assets/rw-loop-security-review.subagent.md` |
| `/.github/skills/rw-loop/assets/rw-loop-task-inspector.subagent.md` | `.github/skills/rw-loop/assets/rw-loop-task-inspector.subagent.md` |
| `/.github/skills/rw-loop/references/loop-contract.md` | `.github/skills/rw-loop/references/loop-contract.md` |
| `/.github/skills/rw-loop/references/subagent-contracts.md` | `.github/skills/rw-loop/references/subagent-contracts.md` |

### Step 3: 검증

다운로드한 파일이 12개인지 확인합니다:
- `rw-planner/`: SKILL.md + assets 2개 + references 1개 = 4개
- `rw-loop/`: SKILL.md + assets 5개 + references 2개 = 8개

### Step 4: 완료 보고

사용자에게 설치 결과를 알려줍니다:
- 설치 성공 시: "rw-planner-loop 스킬 설치 완료 (12개 파일). `@rw-planner`로 시작하세요."
- 실패 시: 실패한 파일과 사유를 보고합니다.

## 수동 설치

```bash
# 저장소 클론 후 .github/skills/ 복사
git clone https://github.com/jihunheodev-lab/rw-planner-loop.git /tmp/rw-planner-loop
mkdir -p .github/skills
cp -r /tmp/rw-planner-loop/.github/skills/rw-planner .github/skills/
cp -r /tmp/rw-planner-loop/.github/skills/rw-loop .github/skills/
rm -rf /tmp/rw-planner-loop
```

## Updating

AI에게 다시 이 URL을 fetch하도록 요청하면 최신 버전으로 덮어씁니다.

## Uninstalling

```bash
rm -rf .github/skills/rw-planner .github/skills/rw-loop
```
