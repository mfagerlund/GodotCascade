# Changelog

All notable changes to GodotCascade are documented here. Versions follow semantic versioning while the project remains in public preview.

## [Unreleased]

- Added `TextInput multiline="true"` as an adapted native `TextEdit`, including validation, writable binding, focus-visible styling, max length, and editing-state preservation.
- Made release archives byte-for-byte reproducible across Windows and Linux.
- Made showcase capture honor each manifest viewport through an isolated `SubViewport`.

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

[Unreleased]: https://github.com/mfagerlund/GodotCascade/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/mfagerlund/GodotCascade/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mfagerlund/GodotCascade/releases/tag/v0.1.0
