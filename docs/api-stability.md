# Public preview stability policy

GodotCascade is a prototype approaching its first public preview. The executable subset is usable, but source and API compatibility are not yet guaranteed across minor revisions.

## Preview guarantees

- Documented GXML elements, attributes, GCSS properties, and pseudo states are supported exactly as listed in `current-support.md`.
- Unsupported syntax produces diagnostics; it is not silently retained as browser-compatible CSS.
- Valid hot reloads preserve compatible keyed native instances and runtime state. Invalid source retains the last valid tree.
- Patch releases will not intentionally remove documented syntax without a replacement and migration note.

## Unstable surfaces

- File extensions, custom component lifecycle, event binding, collection repetition, import resources, and editor tooling remain provisional.
- Compatibility tiers and their current diagnostic contract are documented, but the set of adapted controls may expand before a stable release.
- Serialized scenes should reference the registered component types or `CascadeDocument`; internal helper scripts and metadata keys are not public API.
- The focused GCSS grammar is not a promise of general CSS compatibility.

## Change process

Breaking preview changes require a roadmap entry, a migration note in the release description, updated executable examples, and regression tests for the replacement path. The project will declare a stable source-format version only after importers and migration tooling exist.
