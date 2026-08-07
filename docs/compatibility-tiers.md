# Native control compatibility tiers

GodotCascade classifies native controls by how precisely a supported GCSS property can be honored:

| Tier | Meaning | Development diagnostic |
| --- | --- | --- |
| Exact | GodotCascade owns measurement and drawing for the supported surface. | None for supported properties. |
| Adapted | A documented adapter maps selected properties to native Godot behavior. | A warning identifies the inexact native mapping or an unsupported property. |
| Layout-only | An ordinary `Control` participates in size, margin, flex, grid, and positioning. | Visual declarations warn that native appearance remains unchanged. |

Use the registry when an integration applies authored declarations to a native control:

```gdscript
const CompatibilityRegistry := preload("res://addons/godot_cascade/runtime/compatibility_registry.gd")

var diagnostic := CompatibilityRegistry.diagnose_property(native_control, "background")
if not diagnostic.is_empty():
    push_warning(diagnostic.message)
```

Owned Cascade controls are classified automatically. An adapter declares itself and its mapped property surface explicitly:

```gdscript
line_edit.set_meta("cascade_compatibility_tier", "adapted")
line_edit.set_meta("cascade_adapted_properties", PackedStringArray(["color", "font-size"]))
```

Declaring a tier does not implement an adapter. The integration remains responsible for applying each listed property and documenting semantic differences. Properties not listed receive an unsupported-adapter warning.

`CascadeTable` and `CascadeTableCell` are exact for their documented shared-track and cell box/text surfaces; `CascadeTablePart` is a structural header/body/row carrier. `CascadeScroll`, `CascadeTextInput`, and `CascadeTextArea` are the built-in adapted controls. `CascadeScroll` delegates scrolling, wheel/touch input, and scrollbar behavior to native `ScrollContainer`. The text adapters delegate editing, selection, clipboard, undo/redo, shaping, bidi, and IME behavior to native `LineEdit`/`TextEdit`; password behavior remains native and single-line-only. Cascade maps each adapter's documented box, text, validation, and focus-state properties.

Layout properties accepted without a compatibility warning are width and height constraints, margins, flex growth/alignment, grid placement, and stack positioning. Padding and visual/text declarations are intentionally not claimed for layout-only controls.
