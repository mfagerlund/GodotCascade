# Markup, collections, events, and custom components

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

The path must already resolve to a Dictionary key, Array index, or Godot object property. Native changes assign the value, emit `CascadeDocument.binding_value_changed(path, value, control)`, and refresh other one-way controls. The resolver does not create missing objects, evaluate expressions, call methods, or run converters. Writable paths inside `Repeat` item scopes are intentionally deferred because collection ownership and write identity need a separate contract.

`CascadeDocument.validate()` asks generated adapted controls to validate and emits `validation_changed`. `TextInput` currently supports `required`, a Godot regular-expression `pattern`, and `error-message`; invalid controls expose the `:invalid` style state.

## Event bindings

An `on-<signal>` attribute connects a native Godot signal to a method on `CascadeDocument.event_context`:

```xml
<Button on-pressed="apply_settings">Apply</Button>
<Slider on-value-changed="set_volume" />
```

Hyphens in the authored signal name become underscores. If `event_context` is unset, an object-valued `binding_context` is used, then the document itself. Invalid signals or method names are build errors; a missing target method is a runtime warning. Reload reconnects only authored event bindings and leaves user-created signal connections untouched.

## Custom components

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

The callbacks are mount, update, and unmount respectively. Mount runs after a new custom control enters the reconciled tree, update runs after authored properties are copied into a compatible keyed instance, and unmount runs before removal or replacement. Descendants authored inside the custom tag are built normally. Factories must return a `Control`; custom controls are layout-only unless their factory declares an adapted compatibility surface or uses an owned exact implementation.

Unregistering a tag prevents future builds but does not mutate existing documents. Integrations should remove or reload those documents before unregistering when lifecycle teardown matters.
