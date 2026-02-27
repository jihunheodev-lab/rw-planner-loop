#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import shlex
import shutil
import sys
from pathlib import Path

SUPPORTED_REASONING_EFFORT = {"minimal", "low", "medium", "high"}
SHELL_BUILTINS = {
    "cd",
    "echo",
    "set",
    "export",
    "if",
    "then",
    "fi",
    "for",
    "do",
    "done",
    "while",
    "case",
    "esac",
}


def iter_task_docs(root: Path) -> list[Path]:
    files: list[Path] = []
    task_dir = root / ".ai" / "tasks"
    if task_dir.exists():
        files.extend(sorted(task_dir.glob("TASK-*.md")))
    feature_dir = root / ".ai" / "features"
    if feature_dir.exists():
        files.extend(sorted(feature_dir.glob("*.md")))
    return files


def parse_task00_preflight_requirements(root: Path) -> tuple[set[str], set[str]]:
    envs: set[str] = set()
    commands: set[str] = set()
    task00 = root / ".ai" / "tasks" / "TASK-00-READBEFORE.md"
    if not task00.exists():
        return envs, commands

    try:
        lines = task00.read_text(encoding="utf-8").splitlines()
    except OSError:
        return envs, commands

    in_section = False
    mode: str | None = None

    for raw in lines:
        stripped = raw.strip()
        lower = stripped.lower()

        if stripped.startswith("## "):
            if lower == "## environment preflight requirements":
                in_section = True
                mode = None
                continue
            if in_section:
                break

        if not in_section:
            continue

        if stripped.startswith("### "):
            if "required commands" in lower:
                mode = "cmd"
            elif "required environment variables" in lower:
                mode = "env"
            else:
                mode = None
            continue

        if not stripped.startswith(("-", "*")):
            continue

        item = stripped[1:].strip().strip("`")
        if not item:
            continue

        if mode == "env":
            match = re.match(r"^([A-Z][A-Z0-9_]*)$", item)
            if match:
                envs.add(match.group(1))
            continue

        if mode == "cmd":
            token = normalize_command_token(item)
            if token:
                commands.add(token)

    return envs, commands


def extract_code_fences(text: str) -> list[str]:
    blocks: list[str] = []
    in_fence = False
    current: list[str] = []

    for line in text.splitlines():
        if line.strip().startswith("```"):
            if in_fence:
                blocks.append("\n".join(current))
                current = []
                in_fence = False
            else:
                in_fence = True
            continue
        if in_fence:
            current.append(line)

    return blocks


def normalize_command_token(line: str) -> str | None:
    value = line.strip()
    if not value or value.startswith("#"):
        return None

    # Skip common environment variable assignments in shells.
    if re.match(r"^\$env:[A-Za-z_][A-Za-z0-9_]*\s*=", value):
        return None
    if re.match(r"^[A-Za-z_][A-Za-z0-9_]*\s*=", value):
        return None

    value = value.lstrip("$ ").strip()
    if not value:
        return None

    try:
        parts = shlex.split(value, posix=False)
    except ValueError:
        parts = value.split()
    if not parts:
        return None

    token = parts[0].strip()
    if token in {"|", "&&", "||"}:
        return None
    return token


def extract_requirements(files: list[Path]) -> tuple[set[str], set[str]]:
    required_envs: set[str] = set()
    required_commands: set[str] = set()

    env_patterns = [
        re.compile(r"\$env:([A-Z][A-Z0-9_]*)"),
        re.compile(r"\$\{([A-Z][A-Z0-9_]*)\}"),
        re.compile(r"(?<![A-Za-z0-9_])\$([A-Z][A-Z0-9_]*)"),
        re.compile(r"%([A-Z][A-Z0-9_]*)%"),
    ]

    for path in files:
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue

        for pattern in env_patterns:
            for match in pattern.finditer(text):
                required_envs.add(match.group(1))

        for block in extract_code_fences(text):
            for raw in block.splitlines():
                token = normalize_command_token(raw)
                if not token:
                    continue
                required_commands.add(token)

    return required_envs, required_commands


def command_exists(root: Path, token: str) -> bool:
    if token in SHELL_BUILTINS:
        return True
    if token.lower().endswith((".ps1", ".sh", ".cmd", ".bat", ".py")):
        path = (root / token).resolve()
        return path.exists()
    if token.startswith("./") or token.startswith(".\\"):
        path = (root / token).resolve()
        return path.exists()
    return shutil.which(token) is not None


def check_codex_config(findings: list[str]) -> None:
    config = Path.home() / ".codex" / "config.toml"
    if not config.exists():
        return

    try:
        text = config.read_text(encoding="utf-8")
    except OSError as exc:
        findings.append(f"ENV_PREFLIGHT_FINDING CODEX_CONFIG_UNREADABLE: {exc}")
        return

    for match in re.finditer(
        r'^\s*model_reasoning_effort\s*=\s*["\']([^"\']+)["\']\s*$',
        text,
        flags=re.MULTILINE,
    ):
        value = match.group(1).strip()
        if value not in SUPPORTED_REASONING_EFFORT:
            findings.append(
                "ENV_PREFLIGHT_FINDING CODEX_CONFIG_INVALID model_reasoning_effort="
                + value
                + " expected=minimal|low|medium|high"
            )


def run(root: Path) -> int:
    files = iter_task_docs(root)
    required_envs, required_commands = extract_requirements(files)
    section_envs, section_commands = parse_task00_preflight_requirements(root)
    required_envs.update(section_envs)
    required_commands.update(section_commands)

    findings: list[str] = []

    for env_name in sorted(required_envs):
        if not os.environ.get(env_name, "").strip():
            findings.append(f"ENV_PREFLIGHT_FINDING MISSING_ENV {env_name}")

    for token in sorted(required_commands):
        if not command_exists(root, token):
            findings.append(f"ENV_PREFLIGHT_FINDING MISSING_COMMAND {token}")

    if "codex" in required_commands:
        check_codex_config(findings)

    if findings:
        print("ENV_PREFLIGHT=FAIL")
        for finding in findings:
            print(finding)
        return 1

    print("ENV_PREFLIGHT=PASS")
    if required_envs:
        print("ENV_PREFLIGHT_REQUIRED_ENVS=" + ",".join(sorted(required_envs)))
    if required_commands:
        print("ENV_PREFLIGHT_REQUIRED_COMMANDS=" + ",".join(sorted(required_commands)))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate task-declared runtime preconditions.")
    parser.add_argument("--root", default=".", help="workspace root path")
    args = parser.parse_args()
    return run(Path(args.root).resolve())


if __name__ == "__main__":
    sys.exit(main())
