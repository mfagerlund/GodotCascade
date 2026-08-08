# Migration notes

## 0.8.1 validation and retained-state hardening

Version 0.8.1 retains source format version 1 and the documented 0.8 feature set, but its canonical schema and path parser now turn several previously silent or ambiguous cases into source errors:

- Binding paths use identifiers separated by dots plus non-negative canonical Array indexes. Hyphenated Dictionary keys, negative indexes, and indexes with leading zeroes are no longer accepted as path segments; expose those values through identifier-shaped properties or a typed model. A whole attribute value of `{path}` is dynamic. Text that merely contains braces remains literal; interpolation is still unsupported.
- Built-in elements reject unknown attributes. Registered custom components remain open to their own properties. `Option` continues to accept `id` and `class` because option selectors are supported, but irrelevant visual/common attributes remain errors.
- A document must expand to one visual root, and that root cannot carry `if`. Move the conditional to a child below a stable visual root.
- Generated `@Name` bindings are rejected inside reusable `Component` and `Repeat` templates because one authored ID could otherwise resolve several native controls. Use item-scoped runtime bindings inside Repeat.
- A generated `Bindings class` is one C# identifier, not a dot-qualified name. Put namespace segments in `namespace`, and avoid C# reserved/contextual keywords.
- Nested `@media` blocks intersect their enclosing width ranges. An empty intersection is an error instead of a rule that can never match.
- A virtual Repeat item root cannot use `if` or a false/bound/nontrivial `visible` declaration because removing or hiding the fixed-height root invalidates the virtual geometry. Put conditions inside the stable row root.
- `focus-trap` is accepted only on native Container-backed elements (including registered custom Containers). A full binding refresh in a trap-bearing document validates a complete candidate when `visible` or `disabled` can change, preserving atomic focus containment at a higher documented cost.
- An unnamed semantic `Progress` now produces the same accessibility warning as an unnamed interactive control. Add `accessible-label` or visible identifying text.

Compatible reloads now preserve live checkbox, radio, switch, select, and slider state when their authored state declaration is unchanged. Changing or adding the declaration intentionally reapplies it; a subsequent bound refresh still wins. Applications that relied on unrelated stylesheet/source reloads resetting uncontrolled widgets should reset them explicitly instead.

## 0.8.0 retained invalidation and certification tooling

Version 0.8.0 is backward-compatible with the documented 0.7 source-format version 1 surface. Binding/dependency indexes and the narrow same-identity keyed `Array` reorder path are internal optimizations; existing sources require no changes. Structural or ambiguous collection updates retain the 0.7 candidate-reconciliation behavior. Debugger traces preserve depth-first control and dependency order.

Accessibility diagnostics now carry an `accessibility` category so a repaired repeated value clears and re-audits the complete live document instead of leaving a stale warning. Consumers that display the public diagnostic dictionaries may use the new category but must continue accepting diagnostics without it.

The new platform record/evaluator tools are opt-in development utilities and do not alter packaged runtime behavior.

## 0.7.0 collections, virtualization, and language tooling

Version 0.7.0 is backward-compatible with the documented 0.6 source-format version 1 surface. `CascadeItemModel`, localized collection transactions, fixed-height virtualization, advanced focused styles, SVG textures, focus contracts, and language tooling are additive. Virtual Repeat deliberately has a stricter geometry contract: positive fixed `item-height`, stable keys, one Scroll ancestor, rows that fit the declared height after bindings, no Repeat padding/border, and `row-gap: 0` for virtual tables. Existing non-virtual Repeat sources are unchanged.

## 0.6.0 composition, traces, and GCSS expressions

Version 0.6.0 is backward-compatible with the documented 0.5 source-format version 1 surface; no existing GXML or GCSS migration is required. Reusable typed components, debugger dependency/invalidation traces, case-sensitive custom properties, and typed `calc()` are additive. Ordinary property names remain case-insensitive. Custom property names are intentionally case-sensitive, and unsupported expression dimensions remain recoverable errors rather than browser-compatible token preservation.

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
