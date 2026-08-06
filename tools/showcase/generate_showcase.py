"""Generate the GodotCascade HTML/Godot parity showcase from its manifest."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = ROOT / "examples" / "showcase" / "manifest.json"
OUTPUT_PATH = ROOT / "docs" / "showcase" / "index.html"
REFERENCE_OUTPUT_DIR = OUTPUT_PATH.parent / "references"


def read_text(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def relative_to_output(relative_path: str) -> str:
    return os.path.relpath(ROOT / relative_path, OUTPUT_PATH.parent).replace("\\", "/")


def code_panel(label: str, source_path: str, language: str) -> str:
    source = html.escape(read_text(source_path))
    return f"""
      <details class="source-panel">
        <summary><span>{html.escape(label)}</span><code>{html.escape(source_path)}</code></summary>
        <pre><code class="language-{language}">{source}</code></pre>
      </details>"""


def validate_source_parity(
    demo: dict[str, object], html_source: str, gxml_source: str, gcss_source: str
) -> None:
    demo_id = str(demo["id"])
    for marker in demo.get("shared_copy", []):
        if marker not in html_source or marker not in gxml_source:
            raise SystemExit(
                f"{demo_id}: shared copy marker {marker!r} must exist in both HTML and GXML"
            )
    for assertion in demo.get("source_parity", []):
        label = assertion["label"]
        if assertion["html"] not in html_source:
            raise SystemExit(f"{demo_id}: HTML source is missing parity feature {label!r}")
        if assertion["gxml"] not in gxml_source:
            raise SystemExit(f"{demo_id}: GXML source is missing parity feature {label!r}")
        if "gcss" in assertion and assertion["gcss"] not in gcss_source:
            raise SystemExit(f"{demo_id}: GCSS source is missing parity feature {label!r}")


def reference_output_name(demo: dict[str, object], html_source: str) -> str:
    revision = hashlib.sha256(html_source.encode("utf-8")).hexdigest()[:12]
    return f"{demo['id']}-{revision}.html"


def legacy_reference_redirect(target_name: str) -> str:
    escaped_target = html.escape(target_name, quote=True)
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="0; url={escaped_target}">
  <link rel="canonical" href="{escaped_target}">
  <title>GodotCascade showcase reference moved</title>
</head>
<body>
  <p>This cached showcase reference moved to <a href="{escaped_target}">{escaped_target}</a>.</p>
  <script>location.replace({json.dumps(target_name)});</script>
</body>
</html>
"""


def render_demo(demo: dict[str, object]) -> str:
    viewport_width, viewport_height = demo["viewport"]
    html_source = read_text(str(demo["html"]))
    gxml_source = read_text(str(demo["gxml"]))
    gcss_source = read_text(str(demo["gcss"]))
    validate_source_parity(demo, html_source, gxml_source, gcss_source)
    html_reference_relative = f"references/{reference_output_name(demo, html_source)}"
    screenshot_path = ROOT / str(demo["godot_screenshot"])
    screenshot_relative = relative_to_output(str(demo["godot_screenshot"]))

    if screenshot_path.exists():
        godot_render = (
            f'<img src="{html.escape(screenshot_relative)}" '
            f'alt="GodotCascade render of {html.escape(str(demo["title"]))}">'
        )
        capture_status = "Captured from the native Godot scene"
    else:
        godot_render = (
            '<div class="missing-capture">Run the Godot capture step to generate this preview.</div>'
        )
        capture_status = "Native capture pending"

    mapping_rows = "".join(
        "<tr>" + "".join(f"<td><code>{html.escape(value)}</code></td>" for value in row) + "</tr>"
        for row in demo["mappings"]
    )

    return f"""
    <article class="demo" id="{html.escape(str(demo['id']))}">
      <header class="demo-heading">
        <div>
          <p class="eyebrow">Current demo</p>
          <h2>{html.escape(str(demo['title']))}</h2>
          <p>{html.escape(str(demo['summary']))}</p>
        </div>
        <dl>
          <div><dt>Viewport</dt><dd>{viewport_width} × {viewport_height}</dd></div>
          <div><dt>Godot scene</dt><dd><code>{html.escape(str(demo['godot_scene']))}</code></dd></div>
        </dl>
      </header>

      <div class="comparison">
        <section class="render-column">
          <div class="render-label"><span>HTML reference</span><small><a href="{html.escape(html_reference_relative)}" target="_blank" rel="noreferrer">Open reference</a></small></div>
          <div class="render-frame" data-viewport-width="{viewport_width}" data-viewport-height="{viewport_height}" style="--viewport-width:{viewport_width}px; --viewport-height:{viewport_height}px; aspect-ratio:{viewport_width}/{viewport_height}">
            <iframe width="{viewport_width}" height="{viewport_height}" title="HTML rendering of {html.escape(str(demo['title']))}" src="{html.escape(html_reference_relative)}"></iframe>
          </div>
        </section>
        <section class="render-column">
          <div class="render-label"><span>GodotCascade</span><small>{capture_status}</small></div>
          <div class="render-frame godot-render" data-viewport-width="{viewport_width}" data-viewport-height="{viewport_height}" style="--viewport-width:{viewport_width}px; --viewport-height:{viewport_height}px; aspect-ratio:{viewport_width}/{viewport_height}">{godot_render}</div>
        </section>
      </div>

      <section class="mapping">
        <div>
          <p class="eyebrow">Translation contract</p>
          <h3>Same intent, native target</h3>
          <p>The mapping is semantic rather than a promise of browser compatibility. Each supported declaration resolves into a typed CascadeStyle or layout value.</p>
        </div>
        <table>
          <thead><tr><th>HTML/CSS</th><th>GodotCascade source</th><th>Runtime</th></tr></thead>
          <tbody>{mapping_rows}</tbody>
        </table>
      </section>

      <section class="sources">
        {code_panel("HTML reference", str(demo["html"]), "html")}
        {code_panel("GodotCascade markup", str(demo["gxml"]), "xml")}
        {code_panel("GodotCascade stylesheet", str(demo["gcss"]), "css")}
      </section>
    </article>"""


def generate(check: bool = False) -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    demos = "".join(render_demo(demo) for demo in manifest["demos"])
    document = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="generator" content="tools/showcase/generate_showcase.py">
  <title>{html.escape(manifest['title'])}</title>
  <style>
    :root {{ color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background:#080b12; color:#e9efff; }}
    * {{ box-sizing:border-box; }}
    body {{ margin:0; background:radial-gradient(circle at 50% 0%, #17213b 0, #080b12 38rem); }}
    code, pre {{ font-family:"Cascadia Code", "SFMono-Regular", Consolas, monospace; }}
    .site-header, main, .site-footer {{ width:min(100% - 40px, 1980px); margin-inline:auto; }}
    .site-header {{ padding:72px 0 42px; display:grid; grid-template-columns:minmax(0,1fr) auto; gap:40px; align-items:end; }}
    .brand {{ color:#82b7ff; font-weight:700; letter-spacing:.08em; text-transform:uppercase; }}
    h1 {{ margin:10px 0 14px; max-width:900px; font-size:clamp(38px,5vw,72px); line-height:1.02; letter-spacing:-.045em; }}
    .site-header p {{ max-width:760px; color:#aab7d1; font-size:18px; line-height:1.6; }}
    .pipeline {{ display:flex; align-items:center; gap:8px; color:#aab7d1; }}
    .pipeline span {{ padding:10px 14px; border:1px solid #2c3c5d; border-radius:999px; background:#111827; white-space:nowrap; }}
    .pipeline b {{ color:#5f79a9; }}
    .doc-links {{ margin-top:22px; display:flex; flex-wrap:wrap; gap:10px; }}
    .doc-links a {{ padding:8px 12px; color:#b9d2ff; text-decoration:none; border:1px solid #2c3c5d; border-radius:8px; background:#101827; }}
    .doc-links a:hover {{ color:#fff; border-color:#5f79a9; }}
    .demo {{ margin-bottom:60px; border:1px solid #263554; border-radius:22px; background:rgba(12,17,29,.92); overflow:hidden; box-shadow:0 35px 100px rgba(0,0,0,.3); }}
    .demo-heading {{ padding:30px 34px; display:grid; grid-template-columns:minmax(0,1fr) auto; gap:36px; border-bottom:1px solid #263554; }}
    .eyebrow {{ margin:0 0 7px!important; color:#76a9fa!important; font-size:12px!important; font-weight:700; letter-spacing:.12em; text-transform:uppercase; }}
    h2,h3 {{ margin:0; }}
    h2 {{ font-size:30px; }}
    h3 {{ font-size:22px; }}
    .demo-heading p, .mapping p {{ color:#aab7d1; line-height:1.55; }}
    dl {{ margin:0; display:grid; gap:8px; align-content:start; }}
    dl div {{ display:grid; grid-template-columns:100px 1fr; gap:14px; }}
    dt {{ color:#7e8da9; }} dd {{ margin:0; }}
    .comparison {{ padding:30px; display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:24px; background:#090d16; }}
    .render-column {{ min-width:0; }}
    .render-label {{ height:44px; display:flex; justify-content:space-between; align-items:center; color:#dce6fa; }}
    .render-label span {{ font-weight:700; }} .render-label small, .render-label a {{ color:#7e8da9; }}
    .render-frame {{ position:relative; width:100%; overflow:hidden; border:1px solid #304160; border-radius:12px; background:#0e1014; }}
    .render-frame iframe, .render-frame img {{ position:absolute; inset:0 auto auto 0; display:block; width:var(--viewport-width); height:var(--viewport-height); max-width:none; border:0; transform:scale(var(--render-scale,1)); transform-origin:top left; }}
    .missing-capture {{ height:100%; display:grid; place-items:center; color:#f6b86b; background:repeating-linear-gradient(135deg,#111827,#111827 16px,#151d2d 16px,#151d2d 32px); }}
    .mapping {{ padding:34px; display:grid; grid-template-columns:320px minmax(600px,1fr); gap:40px; border-top:1px solid #263554; }}
    table {{ width:100%; border-collapse:collapse; }} th,td {{ padding:12px 14px; border-bottom:1px solid #25324a; text-align:left; }} th {{ color:#7e8da9; font-size:12px; text-transform:uppercase; }} td code {{ color:#c8d8f5; }}
    .sources {{ padding:0 34px 34px; display:grid; gap:10px; }}
    .source-panel {{ border:1px solid #263554; border-radius:10px; overflow:hidden; background:#090d16; }}
    .source-panel summary {{ padding:15px 17px; display:flex; justify-content:space-between; gap:20px; cursor:pointer; color:#dce6fa; }}
    .source-panel summary code {{ color:#7184a8; font-size:12px; }}
    pre {{ margin:0; padding:20px; max-height:520px; overflow:auto; border-top:1px solid #263554; color:#b9d2ff; font-size:13px; line-height:1.55; tab-size:4; }}
    .site-footer {{ padding:0 0 50px; color:#71809c; }}
    @media (max-width:900px) {{
      .site-header,.demo-heading,.mapping {{ grid-template-columns:1fr; }}
      .comparison {{ grid-template-columns:1fr; }}
      .pipeline {{ display:none; }}
      .mapping {{ overflow-x:auto; }}
      dl div {{ grid-template-columns:90px 1fr; }}
    }}
  </style>
</head>
<body>
  <header class="site-header">
    <div>
      <div class="brand">GodotCascade</div>
      <h1>Design in HTML. Rebuild with native Godot controls.</h1>
      <p>{html.escape(manifest['description'])} This page is generated from the showcase manifest so reference designs, executable source, scenes, and captures evolve together.</p>
      <nav class="doc-links" aria-label="Project documentation">
        <a href="../current-support.md">Current support</a>
        <a href="../architecture.md">Architecture</a>
        <a href="../../ROADMAP.md">Roadmap</a>
      </nav>
    </div>
    <div class="pipeline" aria-label="Migration pipeline"><span>HTML + CSS</span><b>→</b><span>GXML + GCSS</span><b>→</b><span>Godot Controls</span></div>
  </header>
  <main>{demos}</main>
  <footer class="site-footer">Generated from <code>examples/showcase/manifest.json</code>. Do not edit this file directly.</footer>
  <script>
    for (const frame of document.querySelectorAll('.render-frame')) {{
      const width = Number(frame.dataset.viewportWidth);
      const updateScale = () => frame.style.setProperty('--render-scale', frame.clientWidth / width);
      new ResizeObserver(updateScale).observe(frame);
      updateScale();
    }}
  </script>
</body>
</html>
"""
    document = "\n".join(line.rstrip() for line in document.splitlines()) + "\n"
    references = {
        REFERENCE_OUTPUT_DIR / reference_output_name(demo, read_text(str(demo["html"]))): read_text(str(demo["html"]))
        for demo in manifest["demos"]
    }
    current_by_demo = {
        str(demo["id"]): REFERENCE_OUTPUT_DIR / reference_output_name(demo, read_text(str(demo["html"])))
        for demo in manifest["demos"]
    }
    legacy_references: dict[Path, str] = {}
    if REFERENCE_OUTPUT_DIR.exists():
        for candidate in REFERENCE_OUTPUT_DIR.glob("*.html"):
            if candidate in references:
                continue
            matching_demo = next(
                (demo_id for demo_id in current_by_demo if candidate.name.startswith(f"{demo_id}-")),
                None,
            )
            if matching_demo is not None:
                legacy_references[candidate] = legacy_reference_redirect(
                    current_by_demo[matching_demo].name
                )
    if check:
        if not OUTPUT_PATH.exists() or OUTPUT_PATH.read_text(encoding="utf-8") != document:
            raise SystemExit(
                f"{OUTPUT_PATH.relative_to(ROOT)} is stale; run tools/showcase/generate_showcase.py"
            )
        for reference_path, reference_source in references.items():
            if not reference_path.exists() or reference_path.read_text(encoding="utf-8") != reference_source:
                raise SystemExit(
                    f"{reference_path.relative_to(ROOT)} is stale; run tools/showcase/generate_showcase.py"
                )
        for reference_path, redirect_source in legacy_references.items():
            if reference_path.read_text(encoding="utf-8") != redirect_source:
                raise SystemExit(
                    f"{reference_path.relative_to(ROOT)} has a stale compatibility redirect"
                )
        generated_paths = set(REFERENCE_OUTPUT_DIR.glob("*.html")) if REFERENCE_OUTPUT_DIR.exists() else set()
        if generated_paths != set(references) | set(legacy_references):
            raise SystemExit("docs/showcase/references contains stale generated files")
        print(f"Verified {OUTPUT_PATH.relative_to(ROOT)}")
        return

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(document, encoding="utf-8", newline="\n")
    REFERENCE_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for old_reference in REFERENCE_OUTPUT_DIR.glob("*.html"):
        if old_reference in legacy_references:
            old_reference.write_text(legacy_references[old_reference], encoding="utf-8", newline="\n")
        elif old_reference not in references:
            old_reference.unlink()
    for reference_path, reference_source in references.items():
        reference_path.write_text(reference_source, encoding="utf-8", newline="\n")
    print(f"Generated {OUTPUT_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail when the committed report is stale")
    generate(check=parser.parse_args().check)
