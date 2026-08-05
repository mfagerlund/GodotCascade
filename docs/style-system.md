# Style system

The GCSS pipeline keeps syntax, selector matching, typed values, computed declarations, and native theme adaptation separate.

## Tokens and values

`GcssTokenizer` emits recoverable tokens with start/end offsets and line/column spans. Comments and strings are recognized without losing source locations; an unexpected delimiter produces a diagnostic and scanning continues at the next token.

`GcssValue` represents the complete current scalar value grammar:

| Kind | Examples | Normalized data |
| --- | --- | --- |
| Keyword | `cover`, `space-between` | lowercase text |
| Number | `1`, `0.25`, `-2` | floating-point number |
| Length | `12px` | number and `px` unit |
| Time | `150ms`, `0.25s` | number/unit and milliseconds |
| Color | `#4da3ff`, `rebeccapurple` | Godot `Color` |
| String | `"menu"`, `'menu'` | unquoted text |

Transition properties consume time values and normalize seconds/milliseconds to a duration in seconds.

## Selectors and inheritance

Type, class, ID, descendant, and direct-child (`>`) selectors participate in specificity and source order. `color` and `font-size` inherit through the authored GXML element tree. An explicit `inherit` value requests the parent result; at the root it resolves to the component default.

Shorthands expand before cascade winner selection. The supported expansion set is padding and margin edges, solid border width/color, and one- or two-value gap into row/column gaps. This ensures a later or more-specific longhand competes with the corresponding expanded property.

## Computed cache

Computed declarations are cached by the stylesheet revision and the element's type/ID/class ancestry signature. Equivalent rebuilds reuse immutable computed dictionaries. Integrations that mutate selector inputs can invalidate only affected entries:

```gdscript
const ComputedStyleCache := preload("res://addons/godot_cascade/style/computed_style_cache.gd")

ComputedStyleCache.invalidate_class("warning")
ComputedStyleCache.invalidate_id("save")
ComputedStyleCache.invalidate_type("Button")
```

A new stylesheet revision naturally uses a separate cache key, so stale values are never used during hot reload.

## Native theme adapter

Owned exact controls draw directly from `CascadeStyle`. For native adapted controls, `ThemeAdapter` can produce a `StyleBoxFlat` and apply text overrides. Applying an adapter marks the target as adapted and records its mapped property surface, allowing `CompatibilityRegistry` to diagnose inexact or unsupported declarations.
