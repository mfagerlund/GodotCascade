#!/usr/bin/env python3
"""Verify the packaged addon in an otherwise empty Godot project."""

from __future__ import annotations

import argparse
import configparser
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PLUGIN_CONFIG = ROOT / "addons" / "godot_cascade" / "plugin.cfg"
SMOKE_SCRIPT = '''extends SceneTree

const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const GcssParser := preload("res://addons/godot_cascade/style/gcss_parser.gd")
const CascadeBuilder := preload("res://addons/godot_cascade/runtime/cascade_builder.gd")


func _initialize() -> void:
\t_run.call_deferred()


func _run() -> void:
\tvar markup := GxmlParser.parse("<Column><Label id=\\"message\\">Clean install</Label><TextInput id=\\"profile\\" text=\\"Rhea\\" required=\\"true\\" /></Column>")
\tvar stylesheet := GcssParser.parse("#message { color: #4da3ff; font-size: 18px; } TextInput:invalid { border-color: #ff6677; }")
\tvar result := CascadeBuilder.build(markup["root"], stylesheet["rules"])
\tvar diagnostics: Array = markup["diagnostics"] + stylesheet["diagnostics"] + result["diagnostics"]
\tvar root: Control = result["root"]
\tif not diagnostics.is_empty() or root == null or root.get_child_count() != 2:
\t\tpush_error("Packaged addon smoke test failed: %s" % [diagnostics])
\t\tif root != null:
\t\t\troot.free()
\t\tquit(1)
\t\treturn
\tvar label: Control = root.get_child(0)
\tvar input: Control = root.get_child(1)
\tif label.get("text") != "Clean install" or label.get("text_color") != Color("4da3ff") or not input is LineEdit or input.get("text") != "Rhea" or not input.call("validate"):
\t\tpush_error("Packaged addon produced the wrong native control state.")
\t\troot.free()
\t\tquit(1)
\t\treturn
\troot.free()
\tprint("GodotCascade clean-install smoke test passed.")
\tquit(0)
'''


def plugin_version() -> str:
    parser = configparser.ConfigParser()
    parser.read(PLUGIN_CONFIG, encoding="utf-8")
    return parser["plugin"]["version"].strip('"')


def run_godot(command: list[str], label: str) -> int:
    result = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        timeout=150,
    )
    output = result.stdout + result.stderr
    sys.stdout.write(output)
    compile_failure = "SCRIPT ERROR:" in output or "Parse Error:" in output
    if result.returncode != 0 or compile_failure:
        print(f"{label} failed.", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot", help="Godot console executable")
    parser.add_argument("--archive", type=Path, help="archive created by package_addon.py")
    args = parser.parse_args()
    archive = args.archive or ROOT / "dist" / f"godot-cascade-{plugin_version()}.zip"
    if not archive.exists():
        raise SystemExit(f"Missing archive: {archive}")

    with tempfile.TemporaryDirectory(prefix="godot-cascade-smoke-") as temporary:
        project = Path(temporary)
        with zipfile.ZipFile(archive) as bundle:
            names = bundle.namelist()
            if not names or any(
                not name.startswith("addons/godot_cascade/") or ".." in Path(name).parts
                for name in names
            ):
                raise SystemExit("Archive contains a path outside addons/godot_cascade")
            bundle.extractall(project)
        (project / "project.godot").write_text(
            '; Engine configuration file.\nconfig_version=5\n\n'
            '[application]\nconfig/name="GodotCascade package smoke test"\n\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n\n'
            '[editor_plugins]\n'
            'enabled=PackedStringArray("res://addons/godot_cascade/plugin.cfg")\n',
            encoding="utf-8",
            newline="\n",
        )
        (project / "smoke.gd").write_text(SMOKE_SCRIPT, encoding="utf-8", newline="\n")
        import_result = run_godot(
            [
                args.godot,
                "--headless",
                "--path",
                str(project),
                "--import",
            ],
            "Clean-project import scan",
        )
        if import_result != 0:
            return import_result
        return run_godot(
            [
                args.godot,
                "--headless",
                "--path",
                str(project),
                "--script",
                "res://smoke.gd",
                "--quit-after",
                "120",
            ],
            "Packaged-addon runtime smoke test",
        )


if __name__ == "__main__":
    raise SystemExit(main())
