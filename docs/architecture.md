# Architecture

GodotCascade is split into pure data transformations around a narrow Godot adapter. Keeping the core independent from the scene tree makes layout and style behavior deterministic, testable, and usable by editor tooling.

## Runtime pipeline

```text
source files
    │
    ├── .gxml ───────→ markup syntax tree
    └── .gcss ───────→ stylesheet syntax tree
                              │
                              ▼
                    logical element tree
                              │
                              ▼
                      computed styles
                              │
                              ▼
                       layout boxes
                              │
                              ▼
                     native Control tree
```

The source formats are tentatively named `.gxml` and `.gcss`. The stylesheet extension should be confirmed before the public API stabilizes.

## Subsystems

### Source and diagnostics

Parsers retain source spans rather than returning only values. Every recoverable error carries a file, range, explanation, and ideally a suggested correction. Parsing does not create Godot nodes.

### Logical element tree

The logical tree represents authored structure and component expansion. Elements have stable identities, type names, attributes, classes, optional IDs, bindings, and children. It is deliberately smaller than a browser DOM and is not exposed as a general scripting platform.

### Style engine

The style engine indexes rules by the rightmost selector, matches only plausible candidates, and produces immutable computed styles. It owns specificity, inheritance, initial values, pseudo states, and custom properties. Resolved style is kept separate from mutable Godot theme resources.

The current prototype exposes the computed box-model shape as a mutable `CascadeStyle` resource. Both `CascadeBox` and owned components consume it and react to draw, measure, and arrange invalidation flags. Stylesheet resolution will eventually produce immutable snapshots of this same property surface; the editable resource is the bridge used before parsing and selector matching exist.

The first executable stylesheet slice parses type, class, ID, and descendant selectors; resolves specificity and source order; and applies a focused property registry through `CascadeBuilder`. It intentionally emits diagnostics for unsupported values instead of retaining unknown CSS. This is a vertical slice, not the final tokenizer or computed-style cache.

### Layout engine

Layout has two conceptual passes:

1. **Measure** computes desired sizes from constraints and intrinsic content.
2. **Arrange** assigns final rectangles to boxes and their children.

The layout engine consumes plain value objects and produces rectangles. The Phase 1 `CascadeBox` currently performs these operations inside a `Container`; extracting the calculations into engine-only types is the next architectural step.

### Reconciler

The reconciler compares the previous logical tree with the next one, then applies the smallest practical set of mutations to native nodes. It must preserve runtime state—especially focus, line-edit selection, scroll position, animation state, and user signal connections—whenever element identity is stable.

`CascadeDocument` builds each source revision as an off-tree candidate. If parsing and construction succeed, `CascadeReconciler` matches controls by explicit `id` or structural fallback key and copies authored properties into compatible native instances. This preserves focus, runtime state, and user signal connections. Incompatible or removed elements are replaced narrowly; an invalid candidate is discarded so the last valid tree stays interactive. Parsed elements use weak parent links, allowing descendant selector matching without reference cycles.

The runtime watcher compares source-content signatures rather than filesystem timestamps, avoiding timestamp-resolution and editor atomic-save differences. It polls on a configurable interval and uses the same transactional reload path as explicit reloads.

### Godot adapter

The adapter owns control factories, property conversion, theme integration, input-state observation, and intrinsic measurement. Godot-specific behavior should terminate here instead of leaking into parsers or rule matching.

Core components use Godot's lowest useful behavioral primitive while owning their box model and drawing. For example, `CascadeButton` derives from `BaseButton` rather than adapting Godot's themed `Button`. Ordinary native controls remain supported through explicit exact, adapted, or layout-only compatibility tiers. See [ADR 0001](decisions/0001-owned-core-controls.md).

## Invalidation model

Changes have different costs and should not all rebuild the interface:

| Change | Style | Measure | Arrange | Draw | Reconcile |
| --- | ---: | ---: | ---: | ---: | ---: |
| Background color | no | no | no | yes | no |
| Padding | no | yes | yes | yes | no |
| Parent width | no | maybe | yes | yes | no |
| Hover state | targeted | maybe | maybe | yes | no |
| Element type | yes | yes | yes | yes | yes |
| Bound text | no | yes | yes | yes | targeted |

The exact dependency table will eventually become property metadata in the style system.

## Intentional CSS differences

- Logical pixels map directly to Godot UI units.
- Margins do not collapse.
- Percentages are accepted only where their containing block is unambiguous.
- Unsupported properties produce diagnostics instead of being silently stored.
- Native control minimum sizes participate in measurement.
- Theme resolution remains available to native controls.
- Arranged rectangles round their leading and trailing edges independently by default, so adjacent boundaries remain stable; containers may opt into subpixel output.
- Overflow is explicit (`visible` or `clip`) and never inferred from a control type.

## Threading

Godot scene-tree mutation remains on the main thread. Tokenization, parsing, selector indexing, and other pure-data work may move off-thread later, but only immutable results cross back to the runtime adapter.

## Compatibility policy

During the prototype phase, APIs may change without migration support. Before the first public preview, the project should declare a minimum Godot version, source-format versioning, a runtime API deprecation window, and import compatibility expectations.
