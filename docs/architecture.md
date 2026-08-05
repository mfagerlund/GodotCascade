# Architecture

GodotCascade is split into pure data transformations around a narrow Godot adapter. Keeping the core independent from the scene tree makes layout and style behavior deterministic, testable, and usable by editor tooling.

## Runtime pipeline

```text
.gxml ──→ GxmlParser ──┐
                       ├──→ CascadeBuilder ──→ off-tree candidate Controls
.gcss ──→ GcssParser ──┘                              │
                                                      ▼
source watcher ──→ CascadeDocument ──→ CascadeReconciler ──→ live Controls
                                                      │
binding context ──→ BindingResolver ──────────────────┤
                                                      ▼
                                             CascadeBox adapter
                                                      │
                                                      ▼
                                             FlexLayoutEngine
```

The source formats are tentatively named `.gxml` and `.gcss`. The stylesheet extension should be confirmed before the public API stabilizes.

## Subsystems

### Source and diagnostics

Parsers return logical values plus recoverable line/column diagnostics; `CascadeDocument` stamps the source path. Parsing does not create Godot nodes. Complete source spans, ranges, and fix suggestions remain improvements for the tokenizer/parser milestone.

### Logical element tree

The logical tree represents authored structure before native construction. Elements have type names, attributes, classes, optional IDs, text, parent links, and children. `CascadeBuilder` derives explicit-ID or structural keys and binding metadata when it creates the candidate native tree. The logical tree is deliberately smaller than a browser DOM and is not exposed as a general scripting platform.

### Style engine

The style engine indexes rules by the rightmost selector before matching plausible candidates. The target computed-style layer will own inheritance, initial values, pseudo states, and custom properties while keeping resolved style separate from mutable Godot theme resources.

The current executable slice parses rules, matches them against the logical element tree, resolves specificity and source order in `CascadeBuilder`, and applies a focused typed property registry. It exposes the computed box-model shape as a mutable `CascadeStyle` resource. `CascadeBox` and owned components consume it and react to draw, measure, and arrange invalidation flags. A later computed-style layer will produce immutable snapshots of this same property surface.

Type, class, ID, combined-compound, and descendant selectors work today. Selector lists, direct-child and sibling combinators, inheritance, variables, and computed-style caching do not. Unsupported values are diagnosed rather than retained as arbitrary CSS. The exact matrix lives in [current-support.md](current-support.md).

### Interactive state

Pseudo-state selectors are parsed separately from base declarations. The builder resolves interactive state declarations into explicit appearance properties. Owned `BaseButton` components then use a shared adapter to normalize native disabled, pressed, checked/selected, hover, and focus state during drawing; they do not rematch the stylesheet on every pointer event.

The shared precedence is disabled, pressed, checked/selected, hover, focus, then base. Focus-ring drawing is layered independently so keyboard focus remains visible while another state wins. `:open` and select-option state remain part of the upcoming composite-select slice.

### Layout engine

Layout has two conceptual passes:

1. **Measure** computes desired sizes from constraints and intrinsic content.
2. **Arrange** assigns final rectangles to boxes and their children.

`FlexLayoutEngine` consumes plain layout requests and item value objects and produces rectangles without touching the scene tree. `CascadeBox` is the native `Container` adapter: it measures children, translates `CascadeStyle` and compatibility metadata into engine values, then applies the resulting rectangles. Grid, stack, and absolute positioning will use parallel engine boundaries rather than adding unrelated policy to `CascadeBox`.

### Data binding

Exact `{dot.separated.path}` attribute values are stored as metadata on the generated native control. `BindingResolver` traverses dictionaries, arrays, or Godot object properties only; it does not evaluate expressions or invoke methods. `CascadeDocument` applies bindings after initial construction and after reconciliation, so authored reloads and data refreshes share stable native instances. Assigning a context refreshes immediately, while nested state changes use the explicit `refresh_bindings()` boundary until reactive adapters are introduced.

### Reconciler

The reconciler compares the previous logical tree with the next one, then applies the smallest practical set of mutations to native nodes. It must preserve runtime state—especially focus, line-edit selection, scroll position, animation state, and user signal connections—whenever element identity is stable.

`CascadeDocument` builds each source revision as an off-tree candidate. If parsing and construction succeed, `CascadeReconciler` matches controls by explicit `id` or structural fallback key and copies authored properties into compatible native instances. This preserves focus, runtime state, and user signal connections. Incompatible or removed elements are replaced narrowly; an invalid candidate is discarded so the last valid tree stays interactive. Parsed elements use weak parent links, allowing descendant selector matching without reference cycles.

The runtime watcher compares source-content signatures rather than filesystem timestamps, avoiding timestamp-resolution and editor atomic-save differences. It polls on a configurable interval and uses the same transactional reload path as explicit reloads.

### Godot adapter

The adapter owns control factories, property conversion, theme integration, input-state observation, and intrinsic measurement. Godot-specific behavior should terminate here instead of leaking into parsers or rule matching.

Core components use Godot's lowest useful behavioral primitive while owning their box model and drawing. For example, `CascadeButton` derives from `BaseButton` rather than adapting Godot's themed `Button`. Ordinary native controls already participate in layout through compatibility metadata; explicit exact, adapted, or layout-only diagnostics remain planned. See [ADR 0001](decisions/0001-owned-core-controls.md).

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
- Percentages are not accepted in the current length subset.
- Unsupported properties produce diagnostics instead of being silently stored.
- Native control minimum sizes participate in measurement.
- Theme resolution remains available to ordinary/adapted native controls; exact owned components use their explicit Cascade appearance surface.
- Arranged rectangles round their leading and trailing edges independently by default, so adjacent boundaries remain stable; containers may opt into subpixel output.
- Overflow is explicit (`visible` or `clip`) and never inferred from a control type.

## Threading

Godot scene-tree mutation remains on the main thread. Tokenization, parsing, selector indexing, and other pure-data work may move off-thread later, but only immutable results cross back to the runtime adapter.

## Compatibility policy

During the prototype phase, APIs may change without migration support. Before the first public preview, the project should declare a minimum Godot version, source-format versioning, a runtime API deprecation window, and import compatibility expectations.
