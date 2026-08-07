# Architecture

GodotCascade is split into pure data transformations around a narrow Godot adapter. Keeping the core independent from the scene tree makes layout and style behavior deterministic, testable, and usable by editor tooling.

## Runtime pipeline

```text
.gxml ──→ GxmlParser ──→ ComponentExpander ──→ DocumentValidator ──┐
                                                                   ├──→ CascadeBuilder ──→ off-tree candidate Controls
.gcss ──→ GcssParser ──→ DeclarationApplier ─┘               │
binding syntax ─────────→ BindingCompiler ────────────────────┤
                                                             ▼
source watcher ──→ CascadeDocument ──→ CascadeReconciler ──→ live Controls
                                                             │
binding context ──→ BindingResolver ──────────────────────────┤
                                                             ▼
                                                    CascadeBox adapter
                                                             │
                                                             ▼
                                                    FlexLayoutEngine
```

The preview source formats are named `.gxml` and `.gcss`. A future rename would follow the documented preview deprecation and migration policy.

## Subsystems

### Source and diagnostics

Parsers return logical values plus recoverable line/column diagnostics; GCSS tokens carry start/end spans and `CascadeDocument` stamps the source path onto generated controls. Parsing does not create Godot nodes. Higher-level fix suggestions remain an optional diagnostic enhancement.

### Logical element tree

The logical tree represents authored structure before native construction. Elements have type names, attributes, classes, optional IDs, text, parent links, and children. `GxmlComponentExpander` collects root-level reusable definitions, validates typed parameters and slots, substitutes exact `{params.name}` values, and expands instances without introducing native wrapper controls. `DocumentValidator` then rejects duplicate IDs within each component scope and invalid table/scroll relationships. `CascadeBuilder` derives component-qualified explicit-ID or structural keys and creates the candidate native tree, while `BindingCompiler` owns one-way, writable, and event-binding metadata. The logical tree is deliberately smaller than a browser DOM and is not exposed as a general scripting platform.

### Style engine

The style engine indexes rules by the rightmost selector before matching plausible candidates. Computed declarations own specificity, inherited text values, pseudo states, and cache keys while remaining separate from mutable Godot theme resources.

The executable slice tokenizes and parses rules, matches them against the logical element tree, resolves specificity, inherited custom-property environments, source order, and ordinary inheritance in `CascadeBuilder`, and caches immutable computed declaration dictionaries. `GcssExpression` owns lazy `var()` substitution and NUMBER/LENGTH/TIME `calc()` evaluation. `DeclarationApplier` owns shorthand expansion, typed property conversion, focused gradients/transforms/fonts, pseudo-state mapping, and application to native controls. Application exposes the box-model shape as a mutable `CascadeStyle` resource. `CascadeBox` and owned components consume it and react to draw, measure, and arrange invalidation flags.

Type, class, ID, combined-compound, descendant, and direct-child selectors work today. Inherited text/custom properties, case-sensitive `--name` tokens, lazy `var()` fallback, typed `calc()`, and computed-style caching are implemented. Selector lists, sibling combinators, functional selectors, and browser-wide value functions remain outside the focused grammar. Unsupported values are diagnosed rather than retained as arbitrary CSS. The exact matrix lives in [current-support.md](current-support.md).

### Interactive state

Pseudo-state selectors are parsed separately from base declarations. `DeclarationApplier` resolves interactive state declarations into explicit appearance properties. Owned `BaseButton` components then use a shared adapter to normalize native disabled, pressed, checked/selected, hover, and focus state during drawing; they do not rematch the stylesheet on every pointer event.

The shared precedence is disabled, pressed, checked/selected, hover, focus, then base. Focus-ring drawing is layered independently so keyboard focus remains visible while another state wins. Selects add `:open` and option-level selected/hover/disabled state.

### Layout engine

Layout has two conceptual passes:

1. **Measure** computes desired sizes from constraints and intrinsic content.
2. **Arrange** assigns final rectangles to boxes and their children.

`FlexLayoutEngine` and `GridLayoutEngine` consume plain layout requests and item values and produce rectangles without touching the scene tree. `CascadeBox` and `CascadeGrid` are native `Container` adapters that measure children, translate `CascadeStyle` and compatibility metadata into engine values, then apply the resulting rectangles. `CascadeStack` owns overlay and absolute-inset placement without adding unrelated policy to `CascadeBox`.

`CascadeTable` reuses grid track resolution but owns semantic row grouping. It flattens visible cells only for one shared column/row calculation, then projects the resulting rectangles back through `TableHeader`, `TableBody`, repeated row groups, and `TableRow` containers. Cells own their box/text measurement; structural containers remain non-focusable and do not compete with authored interactive cell content.

`CascadeScroll` is a narrow adapter over native `ScrollContainer`. Its minimum-size contract deliberately excludes the content child's height, allowing flex layout to allocate a bounded viewport while Godot owns wheel, touch, scrollbar, focus-following, and clipping behavior.

`FocusManager` validates authored tab/autofocus/trap metadata, derives effective focusability through ancestor visibility and disabled state, and writes deterministic native neighbor paths. `CascadeDocument` reapplies that contract after reconciliation or relevant targeted bindings, redirects escape from an active modal trap through the viewport focus signal, and restores prior focus when the trap closes.

### Data binding

Exact `{dot.separated.path}` attribute values are compiled by `BindingCompiler` into metadata on the generated native control. `BindingResolver` traverses dictionaries, arrays, or Godot object properties only; it does not evaluate expressions or invoke methods. `CascadeDocument` applies bindings after initial construction and after reconciliation, so authored reloads and data refreshes share stable native instances. Assigning a context refreshes immediately. Applications may call the coarse `refresh_bindings()` boundary or wrap their typed model in `ObservableBindingContext` and explicitly invalidate named paths; the latter updates only overlapping dependencies without polling or automatic model observation. Collection invalidation rebuilds only affected retained outer `Repeat` candidates and performs keyed subtree reconciliation; `CascadeItemModel` changes trigger that boundary automatically. Fixed-height virtual repeats additionally materialize only the current window and overscan while native spacer controls preserve the full scroll extent.

`BindingTrace` projects the already-compiled metadata into read-only dependency records and annotates the latest explicit refresh with its trigger, matching paths, targeted/reconcile strategy, reason, affected controls, and reconcile statistics. `DebugSnapshot` and the editor dock consume that projection. The trace is bounded to one event and does not intercept model access, discover dependencies dynamically, or influence refresh policy.

Exact boolean `if="{path}"` conditions are evaluated during candidate construction. The root retains their dependency paths even when a branch is absent, allowing named invalidation to trigger reconciliation without a hidden placeholder node or a general expression runtime.

Godot .NET projects may instead declare `@Name` bindings in a non-visual GXML `Bindings` contract. `CsharpBindingGenerator` emits a disposable partial `Control` class containing node lookup, native signal wiring, refresh logic, and typed partial getter/setter declarations. The permanent companion partial implements those methods. Formatter and parser CDATA bodies are copied into private static methods with `#line` mappings; neither the editor preview nor the runtime parser executes them. `CascadeDocument.document_reloaded` lets generated wiring reconnect after structural hot reload without polling.

### Reconciler

The reconciler compares the previous logical tree with the next one, then applies the smallest practical set of mutations to native nodes. It must preserve runtime state—especially focus, line-edit selection, scroll position, animation state, and user signal connections—whenever element identity is stable.

`CascadeDocument` builds each source revision as an off-tree candidate. If parsing and construction succeed, `CascadeReconciler` matches controls by component-scoped explicit `id`, repeated item key, or structural fallback key and copies authored properties into compatible native instances. This preserves focus, runtime state, and user signal connections across reusable component templates and ordinary authored structure. Incompatible or removed elements are replaced narrowly; an invalid candidate is discarded so the last valid tree stays interactive. Parsed elements use weak parent links, allowing selector matching without reference cycles. `ComponentRegistry` brackets reconciliation with mount/update/unmount callbacks, while the document reconnects only its authored `on-*` signal bindings.

The runtime watcher compares source-content signatures rather than filesystem timestamps, avoiding timestamp-resolution and editor atomic-save differences. It polls on a configurable interval and uses the same transactional reload path as explicit reloads.

The editor plugin reuses those runtime boundaries. Import plugins serialize source text and parser summaries into diagnostic resources; the preview dock hosts a `CascadeDocument` in a `SubViewport`; `DebugSnapshot` projects the generated tree into read-only element, rectangle, style, and source-location rows. The custom Inspector reads the same metadata, so editor tooling does not need a second style or layout implementation.

### Godot adapter

The adapter owns control factories, property conversion, theme integration, input-state observation, and intrinsic measurement. Godot-specific behavior should terminate here instead of leaking into parsers or rule matching.

Core components use Godot's lowest useful behavioral primitive while owning their box model and drawing. For example, `CascadeButton` derives from `BaseButton` rather than adapting Godot's themed `Button`. Ordinary native controls participate in layout through compatibility metadata, while `CompatibilityRegistry` classifies exact, adapted, and layout-only property behavior and emits development warnings for inexact visual mappings. See [ADR 0001](decisions/0001-owned-core-controls.md).

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

The explicit dependency table drives targeted draw, measure, and arrange invalidation; new properties must declare the same impact when added.

## Intentional CSS differences

- Logical pixels map directly to Godot UI units.
- Margins do not collapse.
- Percentages are not accepted in the current length subset.
- Unsupported properties produce diagnostics instead of being silently stored.
- Native control minimum sizes participate in measurement.
- Theme resolution remains available to ordinary/adapted native controls; exact owned components use their explicit Cascade appearance surface.
- Arranged rectangles round their leading and trailing edges independently by default, so adjacent boundaries remain stable; containers may opt into subpixel output.
- Overflow is explicit (`visible` or `clip`) and never inferred from a control type.
- Opacity uses Godot modulation rather than browser group compositing; transforms use Godot 4.7 offset-transform fields and never change layout measurement.
- SVG is an engine-imported native texture, not a DOM, and custom fonts are project-local Godot `Font` resources rather than browser family resolution.

## Threading

Godot scene-tree mutation remains on the main thread. Tokenization, parsing, selector indexing, and other pure-data work may move off-thread later, but only immutable results cross back to the runtime adapter.

## Compatibility policy

The 0.1.0 through 0.8.0 previews target Godot 4.7 and source format version 1. Documented runtime APIs receive a one-preview-minor deprecation window; source imports are derived caches regenerated after addon upgrades. Breaking changes require migration notes and replacement tests.
