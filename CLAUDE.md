# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GodotCascade is a prototype retained-mode UI framework for Godot 4: a declarative markup language
(`.gxml`), a CSS-inspired stylesheet subset (`.gcss`), and a flex box model that produce **native Godot
`Control` nodes**. It is not a browser engine — see the "Non-goals" section of `README.md`.

Everything is GDScript; there is no C# in this project despite the mono editor build being used.

## Commands

Godot is not on `PATH`. Use the **`_console`** binary for headless runs so stdout reaches the Windows
terminal:

```powershell
$godot = "C:\Users\matti\AppData\Local\Programs\Godot\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe"
```

If the local install moves, locate `Godot*_console.exe` and keep the selected version at Godot 4.7 until compatibility testing establishes a wider supported range.

### Tests

There is no test framework — each test is a standalone `SceneTree` script run one at a time. Exit code 0
on pass, 1 on failure; the "single test" granularity is the file.

```powershell
& $godot --headless --path . --script res://tests/flex_layout_engine_test.gd   # pure layout math, fastest
& $godot --headless --path . --script res://tests/layout_smoke_test.gd         # CascadeBox in a scene tree
& $godot --headless --path . --script res://tests/component_test.gd            # owned components
& $godot --headless --path . --script res://tests/source_pipeline_test.gd      # gxml/gcss -> native tree, reload, bindings
```

All four run headless and pass on a clean tree. To narrow further, comment out calls in the test's `_run()`
rather than adding a filter mechanism.

### Running the project

`project.godot` main scene is `examples/generated_showcase.tscn`. Open the folder in the Godot editor
(the addon is already enabled in `project.godot`) or `& $godot --path .`.

### Showcase

`docs/showcase/index.html` is **generated** — never hand-edit it. Edit `examples/showcase/manifest.json`
or `tools/showcase/generate_showcase.py`, then:

```powershell
python tools/showcase/generate_showcase.py           # regenerate
python tools/showcase/generate_showcase.py --check    # verify committed output is current
./tools/showcase/build_showcase.ps1 -GodotPath $godot # capture screenshots + regenerate
```

The capture step needs a real graphics display; the dummy headless renderer will not produce screenshots.
The generator itself is stdlib-only Python.

## Architecture

```
.gxml ──> GxmlParser ──┐
                       ├──> CascadeBuilder ──> off-tree candidate Control tree
.gcss ──> GcssParser ──┘                              │
                                                      ▼
                          CascadeDocument ──> CascadeReconciler ──> live native tree
                                                      │
                                                      ▼
                                        BindingResolver applies {paths}
```

`CascadeBox` (and the owned components) then run `FlexLayoutEngine` to turn styles into rectangles.

| Layer | File | Role |
| --- | --- | --- |
| Markup | `addons/godot_cascade/markup/gxml_parser.gd` | XML → `Element` tree + diagnostics. No nodes created. |
| Style | `addons/godot_cascade/style/gcss_parser.gd` | Stylesheet → `Rule` objects with specificity/order. Selector matching lives on `Rule.matches()`. |
| Style surface | `addons/godot_cascade/style/cascade_style.gd` | `CascadeStyle` resource — the box-model property surface every control consumes, with DRAW/MEASURE/ARRANGE invalidation flags. |
| Build | `addons/godot_cascade/runtime/cascade_builder.gd` | Element + rules → native controls. Owns the tag→control factory and the entire supported-property registry. |
| Reconcile | `addons/godot_cascade/runtime/cascade_reconciler.gd` | Merges a candidate tree into the live one by key, preserving node identity. |
| Host | `addons/godot_cascade/runtime/cascade_document.gd` | The `Control` you place in a scene: source watching, transactional reload, diagnostics, bindings. |
| Layout | `addons/godot_cascade/layout/flex_layout_engine.gd` | Pure geometry: `LayoutItem[]` + `LayoutRequest` → `Rect2[]`. Knows nothing about the scene tree. |
| Adapter | `addons/godot_cascade/layout/cascade_box.gd` | The `Container` that measures children and calls the engine. |
| Components | `addons/godot_cascade/components/*.gd` | Owned controls (see ADR 0001). |

Documentation starts at `docs/README.md`. The exact executable language matrix is in
`docs/current-support.md`; do not infer support from CSS or HTML familiarity. Design docs are
`docs/architecture.md`, `docs/decisions/0001-owned-core-controls.md`, and `ROADMAP.md`.

### Boundaries to preserve

- **Parsers never create Godot nodes.** They return `{root|rules, diagnostics}` dictionaries.
- **`FlexLayoutEngine` never touches the scene tree.** New layout math goes there and is tested by
  `flex_layout_engine_test.gd` with no scene at all — that is the cheapest test loop in the repo.
- **Godot-specific behavior terminates in the builder/components**, not in parsers or selector matching.
- Unsupported input produces a **diagnostic**, never a silently stored value.

## Conventions and cross-file couplings

These are the things that bite when changing code across files.

### Adding a GXML element

1. Add the tag to `CascadeBuilder._create_control()` (unknown tags emit an error diagnostic).
2. If users should be able to add it from the Create Node dialog, register it in
   `addons/godot_cascade/plugin.gd` `_enter_tree()` **and** unregister in `_exit_tree()`.

### Adding a GCSS property or an authored control property

1. Handle it in `CascadeBuilder._apply_declaration()` (or `_apply_state_declaration()` for pseudo states).
2. **Add the target property name to `CascadeReconciler.COPIED_PROPERTIES`.** Anything missing from that
   list is applied on first build but silently not updated on hot reload — the most common bug here.
   `cascade_style` is handled separately (deep-duplicated per node, so styles are never shared instances).

### Identity and reconciliation

- Every built control carries metadata: `cascade_element_type`, `cascade_id`, `cascade_classes`,
  `cascade_key`, `cascade_bindings`.
- `cascade_key` is `"#" + id` when the element has an `id`, otherwise the structural path
  `parentKey/index:Tag`. The reconciler matches children by this key, so **adding an `id` is how an element
  survives reordering**.
- Two controls are "compatible" only if the script *and* `cascade_element_type` match; otherwise the node is
  replaced.

### Diagnostics contract

Dictionaries of `{severity, message}` plus `line`/`column` from parsers; `CascadeDocument` stamps `path`.
Any diagnostic with `severity == "error"` aborts the swap and **leaves the previous valid tree on screen**
(last-valid rendering). Warnings do not. Binding failures use `path == "binding"` and are cleared/recomputed
on every refresh.

### Bindings

Only exact `{dot.separated.path}` attribute values, stored as `cascade_bindings` metadata and applied after
build and after reconcile. `BindingResolver` walks dictionaries, arrays, and object properties only — no
expressions, no method calls. Supported today: `text` on Label/Button, `min`/`max`/`value` on Progress.
Assigning `binding_context` refreshes automatically; mutating nested state requires `refresh_bindings()`.

### Current GCSS subset limits (deliberate, not bugs)

No selector lists (`a, b`), no direct-child combinator (`>`), no shorthand beyond `padding`/`margin`/`border`,
no inheritance. `border` must be exactly `<width> solid <color>`. Lengths accept `px` or bare numbers only.
One trailing pseudo state per selector, from `hover|pressed|focused|disabled|selected`, and pseudo states
currently only apply to `CascadeButton`. Check `ROADMAP.md` before "fixing" a gap — several are scheduled.

The settings-menu/form-control milestone in `ROADMAP.md` is in progress: shared state adapters,
checkbox, radio-button, switch, select, and slider behavior, the native input-state matrix, and a
parity showcase are implemented. The adapted text-input boundary is documented; implementation waits
for the event/two-way-binding milestone.

### GDScript style in this repo

Tabs for indentation; two blank lines between top-level functions. Cross-file references use
`const X := preload("res://...")` at the top. Parsers/engines/reconcilers are `extends RefCounted` with
`static func` entry points; nodes are `@tool` so they behave in the editor. Public functions get `##` doc
comments. `.gitattributes` forces LF for `.gd`/`.tscn`/`.tres` — keep it that way.

### Tests

New test scripts follow the existing shape: `extends SceneTree`, a `_failures: Array[String]`, `_initialize()`
that defers `_run()`, `_expect_*` helpers appending failure strings, then `quit(0)` or push each failure and
`quit(1)`. Scene-tree tests must `await process_frame` (usually 2–3 times) before asserting geometry, since
layout runs on sort notifications.
