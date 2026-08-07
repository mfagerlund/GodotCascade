# Bindings

GodotCascade bindings connect GXML controls to application state without evaluating arbitrary code in markup. The current system deliberately supports exact property paths, explicit form write-back, keyed repeated scopes, and named Godot signal handlers.

## Binding context

Set `CascadeDocument.binding_context` to a nested `Dictionary`, `Array`, or Godot object before loading the document:

```gdscript
extends "res://addons/godot_cascade/runtime/cascade_document.gd"


func _ready() -> void:
    binding_context = {
        "settings": {
            "profile": "Rhea",
            "shadows": true,
            "scale": 100.0,
            "quality": "high",
        },
        "ui": {
            "status": "Change a setting, then apply",
        },
    }
    event_context = self
    binding_value_changed.connect(_on_binding_value_changed)
    super()
```

A path such as `settings.profile` walks the context one segment at a time. Dictionary keys may be `String` or `StringName`; array segments must be numeric indexes; object segments must name Godot-visible properties.

Bindings do not call methods, create missing values, or evaluate expressions.

## One-way bindings

An entire supported attribute value may be an exact brace-wrapped path:

```xml
<Label text="{settings.profile}" />
<Button text="{ui.status}" />
<Progress min="0" max="125" value="{settings.scale}" />
<Slider min="75" max="125" value="{settings.scale}" />
```

The current one-way surface is:

| GXML element | Bound attributes |
| --- | --- |
| `Label`, `Button`, `TextInput` | `text` |
| `Progress`, `Slider` | `min`, `max`, `value` |

Assigning a new `binding_context` refreshes automatically. Mutating a nested value does not notify GodotCascade, so call `refresh_bindings()` afterward:

```gdscript
binding_context["settings"]["scale"] = 115.0
refresh_bindings()
```

The update changes compatible controls in place. It does not rebuild a non-repeated document or replace user-created signal connections.

Interpolation is not supported. This is invalid as a binding:

```xml
<Label text="Scale: {settings.scale}%" />
```

Store a formatted value in the context or update it in code instead:

```gdscript
binding_context["ui"]["scale_label"] = "%d%%" % binding_context["settings"]["scale"]
refresh_bindings()
```

```xml
<Label text="{ui.scale_label}" />
```

## Writable form bindings

Form write-back is explicit through `bind-*` attributes:

```xml
<TextInput bind-text="{settings.profile}" />
<Checkbox bind-checked="{settings.shadows}">Dynamic shadows</Checkbox>
<Switch bind-checked="{settings.vsync}">Vertical sync</Switch>
<Slider bind-value="{settings.scale}" min="75" max="125" />
<Select bind-selected="{settings.quality}">
    <Option value="low">Low quality</Option>
    <Option value="high">High quality</Option>
</Select>
```

| Attribute | Elements | Native change signal | Written value |
| --- | --- | --- | --- |
| `bind-text` | `TextInput` | `text_changed` | `String` |
| `bind-checked` | `Checkbox`, `Switch`, `RadioButton`/`Radio` | `toggled` | `bool` |
| `bind-value` | `Slider` | `value_changed` | numeric value |
| `bind-selected` | `Select` | `selection_changed` | selected option value |

When the user changes a writable control, GodotCascade:

1. Assigns the new value to the existing context path.
2. Emits `binding_value_changed(path, value, control)`.
3. Refreshes every dependent one-way binding.
4. Publishes a diagnostic if the path can no longer be written.

This makes a live echo require no event handler:

```xml
<TextInput bind-text="{settings.profile}" />
<Label text="{settings.profile}" />
```

Typing in the input writes `settings.profile`; the label then refreshes immediately.

The write target must already exist. A binding never invents a missing Dictionary key, array entry, object, or property.

## Reacting in code

Use `binding_value_changed` for derived state or application side effects:

```gdscript
func _on_binding_value_changed(path: String, value: Variant, _control: Control) -> void:
    if path == "settings.scale":
        binding_context["ui"]["scale_label"] = "%d%%" % roundi(float(value))
    binding_context["ui"]["status"] = "Unsaved changes"
```

Writable controls already refresh ordinary one-way bindings after emitting the signal. If the callback adds or changes derived context values, call `refresh_bindings()` when those values must appear immediately. An event handler that mutates context must also refresh explicitly.

## Event bindings

`on-<signal>` connects a native signal to a named method:

```xml
<Button on-pressed="_on_apply_settings">Apply settings</Button>
<Slider on-value-changed="_on_scale_committed" />
```

Hyphens in the authored signal name become underscores. The method target is selected in this order:

1. `CascadeDocument.event_context` when assigned.
2. An object-valued `binding_context`.
3. The `CascadeDocument` itself.

```gdscript
func _on_apply_settings() -> void:
    if not validate():
        binding_context["ui"]["status"] = "Fix invalid fields"
    else:
        binding_context["ui"]["status"] = "Settings applied"
    refresh_bindings()
```

Authored connections are re-established after reload without removing signal connections created by application code.

## Repeated-item scopes

`Repeat` introduces local `item` and `index` values while retaining access to the root context:

```xml
<Repeat items="{settings.channels}" key="id">
    <Checkbox text="{item.label}" bind-checked="{item.enabled}" />
</Repeat>
```

```gdscript
binding_context = {
    "settings": {
        "channels": [
            {"id": "damage", "label": "Damage numbers", "enabled": true},
            {"id": "team", "label": "Team markers", "enabled": false},
        ],
    },
}
```

`bind-checked="{item.enabled}"` writes to the backing item. A `key` preserves native identity when the collection reorders. `index` and bare `item` are read-only; replacing an entire collection item remains application logic.

Because a repeated collection can change tree topology, `refresh_bindings()` rebuilds a candidate document and performs keyed reconciliation when `Repeat` is present.

## Validation

Binding and validation are separate operations. `TextInput` supports required and pattern validation, while `CascadeDocument.validate()` checks generated controls and emits `validation_changed`:

```xml
<TextInput
    bind-text="{settings.profile}"
    required="true"
    pattern="^.{2,16}$"
    error-message="Enter 2–16 characters."
/>
```

```gdscript
if validate():
    save_settings(binding_context["settings"])
```

Invalid input still writes through to the context. Validation decides whether application code accepts the form.

## Diagnostics

Unresolved one-way paths and failed writes produce diagnostics rather than executing fallback code. Observe `diagnostics_changed`, inspect `CascadeDocument.diagnostics`, or use the runnable showcase toolbar and editor preview.

Typical failures include:

- a missing path segment;
- a non-numeric array segment;
- an out-of-range array index;
- a missing Godot-visible object property;
- a non-numeric value bound to a range;
- a `Select` value with no matching option;
- an unsupported `bind-*` attribute on a control.

## C# integration

`CascadeDocument` is currently implemented in GDScript. C# can assign its context and call its public methods through Godot's dynamic object API:

```csharp
private Control _document = null!;
private Godot.Collections.Dictionary _context = null!;

public override void _Ready()
{
    _document = GetNode<Control>("CascadeDocument");
    _context = new Godot.Collections.Dictionary
    {
        ["settings"] = new Godot.Collections.Dictionary
        {
            ["profile"] = "Rhea",
            ["scale"] = 100.0,
        },
    };
    _document.Set("binding_context", _context);
}

private void SetScale(double value)
{
    ((Godot.Collections.Dictionary)_context["settings"])["scale"] = value;
    _document.Call("refresh_bindings");
}
```

Object-backed contexts must expose properties through Godot's property system. GodotCascade does not reflect over arbitrary plain C# objects and does not currently provide Bindot-style typed getter/setter lambdas.

## Intentional limits

The current binding language does not support:

- arbitrary expressions or method calls in GXML;
- string interpolation;
- converters or formatting functions;
- computed dependency tracking;
- implicit write-back from ordinary attributes;
- automatic notification after nested model mutation;
- creation of missing paths;
- replacing a whole repeated item through `item`;
- reflection over arbitrary C# POCO properties.

Keep simple paths in GXML. Put calculations, formatting, persistence, and business decisions in GDScript or C#.

See the executable [settings showcase source](../examples/showcase/settings_menu/interface.gxml), its [document controller](../examples/showcase/settings_menu/settings_menu_document.gd), and the exact [current support reference](current-support.md).
