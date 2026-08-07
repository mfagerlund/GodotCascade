# Changelog

All notable changes to GodotCascade are documented here. Versions follow semantic versioning while the project remains in public preview.

## [Unreleased]

- Added retained binding/dependency indexes so named scalar and repeated-item invalidations update only matching native controls while preserving exact debugger traces.
- Added an atomic zero-candidate path for pure keyed Array reorders whose item identities and row structure are unchanged, with candidate reconciliation retained as the correctness fallback.
- Added a cross-platform side-by-side Cascade/plain-Godot manual certification fixture, evidence-record validator, and external-developer evaluation protocol without overstating headless accessibility coverage.

## [0.7.0] — 2026-08-07

- Added weighted `flex-shrink`/`flex-basis`, descendant opacity, Godot 4.7 container-safe translate/rotate/scale, rounded two-stop linear gradients, and inherited project-local `Font` resources.
- Certified project-local SVG sources through Godot's native texture importer, including intrinsic sizing, binding refresh, and documented non-DOM boundaries.
- Added source-diagnosed `tab-index`, `autofocus`, and modal `focus-trap` contracts with visibility/disabled recomputation, focus-escape redirection, hot-reload stability, and prior-focus restoration.
- Added a headless-testable GXML/GCSS language service, a Godot `CodeEdit` source panel, and a packageable VS Code extension covering completion, hover, formatting, definition, safe rename, and diagnostics.
- Added retained collection-only reconciliation with zero full-document candidates, automatic typed `CascadeItemModel` changes, atomic key validation, and a repeat-template class-isolation fix.
- Added event-driven fixed-height virtualization for 10,000-item lists and semantic tables, including native scroll extents, overscan, overlapping identity, focus pinning, keyed scroll anchoring, debugger statistics, and validated typed-delta key indexes that avoid full scans outside reset.
- Added a five-sample representative workload gate for the real settings, dashboard, leaderboard, and 10,000-item inventory scenes, with hand-authored native baselines, a native `ItemList` comparison, visible collection-update verification, and documented Godot 4.7/4.7.1 results.
- Added a pinned, reproducible non-showcase deployment-queue comparison with GTML, including native captures, identical functional assertions, source metrics, diagnostics, and candid cold/update/reorder measurements.
- Hardened collection transactions against invalid model transitions, malformed deltas, multi-Repeat partial commits, stale scroll caches, dynamic fixed-height contract violations, radio-group candidate side effects, and lost accessibility diagnostics.

## [0.6.0] — 2026-08-07

- Added reusable source-level GXML components with checked `String`/`bool`/`int`/`float`/`Variant` parameters, default and named slots, scoped IDs, source-aware diagnostics, and identity-preserving reconciliation.
- Added bounded binding dependency and invalidation traces to `CascadeDocument`, `DebugSnapshot`, and the editor layout debugger, including targeted-versus-reconcile reasons and affected controls.
- Added case-sensitive, cascading/inherited GCSS custom properties with lazy `var()` fallback plus typed NUMBER/LENGTH/TIME `calc()` arithmetic, source-located diagnostics, shorthand precedence guarantees, full viewport cache keys, showcase coverage, and an expression-heavy benchmark.

## [0.5.0] — 2026-08-07

- Added an observable binding-context adapter with exact parent/child path invalidation, targeted native updates, writable-binding support, and no polling or expression runtime.
- Extended one-way bindings to visibility, disabled and checked state, select values, image sources, and selector-rematched class lists.
- Added exact boolean `if="{path}"` conditional rendering with omitted-branch dependency tracking and keyed reconciliation.
- Split document validation, binding compilation, and declaration application out of the builder hotspot into focused runtime services.
- Made release-archive entry ordering explicitly platform-independent after uppercase license files exposed Windows/Linux `Path` sorting differences.
- Adopted the cascading-native-windows logo, with a deterministic SVG master and square PNG for project and Asset Library use.
- Added a reproducible native live-reload demonstration that verifies instance preservation, plus parity guards for reconciled component properties.
- Corrected non-ASCII GXML diagnostic offsets and added exhaustive structural validation coverage.

## [0.4.0] — 2026-08-07

- Added optional typed C# binding generation from GXML, including partial getter/setter contracts, verbatim formatter/parser bodies, source-mapped compiler diagnostics, native signal wiring, and hot-reload reconnection.
- Added semantic native tables with shared fixed/content/fraction/minmax columns, header/body/row/cell structure, keyed repeated rows, accessible cell metadata, and a runnable HTML/Godot leaderboard parity page.
- Added an adapted native `Scroll` viewport with automatic vertical overflow, plus reliable captured-pointer and keyboard row reordering in the dynamic add/remove/sort leaderboard demo.
- Replaced Dictionary-backed settings showcase state with typed Godot object models and made typed models the recommended binding pattern.
- Added an end-to-end binding guide covering one-way paths, writable forms, dependent refresh, events, repeated scopes, validation, diagnostics, limits, and C# integration.
- Made the settings showcase's two-way write-back visible through live one-way labels bound to the same profile, quality, scale, and shadow values.
- Compacted select popup rows and removed inherited closed-control borders from options.
- Added antialiasing to slider, switch, and radio circular drawing.
- Added native `Slider:hover` feedback across the owned track, fill, and thumb, with matching HTML showcase behavior.
- Kept settings-panel backgrounds stable while hovering form controls and moved container-hover coverage to the layout cards.
- Extended the runnable showcase test to cover checkbox write-back and native radio grouping.
- Made each repeated HUD channel a full-row checkbox target in both native and HTML showcases.
- Rejected duplicate document IDs before keyed reconciliation and retained the last valid tree when a duplicate-ID edit is reloaded.
- Added an automated .NET compile gate for the generated C# binding example and its user-owned partial.
- Added an independent publication-readiness review covering structure, completeness, ecosystem overlap, licensing, and community positioning.
- Released the project under The Unlicense, with matching license copies at the repository root and inside the packaged addon.
- Reworked the README around native Godot captures, a checked-in GXML/GCSS/GDScript quickstart, honest competitor comparisons, and the post-0.4 validation pipeline.
- Added three image-model logo directions for community and maintainer review.

## [0.3.0] — 2026-08-06

- Added `TextInput multiline="true"` as an adapted native `TextEdit`, including validation, writable binding, focus-visible styling, max length, and editing-state preservation.
- Added writable `item.<path>` bindings inside keyed `Repeat` templates, with explicit errors for index and whole-item writes.
- Added `:hover` background adapters for owned Box/Panel, Grid, and Stack layout containers while keeping non-interactive states unsupported.
- Made release archives byte-for-byte reproducible across Windows and Linux.
- Made showcase capture honor each manifest viewport through an isolated `SubViewport`.
- Added a runnable manifest-driven showcase app with navigation, reload, diagnostics, and connection checks for every page.
- Prevented source reconciliation from publishing synthetic writable-control changes.

## [0.2.0] — 2026-08-06

- Added an adapted native single-line `TextInput` with validation and editing-state preservation.
- Added explicit writable `bind-text`, `bind-checked`, `bind-value`, and `bind-selected` property paths.
- Added `:invalid` and input-modality-aware `:focus-visible` styling.
- Made the native and HTML settings showcases interactive, including live scale/status output and Apply validation.
- Preserved superseded hashed showcase references as redirects so cached reports do not break.

## [0.1.0] — 2026-08-06

The first public preview provides:

- source-generated native Godot interfaces from focused GXML and GCSS;
- flex, grid, stack, responsive, and absolute-positioned layout;
- owned labels, panels, images, progress displays, buttons, checkboxes, radio buttons, switches, selects, and sliders;
- keyed reconciliation, hot reload, one-way bindings, repeated collections, and event-to-method wiring;
- interactive pseudo states, transitions, accessibility audits, editor preview/debug tooling, and source-aware diagnostics;
- executable native/HTML parity showcases, four headless test suites, and a 500-control performance gate.

See the [0.1.0 release notes](docs/releases/0.1.0.md) for installation and known boundaries.

[Unreleased]: https://github.com/mfagerlund/GodotCascade/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/mfagerlund/GodotCascade/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/mfagerlund/GodotCascade/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/mfagerlund/GodotCascade/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/mfagerlund/GodotCascade/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/mfagerlund/GodotCascade/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/mfagerlund/GodotCascade/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mfagerlund/GodotCascade/releases/tag/v0.1.0
