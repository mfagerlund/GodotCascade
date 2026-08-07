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
<Button disabled="{saving}">Save</Button>
<Select selected="{quality}">…</Select>
```

The current one-way surface is:

| GXML element | Bound attributes |
| --- | --- |
| `Label`, `Button`, `TextInput` | `text` |
| `TableHeaderCell`, `TableCell` | `text` |
| `Progress`, `Slider` | `min`, `max`, `value` |
| Any visual element | `visible` |
| Any element | `class` as a space-separated `String` or class-name Array |
| Interactive controls | `disabled` |
| `Checkbox`, `Switch`, `RadioButton`/`Radio` | `checked` |
| `Select` | `selected` by option value |
| `Image` | `src` as a `Texture2D` or resource path |

Boolean targets require actual boolean model values; strings such as `"false"` are diagnosed rather than coerced. A bound `class` value participates in selector matching. Changing it rebuilds an off-tree candidate and performs keyed reconciliation so descendant selectors and computed styles update while compatible native controls keep identity. Other state targets update directly in place.

Assigning a new `binding_context` refreshes automatically. The simplest explicit boundary after mutating a nested value is `refresh_bindings()`:

```gdscript
model.scale = 115.0
refresh_bindings()
```

The update changes compatible controls in place. It does not rebuild a non-repeated document or replace user-created signal connections.

### Named-path invalidation

For models with many independent bindings, wrap the same typed object or Dictionary in `ObservableBindingContext`:

```gdscript
const ObservableBindingContext := preload(
    "res://addons/godot_cascade/runtime/observable_binding_context.gd"
)

var model := SettingsViewModel.new()
var observable := ObservableBindingContext.new(model)

func _ready() -> void:
    binding_context = observable
    super()

func set_scale(value: float) -> void:
    model.scale = value
    observable.invalidate("scale")
```

`invalidate(path)` emits synchronously and a non-repeated `CascadeDocument` reapplies only bindings whose path overlaps the invalidated path. Parent and child paths overlap: invalidating `settings` refreshes `settings.profile`, while invalidating `settings.profile.name` also refreshes a control bound to `settings.profile`. Use `invalidate_many(PackedStringArray([...]))` to coalesce several paths, or `invalidate_all()` for the full boundary. `CascadeDocument.refresh_binding_paths()` exposes the same targeted operation without a wrapper.

Paths use the existing identifier/numeric-segment grammar. Expressions, method calls, wildcards, and property interception are not introduced. The adapter does not watch mutations or perform dependency tracking; application code remains responsible for naming what changed. A document containing `Repeat` conservatively rebuilds its candidate tree and performs keyed reconciliation after adapter invalidation because a collection change may alter native topology.

## Conditional rendering

Any non-root visual element may use one exact boolean condition:

```xml
<Label if="{session.connected}">Connection established</Label>
```

`if` accepts only an exact `{dot.separated.path}` resolving to a boolean. A false value omits the element and its subtree from the native candidate; a true value builds it normally. Missing paths and non-boolean values produce diagnostics and omit the branch. Literal truthiness, negation, comparisons, method calls, compound expressions, and `else` branches are not supported.

The document records conditional dependencies even while their controls are absent. Invalidating a condition path rebuilds an off-tree candidate and performs keyed reconciliation, preserving compatible siblings. A branch removed by a false condition is genuinely freed; if later reintroduced, its controls are newly created rather than cached with hidden editing state.

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

## Typed C# code generation

Godot .NET projects can opt into a generated, compile-time-checked binding layer. This is separate from runtime `{path}` resolution: `@Name` refers to a declared generated binding, and the generated partial calls getter and setter methods implemented in the permanent companion partial.

Place one non-visual `Bindings` contract anywhere below the GXML root. Every element using a generated binding must have a unique `id`:

```xml
<Page>
    <Bindings
        class="SettingsBindings"
        namespace="MyGame.UI"
        document="CascadeDocument"
        output="SettingsBindings.g.cs"
    >
        <Using namespace="System.Globalization" />
        <Binding name="Profile" type="string" get="GetProfile" set="SetProfile" />
        <Binding name="UiScale" type="double" get="GetUiScale" set="SetUiScale" />

        <Formatter name="Percent" input="double" output="string"><![CDATA[
return $"{value:0}%";
        ]]></Formatter>

        <Parser name="ParsePercent" input="string" output="double"><![CDATA[
return double.TryParse(
    value.Trim().TrimEnd('%'),
    NumberStyles.Float,
    CultureInfo.InvariantCulture,
    out result
);
        ]]></Parser>
    </Bindings>

    <TextInput id="profile" bind-text="@Profile" />
    <Slider id="scale" min="75" max="125" bind-value="@UiScale" />
    <Label id="scale-label" text="@UiScale" format-text="Percent" />
    <TextInput id="scale-entry" bind-text="@UiScale" parse-text="ParsePercent" />
</Page>
```

Generate the disposable partial from the project root:

```powershell
godot --headless --path . --script res://addons/godot_cascade/codegen/csharp_binding_generator.gd -- res://ui/settings.gxml
```

An explicit second argument overrides the contract's `output` path. Relative output paths are resolved beside the GXML file. Generation fails on missing declarations, duplicate names or IDs, writable bindings without setters, and unknown formatters or parsers.

The generated class derives from `Control` and expects its `CascadeDocumentPath`—`CascadeDocument` by default—to locate a child `CascadeDocument`. It owns `_Ready()`, connects to `document_reloaded`, reconnects native writable signals after hot reload, and exposes `RefreshGeneratedBindings()` for application-driven changes.

Generated one-way `@Name` targets currently cover `text`, `min`, `max`, `value`, `checked`, `selected`, `visible`, and `disabled`. Runtime `{path}` additionally supports bound `class` and `Image.src`; those two require runtime resource loading or selector rematching and are intentionally not generated C# targets.

Implement the required partial methods in the permanent file:

```csharp
using Godot;

namespace MyGame.UI;

public partial class SettingsBindings
{
    private readonly SettingsState _settings = new();

    private partial string GetProfile() => _settings.Profile;
    private partial void SetProfile(string value) => _settings.Profile = value;

    private partial double GetUiScale() => _settings.UiScale;
    private partial void SetUiScale(double value) => _settings.UiScale = value;

    partial void OnGeneratedBindingsReady()
    {
        GD.Print("Bindings connected");
    }
}
```

Getter and setter signatures are emitted from the declared C# type. Missing implementations, incompatible parser results, and unsupported values therefore fail in the C# compiler instead of becoming runtime reflection failures. The optional `OnGeneratedBindingsReady()` partial hook replaces a user `_Ready()` override because the generated partial owns that lifecycle method.

Formatter and parser bodies are user source copied verbatim into private static generated methods. `Formatter` receives `value` and returns its declared output type. `Parser` receives `value`, writes `result`, and returns `bool`. The generator surrounds both bodies with `#line` directives, so C# compiler diagnostics point back to the GXML file. CDATA is required so C# operators and generic syntax do not need XML escaping.

The editor and runtime parser never compile or execute inline C#. Changing the binding contract, formatter, or parser requires regeneration and a normal .NET build; ordinary GXML/GCSS visual edits retain the existing live-reload behavior.

The complete checked example consists of the [GXML contract](../examples/codegen/settings_bindings.gxml), [generated partial](../examples/codegen/SettingsBindings.g.cs.txt), and [user-owned partial](../examples/codegen/SettingsBindings.cs.txt). The repository uses `.txt` for the two C# samples because its own showcase project remains GDScript-only; remove that suffix in a Godot .NET project.

## Dynamic C# integration

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

Dynamic path binding does not reflect over arbitrary plain C# objects. Use Godot-visible object properties or the generated partial-method contract above.

## Intentional limits

The current binding language does not support:

- arbitrary expressions or method calls in GXML;
- string interpolation;
- converters or formatting functions in dynamic `{path}` bindings;
- computed dependency tracking;
- implicit write-back from ordinary attributes;
- automatic notification after nested model mutation;
- creation of missing paths;
- replacing a whole repeated item through `item`;
- reflection over arbitrary C# POCO properties.

Keep simple paths in dynamic GXML bindings. Generated C# bindings may use declared getters, setters, formatters, and parsers, but persistence and business decisions still belong in the user-owned partial.

See the executable [settings showcase source](../examples/showcase/settings_menu/interface.gxml), its [document controller](../examples/showcase/settings_menu/settings_menu_document.gd), and the exact [current support reference](current-support.md).
