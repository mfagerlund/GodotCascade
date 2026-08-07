# Migration notes

## 0.5.0 focused reactivity and conditions

Version 0.5.0 is backward-compatible with the documented 0.4 source-format version 1 surface; no existing GXML or GCSS migration is required. `ObservableBindingContext`, broader one-way state targets, bound class rematching, and exact boolean `if="{path}"` conditions are additive. A false conditional genuinely removes its native subtree, so controls inside that branch are recreated if it later returns; stable siblings continue to reconcile in place.

## 0.4.0 typed bindings and semantic tables

Version 0.4.0 is backward-compatible with the documented 0.3 source-format version 1 surface; no existing GXML or GCSS migration is required.

`Bindings` and `@Name` opt into generated typed C# partial bindings. Existing Godot object, Dictionary, and JSON-shaped runtime property paths remain supported and unchanged. `Table` and its semantic header/body/row/cell elements are additive. Growing tables can be wrapped in the new single-child `Scroll` element for native automatic vertical overflow.

Table sorting, selection, and row reordering remain application-level behavior. The leaderboard showcase demonstrates typed add/remove/sort state changes and captured-pointer or keyboard row reordering over stable `Repeat` keys.

## 0.3.0 scoped and multiline forms

`TextInput multiline="true"` now selects an adapted native `TextEdit`. It supports the existing text, placeholder, read-only, disabled, max-length, required, pattern, error-message, accessibility, state-style, and `bind-text` surface. `secret="true"` remains single-line-only and is an explicit error on the multiline adapter.

Writable bindings inside `Repeat` may now use `item.<path>`. Bare `item` replacement and `index` writes remain explicit errors.

Owned layout containers now accept `:hover` background styling. They remain non-focusable and do not gain pressed, disabled, or activation semantics.

## 0.2.0 interactive forms

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
