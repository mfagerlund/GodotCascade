#!/usr/bin/env python3
"""Create a deterministic addon-only GodotCascade release archive."""

from __future__ import annotations

import argparse
import hashlib
import re
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON_ROOT = ROOT / "addons" / "godot_cascade"
PLUGIN_CONFIG = ADDON_ROOT / "plugin.cfg"
VERSION_PATTERN = re.compile(r'^version="([^"]+)"$', re.MULTILINE)
FIXED_TIMESTAMP = (2026, 1, 1, 0, 0, 0)
EXCLUDED_SUFFIXES = {".import", ".pyc"}


def plugin_version() -> str:
    match = VERSION_PATTERN.search(PLUGIN_CONFIG.read_text(encoding="utf-8"))
    if match is None:
        raise RuntimeError("addons/godot_cascade/plugin.cfg has no version")
    return match.group(1)


def package(output_dir: Path) -> tuple[Path, Path]:
    version = plugin_version()
    output_dir.mkdir(parents=True, exist_ok=True)
    archive = output_dir / f"godot-cascade-{version}.zip"
    checksum = archive.with_suffix(archive.suffix + ".sha256")
    candidates = sorted(path for path in ADDON_ROOT.rglob("*") if path.is_file())
    included = [
        path
        for path in candidates
        if path.suffix.lower() not in EXCLUDED_SUFFIXES
        and "__pycache__" not in path.parts
    ]
    if not included or PLUGIN_CONFIG not in included:
        raise RuntimeError("addon package would be empty or omit plugin.cfg")

    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for path in included:
            relative = path.relative_to(ROOT).as_posix()
            info = zipfile.ZipInfo(relative, FIXED_TIMESTAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            bundle.writestr(info, path.read_bytes(), compresslevel=9)

    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum.write_text(f"{digest}  {archive.name}\n", encoding="utf-8", newline="\n")
    print(f"Packaged {archive.relative_to(ROOT)} ({len(included)} files)")
    print(f"SHA-256 {digest}")
    return archive, checksum


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output-dir", type=Path, default=ROOT / "dist", help="archive output directory"
    )
    args = parser.parse_args()
    package(args.output_dir.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
