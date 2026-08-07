# Editor tooling

Enable the GodotCascade plugin under **Project → Project Settings → Plugins**. The plugin installs the following editor surfaces.

## Source importers

`.gxml` and `.gcss` files are imported as `CascadeMarkupResource` and `CascadeStylesheetResource`. Imported resources retain their original source, source path, parser diagnostics, and root/rule/token summaries. The import result is diagnostic data, not a serialized native scene; `CascadeDocument` remains responsible for context-aware runtime construction.

Because diagnostics are stored in the imported resource, malformed in-progress files remain visible in the FileSystem dock and Inspector instead of disappearing from the project.

## Live preview dock

The **Cascade Preview** dock accepts a `res://` markup path and stylesheet path. It renders the resulting native controls inside a 960×540 `SubViewport`, watches both files, retains the last valid tree on errors, and shows current error/warning counts. **Reload preview** forces an immediate refresh.

The lower tree is the style/layout debugger. Each row shows:

- GXML element, ID, classes, and reconciliation key;
- the resolved native rectangle;
- resolved background and padding values;
- one-way (`←`), writable (`↔`), and reconcile/collection (`⇄`) binding dependencies;
- the latest invalidation sequence on rows it matched and whether it used a targeted update or keyed reconciliation;
- the authored GXML source location.

Hover the binding column for exact property paths, dependency modes, invalidated paths, and matched properties. Conditional dependencies remain visible on the document root when their branch is absent. Class bindings explain selector-rematch reconciliation, and `Repeat` items are identified as collection dependencies.

The debugger retains only the latest invalidation, not an unbounded event log. `CascadeDocument.last_binding_trace()` exposes the same document-level record to runtime tooling, and `binding_trace_changed(trace)` fires after manual, observable, context-change, and native write-back refreshes. A trace reports its sequence, trigger, paths, `targeted`/`reconcile` strategy, reason, affected control IDs/keys, matched dependency count, success, and reconciliation statistics when applicable.

Double-clicking a row selects its source file in the FileSystem dock and opens the **Cascade Source** panel at the exact authored line/column. This provides real source navigation without pretending `.gxml` is a GDScript resource.

## Source language panel

The **Cascade Source** bottom panel is a Godot-owned `CodeEdit` backed by the same focused GXML/GCSS language service used in headless tests. It opens project paths, marks parser/schema diagnostics, supplies completion and hover documentation, formats only when source meaning can be retained, navigates safe same-file definitions, previews safe rename edits, and saves explicitly. See the [language tooling reference](language-tooling.md) for the exact feature and safety boundaries and the companion VS Code extension.

## Generated-control Inspector

Selecting a generated Cascade control shows an Inspector summary before its native properties: element type, ID, classes, key, GXML source path/line/column, and resolved rectangle. The normal Godot properties remain available below it, including `cascade_style` for owned controls.

The debugger and Inspector are read-only views. Edit the source files or explicit native component properties; tooling does not write computed values back into GXML/GCSS.
