# GodotCascade Roadmap

The roadmap favors end-to-end slices over isolated subsystems. Each milestone should produce something visible in a running Godot project and leave behind testable boundaries for the next slice.

## Status snapshot

The executable foundation now covers flex/grid/stack layout, owned and adapted form controls, GXML and focused GCSS parsing, native-tree construction, keyed hot reload, last-valid diagnostics, one-way and explicit writable property-path bindings, automated captures, and the HTML parity report.

All planned 0.1 milestones and every first-public-preview acceptance item are complete. The source-generated settings-menu slice includes shared interactive-state precedence, a native mouse/keyboard/controller test matrix, and owned checkbox, grouped radio-button, switch, select, and slider components. The layout foundation includes native grid tracks, automatic and explicit placement, stack overlays, absolute insets, media, responsive rules, and viewport values. The editor and performance release gates are executable.

Versions 0.1.0 and 0.2.0 are tagged and published through the reproducible release gate. The 0.2 interactive-forms slice adds an adapted native text input, explicit writable bindings, validation state, input-modality-aware focus styling, and a live settings workflow exercised in both native and HTML showcase views.

The reproduced findings in the [2026-08-05 code review](docs/artifacts/review.md) are part of this roadmap. Blocking correctness fixes take priority when they touch the same runtime layer as an active vertical slice.

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

### Deferred beyond the 0.2 slice

- [ ] Multiline `TextInput` adapter on native `TextEdit`
- [x] Publish the automated and platform-dependent [TextInput certification matrix](docs/text-input-certification.md)
- [ ] Complete manual IME, screen-reader, touch selection, and clipboard certification on each supported platform
- [ ] Writable bindings inside repeated-item scopes
- [ ] General pseudo-state adapters for non-interactive layout containers
