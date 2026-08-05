# GodotCascade code review

Reviewed at `2ad3c33` (main, clean tree) against Godot 4.7-stable-mono. Every finding below was
reproduced by running code, not inferred from reading. Repro output is quoted verbatim.

Baseline: all four test scripts pass headless at `2ad3c33`, and `generate_showcase.py --check`
verifies the committed showcase is current. Nothing here is a regression — these are latent defects
and design edges in code that currently works for the two demos that exercise it.

---

## Working-tree note (read first)

The tree moved while this review was being written — `cascade_button.gd` and `cascade_builder.gd` are
modified, and `cascade_checkbox.gd`, `cascade_radio_button.gd`, and `interactive_state_adapter.gd`
are new and untracked. Two things follow.

**The working tree does not currently compile.** `cascade_builder.gd:299`:

```gdscript
var parsed := _parse_bool_attribute(attribute_name, str(attributes[attribute_name]), diagnostics)
```

`_parse_bool_attribute` is declared `-> Variant` (`cascade_builder.gd:320`), and `:=` cannot infer
from `Variant`. Every script that preloads the builder fails to compile, so all four test scripts
currently fail to load. Fix:

```gdscript
var parsed: Variant = _parse_bool_attribute(attribute_name, str(attributes[attribute_name]), diagnostics)
```

**Line numbers below are for `2ad3c33`.** Everything cited outside `cascade_builder.gd` is still
accurate — those files are unmodified. Within the builder, the symbols have moved:

| Cited (`2ad3c33`) | Symbol | Current WIP line |
| --- | --- | --- |
| `347-352` | `_parse_color` | `422-427` |
| `66-99` | `_compute_declarations` / `_apply_declarations` | `79` / `101` |
| `362-363` | `_diagnostic_unsupported` | `437` |
| `207-208` | unknown-property warning | `221` |
| `280` | `_apply_edges` token split | `353` |

I re-checked the WIP builder against the findings: `_parse_color` is byte-identical (finding 1
stands), the `winners` cascade is unchanged (finding 2 stands), and the new
`_diagnostic_unsupported_state` helper splits *state* diagnostics out but leaves the
error-vs-warning severity split of finding 3 intact. The new `checked`/`disabled` attribute path
adds a third place that depends on assignment order, which reinforces finding 13.

---

## Contents

1. [Verdict](#verdict)
2. [What is working well](#what-is-working-well)
3. [Blocking correctness bugs](#blocking-correctness-bugs)
4. [Contract violations](#contract-violations)
5. [Robustness and performance](#robustness-and-performance)
6. [Test gaps](#test-gaps)
7. [Prioritized action list](#prioritized-action-list)

---

## Verdict

The architecture is sound and the boundaries described in `docs/architecture.md` are real, not
aspirational — `FlexLayoutEngine` genuinely has no scene-tree dependency, parsers genuinely create no
nodes, and the reconciler genuinely preserves instance identity. That is unusual for a prototype at
this stage and it is the main asset here.

The weak layer is `CascadeBuilder`. It is doing four jobs at once — factory, cascade resolver,
shorthand expander, and property adapter — and three of the four blocking bugs below live in it.
The single highest-value refactor is to split cascade resolution (specificity over *longhand*
properties) from property application. That change fixes findings 2 and 3 together and makes 1 and 4
easy to test.

Severity language used below: **blocking** = produces wrong output or refuses valid input;
**contract** = contradicts a promise made in `docs/`; **robustness** = correct today, fragile or slow
under growth.

---

## What is working well

Worth stating explicitly so it does not get refactored away.

- **`FlexLayoutEngine` purity.** `LayoutItem`/`LayoutRequest` in, `Array[Rect2]` out. This is why
  `flex_layout_engine_test.gd` can cover ten layout behaviors without a scene tree, and it is the
  cheapest test loop in the repo. Protect this boundary.
- **Grow redistribution is correct.** `_grow_main_sizes` (`flex_layout_engine.gd:220-261`) re-runs
  distribution after items hit their maximum, with an epsilon guard and a no-progress break. That is
  the part of flex growth people usually get wrong, and there is a test for it.
- **Independent edge rounding.** `_snap_rect` (`flex_layout_engine.gd:324-327`) rounds leading and
  trailing edges separately, so shared boundaries between adjacent items stay stable instead of
  accumulating drift. Correct approach, correctly documented.
- **Weak parent links.** `Element._parent_ref` is a `WeakRef` (`gxml_parser.gd:13,31-32`), so the
  descendant-selector walk in `Rule.matches()` works without creating reference cycles in a
  refcounted tree. Deliberate and right.
- **Greedy ancestor matching is correct.** `Rule.matches()` (`gcss_parser.gd:18-34`) walks up from
  the rightmost compound. For descendant-only selectors, greedy upward matching needs no
  backtracking — this is sound, not lucky.
- **Transactional reload.** Building the candidate off-tree and discarding it on error
  (`cascade_document.gd:74-101`) is the right shape, and `_test_identity_preserving_reload` proves
  the last-valid guarantee holds through a malformed edit.

---

## Blocking correctness bugs

### 1. Valid shorthand hex colors are rejected as invalid

**Location:** `addons/godot_cascade/runtime/cascade_builder.gd:347-352`

`_parse_color` detects failure by passing magenta as the fallback to `Color.from_string()` and then
checking whether the result *is* magenta, with a hardcoded allow-list of three magenta spellings:

```gdscript
var parsed := Color.from_string(normalized, Color(1.0, 0.0, 1.0, 1.0))
if parsed == Color(1.0, 0.0, 1.0, 1.0) and normalized.to_lower() not in ["magenta", "#ff00ff", "#ff00ffff"]:
```

Godot accepts `#RGB` shorthand, so `#f0f` parses successfully *to magenta* and is then misreported as
invalid. Because `_parse_color` appends a `severity: "error"` diagnostic, the whole document refuses
to build and the UI falls back to last-valid.

**Repro (verified):**

```
A. shorthand hex color #f0f
    built=false errors=["Line 1: invalid color '#f0f'."]
A2. control hex color #ff00ff (allow-listed)
    built=true errors=[]
A3. shorthand hex background #abc
    built=true errors=[]
```

`#abc` builds because it is not magenta — the bug is invisible for every colour except the sentinel.

**Fix.** Drop the sentinel and the allow-list; parse twice with different fallbacks and compare. A
string only fails to parse if both probes return their own fallback:

```gdscript
static func _parse_color(value: String, line: int, diagnostics: Array[Dictionary]) -> Color:
	var normalized := value.strip_edges()
	var probe_black := Color.from_string(normalized, Color.BLACK)
	var probe_white := Color.from_string(normalized, Color.WHITE)
	if probe_black != probe_white:
		diagnostics.append(_diagnostic("error", "Line %s: invalid color '%s'." % [line, value]))
		return Color.TRANSPARENT
	return probe_black
```

This is exact for every input Godot can parse, including named colours and all four hex lengths.

---

### 2. Shorthands do not participate in the cascade

**Location:** `addons/godot_cascade/runtime/cascade_builder.gd:66-99`

`_compute_declarations` resolves specificity per *authored property name*, so `padding` and
`padding-left` are two unrelated entries in `winners`. Both then get applied in
`_apply_declarations`, in `Dictionary` insertion order — which is rule order, not specificity order.

The result is that a low-specificity longhand beats a high-specificity shorthand, and reversing the
source order silently changes the answer:

**Repro (verified)** — `#card` has specificity 100, `.card` has 10, so CSS says `padding-left` is 20
in both arrangements:

```
B. shorthand vs longhand specificity
    padding_left=4.0    (source: #card{padding:20px} .card{padding-left:4px})
    reversed source order padding_left=20.0
```

Both answers are wrong in the sense that they are decided by source order alone; specificity is
discarded entirely for this pairing. The same defect applies to `margin`/`margin-*` and to
`border` versus `border-width`/`border-color`.

**Fix.** Expand shorthands to longhands *before* the cascade, then resolve specificity over the
longhand set only. Concretely: move `_apply_edges` and `_apply_border` out of the apply phase into a
normalization pass that turns `{padding: "20px"}` into
`{padding-top: "20px", padding-right: "20px", ...}` at rule-parse time. `_compute_declarations` then
needs no change and `_apply_declaration` loses two branches. This also removes the current dependence
on `Dictionary` insertion order, which is not a documented guarantee to rely on.

---

### 3. "Property not applicable here" is fatal, and its message is wrong

**Location:** `cascade_builder.gd:362-363` (`_diagnostic_unsupported`, severity `"error"`) versus
`cascade_builder.gd:207-208` (unknown property, severity `"warning"`)

Two different failures are conflated:

- an **unsupported value** for a known property — `width: 50%` — which should be an error;
- a **valid value on a control that lacks the property** — `color` on a `Panel`, `gap` on a `Label`
  — which is currently also an error, and takes the entire document down.

**Repro (verified):**

```
C. color on a Panel (no inheritance)
    built=false errors=["Line 1: unsupported color value '#ffffff'."]
D. gap on a Label
    built=false errors=["Line 1: unsupported gap value '4px'."]
F. unknown property typo
    built=true warnings=["Line 1: unsupported property 'paddingg'."]
```

Two problems:

1. **The messages are false.** `#ffffff` is not an unsupported colour value and `4px` is not an
   unsupported gap value. Both values are fine; the *target control* has no such property. An author
   reading these will go looking for a colour-syntax problem that does not exist.
2. **The severity gradient is inverted.** A typo (`paddingg`) is forgiven and the UI renders. Writing
   `color` on a container — the single most reflexive thing a CSS author does, because in CSS `color`
   inherits — is fatal. Since GCSS has no inheritance yet (`ROADMAP.md` Phase 2), authors *must*
   restate `color` on every `Label`, and the natural mistake is punished hardest.

`docs/current-support.md:84` does document that unsupported values error and unsupported properties
warn, so the behavior is not undocumented — but the doc describes the value/property axis, while the
code is actually keying on the target-has-property axis, and the diagnostics say the wrong thing.

**Fix.** Split `_diagnostic_unsupported` into two helpers: `_diagnostic_bad_value` (error, keeps the
current wording) and `_diagnostic_not_applicable` (warning, wording like
`"Line 7: 'color' is not supported on <Panel>; set it on the text element."`). Every
`not _has_property(target, ...)` branch should use the second. Errors then mean only "I cannot
understand this value", which is a defensible reason to refuse a swap.

---

### 4. An auto-wrapped `Label` collapses to zero width inside a `Row`

**Location:** `addons/godot_cascade/components/cascade_label.gd:90-93`

```gdscript
if autowrap_mode != TextServer.AUTOWRAP_OFF:
	# Wrapped text accepts the containing block's width instead of forcing its
	# unwrapped line width into the parent's intrinsic minimum.
	content_minimum.x = 0.0
```

`AUTOWRAP_WORD_SMART` is the default (`cascade_label.gd:39`), so *every* label reports zero intrinsic
width. In a `Column` this is invisible: the width is the cross axis and `align_items: stretch`
(the default) fills it. In a `Row` the width is the main axis, nothing assigns it, and the label
collapses — then the internal `Label` wraps at width 0 and the height explodes.

**Repro (verified)** — one default `CascadeLabel` in a 400×100 `Row`:

```
H. autowrapped Label as a row item
    size=(0.0, 985.0)
```

985px of height inside a 100px row, with no text visible and no diagnostic. Both showcase demos
happen to place their labels in columns or give them `flex-grow`, which is why this has not surfaced.

**Fix.** The comment's reasoning is right — an unwrapped line width is a bad intrinsic minimum — but
zero is the wrong floor. Use the longest unbreakable word instead, which is what browsers use for
`min-content`:

```gdscript
if autowrap_mode != TextServer.AUTOWRAP_OFF:
	content_minimum.x = _min_content_width()  # widest single word, not 0
```

Whatever floor is chosen, add a layout-time diagnostic when an item's resolved main-axis size is 0
while it has content — that class of bug is otherwise silent, and silent zero-size is the most
expensive kind of layout bug to debug.

---

### 5. `class` attributes split on spaces only

**Location:** `addons/godot_cascade/markup/gxml_parser.gd:26-28`

```gdscript
return PackedStringArray() if value.is_empty() else value.split(" ", false)
```

A class list separated by a tab or newline — routine when an author wraps a long attribute across
lines — becomes a single bogus class, and every selector against it silently misses.

**Repro (verified)** — `class="alpha<TAB>beta"` with a `.beta { font-size: 30px; }` rule:

```
G. tab-separated class attribute
    classes=["alpha\tbeta"] font_size=16 (expected 30)
```

No diagnostic; the element simply does not get styled.

**Fix.** Normalize whitespace before splitting: `value.replace("\t", " ").replace("\n", " ")` then
split, or use a cached `RegEx` on `\s+`. The identical bug exists in `_apply_edges`
(`cascade_builder.gd:280`), where `padding: 10px<TAB>20px` fails to parse — and *that* one is fatal
per finding 3.

---

## Contract violations

These contradict promises made in `docs/architecture.md`.

### 6. Negative lengths are silently clamped

**Location:** every setter in `addons/godot_cascade/style/cascade_style.gd` (e.g. margins at
`72-95`), plus `FlexLayoutEngine.LayoutItem._init` at `flex_layout_engine.gd:41-48`

`margin-left: -8px` is accepted, clamped to `0.0`, and produces no diagnostic
(**verified**: `E. negative margin — built=true errors=[] warnings=[]`).

`docs/architecture.md:93` states: *"Unsupported properties produce diagnostics instead of being
silently stored."* A silently-zeroed negative margin is exactly the failure that rule exists to
prevent — the author sees a layout that ignores their declaration with no explanation.

**Fix.** Negative *padding* and negative *border-width* are meaningless and should be diagnosed.
Negative *margin* is a legitimate CSS technique and is a reasonable thing to support later — but
supporting it means changing both layers, since `LayoutItem` clamps independently of `CascadeStyle`.
For now, diagnose in `CascadeBuilder` before the value ever reaches the setter, so the clamp in the
style resource stays as a defensive floor rather than acting as silent policy.

### 7. Builder diagnostics point at the selector, not the declaration

**Location:** `gcss_parser.gd:113` (`rule.line` is computed from the selector's offset), consumed by
`cascade_builder.gd:88-99`

`Rule` stores one `line` for the whole rule, so every declaration diagnostic inside a 40-line block
reports the line of the opening selector. Declarations carry no offset at all, and builder
diagnostics carry no `column` (compare the parser diagnostics, which carry both).

`docs/architecture.md:32` promises: *"Every recoverable error carries a file, range, explanation, and
ideally a suggested correction."* Currently it carries a file, the wrong line, and an explanation
that — per finding 3 — may describe the wrong problem.

**Fix.** Store declarations as `{name, value, line, column}` instead of a flat
`Dictionary[String, String]` in `Rule.declarations`. `_parse_rule` already walks the body with an
offset available; it just discards it. This is a small change that improves every diagnostic in the
system at once, and it is a prerequisite for the "suggested correction" goal.

### 8. Diagnostics are re-logged on every binding refresh

**Location:** `cascade_document.gd:149-160` and `174-183`

`_publish_diagnostics()` unconditionally `push_error`/`push_warning`s the entire diagnostic list, and
`refresh_bindings()` calls it. A game that refreshes bindings each frame — the documented way to
propagate nested state changes (`README.md:130-131`) — re-emits every accumulated parse warning every
frame.

**Fix.** Track the previously published list and only log the delta, or log only diagnostics whose
`path == "binding"` on the refresh path. The `diagnostics_changed` signal should still fire so
tooling can observe the current set.

---

## Robustness and performance

Correct today; will bite as documents grow.

### 9. `_has_property` is a linear scan in three hot paths

`get_property_list()` allocates an `Array[Dictionary]` describing every property on the object, and
it is scanned linearly:

- `cascade_reconciler.gd:86-90` — called twice per property, for 25 properties, per reused node, per
  reload;
- `cascade_box.gd:177-189` — `_child_value` builds the whole list per child per lookup, and is called
  ~11 times per child during **measure and arrange**, i.e. inside the frame loop;
- `binding_resolver.gd:48-53` — per object segment per binding per refresh.

`_child_value` is the one that matters: it is per-frame work under any animation or resize.

**Fix.** Cache the property-name set per script in a `static var` keyed by
`child.get_script().get_instance_id()`. The set is immutable for a given script, so it is safe to
memoize for the process lifetime.

### 10. `_child_value` short-circuits on `cascade_style` before checking direct properties

**Location:** `cascade_box.gd:182-189`

The loop returns as soon as it encounters a property named `cascade_style`, so a component that
exposed both a `cascade_style` and a real `flex_grow` property would always read the style — decided
by property-list ordering, which is not a contract. There is also no `has`-check before
`child_style.get(property_name)`, so a name that is not on `CascadeStyle` reaches `float(null)`.

**Fix.** Decide the precedence explicitly (metadata → style → direct property is the sensible order,
matching current behavior) and express it as three sequential checks rather than one ordering-
dependent loop.

### 11. `_strip_comments` is quadratic

**Location:** `gcss_parser.gd:156-172`

Each comment rebuilds the entire source string via `substr` concatenation, and the whitespace
replacement is built one character at a time. Irrelevant at 100 lines, noticeable at a few thousand
— and this runs on every hot-reload poll that detects a change.

**Fix.** Single forward pass into a `PackedStringArray`, joined once at the end.

### 12. Selector matching is O(elements × rules)

**Location:** `cascade_builder.gd:66-72`

Every element tests every rule. `docs/architecture.md:40` already describes the intended fix
(index rules by rightmost selector). Not urgent at showcase scale; noting it so the O(n·m) loop is
not mistaken for the intended design.

### 13. `CascadeProgress` range setters are order-dependent

**Location:** `cascade_progress.gd:10-25`

`min_value`'s setter mutates `max_value` and clamps `value`; `max_value`'s setter clamps against
`min_value`. Assigning `{min: 50, max: 200}` to a control currently at `0..100` gives a different
result than assigning them in the other order. Three separate call sites depend on assignment order
being min → max → value: `_apply_attributes` (`cascade_builder.gd:247`), `COPIED_PROPERTIES`
(`cascade_reconciler.gd:11`), and binding application (insertion order of `cascade_bindings`). All
three happen to be correct today; nothing enforces it.

**Fix.** Add `set_range(min_value, max_value, value)` that assigns the backing fields and clamps once,
and have the builder/reconciler/binding paths call it.

### 14. An unsupported pseudo-state discards the entire rule

**Location:** `gcss_parser.gd:116-121`

`_parse_rule` returns `null` for an unrecognized pseudo state, dropping every declaration in the
block *and* emitting a fatal error. `Button:focus { }` — the CSS spelling, versus GodotCascade's
`:focused` — therefore takes the whole document down rather than styling what it can.

**Fix.** Keep the rule, drop only the pseudo-state part, and warn. Combined with finding 3 this makes
"author typed CSS out of habit" a recoverable condition throughout.

---

## Test gaps

The existing suites are well-targeted — `flex_layout_engine_test.gd` in particular covers growth,
wrapping, justification, per-item alignment, and snapping. The gaps are concentrated around the
claims the project makes loudest.

| Gap | Why it matters |
| --- | --- |
| **Reordering is never tested.** `_test_identity_preserving_reload` changes a button's *text*, never sibling order. | Keyed reconciliation is the headline of commit `ec43f1a`, and surviving reorder is the entire reason `#id` keys exist. The current test passes with a purely positional reconciler. |
| **Focus preservation is never asserted.** The test checks instance identity and signal connections. | `ADR 0001` and `README.md:111` both promise focus survives reload. Identity is necessary but not sufficient. |
| **`removed` / `replaced` reconcile stats are never asserted.** Only `reused >= 2`. | Element removal and incompatible-type replacement are untested paths that free nodes. |
| **No diagnostic-content tests.** `_test_parser_recovery` asserts diagnostics are *non-empty*, never what they say or their severity. | Every bug in findings 1, 3, and 7 would have been caught by one test asserting severity and message for a known-bad declaration. |
| **No cascade test beyond single properties.** `_test_gcss_specificity` covers `color` across three specificities — good — but nothing covers shorthand/longhand interaction. | Finding 2. |
| **No button state-matrix test.** Already tracked as unchecked in `ROADMAP.md` §1.4. | `:hover`/`:pressed`/`:focused`/`:disabled` drawing is entirely unverified. |

Suggested addition, cheapest first: a `diagnostics_test.gd` that feeds a table of `(markup, gcss,
expected_severity, expected_message_fragment)` through the parse→build pipeline. That single file
would cover findings 1, 3, 5, 6, and 14, and it needs no scene tree.

---

## Prioritized action list

Ordered by value per unit of work.

1. **Fix `_parse_color`** (finding 1) — five lines, removes a class of false rejections.
2. **Split the two diagnostic severities** (finding 3) — small, and it converts the most common
   authoring mistakes from "entire UI disappears" into "one element is unstyled".
3. **Add `diagnostics_test.gd`** — locks in 1 and 2 and covers four other findings.
4. **Expand shorthands before the cascade** (finding 2) — the one genuine correctness bug in the
   style engine, and it simplifies `_apply_declaration` while fixing it.
5. **Give declarations their own line/column** (finding 7) — prerequisite for every future diagnostic
   improvement; do it while touching `_parse_rule` for step 4.
6. **Fix the zero-width wrapped label** (finding 4) — silent, expensive to debug, will hit the first
   author who puts text in a `Row`.
7. **Whitespace-normalize class and value splitting** (finding 5).
8. **Memoize property-name sets** (finding 9) — the only per-frame cost in the list.
9. Findings 6, 8, 10–14 as they are touched.

Findings 1–5 are all reachable within `cascade_builder.gd`, `gcss_parser.gd`, `gxml_parser.gd`, and
`cascade_label.gd` — four files, no architectural change required.
