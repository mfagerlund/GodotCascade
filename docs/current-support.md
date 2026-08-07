# Current support reference

This page documents the executable subset on `main`. GodotCascade borrows productive concepts from HTML and CSS, but unsupported web syntax is diagnosed rather than silently accepted.

## GXML elements

| Element | Native implementation | Notes |
| --- | --- | --- |
| `Page` | `CascadeBox` | Column layout by default; useful as a document root |
| `Row` | `CascadeBox` | Row layout by default |
| `Column` | `CascadeBox` | Column layout by default |
| `Grid` | `CascadeGrid` | Fixed, fractional, content, and min/max tracks with explicit or automatic placement |
| `Stack` | `CascadeStack` | Overlay layout with an absolute-inset escape hatch |
| `Panel` | `CascadePanel` | Semantic styled `CascadeBox` |
| `Label` | `CascadeLabel` | Owned outer box with an internal native `Label` |
| `Button` | `CascadeButton` | Owned drawing on `BaseButton` behavior |
| `Checkbox` | `CascadeCheckbox` | Owned indicator and label on native toggle behavior |
| `RadioButton` / `Radio` | `CascadeRadioButton` | Owned indicator and label with native `ButtonGroup` exclusivity |
| `Switch` | `CascadeSwitch` | Checkbox semantics with owned track and thumb drawing |
| `Select` | `CascadeSelect` | Owned closed control with native popup, options, and keyboard navigation |
| `Option` | Select option data | Valid only as a direct authored child of `Select` |
| `Slider` | `CascadeSlider` | Native range semantics with owned track, fill, thumb, and pointer/keyboard input |
| `TextInput` / `Input` | `CascadeTextInput` or `CascadeTextArea` | Adapted native `LineEdit`; `multiline="true"` selects `TextEdit` |
| `Progress` | `CascadeProgress` | Owned horizontal track, fill, range, and box model |
| `Image` | `CascadeImage` | Texture resource rendering with contain, cover, fill, or intrinsic crop geometry |
| `Repeat` | `CascadeBox` plus expanded template | One child template repeated from an array binding with optional item key |
| `Scroll` | `CascadeScroll` | Adapted native `ScrollContainer` with automatic vertical overflow |
| `Table` | `CascadeTable` | Shared column measurement across semantic header and body rows |
| `TableHeader` / `TableBody` | `CascadeTablePart` | Non-focusable semantic row groups |
| `TableRow` | `CascadeTablePart` | Non-focusable semantic row container arranged by its table |
| `TableHeaderCell` / `TableCell` | `CascadeTableCell` | Owned box/text cell with optional authored native content |

Every element accepts `id`, `class`, `accessible-label`, and `accessible-description`. Text-bearing controls use their visible text as the native accessibility name when no explicit label is authored. `Label`, `Button`, `Checkbox`, `RadioButton`, `Switch`, `TableHeaderCell`, and `TableCell` accept text as element content or through a `text` attribute. Interactive controls accept boolean `disabled`; toggle controls accept boolean `checked`; radio buttons use `group` to share a native `ButtonGroup`. `Select` accepts `selected` as an option value or zero-based index; `Option` accepts `value` and boolean `disabled`. `Progress` and `Slider` accept numeric `min`, `max`, and `value`; `Slider` also accepts a positive `step`. `TextInput` accepts `text`, `placeholder`, boolean `read-only`, `disabled`, `required`, and `multiline`, non-negative `max-length`, a Godot regular-expression `pattern`, and `error-message`. `secret` is supported only by the single-line adapter and is an error with `multiline="true"`. `Image` requires a `src` path that loads a Godot `Texture2D` resource.

Unknown elements are build errors unless their native factory is registered through `ComponentRegistry`. `Window` is not implemented.

`Scroll` requires exactly one content child. It disables horizontal scrolling, adds a native vertical scrollbar when that child's intrinsic height exceeds the available viewport, and maps the supported box-model appearance through Godot's `ScrollContainer` panel style.

### Tables

`Table` accepts `TableHeader`, `TableBody`, direct `TableRow`, or a `Repeat` whose single template is `TableRow`. Header and body groups accept rows or repeated rows. A row accepts only `TableHeaderCell` and `TableCell`. Invalid structure is a build error.

```xml
<Table accessible-label="Flight leaderboard">
    <TableHeader>
        <TableRow>
            <TableHeaderCell>Rank</TableHeaderCell>
            <TableHeaderCell>Pilot</TableHeaderCell>
            <TableHeaderCell>Rating</TableHeaderCell>
        </TableRow>
    </TableHeader>
    <TableBody>
        <Repeat items="{entries}" key="id">
            <TableRow>
                <TableCell text="{item.rank}" />
                <TableCell text="{item.pilot}" />
                <TableCell text="{item.rating}" />
            </TableRow>
        </Repeat>
    </TableBody>
</Table>
```

`grid-template-columns` on `Table` uses the existing fixed (`80px`), content (`auto`), fractional (`1fr`), and `minmax()` track grammar. When omitted, the table infers one content track for each cell in its widest row. `column-gap`, `row-gap`, and one- or two-value `gap` are supported. Every row uses the same resolved column widths; row heights remain content-sized. `grid-template-rows`, cell spanning, and per-row column definitions are intentionally unsupported.

Cells accept direct text, `text`, one-way text bindings, accessibility attributes, and authored child controls. Authored children fill the cell content box and retain their own keyboard behavior. Table structure and cells are not focusable themselves, so interactive cell contents remain in ordinary document focus order. Header/cell semantic roles are retained as `cascade_table_role` metadata; native accessibility names and descriptions remain available through the normal attributes. Style the table and cells for exact padding, background, border, size, color, and font behavior. Header/body/row structural nodes support background and border painting but do not introduce padding or independent sizing.

This is a semantic display table, not a data-grid widget. Wrap it in `Scroll` when repeated rows may exceed the available height. Sorting and row reordering remain application-level operations, as demonstrated by the leaderboard showcase; row/cell selection, column resizing/reordering, sticky headers, pagination, and virtualization remain application-level or future component work.

## Bindings

For an end-to-end explanation and application examples, see the dedicated [binding guide](bindings.md).

An entire supported attribute value may be an exact property-path binding:

```xml
<Label text="{player.name}" />
<Progress min="0" max="100" value="{player.health}" />
```

The one-way property-binding surface is:

- `text` on `Label`, `Button`, `TextInput`, `TableHeaderCell`, and `TableCell`;
- `min`, `max`, and `value` on `Progress` and `Slider`.

`BindingResolver` traverses typed Godot object properties, Arrays using numeric path segments, and Dictionaries. Typed `RefCounted` or `Resource` models are recommended for application state; Dictionaries remain useful for JSON-shaped data and prototypes. The resolver does not execute expressions or call methods. Assigning a new `CascadeDocument.binding_context` refreshes automatically. After nested mutations, call `refresh_bindings()` or wrap the model in `ObservableBindingContext` and call `invalidate("named.path")`; exact, parent, and child dependencies are refreshed without polling. Repeated documents still reconcile when a named path is invalidated because collection topology may have changed.

`Repeat` accepts an array path through `items="{path}"`; its template can bind through local `item` and `index` scopes while retaining access to root paths. A `key` path relative to each item enables identity-preserving reorder/add/remove reconciliation.

Form write-back is explicit and reuses the same exact path grammar:

```xml
<TextInput bind-text="{settings.profile}" />
<Checkbox bind-checked="{settings.shadows}">Dynamic shadows</Checkbox>
<Slider bind-value="{settings.scale}" min="75" max="125" />
<Select bind-selected="{settings.quality}">…</Select>
```

`bind-text`, `bind-checked`, `bind-value`, and `bind-selected` initialize from the context and assign native changes back to an existing Dictionary key, Array index, or Godot object property. Successful writes emit `binding_value_changed` and refresh dependent one-way bindings. Missing paths produce diagnostics and are never created implicitly. Inside `Repeat`, nested `item.<path>` targets the current backing item and follows keyed reorders; `index` and whole-item replacement are intentionally read-only.

`on-<signal>="method_name"` connects a native signal to `CascadeDocument.event_context`, an object-valued binding context, or the document itself. Authored connections are refreshed without disturbing user signal connections. See [markup and state](markup-and-state.md).

### Generated C# bindings

A GXML document may include one non-visual `Bindings` contract for optional Godot .NET code generation. `@Name` on supported one-way and `bind-*` attributes selects a declared typed binding instead of a dynamic property path. Every generated-bound element requires a unique `id`.

`Binding` declarations support a C# `type`, required getter method, and optional setter method. `Formatter` and `Parser` declarations copy CDATA bodies verbatim into the generated partial class with GXML `#line` mappings. The generated class owns native signal wiring, `RefreshGeneratedBindings()`, and reconnection through `CascadeDocument.document_reloaded`; the permanent companion partial implements the declared methods. This does not add arbitrary expression evaluation to runtime GXML. See [Bindings](bindings.md#typed-c-code-generation) for the exact syntax and command.

Interpolation such as `"Health: {player.health}"`, converters in dynamic path bindings, computed assignments, and implicit write-back from ordinary attributes are not supported. Generated C# bindings provide explicit typed getters, setters, formatters, and parsers as a separate compile-time path.

## Selectors

Supported selector forms:

```css
Button { }
.primary { }
#save { }
.dialog Button { }
Panel.card .title { }
Panel.card > .title { }
```

Type, class, ID, combined compounds, descendant matching, and the direct-child combinator (`>`) participate in specificity and source order. Selector lists, sibling combinators, attribute selectors, `:not()`, and other functional selectors are not supported.

`color` and `font-size` inherit through the authored element tree. Authors may use the explicit `inherit` keyword; a root-level `inherit` falls back to the component default.

## Pseudo states

The parser recognizes `:hover`, `:pressed`, `:checked`, `:focused`, `:focus-visible`, `:disabled`, `:selected`, `:open`, and `:invalid`. Runtime state styling is implemented for owned `BaseButton` controls, select options, sliders, and the adapted text input:

| Selector | Supported declarations | Runtime source |
| --- | --- | --- |
| `:hover` | `background`, `background-color` | Native pointer hover on interactive controls and owned layout containers |
| `:pressed` | `background`, `background-color` | Native activation press |
| `:checked` / `:selected` | `background`, `background-color`, `color` | Native toggle selection; `:selected` is the style alias |
| `:focused` | `border-color`, `border-width` | Native focus state |
| `:focus-visible` | `border-color`, `border-width` | Keyboard/controller focus modality on interactive controls |
| `:disabled` | `background`, `background-color`, `color` | Native disabled state |
| `TextInput:invalid` | `background`, `background-color`, `color`, `border-color` | Required/pattern validation result |
| `Select:open` | `background`, `background-color` | Visible option popup |
| `Option:selected` | `background`, `background-color`, `color` | Current select option |

Unlike a browser, state rules are resolved into typed component state properties during the build. Native Godot state changes then select the appropriate drawing dynamically. State precedence is `disabled` → `pressed` → `checked`/`selected` → `hover` → `focus` → base; focus-ring drawing remains visible alongside other states. `:pressed` is the GodotCascade equivalent of HTML `:active`.

On `Slider`, a `:hover` background declaration colors the unfilled owned track while the pointer is inside the control. The owned filled track and thumb also brighten together so the complete slider has visible hover feedback.

`Page`/`Row`/`Column`/`Panel`, `Grid`, and `Stack` accept `:hover` background declarations without becoming focusable or clickable. Other pseudo states on non-interactive containers remain unsupported. There is no pseudo-state animation support; reconciliation-time style transitions are documented below. Pseudo-state declarations on unsupported controls warn.

### Input behavior

Owned interactive controls retain native `BaseButton` input behavior. Pointer press/release and the focused `ui_accept` action activate buttons and toggles; this covers keyboard acceptance and mapped controller buttons. Checkbox and switch activation toggles their checked state, radio buttons update their native group selection, and disabled controls ignore activation. The document wires linear next/previous focus order after reconciliation; controller directional navigation continues to use Godot's native behavior. Its accessibility audit warns about unnamed interactive controls and undescribed images.

The text adapters delegate caret movement, selection, clipboard, undo/redo, context menus, shaping, bidi, IME, and native accessibility behavior to Godot `LineEdit`/`TextEdit`; password masking is single-line-only. GodotCascade preserves single-line text/caret/selection and multiline text/primary-caret/selection/scroll across compatible keyed reloads, and owns required/pattern validation plus adapted box styles. Call `CascadeDocument.validate()` to publish validation diagnostics before committing a form.

When a select popup is open, `ui_up` and `ui_down` move through enabled options, `ui_accept` commits the highlighted option, and `ui_cancel` closes the popup. Pointer selection uses the same option path. Authors should provide `accessible-label` whenever visible text alone does not describe a control's purpose.

## GCSS properties

| Category | Properties and values |
| --- | --- |
| Flow | `display: flex`, `flex-direction: row\|column`, `flex-wrap: wrap\|nowrap` |
| Distribution | `justify-content: start\|center\|end\|space-between\|space-around\|space-evenly` |
| Alignment | `align-items: start\|center\|end\|stretch`, `align-self: auto\|start\|center\|end\|stretch` |
| Spacing | one- or two-value `gap`, one-to-four-value `padding`/`margin`, and individual gap/padding/margin edges |
| Grid | `grid-template-columns`, `grid-template-rows`, `column-gap`, `row-gap`, `grid-column`, `grid-row` |
| Position | `position: relative\|absolute`, `left`, `top`, `right`, `bottom` within `Stack` |
| Size | `width`, `height`, `min-width`, `min-height`, `max-width`, `max-height`, `flex-grow` |
| Box | `background`, `background-color`, `border`, `border-color`, `border-width`, `border-radius`, `overflow` |
| Text | `color`, `font-size` on controls exposing the corresponding property |
| Range display/input | `fill-color` on `Progress` and `Slider` |
| Image | `object-fit: contain\|cover\|fill\|none` |
| Transition | `transition: <property> <time>`, `transition-property`, `transition-duration` for reconciliation-time style changes |

Lengths accept bare numbers, `px`, `vw`, or `vh`. The typed value layer recognizes seconds and milliseconds for transitions. Percentages, `em`/`rem`, `calc()`, variables, and automatic values are not implemented. `padding` and `margin` accept the familiar one-to-four-value form; `gap` accepts row and optional column values. `border` must be `<width> solid <color>`. Shorthands expand before cascade winner selection.

Top-level `@media (min-width: <px>)` and `@media (max-width: <px>)` blocks condition rules on the document viewport. Compound queries, orientation, and nested media blocks are unsupported.

Unsupported properties produce warnings; unsupported values for known properties generally produce errors and prevent a document swap.

## Layout behavior

- Flex rows and columns support wrapping, gaps, growth, main-axis distribution, cross-axis alignment, and `align-self`.
- Grid tracks accept fixed lengths, `fr`, `auto`/`content`, and `minmax(<length>, <length-or-fr>)`; children are placed row-major unless `grid-column` or `grid-row` specifies a one-based start and optional `span`.
- `Stack` overlays normal children across its content box. Children using `position: absolute` may use pixel `left`, `top`, `right`, and `bottom` insets; opposing insets stretch that axis.
- Every Cascade-owned element uses the same padding, margin, border, preferred/min/max size, and overflow model.
- Margins do not collapse.
- Final rectangles are pixel-snapped by rounding leading and trailing edges independently.
- `overflow` supports `visible`, `clip`, and `hidden` as an alias for clipping.
- Percentages and flex shrink/basis shorthands are outside the current preview surface.

## Component support

Implemented exact components are `CascadeBox`, `CascadeGrid`, `CascadeStack`, `CascadePanel`, `CascadeLabel`, `CascadeImage`, `CascadeButton`, `CascadeCheckbox`, `CascadeRadioButton`, `CascadeSwitch`, `CascadeSelect`, `CascadeSlider`, `CascadeProgress`, `CascadeTable`, and `CascadeTableCell`. `CascadeTablePart` is structural. `CascadeScroll`, `CascadeTextInput`, and `CascadeTextArea` are adapted: native `ScrollContainer`, `LineEdit`, and `TextEdit` own scrolling or editing behavior while Cascade maps each documented style surface. Exact means GodotCascade owns the supported measurement and visual semantics.

Ordinary Godot `Control` children are layout-only by default. Integrations can declare an adapted property surface; `CompatibilityRegistry` reports warnings for inexact or unsupported visual mappings while permitting layout properties. See the [compatibility tier reference](compatibility-tiers.md) and [ADR 0001](decisions/0001-owned-core-controls.md).

## Hot reload

`CascadeDocument` watches GXML and GCSS contents during development. A valid edit is built off-tree and reconciled by explicit `id` or structural key. Compatible native instances retain focus, signals, and runtime state. Invalid edits publish diagnostics and leave the last valid UI interactive.

Authored transition metadata animates supported CascadeStyle target changes during reconciliation. Interruptions start from the currently sampled value. See [production readiness](production-readiness.md).

Use an `id` when an element must retain identity after sibling reordering. Unkeyed elements use their structural path and are intended for stable local structure.

## Editor tooling

The editor plugin imports `.gxml`/`.gcss` sources into diagnostic resources and adds the **Cascade Preview** dock. The dock provides a watched native preview, error/warning status, hierarchy/style/layout rows, and GXML source navigation. Generated controls expose element metadata and resolved rectangles through a custom Inspector summary. See the [editor tooling guide](editor-tooling.md).

## HTML migration expectations

The migration target is semantic, not source-compatible:

| HTML/CSS intent | GodotCascade today |
| --- | --- |
| Flex row or column | `Row`/`Column` plus focused flex declarations |
| `button` | `Button` → `CascadeButton` |
| checkbox | `Checkbox` → `CascadeCheckbox` |
| grouped radio input | `RadioButton group="…"` → `CascadeRadioButton` + `ButtonGroup` |
| switch input | `Switch` → `CascadeSwitch` |
| select input | `Select` + `Option` → `CascadeSelect` + native popup |
| single-line text input | `TextInput` → adapted native `LineEdit` |
| multiline textarea | `TextInput multiline="true"` → adapted native `TextEdit` |
| `progress` | `Progress` → `CascadeProgress` |
| Application data | Exact one-way `{path.to.value}` or explicit writable `bind-*="{path}"` attributes |
| `:hover`/`:active` button appearance | `:hover`/`:pressed` |
| Arbitrary HTML, scripts, DOM APIs | Not a goal |

The [parity showcase](showcase/index.html) keeps the HTML reference, GXML/GCSS translation, native scene, and Godot capture together so differences remain visible.
