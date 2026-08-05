# GodotCascade

GodotCascade is an experimental retained-mode UI framework for Godot 4. It brings a declarative UI language, CSS-inspired styling, and a predictable box model to native Godot `Control` nodes.

The goal is to make game UI faster to build and easier to maintain without embedding a browser or replacing Godot's renderer. A GodotCascade interface remains a tree of native controls, so it can continue to use Godot's signals, themes, input, rendering, and editor tooling.

> [!IMPORTANT]
> GodotCascade is at the prototype stage. The first layout primitive is usable, but the markup and stylesheet examples below describe the target API and are not implemented yet.

## Why GodotCascade?

Godot's container system is capable, but non-trivial interfaces often require deeply nested scene trees. Spacing can be split between several containers, theme constants, and wrapper controls, making the visual intent difficult to see.

GodotCascade is built around a few ideas:

- one consistent box model for margin, padding, border, and size;
- flex and grid layout without excessive wrapper nodes;
- reusable styles separated from scene structure;
- declarative markup for concise, reviewable interfaces;
- hot reload for short iteration cycles;
- native Godot controls at runtime.

## The intended authoring experience

Markup files use the `.gxml` extension:

```xml
<Window class="inventory">
    <Label class="title">Inventory</Label>

    <Grid class="items">
        <ItemSlot repeat="player.inventory" />
    </Grid>

    <Button id="close">Close</Button>
</Window>
```

Stylesheets provide layout and appearance:

```css
.inventory {
    width: 600px;
    margin: 20px;
    padding: 24px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    background: #26292f;
    border-radius: 8px;
}

.title {
    font-size: 26px;
    margin-bottom: 8px;
}

Button:hover {
    background: #444;
    scale: 1.05;
}
```

Bindings connect the interface to game state:

```xml
<Label text="{player.name}" />
<ProgressBar value="{player.health}" />
<ItemList items="{inventory.items}" />
```

These formats deliberately borrow familiar ideas from HTML and CSS, but they are small, Godot-specific languages. GodotCascade is not a browser engine and does not aim for web standards compatibility.

## What works today

The repository currently contains the first Phase 1 vertical slice:

- an installable Godot 4 editor addon;
- `CascadeBox`, a native `Container` with row and column flow;
- padding, child margins, gap, preferred/min/max sizing;
- start, center, end, stretch, and space distribution;
- basic flex growth and wrapping;
- optional background, border, and corner radius drawing;
- a shared `CascadeStyle` resource consumed by layout and owned components;
- `CascadeButton`, an owned `BaseButton` implementation with exact box-model sizing;
- an example scene that exercises the layout container.

Markup, stylesheet parsing, selectors, data binding, and hot reload remain roadmap work.

## Trying the prototype

1. Open this folder with Godot 4.3 or newer.
2. Enable **GodotCascade** under **Project → Project Settings → Plugins**.
3. Run the project. The configured main scene is `examples/basic_layout.tscn`.
4. Add a **CascadeBox** from the Create New Node dialog to experiment in your own scene.

No external runtime dependencies are required.

Run the current headless smoke test with:

```shell
godot --headless --path . --script res://tests/layout_smoke_test.gd
godot --headless --path . --script res://tests/flex_layout_engine_test.gd
godot --headless --path . --script res://tests/component_test.gd
```

## Using `CascadeBox`

`CascadeBox` works like any other Godot `Container`. Add child `Control` nodes, choose a direction, configure flow and gap on the container, and edit its shared `CascadeStyle` resource for padding, margin, constraints, background, and border.

Cascade-aware children expose their own margin and flex properties. For ordinary Godot controls, the same values can be attached as metadata:

```gdscript
button.set_meta("cascade_margin_left", 8.0)
button.set_meta("cascade_margin_right", 8.0)
button.set_meta("cascade_flex_grow", 1.0)
button.set_meta("cascade_min_width", 120.0)
```

Supported child metadata keys are:

```text
cascade_margin_left      cascade_margin_top
cascade_margin_right     cascade_margin_bottom
cascade_flex_grow
cascade_align_self        # 0 auto, 1 start, 2 center, 3 end, 4 stretch
cascade_preferred_width  cascade_preferred_height
cascade_min_width        cascade_min_height
cascade_max_width        cascade_max_height
```

The metadata bridge is an early compatibility mechanism. Later phases will apply these values through the style engine, so standard controls will not need wrappers or manual metadata.

Final layout rectangles are pixel-snapped by rounding their leading and trailing edges independently, preserving shared boundaries while avoiding fractional rendering blur. Set `pixel_snap` to `false` on `CascadeBox` when subpixel geometry is intentional. `CascadeStyle.overflow` explicitly selects visible or clipped content, and `align_self` overrides a parent's cross-axis alignment for one item.

GodotCascade owns the visual implementation of its core components so supported CSS settings have exact, shared semantics. Those components still derive from useful native primitives—for example, `CascadeButton` derives from `BaseButton` to retain focus, activation, toggle, shortcut, accessibility, and signal behavior. Ordinary Godot controls remain usable through documented compatibility tiers. See [ADR 0001](docs/decisions/0001-owned-core-controls.md) for the decision and tradeoffs.

### Using `CascadeButton`

Add a **CascadeButton** from the Create New Node dialog after enabling the addon. Its inspector exposes content and state appearance directly; shared padding, margin, sizing, background, and border values live in its `CascadeStyle` resource. Because it derives from `BaseButton`, connect `pressed`, `button_down`, `button_up`, and `toggled` exactly as you would for a native Godot button.

## HTML parity showcase

The generated [parity showcase](docs/showcase/index.html) presents each demo as a fixed-viewport HTML reference beside an actual capture of its GodotCascade scene. It also includes the proposed `.gxml` and `.gcss` translation and a semantic mapping table.

Showcases are registered in `examples/showcase/manifest.json`. A demo keeps four artifacts together:

- the original HTML reference;
- proposed GodotCascade markup and stylesheet;
- the current native Godot scene;
- a captured Godot render.

Build the showcase on Windows with:

```powershell
./tools/showcase/build_showcase.ps1 -GodotPath "C:\path\to\godot.exe"
```

The capture requires a real graphics display rather than Godot's dummy headless renderer. The generator itself uses only Python's standard library:

```shell
python tools/showcase/generate_showcase.py
python tools/showcase/generate_showcase.py --check
```

## Architecture

```text
Markup (.gxml) ──→ Parser ──→ UI tree ──→ Style engine
                                                │
                                                ▼
Native Controls ←── Reconciler ←── Layout engine
```

The major boundaries are intentionally separate:

- **Parser:** turns source files into immutable syntax and diagnostics.
- **UI tree:** stores element identity, attributes, bindings, and component boundaries.
- **Style engine:** matches selectors and computes resolved values.
- **Layout engine:** translates box, flex, and grid rules into control rectangles.
- **Reconciler:** updates existing Godot nodes while preserving runtime state and signal connections.
- **Tooling:** watches source files and explains markup, style, and layout decisions.

See [docs/architecture.md](docs/architecture.md) for design constraints and [ROADMAP.md](ROADMAP.md) for the planned delivery sequence.

## Project principles

1. **Godot-native output.** Rendering and interaction stay in `Control` nodes.
2. **A focused language.** Implement useful UI concepts, not arbitrary HTML or CSS.
3. **Deterministic layout.** The same inputs must produce the same rectangles.
4. **Incremental updates.** Hot reload should preserve node identity where possible.
5. **Actionable diagnostics.** Invalid markup and styles should identify the source and suggest a fix.
6. **Pay only for what changes.** Style, layout, and reconciliation should be independently invalidated.

## Roadmap

- **Phase 1 — Layout:** box model, flex flow, wrapping, constraints, and core controls.
- **Phase 2 — Styling:** stylesheets, selectors, cascade, inheritance, and pseudo states.
- **Phase 3 — Markup:** `.gxml`, components, bindings, and reconciliation.
- **Phase 4 — Tooling:** editor integration, live preview, hot reload, and inspection.
- **Phase 5 — Polish:** transitions, accessibility, responsive rules, optimization, and documentation.

## Contributing

The project is young enough that API decisions are still inexpensive to change. Before adding a large feature, write down the user-facing behavior, define how invalid input is diagnosed, and keep parsing, style resolution, layout, and node mutation separable.

When contributing code:

- target the minimum supported Godot version documented above;
- keep addon code under `addons/godot_cascade/`;
- add focused examples for visible behavior;
- avoid relying on editor-only APIs at runtime;
- document intentional differences from CSS.

## Non-goals

GodotCascade will not support arbitrary HTML, JavaScript, DOM APIs, full CSS compatibility, or general web content. It is a UI toolkit for Godot, not a web platform.

## License

A license has not been selected yet. Until one is added, the source is not offered under an open-source license.
