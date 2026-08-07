# GodotCascade Roadmap

The roadmap favors end-to-end slices over isolated subsystems. Each milestone should produce something visible in a running Godot project and leave behind testable boundaries for the next slice.

## Status snapshot

The executable foundation now covers flex/grid/stack layout, owned and adapted form controls, GXML and focused GCSS parsing, reusable typed components with slots and scoped IDs, native-tree construction, keyed hot reload, last-valid diagnostics, one-way and explicit writable property-path bindings, automated captures, the HTML parity report, and a manifest-driven runnable Godot showcase app.

All planned 0.1 milestones and every first-public-preview acceptance item are complete. The source-generated settings-menu slice includes shared interactive-state precedence, a native mouse/keyboard/controller test matrix, and owned checkbox, grouped radio-button, switch, select, and slider components. The layout foundation includes native grid tracks, automatic and explicit placement, stack overlays, absolute insets, media, responsive rules, and viewport values. The editor and performance release gates are executable.

Versions 0.1.0 through 0.6.0 are tagged and published through the reproducible release gate. The 0.2 interactive-forms slice adds an adapted native single-line text input, explicit writable bindings, validation state, input-modality-aware focus styling, and a live settings workflow exercised in both native and HTML showcase views. Version 0.3 adds the corresponding native multiline adapter, repeated-item write-back, and owned-container hover backgrounds. Version 0.4 adds optional typed C# generation, semantic tables, native scrolling, and dynamic collection examples. Version 0.5 adds targeted invalidation, broader one-way native state, and exact conditional rendering. Version 0.6 adds reusable typed GXML components, debugger dependency traces, and focused GCSS custom properties with typed arithmetic.

The reproduced findings in the [2026-08-05 code review](docs/artifacts/review.md) and the [2026-08-07 publication-readiness review](docs/artifacts/publication-readiness-review-2026-08-07.md) are part of this roadmap. Blocking correctness fixes take priority when they touch the same runtime layer as an active vertical slice.

The latest completed vertical slices add targeted observable invalidation, broader one-way state, exact boolean conditions, and reusable source-level components without replacing the lightweight runtime path resolver or introducing an expression engine.

## Forward pipeline at a glance

The next work keeps external validation separate from the remaining engineering pipeline:

1. **Public validation:** finalize the Asset Library listing, publish a short native-tree/live-reload demonstration, invite a Godot developer to build a real interface, and compare one production-shaped UI directly with GTML.
2. **Focused reactivity and composition:** path invalidation, broader state bindings, conditions, reusable components, component-boundary reconciliation, and debugger traces are complete.
3. **Language and tooling depth:** add the highest-value GCSS primitives, SVG textures and authored focus order, then provide completion, hover, formatting, rename, and navigation in Godot and VS Code.
4. **Scale and platform confidence:** add incremental collection updates, item models and virtualization, benchmark realistic interfaces, extend CI across desktop platforms, and complete manual input/accessibility certification.

Phases 10–13 below turn this sequence into falsifiable deliverables. Correctness work from the two independent reviews remains ahead of feature expansion when it touches the same runtime layer.

## Review follow-up

- [x] [Fix valid shorthand-magenta color parsing](docs/artifacts/review.md#1-valid-shorthand-hex-colors-are-rejected-as-invalid)
- [x] [Resolve shorthands before cascade winner selection](docs/artifacts/review.md#2-shorthands-do-not-participate-in-the-cascade)
- [x] [Separate invalid-value errors from not-applicable warnings](docs/artifacts/review.md#3-property-not-applicable-here-is-fatal-and-its-message-is-wrong)
- [x] [Give wrapped labels a non-zero min-content width](docs/artifacts/review.md#4-an-auto-wrapped-label-collapses-to-zero-width-inside-a-row)
- [x] [Normalize whitespace in class lists and multi-value declarations](docs/artifacts/review.md#5-class-attributes-split-on-spaces-only)
- [x] [Diagnose unsupported negative lengths](docs/artifacts/review.md#6-negative-lengths-are-silently-clamped)
- [x] [Attach declaration-level source locations to builder diagnostics](docs/artifacts/review.md#7-builder-diagnostics-point-at-the-selector-not-the-declaration)
- [x] [Avoid duplicate diagnostic logging on binding refresh](docs/artifacts/review.md#8-diagnostics-are-re-logged-on-every-binding-refresh)
- [x] [Cache property lookups in runtime hot paths](docs/artifacts/review.md#9-_has_property-is-a-linear-scan-in-three-hot-paths)
- [x] [Make CascadeBox property-source precedence explicit](docs/artifacts/review.md#10-_child_value-short-circuits-on-cascade_style-before-checking-direct-properties)
- [x] [Make GCSS comment stripping linear](docs/artifacts/review.md#11-_strip_comments-is-quadratic)
- [x] [Index selectors before documents grow](docs/artifacts/review.md#12-selector-matching-is-oelements--rules)
- [x] [Make progress range updates atomic](docs/artifacts/review.md#13-cascadeprogress-range-setters-are-order-dependent)
- [x] [Recover from unsupported pseudo states](docs/artifacts/review.md#14-an-unsupported-pseudo-state-discards-the-entire-rule)
- [x] Add the review's reconciliation, focus-preservation, diagnostic-content, cascade, and state-matrix regression tests

### 2026-08-07 publication review follow-up

- [x] Reject duplicate document IDs before reconciliation and retain the last valid tree on reload
- [x] Compile the generated C# example and its user-owned partial in CI
- [x] Correct the 0.4 publication status and distinguish automated tests from manual platform certification
- [x] Select and add a software license before publishing 0.4 or submitting to the Godot Asset Library
- [x] Split the builder hotspot before substantially broadening the source language
- [x] Correct non-ASCII diagnostic offsets and add a regression test
- [x] Add reconciler property-copy parity coverage before expanding custom component properties
- [ ] Validate the approach with a non-showcase UI and publish an honest comparison with GTML

## Phase 1 — Layout foundation

### 1.1 Box and flex prototype — complete

- [x] Godot addon scaffold
- [x] Native `CascadeBox` container
- [x] Row and column flow
- [x] Padding, child margin, and gap
- [x] Main-axis justification and cross-axis alignment
- [x] Flex growth and wrapping
- [x] Preferred, minimum, and maximum constraints
- [x] Example scene
- [x] Headless layout smoke test
- [x] Comprehensive automated layout test matrix
- [x] Explicit visible/clip overflow behavior
- [x] Per-child alignment override

### 1.2 Layout model extraction

- [x] Introduce engine-only box and constraint value types
- [x] Separate measurement from arrangement
- [x] Add deterministic unit tests for row, column, wrap, and constraints
- [x] Shared `CascadeStyle` box-model resource with targeted invalidation
- [x] Add dirty flags for measure and arrange invalidation
- [x] Define pixel rounding rules

### 1.3 Grid and stack — complete

- [x] Fixed, fractional, content-sized, and min/max grid tracks
- [x] Row and column gaps
- [x] Explicit and automatic placement
- [x] Stack/overlay layout
- [x] Absolute positioning escape hatch

### 1.4 Core components — complete

- [x] Shared box-painting and content-box primitive
- [x] `CascadeButton` based on `BaseButton`
- [x] `CascadeLabel` with wrapping and overflow rules
- [x] `CascadePanel` semantic styled container
- [x] `CascadeProgress` owned range display
- [x] `CascadeImage` with fit and crop behavior
- [x] Exact/adapted/layout-only compatibility diagnostics
- [x] State matrix tests for hover, pressed, focused, and disabled controls

### 1.5 Form controls and settings showcase — complete

- [x] Generalize native pseudo-state adapters beyond `CascadeButton`
- [x] Define shared state names and precedence: disabled, pressed, checked/selected, hover, focus
- [x] `CascadeCheckbox` on `BaseButton` toggle behavior with owned indicator, label, and box model
- [x] `CascadeRadioButton` on `BaseButton` plus native `ButtonGroup`
- [x] GXML `checked`, `disabled`, `group`, and accessible-label attributes
- [x] `:checked` pseudo state and generalized `:disabled`, `:hover`, and `:focused`
- [x] Mouse, keyboard, controller, focus, checked, and disabled state matrix tests
- [x] Source-generated settings-menu HTML/Godot parity demo
- [x] `CascadeSwitch` using checkbox semantics and switch-specific drawing
- [x] `CascadeSelect` composite with popup placement, option selection, keyboard navigation, and `:open`/`:selected`
- [x] `CascadeSlider` on native range semantics with owned track, fill, and thumb drawing
- [x] Adapted `CascadeTextInput` plan covering selection, IME, clipboard, bidi, and accessibility

## Phase 2 — Styles — complete

- [x] Tokenizer with source spans and recovery
- [x] Initial length, color, keyword, and number value subset
- [x] Complete typed value model including time values
- [x] Shorthand expansion for margin, padding, border, and gap
- [x] Type, class, and ID selectors
- [x] Descendant combinator
- [x] Direct-child combinator
- [x] Specificity and source ordering
- [x] Style inheritance
- [x] Button `:hover`, `:pressed`, `:focused`, and `:disabled`
- [x] Generalized `:checked`, `:selected`, `:open`, and pseudo-state adapters
- [x] Computed-style caching and targeted invalidation
- [x] Godot theme and `StyleBox` adapters

## Phase 3 — Markup and state — complete

- [x] `.gxml` parser with source-aware diagnostics and nesting recovery
- [x] Element registry and native control factories
- [x] `CascadeDocument` GXML/GCSS-to-native vertical slice
- [x] Stable identity and keyed reconciliation
- [x] Preserve native identity, focus, runtime state, and signal connections for compatible controls
- [x] Custom component lifecycle
- [x] Focused property paths and explicitly refreshed one-way bindings
- [x] Repeated elements and keyed collection updates
- [x] Event-to-method binding

## Phase 4 — Tooling — complete

- [x] Importers for `.gxml` and stylesheet resources
- [x] Runtime file watching and hot reload with last-valid fallback
- [x] Dockable live preview
- [x] Inspector support for classes, IDs, and resolved values
- [x] Style and layout debugger
- [x] Source navigation from generated controls

## Phase 5 — Production readiness — complete

- [x] Property transitions and animation interruption rules
- [x] Keyboard navigation and accessibility metadata
- [x] Responsive conditions and viewport-aware values
- [x] Performance benchmarks and allocation budgets
- [x] API stability policy and migration notes
- [x] Complete guides, reference, and example projects

## First public preview

The first public preview should build a small settings menu from `.gxml` and a stylesheet, update bound values, react to pointer and focus states, and hot-reload edits without losing focus or signal connections.

- [x] Settings menu built from GXML/GCSS
- [x] Checkbox, radio button, and select controls with keyboard/controller behavior
- [x] Focused one-way bound values
- [x] Pointer and focus states on buttons
- [x] Keyed hot reload preserving compatible native instances and signal connections
- [x] Malformed-source diagnostics with last-valid rendering
- [x] Headless layout, component, and source-pipeline tests
- [x] Accessibility pass and documented keyboard navigation
- [x] Public-preview API and source-format stability notes

## Phase 6 — 0.2 interactive forms — complete

- [x] Adapted single-line `CascadeTextInput` on native `LineEdit` editing semantics
- [x] GXML text-input attributes for placeholder, read-only, disabled, secret, max length, and accessibility
- [x] Required and regular-expression validation with accessible messages and `:invalid`
- [x] Explicit `bind-text`, `bind-checked`, `bind-value`, and `bind-selected` writable paths
- [x] Writable Dictionary, Array, and Godot object property assignment without expressions or method calls
- [x] Dependent one-way binding refresh after native edits
- [x] `:focus-visible` border styling driven by keyboard/controller versus pointer modality
- [x] Text-input hover, focused, disabled, and invalid adapted appearance states
- [x] Preserve text, caret, and selection across compatible keyed hot reloads
- [x] Interactive settings-menu Apply workflow in native Godot and HTML parity views
- [x] Component, pipeline, validation, writable-binding, and clean-install regression coverage

## Phase 7 — 0.3 scoped and multiline forms — complete

- [x] Multiline `TextInput` adapter on native `TextEdit`
- [x] Multiline validation, max length, read-only/disabled behavior, writable binding, and adapted pseudo states
- [x] Preserve multiline text, primary caret, selection, and scroll across compatible keyed hot reloads
- [x] Add multiline editing to the native and HTML settings showcase without removing existing form controls
- [x] Writable bindings inside repeated-item scopes with keyed reorder regression coverage
- [x] `:hover` background adapters for non-interactive Box/Panel, Grid, and Stack containers without changing focus/navigation semantics
- [x] Runnable manifest-driven Godot showcase with page navigation, reload, live diagnostics, and automated connection checks

## Ongoing platform-dependent certification

- [x] Publish the automated and platform-dependent [TextInput certification matrix](docs/text-input-certification.md)
- [ ] Complete manual IME, screen-reader, touch selection, and clipboard certification on each supported platform

## Phase 8 — typed C# bindings — complete

- [x] Non-visual GXML `Bindings` contract and explicit `@Name` usage syntax
- [x] Typed partial getter/setter declarations implemented in a permanent companion class
- [x] Verbatim C# formatter and parser bodies with GXML `#line` compiler mappings
- [x] Generated native signal wiring, refresh, feedback suppression, and document hot-reload reconnection
- [x] Packaged headless generator command, deterministic example output, diagnostics, and automated .NET compile verification
- [x] Preserve the existing typed Godot-object and Dictionary/JSON runtime binding paths

## Phase 9 — native tables — complete

- [x] Semantic `Table`, `TableHeader`, `TableBody`, `TableRow`, `TableHeaderCell`, and `TableCell` elements
- [x] Shared column measurement across header and body rows
- [x] Fixed, fractional, content-sized, and min/max column tracks
- [x] Header/cell accessibility metadata and deterministic keyboard focus behavior
- [x] Repeated row binding with stable keys
- [x] HTML/native showcase parity page and component/layout regression matrix
- [x] Application-level add, remove, sort, and drag-reorder demo over keyed rows
- [x] Native `Scroll` viewport with automatic vertical overflow for growing tables
- [x] Document explicit boundaries for sorting, selection, resizing, and virtualization

## Phase 10 — public validation pipeline

- [x] Select a permissive software license and include it in both the repository and packaged addon
- [x] Publish a visual README with runnable GXML, GCSS, and GDScript plus native Godot captures
- [x] Document the direct comparison with GTML, Reactive UI Toolkit, GUML, and native Godot
- [x] Publish the 0.4 experimental-preview release
- [x] Select, small-size test, and publish a square project and Asset Library icon
- [x] Make the repository public after verifying its release page and installation archive
- [x] Prepare and verify the remaining Godot Asset Library metadata for a testing-support submission
- [ ] Submit the prepared 0.6.0 entry through the authenticated Godot Asset Library form
- [x] Prepare a short, reproducible native-tree/live-reload demonstration
- [x] Prepare a candid Godot community announcement and structured feedback questions
- [ ] Publish the live-reload artifact after maintainer approval
- [ ] Share the public demonstration through an authenticated Godot community account
- [ ] Invite at least one external Godot developer to build a real interface and record where the authoring model helps or obstructs them
- [ ] Build one non-showcase production-shaped UI in both GodotCascade and GTML and publish the comparison
- [ ] Collect structured feedback on authoring speed, diagnostics, binding ergonomics, runtime cost, and missing controls

## Phase 11 — focused reactivity and composition

- [x] Add an observable adapter that can invalidate named paths without polling or a general expression runtime
- [x] Extend one-way targets to documented state such as visibility, disabled state, classes, image source, and selected values
- [x] Design explicit conditional rendering that remains diagnosable and does not evaluate arbitrary code
- [x] Add reusable GXML components with typed parameters, slots, scoped IDs, and source-aware diagnostics
- [x] Preserve keyed identity and native editing state across conditional/component boundaries
- [x] Add dependency and invalidation traces to the layout debugger

## Phase 12 — language and editor depth

- [x] Evaluate and implement focused GCSS custom properties and typed `calc()` without claiming browser compatibility ([experiment record](docs/artifacts/custom-properties-calc-experiments-2026-08-07.md))
- [x] Add the highest-value missing layout/style primitives: flex shrink/basis, opacity, transforms, gradients, and custom fonts
- [x] Define SVG support through native Godot textures rather than a browser DOM
- [x] Add authored autofocus, tab order, and modal focus-trap contracts
- [x] Provide completion, hover, formatting, go-to-definition, rename, and diagnostics in the Godot editor and VS Code
- [x] Split `cascade_builder.gd` into construction, validation, binding, and declaration-application services first

## Phase 13 — scale and platform confidence

- [ ] Avoid rebuilding a complete off-tree candidate for collection-only updates
- [ ] Add item-model adapters and virtualization for large lists and tables
- [ ] Benchmark real settings, inventory, dashboard, and leaderboard workloads against native scenes and close alternatives
- [ ] Add Windows and macOS CI coverage where the engine runner permits it
- [ ] Complete manual IME, clipboard, touch-selection, virtual-keyboard, and screen-reader certification
- [ ] Publish tested support levels per Godot version and desktop/mobile platform
