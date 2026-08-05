# GodotCascade Roadmap

The roadmap favors end-to-end slices over isolated subsystems. Each milestone should produce something visible in a running Godot project and leave behind testable boundaries for the next slice.

## Status snapshot

The roadmap is not empty. The executable foundation now covers flex/box layout, owned button/label/panel/progress controls, GXML and focused GCSS parsing, native-tree construction, keyed hot reload, last-valid diagnostics, one-way property-path bindings, automated captures, and the HTML parity report.

The recommended next vertical slice is a source-generated settings menu. It requires generalized interactive-state adapters followed by owned checkbox and radio-button components. Dropdown/select behavior follows after the shared state and keyboard test matrix is established.

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

### 1.3 Grid and stack

- [ ] Fixed, fractional, content-sized, and min/max grid tracks
- [ ] Row and column gaps
- [ ] Explicit and automatic placement
- [ ] Stack/overlay layout
- [ ] Absolute positioning escape hatch

### 1.4 Core components

- [x] Shared box-painting and content-box primitive
- [x] `CascadeButton` based on `BaseButton`
- [x] `CascadeLabel` with wrapping and overflow rules
- [x] `CascadePanel` semantic styled container
- [x] `CascadeProgress` owned range display
- [ ] `CascadeImage` with fit and crop behavior
- [ ] Exact/adapted/layout-only compatibility diagnostics
- [ ] State matrix tests for hover, pressed, focused, and disabled controls

### 1.5 Form controls and settings showcase — next

- [ ] Generalize native pseudo-state adapters beyond `CascadeButton`
- [ ] Define shared state names and precedence: disabled, pressed, checked/selected, hover, focus
- [ ] `CascadeCheckbox` on `BaseButton` toggle behavior with owned indicator, label, and box model
- [ ] `CascadeRadioButton` on `BaseButton` plus native `ButtonGroup`
- [ ] GXML `checked`, `disabled`, `group`, and accessible-label attributes
- [ ] `:checked` pseudo state and generalized `:disabled`, `:hover`, and `:focused`
- [ ] Mouse, keyboard, controller, focus, checked, and disabled state matrix tests
- [ ] Source-generated settings-menu HTML/Godot parity demo
- [ ] `CascadeSwitch` using checkbox semantics and switch-specific drawing
- [ ] `CascadeSelect` composite with popup placement, option selection, keyboard navigation, and `:open`/`:selected`
- [ ] `CascadeSlider` on native range semantics with owned track, fill, and thumb drawing
- [ ] Adapted `CascadeTextInput` plan covering selection, IME, clipboard, bidi, and accessibility

## Phase 2 — Styles

- [ ] Tokenizer with source spans and recovery
- [x] Initial length, color, keyword, and number value subset
- [ ] Complete typed value model including time values
- [ ] Shorthand expansion for margin, padding, border, and gap
- [x] Type, class, and ID selectors
- [x] Descendant combinator
- [ ] Direct-child combinator
- [x] Specificity and source ordering
- [ ] Style inheritance
- [x] Button `:hover`, `:pressed`, `:focused`, and `:disabled`
- [ ] Generalized `:checked`, `:selected`, `:open`, and pseudo-state adapters
- [ ] Computed-style caching and targeted invalidation
- [ ] Godot theme and `StyleBox` adapters

## Phase 3 — Markup and state

- [x] `.gxml` parser with source-aware diagnostics and nesting recovery
- [x] Element registry and native control factories
- [x] `CascadeDocument` GXML/GCSS-to-native vertical slice
- [x] Stable identity and keyed reconciliation
- [x] Preserve native identity, focus, runtime state, and signal connections for compatible controls
- [ ] Custom component lifecycle
- [x] Focused property paths and explicitly refreshed one-way bindings
- [ ] Repeated elements and keyed collection updates
- [ ] Event-to-method binding

## Phase 4 — Tooling

- [ ] Importers for `.gxml` and stylesheet resources
- [x] Runtime file watching and hot reload with last-valid fallback
- [ ] Dockable live preview
- [ ] Inspector support for classes, IDs, and resolved values
- [ ] Style and layout debugger
- [ ] Source navigation from generated controls

## Phase 5 — Production readiness

- [ ] Property transitions and animation interruption rules
- [ ] Keyboard navigation and accessibility metadata
- [ ] Responsive conditions and viewport-aware values
- [ ] Performance benchmarks and allocation budgets
- [ ] API stability policy and migration notes
- [ ] Complete guides, reference, and example projects

## First public preview

The first public preview should build a small settings menu from `.gxml` and a stylesheet, update bound values, react to pointer and focus states, and hot-reload edits without losing focus or signal connections.

- [ ] Settings menu built from GXML/GCSS
- [ ] Checkbox, radio button, and select controls with keyboard/controller behavior
- [x] Focused one-way bound values
- [x] Pointer and focus states on buttons
- [x] Keyed hot reload preserving compatible native instances and signal connections
- [x] Malformed-source diagnostics with last-valid rendering
- [x] Headless layout, component, and source-pipeline tests
- [ ] Accessibility pass and documented keyboard navigation
- [ ] Public-preview API and source-format stability notes
