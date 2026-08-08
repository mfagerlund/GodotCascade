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
MARKDOWN_IMAGE = re.compile(r"!\[[^\]]*\]\(([^)]+)\)")


def tracked_files() -> list[Path]:
    output = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
    ).decode("utf-8")
    return [ROOT / item for item in output.split("\0") if item]


def check_text_format(files: list[Path], failures: list[str]) -> None:
    for path in files:
        if not path.is_file():
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES and path.name != "LICENSE":
            continue
        data = path.read_bytes()
        relative = path.relative_to(ROOT)
        if data.startswith(b"\xef\xbb\xbf"):
            failures.append(f"{relative}: UTF-8 BOM is not allowed")
        if b"\r" in data:
            failures.append(f"{relative}: use LF line endings")
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError as error:
            failures.append(f"{relative}: invalid UTF-8: {error}")
            continue
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
    anchor_cache: dict[Path, set[str]] = {}
    for path in files:
        if not path.is_file():
            continue
        if path.suffix.lower() != ".md":
            continue
        text = path.read_text(encoding="utf-8")
        matches = [*MARKDOWN_LINK.finditer(text), *MARKDOWN_IMAGE.finditer(text)]
        for match in matches:
            raw_target = match.group(1).strip()
            if raw_target.startswith("<") and raw_target.endswith(">"):
                raw_target = raw_target[1:-1]
            target = raw_target.split(maxsplit=1)[0]
            if not target or target.startswith(("/", "http://", "https://", "mailto:")):
                continue
            file_part = unquote(target.split("#", 1)[0].split("?", 1)[0])
            target_path = path if not file_part else (path.parent / file_part).resolve()
            if file_part and not target_path.exists():
                line = text.count("\n", 0, match.start()) + 1
                failures.append(
                    f"{path.relative_to(ROOT)}:{line}: missing link target {file_part}"
                )
                continue
            fragment = unquote(target.split("#", 1)[1]) if "#" in target else ""
            if fragment and target_path.suffix.lower() == ".md":
                anchors = anchor_cache.setdefault(target_path, markdown_anchors(target_path))
                if fragment not in anchors:
                    line = text.count("\n", 0, match.start()) + 1
                    target_display = (
                        target_path.relative_to(ROOT)
                        if target_path.is_relative_to(ROOT)
                        else target_path
                    )
                    failures.append(
                        f"{path.relative_to(ROOT)}:{line}: missing Markdown anchor #{fragment} in {target_display}"
                    )


def markdown_anchors(path: Path) -> set[str]:
    anchors: set[str] = set()
    counts: dict[str, int] = {}
    in_fence = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        explicit = re.search(r'<a\s+(?:name|id)=["\']([^"\']+)["\']', line, re.IGNORECASE)
        if explicit:
            anchors.add(explicit.group(1))
        heading = re.match(r"^#{1,6}\s+(.+?)\s*#*\s*$", line)
        if not heading:
            continue
        label = re.sub(r"<[^>]+>", "", heading.group(1))
        # GitHub drops Markdown formatting punctuation but preserves underscores
        # that are literal code/name content inside headings.
        label = re.sub(r"[`*~]", "", label).lower().strip()
        slug = re.sub(r"[^\w\s-]", "", label, flags=re.UNICODE)
        slug = re.sub(r"\s", "-", slug).strip("-")
        duplicate = counts.get(slug, 0)
        counts[slug] = duplicate + 1
        anchors.add(slug if duplicate == 0 else f"{slug}-{duplicate}")
    return anchors


def check_license_copies(failures: list[str]) -> None:
    root_license = ROOT / "LICENSE"
    addon_license = ROOT / "addons" / "godot_cascade" / "LICENSE"
    if not root_license.is_file():
        failures.append("LICENSE: required repository license is missing")
        return
    if not addon_license.is_file():
        failures.append("addons/godot_cascade/LICENSE: packaged license is missing")
        return
    if root_license.read_bytes() != addon_license.read_bytes():
        failures.append("LICENSE and addons/godot_cascade/LICENSE must match exactly")


def check_deployment_comparison(failures: list[str]) -> None:
    result_path = ROOT / "docs" / "artifacts" / "deployment-queue-results.json"
    report_path = ROOT / "docs" / "artifacts" / "godotcascade-vs-gtml-deployment-queue.md"
    try:
        payload = json.loads(result_path.read_text(encoding="utf-8"))
        report = report_path.read_text(encoding="utf-8")
        cascade = payload["results"]["godot-cascade"]
        gtml = payload["results"]["gtml"]
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        failures.append(f"deployment comparison artifacts are invalid: {error}")
        return
    if not cascade.get("functional", {}).get("passed", False):
        failures.append("deployment comparison: GodotCascade functional result is not passing")
    if not gtml.get("functional", {}).get("passed", False):
        failures.append("deployment comparison: GTML functional result is not passing")
    try:
        cascade_reorder = cascade["timings"]["keyed_reorder_batch"]
        measurements = (
            cascade["timings"]["cold_build_median_ms"],
            gtml["timings"]["cold_build_median_ms"],
            cascade["timings"]["scalar_update_batch"]["total_ms"],
            gtml["timings"]["scalar_update_batch"]["total_ms"],
            cascade["timings"]["scalar_coalesced_batch"]["total_ms"],
            cascade_reorder["total_ms"],
            gtml["timings"]["keyed_reorder_batch"]["total_ms"],
        )
    except (KeyError, TypeError) as error:
        failures.append(f"deployment comparison measurements are invalid: {error}")
        return
    if not cascade_reorder.get("zero_candidate_retained", False):
        failures.append("deployment comparison: Cascade keyed reorder did not prove its retained zero-candidate path")
    if int(cascade_reorder.get("reconcile_stats", {}).get("repeat_candidates", -1)) != 0:
        failures.append("deployment comparison: Cascade keyed reorder unexpectedly built a Repeat candidate")
    for measurement in measurements:
        rendered = f"{float(measurement):,.3f}"
        if rendered not in report:
            failures.append(f"deployment comparison report is missing current measurement {rendered} ms")
    for capture in payload.get("captures", {}).values():
        capture_path = ROOT / str(capture.get("path", ""))
        if not capture_path.is_file() or capture_path.stat().st_size != int(capture.get("bytes", -1)):
            failures.append(f"deployment comparison capture does not match JSON metadata: {capture_path}")


def main() -> int:
    files = tracked_files()
    failures: list[str] = []
    check_text_format(files, failures)
    check_json(files, failures)
    check_markdown_links(files, failures)
    check_license_copies(failures)
    check_deployment_comparison(failures)

    if failures:
        print("Repository verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print(
        f"Repository verification passed for {len(files)} repository files "
        "(formatting, JSON, relative links/images, license copies, and comparison artifacts)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
