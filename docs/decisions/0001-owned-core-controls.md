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

| GodotCascade component | Native base | Godot behavior retained | Behavior owned by GodotCascade |
| --- | --- | --- | --- |
| `CascadeButton` | `BaseButton` | activation, focus, toggle, disabled state, shortcuts, signals | box model, text/icon layout, state drawing |
| `CascadeLabel` | `Control` | canvas item and accessibility hooks | text measurement, wrapping, overflow, drawing |
| `CascadeProgress` | `Range` | value constraints and change signals | track/fill layout and drawing |
| `CascadePanel` | `Control` | native scene/input lifecycle | box model and drawing |
| `CascadeImage` | `Control` | native texture resources | fit, position, clipping, and drawing |

Complex editors such as line edits and rich text will initially use native controls behind explicit compatibility adapters. Replacing them requires separate design work around selection, IME composition, shaping, bidirectional text, clipboard behavior, and accessibility.

## Compatibility tier

Ordinary Godot controls remain valid children of Cascade layouts. The style system will classify control support:

- **Exact:** GodotCascade-owned components honor every supported property with documented semantics.
- **Adapted:** a native control maps supported properties through a dedicated adapter; limitations are documented.
- **Layout-only:** the control participates in sizing, margin, flex, grid, and positioning, while appearance remains Godot-owned.

Unsupported or inexact declarations should produce a diagnostic in development builds rather than failing silently.

## Consequences

- Core components can share one box-model implementation and exact state styles.
- Components remain native Godot nodes and retain relevant engine behavior.
- The project owns more drawing, text layout, theme interoperability, and tests.
- Theme adapters become optional integration paths rather than the foundation of styling.
- The first implemented component is `CascadeButton`, based on `BaseButton`, because it exercises intrinsic content, interaction states, focus, disabled behavior, and text layout without requiring a full text editor.
