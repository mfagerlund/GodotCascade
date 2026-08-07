#!/usr/bin/env python3
"""Record the deterministic native live-reload demo and assemble its GIF."""

from __future__ import annotations

import argparse
import subprocess
import tempfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "docs" / "showcase" / "assets" / "live-reload-demo.gif"
SCENE = "res://examples/live_reload_demo/live_reload_demo.tscn"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="godot-cascade-live-reload-") as directory:
        frame_root = Path(directory) / "frame.png"
        completed = subprocess.run(
            [
                str(args.godot.resolve()),
                "--path",
                str(ROOT),
                "--write-movie",
                str(frame_root),
                "--fixed-fps",
                "10",
                "--quit-after",
                "70",
                "--disable-vsync",
                "--resolution",
                "960x540",
                SCENE,
            ],
            check=True,
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        output = completed.stdout + completed.stderr
        print(output, end="")
        if "SCRIPT ERROR:" in output or "Failed to load script" in output:
            raise RuntimeError("Godot could not load the live-reload demo")
        paths = sorted(Path(directory).glob("frame*.png"))
        if len(paths) != 70:
            raise RuntimeError(f"Expected 70 movie frames, found {len(paths)}")
        frames = [Image.open(path).convert("RGB") for path in paths]
        candidate = Path(directory) / OUTPUT.name
        frames[0].save(
            candidate,
            save_all=True,
            append_images=frames[1:],
            duration=100,
            loop=0,
            optimize=True,
        )
        if args.check:
            if not OUTPUT.is_file() or OUTPUT.read_bytes() != candidate.read_bytes():
                raise SystemExit(f"{OUTPUT.relative_to(ROOT)} is stale; recapture the live-reload demo")
        else:
            OUTPUT.parent.mkdir(parents=True, exist_ok=True)
            OUTPUT.write_bytes(candidate.read_bytes())
            print(f"Recorded {OUTPUT.relative_to(ROOT)} ({len(frames)} frames)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
