# Migration notes

## 0.2 development line

The interactive-forms additions are backward-compatible with source format version 1:

- ordinary `{path}` attribute bindings remain one-way;
- write-back is opt-in through `bind-text`, `bind-checked`, `bind-value`, or `bind-selected`;
- `TextInput` is an adapted native single-line editor; `multiline="true"` is an explicit error;
- `:invalid` and `:focus-visible` add states without changing the existing `:focused` contract.

No 0.1 source migration is required.

## 0.1.0 public preview

This is the first versioned preview contract. Earlier prototype commits were intentionally unstable.

- The minimum tested engine is Godot 4.7.
- GXML/GCSS import resources use source format version 1.
- `Grid`, `Stack`, `Image`, form controls, `Repeat`, `on-*` events, and registered custom components are now documented public source surfaces.
- `gap` uses row/column semantics and expands before cascade winner selection.
- Unknown elements, invalid values, duplicate repeat keys, and invalid event signals are errors. Inexact native appearance mappings are warnings.
- Hot reload uses explicit IDs, repeat keys, or structural fallback keys and preserves compatible native instances.

Public runtime methods documented in the guides receive at least one preview minor release of deprecation before removal. Patch releases do not intentionally remove documented syntax. Internal helper scripts, metadata keys, and editor-node structure remain private.

Imported `.res` files are derived cache artifacts. After upgrading the addon, let Godot reimport `.gxml` and `.gcss`; do not distribute old imported cache files as source of truth.

Future breaking preview changes must add a section here containing the old form, replacement form, automated migration availability, and the first release where the old form is removed.
