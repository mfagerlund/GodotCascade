# Public preview stability policy

GodotCascade 0.4.0 is the prepared release candidate targeting Godot 4.7. The latest published preview remains 0.3.0 until the 0.4 release workflow completes. Source format version 1 and the documented runtime surface follow the preview guarantees below; broader API compatibility is not promised until a stable release.

## Preview guarantees

- Documented GXML elements, attributes, GCSS properties, and pseudo states are supported exactly as listed in `current-support.md`.
- Unsupported syntax produces diagnostics; it is not silently retained as browser-compatible CSS.
- Valid hot reloads preserve compatible keyed native instances and runtime state. Invalid source retains the last valid tree.
- Patch releases will not intentionally remove documented syntax without a replacement and migration note.
- Documented public runtime methods receive at least one preview minor release of deprecation before removal.
- Imported source resources declare format version 1 and are regenerated from `.gxml`/`.gcss` after addon upgrades.

## Unstable surfaces

- New custom component adapters and editor extensions remain provisional additions, but the documented lifecycle/event/repeat contracts follow the deprecation rule above.
- Compatibility tiers and their current diagnostic contract are documented, but the set of adapted controls may expand before a stable release.
- Serialized scenes should reference the registered component types or `CascadeDocument`; internal helper scripts and metadata keys are not public API.
- The focused GCSS grammar is not a promise of general CSS compatibility.

## Change process

Breaking preview changes require a roadmap entry, a section in [migration notes](migrations.md), updated executable examples, and regression tests for the replacement path. Source format version increments only when existing version-1 input cannot retain its documented meaning.
