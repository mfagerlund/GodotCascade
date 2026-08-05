# ADR 0001: Own the core control implementations

- **Status:** Accepted
- **Date:** 2026-08-05

## Context

Godot's built-in controls combine intrinsic sizing, theme constants, `StyleBox` content margins, and control-specific drawing behavior. An adapter can approximate CSS padding and borders by generating theme resources, but it cannot guarantee that every native control interprets the same box-model values identically.

GodotCascade promises a consistent styling model. A `padding: 12px` declaration should mean the same thing on a panel, button, progress bar, and custom component. Quietly accepting declarations that are then constrained or reinterpreted by a built-in control would make layout difficult to reason about.

At the same time, reimplementing interaction behavior from a bare `Control` would discard useful Godot behavior such as focus, shortcuts, accessibility metadata, toggle state, and standard signals.

## Decision

GodotCascade will own the visual and measurement implementation of its core component set while deriving from the lowest useful native Godot primitive.

Examples:

| GodotCascade component | Status | Native base | Godot behavior retained | Behavior owned by GodotCascade |
| --- | --- | --- | --- | --- |
| `CascadeButton` | Implemented | `BaseButton` | activation, focus, toggle, disabled state, shortcuts, signals | box model, text layout, and state drawing |
| `CascadeLabel` | Implemented | `Control` with internal `Label` | shaping, wrapping, bidi, localization, accessibility hooks | outer box model, clipping, and sizing contract |
| `CascadeProgress` | Implemented | `Control` | native scene and drawing lifecycle | clamped range values, track/fill layout, drawing, and box model |
| `CascadePanel` | Implemented | `CascadeBox` / `Container` | container lifecycle and child layout notifications | semantic component identity plus shared box/flex behavior |
| `CascadeImage` | Implemented | `Control` | native texture resources | contain/cover/fill/intrinsic crop geometry, clipping, drawing, and box model |

The form-control roadmap follows the same rule:

| Proposed component | Behavioral foundation | GodotCascade-owned surface |
| --- | --- | --- |
| `CascadeCheckbox` | `BaseButton` toggle behavior | indicator, label layout, box model, and checked-state drawing |
| `CascadeRadioButton` | `BaseButton` plus `ButtonGroup` | indicator, group-facing attributes, label layout, and state drawing |
| `CascadeSwitch` (implemented) | Checkbox/toggle semantics | switch track, thumb, and state drawing |
| `CascadeSelect` (implemented) | Composite native button, popup, and option list behavior | closed control, popup styling, option layout, and open/selected states |
| `CascadeSlider` (implemented) | Native range semantics | track, fill, thumb geometry, and pointer/focus states |

Complex editors such as line edits and rich text will initially use native controls behind explicit compatibility adapters. Replacing them requires separate design work around selection, IME composition, shaping, bidirectional text, clipboard behavior, and accessibility.

## Compatibility tier

Ordinary Godot controls remain valid children of Cascade layouts. The style system will classify control support:

- **Exact:** GodotCascade-owned components honor every supported property with documented semantics.
- **Adapted:** a native control maps supported properties through a dedicated adapter; limitations are documented.
- **Layout-only:** the control participates in sizing, margin, flex, grid, and positioning, while appearance remains Godot-owned.

Unsupported or inexact declarations produce a compatibility diagnostic through `CompatibilityRegistry` rather than failing silently.

## Consequences

- Core components can share one box-model implementation and exact state styles.
- Components remain native Godot nodes and retain relevant engine behavior.
- The project owns more drawing, text layout, theme interoperability, and tests.
- Theme adapters become optional integration paths rather than the foundation of styling.
- `CascadeButton`, `CascadeLabel`, `CascadePanel`, `CascadeProgress`, and `CascadeImage` validate the decision across interactive, textual, container, value-display, and media controls.
- Checkbox and radio-button work now shares one pseudo-state adapter; select/dropdown can build on it when popup, option-selection, and keyboard-navigation behavior is introduced.
