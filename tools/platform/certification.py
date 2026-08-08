#!/usr/bin/env python3
"""Launch the manual fixture and create/validate platform-certification records."""

from __future__ import annotations

import argparse
import datetime as dt
import platform as host_platform
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ARTIFACT_ROOT = ROOT / "docs" / "artifacts"
SCENE = "res://examples/platform_certification/platform_certification.tscn"
PLATFORMS = ("windows", "linux", "macos", "android", "ios")
ROWS = (
    "Clipboard",
    "IME",
    "Active IME reload",
    "Bidirectional text",
    "Touch selection",
    "Virtual keyboard",
    "Screen reader",
    "Keyboard/controller",
    "Reload preservation",
)
DESKTOP_REQUIRED = (
    "Clipboard",
    "IME",
    "Active IME reload",
    "Bidirectional text",
    "Screen reader",
    "Keyboard/controller",
    "Reload preservation",
)
FINAL_RESULTS = {"Pass", "Fail", "Unavailable"}
PLACEHOLDERS = {"", "todo", "not recorded", "not run", "unknown"}
CERTIFICATION_RECORD_PATH = re.compile(
    r"^docs/artifacts/platform-certification-\d{4}-\d{2}-\d{2}-(?:windows|linux|macos|android|ios)\.md$"
)


def run_command(command: list[str]) -> tuple[bool, str]:
    try:
        completed = subprocess.run(
            command,
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=20,
            check=True,
        )
    except (OSError, subprocess.SubprocessError):
        return False, ""
    # Successful command diagnostics are not command data. In particular, Git
    # may emit advisory text on stderr while a clean porcelain status has an
    # intentionally empty stdout stream.
    return True, completed.stdout.strip()


def command_output(command: list[str]) -> str:
    succeeded, output = run_command(command)
    return output if succeeded and output else "TODO"


def resolve_closure_target_commit(explicit_target: str = "") -> str:
    """Resolve the closure target without making an evidence commit self-certify.

    Manual records must name the clean source commit that was actually tested.
    The completed records are necessarily committed afterward, so a default of
    literal HEAD would otherwise look for records certifying their own evidence
    commit. Peel a conservative chain of record-only commits; any mixed,
    deleted, renamed, merge, or uninspectable commit remains the target itself.
    An explicit target is always authoritative.
    """
    explicit_target = explicit_target.strip()
    if explicit_target:
        return explicit_target
    succeeded, head = run_command(["git", "rev-parse", "HEAD"])
    if not succeeded or not head:
        return "TODO"
    candidate = head
    peeled = 0
    while True:
        parents_succeeded, parents_output = run_command(
            ["git", "rev-list", "--parents", "-n", "1", candidate]
        )
        if not parents_succeeded:
            break
        commit_and_parents = parents_output.split()
        if len(commit_and_parents) != 2:
            break
        changes_succeeded, changes_output = run_command(
            ["git", "diff-tree", "--no-commit-id", "--name-status", "-r", candidate]
        )
        if not changes_succeeded or not _is_certification_record_only_change(changes_output):
            break
        candidate = commit_and_parents[1]
        peeled += 1
    if peeled:
        print(
            f"Default closure target: {candidate} "
            f"(peeled {peeled} certification-record-only HEAD commit{'s' if peeled != 1 else ''})."
        )
    return candidate


def _is_certification_record_only_change(name_status: str) -> bool:
    lines = [line for line in name_status.splitlines() if line.strip()]
    if not lines:
        return False
    for line in lines:
        parts = line.split("\t")
        if len(parts) != 2 or parts[0] not in {"A", "M"}:
            return False
        if CERTIFICATION_RECORD_PATH.fullmatch(parts[1].replace("\\", "/")) is None:
            return False
    return True


def create_record(args: argparse.Namespace) -> int:
    status_succeeded, status = run_command(
        ["git", "status", "--porcelain", "--untracked-files=normal"]
    )
    if not status_succeeded:
        raise SystemExit("Unable to verify a clean Git worktree; certification provenance would be ambiguous")
    if status:
        raise SystemExit("Refusing to create certification evidence from a dirty Git worktree; commit or stash changes first")
    output = args.output or ARTIFACT_ROOT / f"platform-certification-{dt.date.today().isoformat()}-{args.platform}.md"
    output = output.resolve()
    if output.exists() and not args.force:
        raise SystemExit(f"Refusing to overwrite {output}; pass --force intentionally")
    godot_build = command_output([str(args.godot.resolve()), "--version"]) if args.godot else "TODO"
    commit = command_output(["git", "rev-parse", "HEAD"])
    os_device = args.device or host_platform.platform()
    rows = "\n".join(f"| {name} | Not run | TODO |" for name in ROWS)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        f"""# Platform certification — {args.platform}

- Platform: {args.platform}
- OS/device: {os_device}
- Godot build: {godot_build}
- GodotCascade commit: {commit}
- Rendering backend: {args.renderer or 'TODO'}
- Keyboard/IME: {args.ime or 'TODO'}
- Clipboard environment: {args.clipboard or 'TODO'}
- Touch/virtual keyboard: {args.touch or 'TODO'}
- Screen reader: {args.screen_reader or 'TODO'}

| Check | Result | Notes/evidence |
| --- | --- | --- |
{rows}
""",
        encoding="utf-8",
        newline="\n",
    )
    print(f"Created incomplete record: {output}")
    print("Fill every row with Pass, Fail, or Unavailable plus concrete evidence, then run validate.")
    return 0


def parse_record(path: Path) -> tuple[dict[str, str], dict[str, tuple[str, str]], list[str]]:
    source = path.read_text(encoding="utf-8")
    metadata: dict[str, str] = {}
    for match in re.finditer(r"(?m)^- ([^:]+):\s*(.*)$", source):
        metadata[match.group(1).strip()] = match.group(2).strip()
    rows: dict[str, tuple[str, str]] = {}
    for line in source.splitlines():
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) == 3 and cells[0] in ROWS:
            rows[cells[0]] = (cells[1], cells[2])
    errors: list[str] = []
    required_metadata = (
        "Platform",
        "OS/device",
        "Godot build",
        "GodotCascade commit",
        "Rendering backend",
        "Keyboard/IME",
        "Clipboard environment",
        "Touch/virtual keyboard",
        "Screen reader",
    )
    for name in required_metadata:
        value = metadata.get(name, "")
        if value.strip().lower() in PLACEHOLDERS:
            errors.append(f"metadata '{name}' is incomplete")
    if metadata.get("Platform", "").lower() not in PLATFORMS:
        errors.append(f"Platform must be one of {', '.join(PLATFORMS)}")
    for name in ROWS:
        if name not in rows:
            errors.append(f"missing result row '{name}'")
            continue
        result, evidence = rows[name]
        if result not in FINAL_RESULTS:
            errors.append(f"'{name}' result must be Pass, Fail, or Unavailable")
        if evidence.strip().lower() in PLACEHOLDERS:
            errors.append(f"'{name}' requires notes/evidence, including when unavailable")
    return metadata, rows, errors


def validate_records(paths: list[Path], closure: bool, target_commit: str = "") -> int:
    if not paths:
        print("No certification records found.", file=sys.stderr)
        return 1
    parsed: list[tuple[Path, dict[str, str], dict[str, tuple[str, str]]]] = []
    failed = False
    for path in paths:
        if not path.is_file():
            failed = True
            print(f"{path}: record does not exist")
            continue
        metadata, rows, errors = parse_record(path)
        parsed.append((path, metadata, rows))
        if errors:
            failed = True
            print(f"{path}:")
            for error in errors:
                print(f"  - {error}")
        else:
            print(f"Validated record: {path}")
    if closure:
        target_commit = resolve_closure_target_commit(target_commit)
        closure_errors = certification_closure_errors(parsed, target_commit)
        if closure_errors:
            failed = True
            print("Certification closure remains open:")
            for error in closure_errors:
                print(f"  - {error}")
        else:
            print("Manual platform-certification closure is complete.")
    return 1 if failed else 0


def certification_closure_errors(
    records: list[tuple[Path, dict[str, str], dict[str, tuple[str, str]]]],
    target_commit: str,
) -> list[str]:
    errors: list[str] = []
    matching = [record for record in records if commits_match(record[1].get("GodotCascade commit", ""), target_commit)]
    if not matching:
        return [f"no records match target commit {target_commit}"]
    # Preserve historical records, but let the lexically latest dated artifact
    # supersede earlier evidence for the same platform and target commit.
    by_platform: dict[str, tuple[Path, dict[str, tuple[str, str]]]] = {}
    for path, metadata, rows in sorted(matching, key=lambda record: record[0].name):
        by_platform[metadata.get("Platform", "").lower()] = (path, rows)
    for platform_name in ("windows", "linux", "macos"):
        platform_record = by_platform.get(platform_name)
        if platform_record is None:
            errors.append(f"no {platform_name} record")
            continue
        rows = platform_record[1]
        for check in DESKTOP_REQUIRED:
            if rows.get(check, ("", ""))[0] != "Pass":
                errors.append(f"{platform_name}: '{check}' has no passing evidence")
    for check in ("Touch selection", "Virtual keyboard"):
        if not any(rows.get(check, ("", ""))[0] == "Pass" for _path, rows in by_platform.values()):
            errors.append(f"'{check}' has no passing evidence on any applicable device")
    if any(result == "Fail" for _path, rows in by_platform.values() for result, _evidence in rows.values()):
        errors.append("one or more current target-commit checks fail")
    return errors


def commits_match(recorded: str, target: str) -> bool:
    recorded = recorded.strip().lower()
    target = target.strip().lower()
    if len(recorded) < 7 or len(target) < 7:
        return False
    return recorded == target or recorded.startswith(target) or target.startswith(recorded)


def launch(args: argparse.Namespace) -> int:
    godot = args.godot.resolve()
    if not godot.is_file():
        raise SystemExit(f"Godot executable not found: {godot}")
    return subprocess.run(
        [str(godot), "--path", str(ROOT), SCENE],
        cwd=ROOT,
        check=False,
    ).returncode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    launch_parser = subparsers.add_parser("launch", help="launch the side-by-side native fixture")
    launch_parser.add_argument("--godot", type=Path, required=True)
    launch_parser.set_defaults(handler=launch)

    create_parser = subparsers.add_parser("create", help="create an incomplete evidence record")
    create_parser.add_argument("--platform", choices=PLATFORMS, required=True)
    create_parser.add_argument("--godot", type=Path)
    create_parser.add_argument("--output", type=Path)
    create_parser.add_argument("--device")
    create_parser.add_argument("--renderer")
    create_parser.add_argument("--ime")
    create_parser.add_argument("--clipboard")
    create_parser.add_argument("--touch")
    create_parser.add_argument("--screen-reader")
    create_parser.add_argument("--force", action="store_true")
    create_parser.set_defaults(handler=create_record)

    validate_parser = subparsers.add_parser("validate", help="validate records without inventing passes")
    validate_parser.add_argument("paths", nargs="*", type=Path)
    validate_parser.add_argument("--all", action="store_true", help="validate every checked-in record")
    validate_parser.add_argument("--closure", action="store_true", help="also enforce the cross-platform closure gate")
    validate_parser.add_argument(
        "--target-commit",
        help="commit the closure records must certify (defaults to HEAD, after peeling record-only evidence commits)",
    )
    validate_parser.set_defaults(handler=lambda args: validate_records(
        sorted(ARTIFACT_ROOT.glob("platform-certification-*.md")) if args.all else [path.resolve() for path in args.paths],
        args.closure,
        args.target_commit or "",
    ))

    args = parser.parse_args()
    return args.handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
