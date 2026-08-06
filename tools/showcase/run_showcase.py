#!/usr/bin/env python3
"""Launch the native manifest-driven GodotCascade showcase application."""

from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", help="Godot 4.7 executable; defaults to godot on PATH")
    parser.add_argument("--page", help="Initial manifest page id")
    args = parser.parse_args()
    godot = args.godot or shutil.which("godot")
    if not godot:
        parser.error("Godot was not found; pass --godot path/to/godot")
    command = [godot, "--path", str(ROOT)]
    if args.page:
        command.extend(["--", f"--showcase-page={args.page}"])
    return subprocess.run(command, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
