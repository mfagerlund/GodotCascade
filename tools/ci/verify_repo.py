#!/usr/bin/env python3
"""Run fast, dependency-free repository integrity checks."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[2]
TEXT_SUFFIXES = {
    ".cs",
    ".csproj",
    ".cfg",
    ".gcss",
    ".gd",
    ".godot",
    ".gxml",
    ".html",
    ".json",
    ".md",
    ".ps1",
    ".py",
    ".tscn",
    ".tres",
    ".yaml",
    ".yml",
}
MARKDOWN_LINK = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")


def tracked_files() -> list[Path]:
    output = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
    ).decode("utf-8")
    return [ROOT / item for item in output.split("\0") if item]


def check_text_format(files: list[Path], failures: list[str]) -> None:
    for path in files:
        if not path.is_file():
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        data = path.read_bytes()
        relative = path.relative_to(ROOT)
        if data.startswith(b"\xef\xbb\xbf"):
            failures.append(f"{relative}: UTF-8 BOM is not allowed")
        if b"\r" in data:
            failures.append(f"{relative}: use LF line endings")
        text = data.decode("utf-8")
        for line_number, line in enumerate(text.splitlines(), start=1):
            if line.rstrip(" \t") != line:
                failures.append(f"{relative}:{line_number}: trailing whitespace")
        if data and not data.endswith(b"\n"):
            failures.append(f"{relative}: missing final newline")


def check_json(files: list[Path], failures: list[str]) -> None:
    for path in files:
        if not path.is_file():
            continue
        if path.suffix.lower() != ".json":
            continue
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            failures.append(f"{path.relative_to(ROOT)}: invalid JSON: {error}")


def check_markdown_links(files: list[Path], failures: list[str]) -> None:
    for path in files:
        if not path.is_file():
            continue
        if path.suffix.lower() != ".md":
            continue
        text = path.read_text(encoding="utf-8")
        for match in MARKDOWN_LINK.finditer(text):
            raw_target = match.group(1).strip()
            if raw_target.startswith("<") and raw_target.endswith(">"):
                raw_target = raw_target[1:-1]
            target = raw_target.split(maxsplit=1)[0]
            if not target or target.startswith(("#", "/", "http://", "https://", "mailto:")):
                continue
            file_part = unquote(target.split("#", 1)[0].split("?", 1)[0])
            if file_part and not (path.parent / file_part).exists():
                line = text.count("\n", 0, match.start()) + 1
                failures.append(
                    f"{path.relative_to(ROOT)}:{line}: missing link target {file_part}"
                )


def main() -> int:
    files = tracked_files()
    failures: list[str] = []
    check_text_format(files, failures)
    check_json(files, failures)
    check_markdown_links(files, failures)

    if failures:
        print("Repository verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print(
        f"Repository verification passed for {len(files)} repository files "
        "(formatting, JSON, and relative links)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
