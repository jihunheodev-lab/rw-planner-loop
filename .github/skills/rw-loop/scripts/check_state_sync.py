#!/usr/bin/env python3
"""
rw-loop state sync checker.

Validates status consistency across:
1) .ai/PROGRESS.md
2) .ai/tasks/TASK-*.md frontmatter
3) .ai/plans/<PLAN_ID>/task-graph.yaml

Also validates that completed tasks do not keep active strike/security counters.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List


ALLOWED_STATUS = {"pending", "in-progress", "completed", "blocked"}
TASK_ID_PATTERN = re.compile(r"^TASK-[A-Z0-9_-]+$")


@dataclass
class ParseOutcome:
    data: Dict[str, str] = field(default_factory=dict)
    issues: List[str] = field(default_factory=list)


@dataclass
class StrikeState:
    strike_active: Dict[str, int] = field(default_factory=dict)
    security_active: Dict[str, int] = field(default_factory=dict)
    legacy: Dict[str, int] = field(default_factory=dict)
    issues: List[str] = field(default_factory=list)


def normalize_scalar(raw: str) -> str:
    value = raw.strip()
    if not value:
        return value
    if value[0] in {"'", '"'} and value[-1] == value[0] and len(value) >= 2:
        return value[1:-1].strip()
    return value


def parse_progress(path: Path) -> ParseOutcome:
    outcome = ParseOutcome()
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        outcome.issues.append(f"cannot read PROGRESS file: {path} ({exc})")
        return outcome

    in_task_status = False
    for line in lines:
        stripped = line.strip()
        if stripped == "## Task Status":
            in_task_status = True
            continue
        if not in_task_status:
            continue
        if stripped.startswith("## ") and stripped != "## Task Status":
            break
        if not stripped or stripped.startswith("|------"):
            continue
        if not stripped.startswith("|"):
            continue

        cols = [col.strip() for col in stripped.strip("|").split("|")]
        if len(cols) < 3:
            continue
        task_id = cols[0]
        status = cols[2].lower()
        if TASK_ID_PATTERN.match(task_id):
            outcome.data[task_id] = status

    if not outcome.data:
        outcome.issues.append("no task rows found in PROGRESS task table")
    return outcome


def parse_task_frontmatter(task_file: Path) -> tuple[str | None, str | None, List[str]]:
    issues: List[str] = []
    try:
        lines = task_file.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        return None, None, [f"cannot read task file: {task_file} ({exc})"]

    inferred_task_id = None
    name_match = re.match(r"^(TASK-[A-Z0-9_-]+)", task_file.name)
    if name_match:
        inferred_task_id = name_match.group(1)

    if not lines or lines[0].strip() != "---":
        return inferred_task_id, None, [f"missing YAML frontmatter: {task_file}"]

    end = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end = idx
            break
    if end is None:
        return inferred_task_id, None, [f"unterminated YAML frontmatter: {task_file}"]

    frontmatter: Dict[str, str] = {}
    for row in lines[1:end]:
        match = re.match(r"^\s*([A-Za-z0-9_-]+)\s*:\s*(.*?)\s*$", row)
        if not match:
            continue
        key = match.group(1).strip().lower()
        value = normalize_scalar(match.group(2))
        frontmatter[key] = value

    task_id = frontmatter.get("task_id") or inferred_task_id
    status = frontmatter.get("status")
    if task_id and not TASK_ID_PATTERN.match(task_id):
        issues.append(f"invalid task_id in task file frontmatter: {task_file} ({task_id})")
    if not task_id:
        issues.append(f"missing task_id in task file: {task_file}")
    if status is None:
        issues.append(f"missing status in task frontmatter: {task_file}")

    return task_id, status.lower() if status else None, issues


def parse_task_files(tasks_dir: Path) -> ParseOutcome:
    outcome = ParseOutcome()
    for task_file in sorted(tasks_dir.glob("TASK-*.md")):
        if task_file.name.upper().startswith("TASK-00-READBEFORE"):
            continue
        task_id, status, issues = parse_task_frontmatter(task_file)
        outcome.issues.extend(issues)
        if task_id and status:
            outcome.data[task_id] = status
    if not outcome.data:
        outcome.issues.append("no task frontmatter statuses found in .ai/tasks")
    return outcome


def parse_task_graph(path: Path) -> ParseOutcome:
    outcome = ParseOutcome()
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        outcome.issues.append(f"cannot read task graph: {path} ({exc})")
        return outcome

    in_nodes = False
    current_task: str | None = None
    current_status: str | None = None

    def finalize_current(line_no: int) -> None:
        nonlocal current_task, current_status
        if current_task is None:
            return
        if not TASK_ID_PATTERN.match(current_task):
            outcome.issues.append(
                f"invalid task id in task-graph at line {line_no}: {current_task}"
            )
        elif current_status is None:
            outcome.issues.append(
                f"missing node status in task-graph for {current_task} (near line {line_no})"
            )
        else:
            outcome.data[current_task] = current_status.lower()
        current_task = None
        current_status = None

    for idx, line in enumerate(lines, start=1):
        stripped = line.strip()
        if not in_nodes:
            if stripped == "nodes:" and line.lstrip() == line:
                in_nodes = True
            continue

        # Reached a new top-level key.
        if line.lstrip() == line and stripped and stripped != "nodes:" and stripped.endswith(":"):
            finalize_current(idx)
            in_nodes = False
            continue

        node_start = re.match(r"^\s*-\s*(?:task_id|id)\s*:\s*(\S+)\s*$", line)
        if node_start:
            finalize_current(idx)
            current_task = normalize_scalar(node_start.group(1))
            current_status = None
            continue

        if current_task is None:
            nested_task_id = re.match(r"^\s*(?:task_id|id)\s*:\s*(\S+)\s*$", line)
            if nested_task_id:
                current_task = normalize_scalar(nested_task_id.group(1))
            continue

        status_match = re.match(r"^\s*status\s*:\s*(.+?)\s*$", line)
        if status_match:
            current_status = normalize_scalar(status_match.group(1))

    finalize_current(len(lines))
    if not outcome.data:
        outcome.issues.append("no task nodes with status found in task-graph.yaml")
    return outcome


def parse_strike_state(path: Path) -> StrikeState:
    state = StrikeState()
    if not path.exists():
        return state

    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        state.issues.append(f"cannot read strike state file: {path} ({exc})")
        return state

    in_tasks = False
    current_task: str | None = None
    current_group: str | None = None

    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        if line.lstrip() == line and stripped == "tasks:":
            in_tasks = True
            current_task = None
            current_group = None
            continue

        if in_tasks and line.lstrip() == line and stripped.endswith(":") and stripped != "tasks:":
            in_tasks = False
            current_task = None
            current_group = None

        if in_tasks:
            task_match = re.match(r"^\s{2}(TASK-[A-Z0-9_-]+)\s*:\s*$", line)
            if task_match:
                current_task = task_match.group(1)
                current_group = None
                continue

            group_match = re.match(r"^\s{4}(strike|security)\s*:\s*$", line)
            if group_match and current_task:
                current_group = group_match.group(1)
                continue

            active_match = re.match(r"^\s{6}active\s*:\s*(\d+)\s*$", line)
            if active_match and current_task and current_group:
                value = int(active_match.group(1))
                if current_group == "strike":
                    state.strike_active[current_task] = value
                else:
                    state.security_active[current_task] = value
                continue

        legacy_match = re.match(r"^\s*(TASK-[A-Z0-9_-]+)\s*:\s*(\d+)\s*$", line)
        if legacy_match and not in_tasks:
            state.legacy[legacy_match.group(1)] = int(legacy_match.group(2))

    if state.legacy and not state.strike_active:
        state.issues.append(
            "legacy strike schema detected (TASK-XX: <count>). migrate to tasks.<TASK>.{strike,security}.{total,active}."
        )
    return state


def require_file(path: Path, label: str, issues: List[str]) -> bool:
    if not path.exists():
        issues.append(f"missing required {label}: {path}")
        return False
    if path.is_dir():
        issues.append(f"expected file for {label}, but found directory: {path}")
        return False
    return True


def run(root: Path) -> int:
    issues: List[str] = []
    warnings: List[str] = []

    progress_file = root / ".ai" / "PROGRESS.md"
    tasks_dir = root / ".ai" / "tasks"
    plan_id_file = root / ".ai" / "runtime" / "rw-active-plan-id.txt"
    strike_file = root / ".ai" / "runtime" / "rw-strike-state.yaml"

    ok = True
    ok &= require_file(progress_file, "PROGRESS.md", issues)
    ok &= require_file(plan_id_file, "rw-active-plan-id.txt", issues)
    if not tasks_dir.exists() or not tasks_dir.is_dir():
        issues.append(f"missing required tasks directory: {tasks_dir}")
        ok = False

    plan_id = ""
    task_graph_file = None
    if ok:
        try:
            plan_id = plan_id_file.read_text(encoding="utf-8").strip().splitlines()[0].strip()
        except (OSError, IndexError) as exc:
            issues.append(f"cannot read plan id from {plan_id_file} ({exc})")
            ok = False
        if plan_id:
            task_graph_file = root / ".ai" / "plans" / plan_id / "task-graph.yaml"
            ok &= require_file(task_graph_file, "task-graph.yaml", issues)
        else:
            issues.append(f"empty plan id in {plan_id_file}")
            ok = False

    if not ok or task_graph_file is None:
        print("STATE_SYNC_CHECK=FAIL")
        print("TARGET_ROOT_INVALID")
        for msg in issues:
            print(f"STATE_SYNC_FINDING {msg}")
        return 3

    progress = parse_progress(progress_file)
    task_files = parse_task_files(tasks_dir)
    task_graph = parse_task_graph(task_graph_file)
    strike_state = parse_strike_state(strike_file)

    issues.extend(progress.issues)
    issues.extend(task_files.issues)
    issues.extend(task_graph.issues)
    warnings.extend(strike_state.issues)

    graph_tasks = sorted(task_graph.data.keys())
    if not graph_tasks:
        issues.append("task-graph has no dispatchable task nodes")

    progress_only = sorted(set(progress.data.keys()) - set(graph_tasks))
    taskfile_only = sorted(set(task_files.data.keys()) - set(graph_tasks))
    if progress_only:
        warnings.append(f"tasks only in PROGRESS (not active graph): {', '.join(progress_only)}")
    if taskfile_only:
        warnings.append(f"tasks only in task files (not active graph): {', '.join(taskfile_only)}")

    for task_id in graph_tasks:
        src_status: Dict[str, str] = {}
        if task_id in progress.data:
            src_status["PROGRESS"] = progress.data[task_id]
        else:
            issues.append(f"missing task in PROGRESS: {task_id}")

        if task_id in task_files.data:
            src_status["TASK_FILE"] = task_files.data[task_id]
        else:
            issues.append(f"missing task frontmatter entry: {task_id}")

        if task_id in task_graph.data:
            src_status["TASK_GRAPH"] = task_graph.data[task_id]

        for source_name, status in src_status.items():
            if status not in ALLOWED_STATUS:
                issues.append(f"invalid status token ({source_name}) for {task_id}: {status}")

        if len(set(src_status.values())) > 1:
            details = ", ".join(f"{name}={value}" for name, value in sorted(src_status.items()))
            issues.append(f"status mismatch for {task_id}: {details}")

        if "completed" in src_status.values():
            strike_active = strike_state.strike_active.get(task_id, 0)
            security_active = strike_state.security_active.get(task_id, 0)
            legacy_value = strike_state.legacy.get(task_id, 0)
            if strike_active > 0:
                issues.append(
                    f"completed task has strike.active > 0 for {task_id}: {strike_active}"
                )
            if security_active > 0:
                issues.append(
                    f"completed task has security.active > 0 for {task_id}: {security_active}"
                )
            if legacy_value > 0 and task_id not in strike_state.strike_active:
                issues.append(
                    f"completed task has legacy strike count > 0 for {task_id}: {legacy_value}"
                )

    if warnings:
        for msg in warnings:
            print(f"STATE_SYNC_WARNING {msg}")

    if issues:
        print("STATE_SYNC_CHECK=FAIL")
        print("RW_SUBAGENT_STATE_SYNC_INVALID")
        for msg in issues:
            print(f"STATE_SYNC_FINDING {msg}")
        return 2

    print("STATE_SYNC_CHECK=PASS")
    print(f"PLAN_ID={plan_id}")
    print(f"SYNC_TASK_COUNT={len(graph_tasks)}")
    print(f"SYNC_WARNING_COUNT={len(warnings)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate rw-loop state sync artifacts.")
    parser.add_argument(
        "--root",
        default=".",
        help="workspace root path (default: current directory)",
    )
    args = parser.parse_args()
    return run(Path(args.root).resolve())


if __name__ == "__main__":
    sys.exit(main())

