# Getting started

GodotCascade currently targets Godot 4.7.

1. Copy `addons/godot_cascade` into a Godot project, or use this repository directly.
2. Enable **GodotCascade** under **Project → Project Settings → Plugins**.
3. Create paired source files, for example `ui/settings.gxml` and `ui/settings.gcss`.
4. Add a `CascadeDocument` to a scene and assign both paths, or use the **Cascade Preview** dock while authoring.

Minimal markup:

```xml
<Page class="settings">
    <Label class="title">Settings</Label>
    <Checkbox checked="true">Enable shadows</Checkbox>
    <Button on-pressed="apply_settings">Apply</Button>
</Page>
```

Minimal stylesheet:

```css
.settings { padding: 24px; gap: 12px; background: #101828; }
.title { color: #f2f4f7; font-size: 28px; }
Button { padding: 8px 14px; background: #1c64d1; border-radius: 7px; }
```

For bound data, assign `binding_context` before the document loads. Assign an object to `event_context` for `on-*` handlers. Use explicit IDs and repeat keys whenever identity must survive reorder or hot reload.

Continue with the [current support reference](current-support.md), [style system](style-system.md), [markup/state guide](markup-and-state.md), and [editor tooling](editor-tooling.md). The [parity showcase](showcase/index.html) contains three executable projects with their HTML references, GXML/GCSS source, native scenes, and captures.
