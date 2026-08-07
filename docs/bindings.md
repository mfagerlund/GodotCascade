# Bindings

GodotCascade bindings connect GXML controls to application state without evaluating arbitrary code in markup. The current system deliberately supports exact property paths, explicit form write-back, keyed repeated scopes, and named Godot signal handlers.

## Binding context

Prefer a typed `RefCounted`, `Resource`, or other Godot object for application state. Script properties are visible to the resolver while the model retains names, types, autocomplete, and refactoring support:

```gdscript
class_name SettingsViewModel
extends RefCounted

var profile := "Rhea"
var shadows := true
var scale := 100.0
var quality := "high"
var status := "Change a setting, then apply"

class ChannelState extends RefCounted:
    var id: String
    var label: String
    var enabled: bool

    func _init(channel_id: String, channel_label: String, channel_enabled: bool) -> void:
        id = channel_id
        label = channel_label
        enabled = channel_enabled

var channels: Array[ChannelState] = [
    ChannelState.new("damage", "Damage numbers", true),
    ChannelState.new("team", "Team markers", false),
]
```

Assign the model before loading the document:

```gdscript
extends "res://addons/godot_cascade/runtime/cascade_document.gd"

var model: SettingsViewModel

func _ready() -> void:
    model = SettingsViewModel.new()
    binding_context = model
    event_context = self
    binding_value_changed.connect(_on_binding_value_changed)
    super()
```

A path such as `profile` walks the context one segment at a time. Models may contain other typed Godot objects and arrays, so `settings.profile` and `players.0.name` are also valid when those segments exist. Object segments must name Godot-visible properties and array segments must be numeric indexes.

`Dictionary` contexts remain supported for parsed JSON, external data, and quick prototypes. Dictionary keys may be `String` or `StringName`; they are not required for ordinary application models.

Bindings do not call methods, create missing values, or evaluate expressions.

## One-way bindings

An entire supported attribute value may be an exact brace-wrapped path:

```xml
<Label text="{profile}" />
<Button text="{status}" />
<Progress min="0" max="125" value="{scale}" />
<Slider min="75" max="125" value="{scale}" />
```

The current one-way surface is:

| GXML element | Bound attributes |
| --- | --- |
| `Label`, `Button`, `TextInput` | `text` |
| `Progress`, `Slider` | `min`, `max`, `value` |

Assigning a new `binding_context` refreshes automatically. Mutating a nested value does not notify GodotCascade, so call `refresh_bindings()` afterward:

```gdscript
model.scale = 115.0
refresh_bindings()
```

The update changes compatible controls in place. It does not rebuild a non-repeated document or replace user-created signal connections.

Interpolation is not supported. This is invalid as a binding:

```xml
<Label text="Scale: {scale}%" />
```

Store a formatted value in the context or update it in code instead:

```gdscript
model.status = "%d%%" % model.scale
refresh_bindings()
```

```xml
<Label text="{status}" />
```

## Writable form bindings

Form write-back is explicit through `bind-*` attributes:

```xml
<TextInput bind-text="{profile}" />
<Checkbox bind-checked="{shadows}">Dynamic shadows</Checkbox>
<Slider bind-value="{scale}" min="75" max="125" />
<Select bind-selected="{quality}">
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
<TextInput bind-text="{profile}" />
<Label text="{profile}" />
```

Typing in the input writes `model.profile`; the label then refreshes immediately.

The write target must already exist. A binding never invents a missing Dictionary key, array entry, object, or property.

## Reacting in code

Use `binding_value_changed` for derived state or application side effects:

```gdscript
func _on_binding_value_changed(path: String, value: Variant, _control: Control) -> void:
    if path == "scale":
        model.status = "%d%%" % roundi(float(value))
    else:
        model.status = "Unsaved changes"
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
        model.status = "Fix invalid fields"
    else:
        model.status = "Settings applied"
    refresh_bindings()
```

Authored connections are re-established after reload without removing signal connections created by application code.

## Repeated-item scopes

`Repeat` introduces local `item` and `index` values while retaining access to the root context:

```xml
<Repeat items="{channels}" key="id">
    <Checkbox text="{item.label}" bind-checked="{item.enabled}" />
</Repeat>
```

`bind-checked="{item.enabled}"` writes to the backing item. A `key` preserves native identity when the collection reorders. `index` and bare `item` are read-only; replacing an entire collection item remains application logic.

Because a repeated collection can change tree topology, `refresh_bindings()` rebuilds a candidate document and performs keyed reconciliation when `Repeat` is present.

## Validation

Binding and validation are separate operations. `TextInput` supports required and pattern validation, while `CascadeDocument.validate()` checks generated controls and emits `validation_changed`:

```xml
<TextInput
    bind-text="{profile}"
    required="true"
    pattern="^.{2,16}$"
    error-message="Enter 2–16 characters."
/>
```

```gdscript
if validate():
    save_settings(model)
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

Use a typed Godot `Resource` or another Godot object for C# state. Exported properties participate in Godot's property system and can therefore be resolved by GodotCascade:

```csharp
using Godot;

[GlobalClass]
public partial class SettingsViewModel : Resource
{
    [Export] public string Profile { get; set; } = "Rhea";
    [Export] public double Scale { get; set; } = 100.0;
}
```

`CascadeDocument` is currently implemented in GDScript, so C# assigns the typed model and calls document methods through Godot's dynamic object API. GXML paths use the property names exposed to Godot—for this model, `{Profile}` and `{Scale}`:

```csharp
private Control _document = null!;
private SettingsViewModel _model = null!;

public override void _Ready()
{
    _document = GetNode<Control>("CascadeDocument");
    _model = new SettingsViewModel();
    _document.Set("binding_context", _model);
}

private void SetScale(double value)
{
    _model.Scale = value;
    _document.Call("refresh_bindings");
}
```

GodotCascade does not reflect over arbitrary plain C# objects and does not currently provide Bindot-style typed getter/setter lambdas.

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
