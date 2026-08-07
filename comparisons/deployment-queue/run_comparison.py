#!/usr/bin/env python3
"""Run the pinned GodotCascade/GTML deployment-queue comparison."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
COMPARISON_ROOT = ROOT / "comparisons" / "deployment-queue"
GTML_URL = "https://github.com/Niekvdm/godot-plugins-gtml.git"
GTML_COMMIT = "7ddabfe3cffa69d7c8abd12b8d69bf80de49e59f"
GTML_VERSION = "0.8.4"
CASCADE_SCENE = "res://comparisons/deployment-queue/godot-cascade/deployment_queue.tscn"
GTML_SCENE = "res://comparison/deployment_queue.tscn"
DEFAULT_RESULTS = ROOT / "docs" / "artifacts" / "deployment-queue-results.json"
DEFAULT_CASCADE_CAPTURE = ROOT / "docs" / "artifacts" / "deployment-queue-godotcascade.png"
DEFAULT_GTML_CAPTURE = ROOT / "docs" / "artifacts" / "deployment-queue-gtml.png"


def run(
    command: list[str],
    *,
    cwd: Path,
    timeout: int = 240,
    require_result: bool = False,
) -> tuple[subprocess.CompletedProcess[str], float, dict[str, Any] | None]:
    started = time.perf_counter()
    completed = subprocess.run(
        command,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
        encoding="utf-8",
        errors="replace",
    )
    elapsed_ms = (time.perf_counter() - started) * 1000.0
    combined = completed.stdout + completed.stderr
    result = None
    for line in completed.stdout.splitlines():
        if line.startswith("COMPARISON_JSON="):
            result = json.loads(line.removeprefix("COMPARISON_JSON="))
    if completed.returncode != 0:
        raise RuntimeError(
            f"Command exited {completed.returncode}: {' '.join(command)}\n{combined}"
        )
    if require_result and result is None:
        raise RuntimeError(f"Command produced no COMPARISON_JSON result:\n{combined}")
    if "SCRIPT ERROR:" in combined:
        raise RuntimeError(f"Godot reported a script error:\n{combined}")
    return completed, elapsed_ms, result


def prepare_gtml(target: Path, source: Path | None) -> str:
    if source is None:
        run(
            ["git", "clone", "--quiet", GTML_URL, str(target)],
            cwd=target.parent,
            timeout=180,
        )
    else:
        run(
            ["git", "clone", "--quiet", "--no-hardlinks", str(source.resolve()), str(target)],
            cwd=target.parent,
            timeout=180,
        )
    run(["git", "checkout", "--quiet", GTML_COMMIT], cwd=target)
    commit = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=target, text=True, encoding="utf-8"
    ).strip()
    if commit != GTML_COMMIT:
        raise RuntimeError(f"Expected GTML {GTML_COMMIT}, got {commit}")
    destination = target / "comparison"
    destination.mkdir()
    for path in (COMPARISON_ROOT / "gtml").iterdir():
        if path.is_file():
            shutil.copy2(path, destination / path.name)
    shutil.copy2(COMPARISON_ROOT / "fixture.json", destination / "fixture.json")
    return commit


def diagnostic_counts(completed: subprocess.CompletedProcess[str]) -> dict[str, int]:
    combined = completed.stdout + completed.stderr
    return {
        "warnings": len(re.findall(r"(?m)^WARNING:", combined)),
        "errors": len(re.findall(r"(?m)^ERROR:", combined)),
        "script_errors": len(re.findall(r"(?m)^SCRIPT ERROR:", combined)),
    }


def source_metrics() -> dict[str, Any]:
    definitions = {
        "godot-cascade": [
            COMPARISON_ROOT / "godot-cascade" / "interface.gxml",
            COMPARISON_ROOT / "godot-cascade" / "style.gcss",
            COMPARISON_ROOT / "godot-cascade" / "deployment_state.gd",
            COMPARISON_ROOT / "godot-cascade" / "deployment_queue.gd",
        ],
        "gtml": [
            COMPARISON_ROOT / "gtml" / "index.html",
            COMPARISON_ROOT / "gtml" / "style.css",
            COMPARISON_ROOT / "gtml" / "deployment_queue.gd",
        ],
    }
    result: dict[str, Any] = {}
    for implementation, paths in definitions.items():
        files: dict[str, int] = {}
        total = 0
        for path in paths:
            count = sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line.strip())
            files[str(path.relative_to(COMPARISON_ROOT)).replace("\\", "/")] = count
            total += count
        result[implementation] = {"nonblank_physical_lines": total, "files": files}
    result["shared_fixture_nonblank_physical_lines"] = sum(
        1
        for line in (COMPARISON_ROOT / "fixture.json")
        .read_text(encoding="utf-8")
        .splitlines()
        if line.strip()
    )
    return result


def capture(
    godot: Path,
    project: Path,
    script: str,
    output: Path,
) -> dict[str, Any]:
    output.parent.mkdir(parents=True, exist_ok=True)
    completed, elapsed_ms, _ = run(
        [
            str(godot),
            "--path",
            str(project),
            "--rendering-method",
            "gl_compatibility",
            "--audio-driver",
            "Dummy",
            "--disable-vsync",
            "--resolution",
            "1200x760",
            "--script",
            script,
            "--",
            f"--output={output.resolve()}",
        ],
        cwd=project,
    )
    if not output.is_file() or output.stat().st_size == 0:
        raise RuntimeError(f"Capture did not create {output}")
    return {
        "path": str(output.relative_to(ROOT)).replace("\\", "/"),
        "bytes": output.stat().st_size,
        "process_total_ms": round(elapsed_ms, 3),
        "diagnostics": diagnostic_counts(completed),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True, help="Official Godot console executable")
    parser.add_argument("--gtml-source", type=Path, help="Optional existing GTML checkout used as clone source")
    parser.add_argument("--output", type=Path, default=DEFAULT_RESULTS)
    parser.add_argument("--capture", action="store_true")
    args = parser.parse_args()

    godot = args.godot.resolve()
    if not godot.is_file():
        raise SystemExit(f"Godot executable not found: {godot}")
    version_completed, _, _ = run([str(godot), "--version"], cwd=ROOT)
    engine_version = version_completed.stdout.strip()

    with tempfile.TemporaryDirectory(prefix="godot-cascade-gtml-comparison-") as directory:
        temp_root = Path(directory)
        gtml_root = temp_root / "gtml"
        commit = prepare_gtml(gtml_root, args.gtml_source)

        import_completed, import_elapsed, _ = run(
            [str(godot), "--headless", "--editor", "--path", str(gtml_root), "--quit-after", "8"],
            cwd=gtml_root,
        )
        cascade_completed, cascade_elapsed, cascade_result = run(
            [
                str(godot),
                "--headless",
                "--path",
                str(ROOT),
                CASCADE_SCENE,
                "--",
                "--comparison-verify",
            ],
            cwd=ROOT,
            require_result=True,
        )
        gtml_completed, gtml_elapsed, gtml_result = run(
            [
                str(godot),
                "--headless",
                "--path",
                str(gtml_root),
                GTML_SCENE,
                "--",
                "--comparison-verify",
            ],
            cwd=gtml_root,
            require_result=True,
        )
        assert cascade_result is not None and gtml_result is not None
        cascade_result["process_total_ms"] = round(cascade_elapsed, 3)
        cascade_result["process_diagnostics"] = diagnostic_counts(cascade_completed)
        gtml_result["process_total_ms"] = round(gtml_elapsed, 3)
        gtml_result["process_diagnostics"] = diagnostic_counts(gtml_completed)

        payload: dict[str, Any] = {
            "schema": 1,
            "engine": {
                "version_command_output": engine_version,
                "executable_name": godot.name,
            },
            "gtml": {
                "upstream": GTML_URL,
                "commit": commit,
                "plugin_version": GTML_VERSION,
                "project_feature": "4.6",
                "import_process_total_ms": round(import_elapsed, 3),
                "import_diagnostics": diagnostic_counts(import_completed),
            },
            "methodology": {
                "viewport": [1200, 760],
                "cold_build_samples": 10,
                "scalar_update_batch_operations": 100,
                "keyed_reorder_batch_operations": 40,
                "timing_unit": "milliseconds",
                "timing_scope": "Synchronous parse/build or the explicitly labelled operation batch; never per-frame.",
                "source_metric": "Nonblank physical lines in runtime UI source; scenes, capture scripts, invalid fixtures, runner, and shared JSON fixture excluded.",
            },
            "source_metrics": source_metrics(),
            "results": {
                "godot-cascade": cascade_result,
                "gtml": gtml_result,
            },
        }
        if args.capture:
            payload["captures"] = {
                "godot-cascade": capture(
                    godot,
                    ROOT,
                    "res://comparisons/deployment-queue/godot-cascade/capture.gd",
                    DEFAULT_CASCADE_CAPTURE,
                ),
                "gtml": capture(
                    godot,
                    gtml_root,
                    "res://comparison/capture.gd",
                    DEFAULT_GTML_CAPTURE,
                ),
            }

    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="\n") as output_file:
        output_file.write(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print(f"Wrote {output}")
    print(json.dumps(payload["results"], indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
