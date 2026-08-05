# Current support reference

This page documents the executable subset on `main`. GodotCascade borrows productive concepts from HTML and CSS, but unsupported web syntax is diagnosed rather than silently accepted.

## GXML elements

| Element | Native implementation | Notes |
| --- | --- | --- |
| `Page` | `CascadeBox` | Column layout by default; useful as a document root |
| `Row` | `CascadeBox` | Row layout by default |
| `Column` | `CascadeBox` | Column layout by default |
| `Panel` | `CascadePanel` | Semantic styled `CascadeBox` |
| `Label` | `CascadeLabel` | Owned outer box with an internal native `Label` |
| `Button` | `CascadeButton` | Owned drawing on `BaseButton` behavior |
| `Checkbox` | `CascadeCheckbox` | Owned indicator and label on native toggle behavior |
| `RadioButton` / `Radio` | `CascadeRadioButton` | Owned indicator and label with native `ButtonGroup` exclusivity |
| `Switch` | `CascadeSwitch` | Checkbox semantics with owned track and thumb drawing |
| `Select` | `CascadeSelect` | Owned closed control with native popup, options, and keyboard navigation |
| `Option` | Select option data | Valid only as a direct authored child of `Select` |
| `Slider` | `CascadeSlider` | Native range semantics with owned track, fill, thumb, and pointer/keyboard input |
| `Progress` | `CascadeProgress` | Owned horizontal track, fill, range, and box model |

Every element accepts `id`, `class`, `accessible-label`, and `accessible-description`. Text-bearing controls use their visible text as the native accessibility name when no explicit label is authored. `Label`, `Button`, `Checkbox`, `RadioButton`, and `Switch` accept text as element content or through a `text` attribute. Interactive controls accept boolean `disabled`; toggle controls accept boolean `checked`; radio buttons use `group` to share a native `ButtonGroup`. `Select` accepts `selected` as an option value or zero-based index; `Option` accepts `value` and boolean `disabled`. `Progress` and `Slider` accept numeric `min`, `max`, and `value`; `Slider` also accepts a positive `step`.

Unknown elements are build errors. `Window`, `Grid`, `Stack`, `TextInput`, `Image`, repeated elements, and custom components are not implemented yet.

## Bindings

An entire supported attribute value may be an exact property-path binding:

```xml
<Label text="{player.name}" />
<Progress min="0" max="100" value="{player.health}" />
```

The current binding surface is:

- `text` on `Label` and `Button`;
- `min`, `max`, and `value` on `Progress`.

`BindingResolver` traverses Dictionaries, Arrays using numeric path segments, and Godot object properties. It does not execute expressions or call methods. Assigning a new `CascadeDocument.binding_context` refreshes automatically; nested mutations require `refresh_bindings()`.

Interpolation such as `"Health: {player.health}"`, two-way binding, collection repetition, converters, and event-to-method binding are not supported.

## Selectors

Supported selector forms:

```css
Button { }
.primary { }
#save { }
.dialog Button { }
Panel.card .title { }
```

Type, class, ID, combined compounds, and descendant matching participate in specificity and source order. Selector lists, the direct-child combinator (`>`), sibling combinators, attribute selectors, `:not()`, and other functional selectors are not supported.

## Pseudo states

The parser recognizes `:hover`, `:pressed`, `:checked`, `:focused`, `:disabled`, `:selected`, and `:open`. Runtime state styling is implemented for the owned `BaseButton` controls and select options:

| Selector | Supported declarations | Runtime source |
| --- | --- | --- |
| `:hover` | `background`, `background-color` | Native pointer hover |
| `:pressed` | `background`, `background-color` | Native activation press |
| `:checked` / `:selected` | `background`, `background-color`, `color` | Native toggle selection; `:selected` is the style alias |
| `:focused` | `border-color`, `border-width` | Native focus state |
| `:disabled` | `background`, `background-color`, `color` | Native disabled state |
| `Select:open` | `background`, `background-color` | Visible option popup |
| `Option:selected` | `background`, `background-color`, `color` | Current select option |

Unlike a browser, state rules are resolved into typed component state properties during the build. Native Godot state changes then select the appropriate drawing dynamically. State precedence is `disabled` → `pressed` → `checked`/`selected` → `hover` → `focus` → base; focus-ring drawing remains visible alongside other states. `:pressed` is the GodotCascade equivalent of HTML `:active`.

There is no general `Panel:hover`, `:focus-visible`, transition, or animation support yet. Pseudo-state declarations on unsupported controls warn.

### Input behavior

Owned interactive controls retain native `BaseButton` input behavior. Pointer press/release and the focused `ui_accept` action activate buttons and toggles; this covers keyboard acceptance and mapped controller buttons. Checkbox and switch activation toggles their checked state, radio buttons update their native group selection, and disabled controls ignore activation. Focus traversal and controller directional navigation use Godot's native `Control` focus-neighbor behavior.

When a select popup is open, `ui_up` and `ui_down` move through enabled options, `ui_accept` commits the highlighted option, and `ui_cancel` closes the popup. Pointer selection uses the same option path. Authors should provide `accessible-label` whenever visible text alone does not describe a control's purpose.

## GCSS properties

| Category | Properties and values |
| --- | --- |
| Flow | `display: flex`, `flex-direction: row\|column`, `flex-wrap: wrap\|nowrap` |
| Distribution | `justify-content: start\|center\|end\|space-between\|space-around\|space-evenly` |
| Alignment | `align-items: start\|center\|end\|stretch`, `align-self: auto\|start\|center\|end\|stretch` |
| Spacing | `gap`, `padding`, `margin`, and individual padding/margin edges |
| Size | `width`, `height`, `min-width`, `min-height`, `max-width`, `max-height`, `flex-grow` |
| Box | `background`, `background-color`, `border`, `border-color`, `border-width`, `border-radius`, `overflow` |
| Text | `color`, `font-size` on controls exposing the corresponding property |
| Range display/input | `fill-color` on `Progress` and `Slider` |

Lengths accept bare numbers or `px`. Percentages, viewport units, `em`/`rem`, `calc()`, variables, and automatic values are not implemented. `padding` and `margin` accept the familiar one-to-four-value form. `border` must be `<width> solid <color>`.

Unsupported properties produce warnings; unsupported values for known properties generally produce errors and prevent a document swap.

## Layout behavior

- Flex rows and columns support wrapping, gaps, growth, main-axis distribution, cross-axis alignment, and `align-self`.
- Every Cascade-owned element uses the same padding, margin, border, preferred/min/max size, and overflow model.
- Margins do not collapse.
- Final rectangles are pixel-snapped by rounding leading and trailing edges independently.
- `overflow` supports `visible`, `clip`, and `hidden` as an alias for clipping.
- Grid, stack/overlay, absolute positioning, percentages, and flex shrink/basis shorthands are roadmap work.

## Component support

Implemented exact components are `CascadeBox`, `CascadePanel`, `CascadeLabel`, `CascadeButton`, `CascadeCheckbox`, `CascadeRadioButton`, `CascadeSwitch`, `CascadeSelect`, `CascadeSlider`, and `CascadeProgress`. Exact means GodotCascade owns the supported measurement and visual semantics.

Ordinary Godot `Control` children can participate in Cascade layout through compatibility metadata, but the exact/adapted/layout-only diagnostic system is not implemented yet. See [ADR 0001](decisions/0001-owned-core-controls.md).

## Hot reload

`CascadeDocument` watches GXML and GCSS contents during development. A valid edit is built off-tree and reconciled by explicit `id` or structural key. Compatible native instances retain focus, signals, and runtime state. Invalid edits publish diagnostics and leave the last valid UI interactive.

Use an `id` when an element must retain identity after sibling reordering. Unkeyed elements use their structural path and are intended for stable local structure.

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
| `progress` | `Progress` → `CascadeProgress` |
| Application data | Exact `{path.to.value}` attributes |
| `:hover`/`:active` button appearance | `:hover`/`:pressed` |
| Arbitrary HTML, scripts, DOM APIs | Not a goal |

The [parity showcase](showcase/index.html) keeps the HTML reference, GXML/GCSS translation, native scene, and Godot capture together so differences remain visible.
