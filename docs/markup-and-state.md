# Markup, collections, events, and components

## Reusable GXML components

Declare a source-level component as a direct child of the document root. A definition is non-visual, has typed `Param` declarations, and contains exactly one visual template root:

```xml
<Page>
    <Component name="SettingsField">
        <Param name="title" type="String" required="true" />
        <Param name="enabled" type="bool" default="true" />
        <Panel class="settings-field" visible="{params.enabled}">
            <Label id="title" text="{params.title}" />
            <Slot />
            <Row class="actions">
                <Slot name="actions"><Label>No actions</Label></Slot>
            </Row>
        </Panel>
    </Component>

    <SettingsField id="graphics" title="Graphics">
        <Switch>Vertical sync</Switch>
        <Button slot="actions">Reset</Button>
    </SettingsField>
</Page>
```

Supported parameter types are `String`, `bool`, `int`, `float`, and `Variant`. Required and default values are mutually exclusive. Literal arguments are checked during construction; an exact binding such as `title="{settings.title}"` is passed through to the template and retains its original dependency path. Template references must occupy the complete value and use `{params.name}`—string interpolation and expressions remain unsupported.

Children without `slot` fill the default `<Slot />`. `slot="name"` fills the matching named slot; slot children in the definition are fallback content. Missing required parameters, unknown parameters or slots, invalid literal types, duplicate declarations, recursion, and undeclared `{params.*}` references are source-located build errors. A component definition must not use `<Slot>` as its template root.

The invocation's `id`, `class`, and `if` are forwarded to the expanded template root. Template elements remain ordinary native controls and selectors match their actual element, class, and local ID; the component tag itself does not create a wrapper or selector boundary.

Local IDs may repeat in separate component instances. Controls expose `cascade_scoped_id` metadata such as `graphics/title`; use `CascadeDocument.get_element_by_scoped_id("graphics/title")` to resolve one. `get_element_by_id("title")` returns `null` when that local ID is ambiguous. Give component instances explicit IDs for stable, readable scopes; an omitted ID receives a source-location scope.

Component scopes participate in reconciliation keys. Compatible controls therefore retain native identity, focus, text, caret, selection, scroll, and signal connections when component parameters, slots, or templates reload. A false `if` still removes its entire branch: its controls are recreated if the condition later becomes true, while keyed siblings—including component instances—remain stable.

Reusable templates support runtime `{path}` and `bind-*` bindings. Generated C# `@Name` bindings are intentionally unsupported inside templates and as component arguments because a single generated member cannot unambiguously address multiple scoped instances.

## Keyed collections

`Repeat` expands exactly one child template for each item in an array binding:

```xml
<Repeat items="{inventory.items}" key="id">
    <Row class="item-row">
        <Label text="{item.name}" />
        <Button text="{item.action}" on-pressed="select_item" />
    </Row>
</Repeat>
```

Inside the template, `item` is the current value and `index` is its current zero-based position. Other paths continue to resolve against the document's root `binding_context`. The optional `key` is a dot-separated path relative to each item. A key is strongly recommended: it preserves native identity, focus, runtime state, and user signal connections when a collection reorders. Duplicate or missing keys are build errors.

Calling `refresh_bindings()` on a document containing `Repeat` rebuilds the candidate tree and performs keyed reconciliation. Non-repeated documents retain the lighter property-only refresh path.

## Writable form bindings

Ordinary `{path}` values are one-way. Form controls opt into write-back with a `bind-*` attribute:

```xml
<TextInput bind-text="{settings.profile}" required="true" />
<Checkbox bind-checked="{settings.shadows}">Dynamic shadows</Checkbox>
<Slider bind-value="{settings.scale}" />
<Select bind-selected="{settings.quality}">…</Select>
```

Ordinary one-way paths also support `visible`, interactive `disabled`, toggle `checked`, `Select.selected`, `Image.src`, and `class`. Class bindings accept a space-separated String or class-name Array and rematch GCSS selectors through keyed reconciliation when changed. Boolean state targets require booleans rather than truthy strings.

Use `if="{state.boolean_path}"` on a non-root element to include or omit its native subtree. This is exact boolean path resolution, not an expression language: comparisons, negation, calls, and `else` are unsupported. Omitted dependencies remain tracked so invalidating the path can reconcile the branch back into the document. Stable siblings keep identity, while controls inside a removed branch are freed.

The path must already resolve to a Dictionary key, Array index, or Godot object property. Native changes assign the value, emit `CascadeDocument.binding_value_changed(path, value, control)`, and refresh other one-way controls. The resolver does not create missing objects, evaluate expressions, call methods, or run converters.

Inside a `Repeat` template, writable bindings may target an existing nested item property such as `bind-checked="{item.enabled}"`. The control carries the current item scope through keyed reconciliation, so a reorder keeps native identity while later edits reach the correct backing item. `index` and bare `item` are read-only: replacing collection entries is an application-level operation rather than an implicit form write.

`CascadeDocument.validate()` asks generated adapted controls to validate and emits `validation_changed`. `TextInput` currently supports `required`, a Godot regular-expression `pattern`, and `error-message`; invalid controls expose the `:invalid` style state.

## Event bindings

An `on-<signal>` attribute connects a native Godot signal to a method on `CascadeDocument.event_context`:

```xml
<Button on-pressed="apply_settings">Apply</Button>
<Slider on-value-changed="set_volume" />
```

Hyphens in the authored signal name become underscores. If `event_context` is unset, an object-valued `binding_context` is used, then the document itself. Invalid signals or method names are build errors; a missing target method is a runtime warning. Reload reconnects only authored event bindings and leaves user-created signal connections untouched.

## Native custom components

Register a factory before the document builds:

```gdscript
const ComponentRegistry := preload("res://addons/godot_cascade/runtime/component_registry.gd")

ComponentRegistry.register(
    "InventoryCard",
    func(): return InventoryCard.new(),
    func(control): control.begin_live_updates(),
    func(control): control.refresh_from_authored_properties(),
    func(control): control.end_live_updates()
)
```

The callbacks are mount, update, and unmount respectively. Mount runs after a new custom control enters the reconciled tree, update runs after authored properties are copied into a compatible keyed instance, and unmount runs before removal or replacement. Descendants authored inside the custom tag are built normally. Factories must return a `Control`; custom controls are layout-only unless their factory declares an adapted compatibility surface or uses an owned exact implementation. This native registry is separate from source-level `<Component>` composition.

Unregistering a tag prevents future builds but does not mutate existing documents. Integrations should remove or reload those documents before unregistering when lifecycle teardown matters.
