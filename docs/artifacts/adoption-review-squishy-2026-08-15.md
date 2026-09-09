# Adoption review — a C# game client that evaluated GodotCascade and chose not to migrate

**Date:** 2026-08-15
**Reviewer:** Claude (Opus 5) with an independent Codex cross-check, working for the maintainer of
`C:\Dev\Evolvatron.Squishy`.
**Version reviewed:** 0.8.1 (`addons/godot_cascade/plugin.cfg`), working tree at `973a42e`.
**Method:** documentation and source reading only. **No build, test suite, benchmark or Godot session
was run against either repository.** Every claim below cites a file and a line; nothing here is a
runtime observation.

## What this is, and what it is not

This is an **adoption review by a prospective consumer**, recording why a specific real project
declined to migrate and what would change that. It is deliberately filed under a name that cannot be
mistaken for the roadmap's outstanding public-validation item.

**It is not the external-developer evaluation** that `docs/external-evaluation.md` asks for, and it
must not be used to tick that box. That protocol opens by saying it "does not substitute an automated
or AI review for experience from an external Godot developer", and it is right to. Two of its
requirements are unmet here by construction: the evaluator is not an external Godot developer, and no
interface was actually built. The corresponding ROADMAP entries stay unchecked:

- Phase 10 — *"Invite at least one external Godot developer to follow the real-interface evaluation
  protocol"*
- Phase 10 — *"Collect structured feedback on authoring speed, diagnostics, binding ergonomics,
  runtime cost, and missing controls"*

What this review can offer that a template response cannot is the **shape of the decision** — which
findings actually decided it, and in what order they were hit.

## The decision, and the one number behind it

**Verdict: did not migrate.** Not because the framework is weak; because the project is the wrong
customer, and that turned out to be measurable.

Two independent classifications of the client's UI source agreed:

| | layout/style a markup+stylesheet framework replaces | procedural paint / 3D / rasterisation | behaviour and live data |
|---|---:|---:|---:|
| per-line, 11 UI files, 2,967 impl. lines | **29%** | 39% | 33% |
| per-file, all 31 files, 15,904 lines | ~22% | ~39% | ~40% |

**About 70% of that UI is not replaceable layout on either count.** The client is a soft-body physics
game: `MultiMeshInstance3D` creature skins, a spatial-shader terrain, a `SubViewport` voxel editor
with an Amanatides–Woo picking walk, a procedural run chart with gradient-filled stacked bands, and
seven icons rasterised in code from predicates. GodotCascade competes for the remaining third, and
the third that remains is heavily coupled to live simulation state.

**This is a positioning finding, not a defect.** GodotCascade's own benchmark fixtures — settings,
system dashboard, leaderboard, virtual inventory (`docs/performance.md`) — name its real customer
precisely. The README does not. An adopter cannot currently tell from the front page whether their
project is in the 29% case or the 90% case, and that is the single cheapest thing to fix in the whole
list below (**C12**).

---

## Findings

Priority key: **P0** blocks a C# adopter on day one · **P1** costs an adopter real time · **P2** doc
and polish.

### C1 · P0 — `CLAUDE.md` describes a framework three versions and one language behind the repository

`CLAUDE.md:7-12` says the project is "public-preview" and that "Everything is GDScript; there is no
C# in this project." `CLAUDE.md:25-38` says there is no test framework and lists **four** standalone
`SceneTree` scripts. `CLAUDE.md:143-151` describes the supported subset in terms of "the 0.2 line"
and "version 0.3".

The repository is at **0.8.1**. There is a typed C# binding generator
(`addons/godot_cascade/codegen/csharp_binding_generator.gd`), a compile gate for its output, and CI
runs **eleven** headless suites plus performance gates, packaging and a clean-install smoke
(`.github/workflows/ci.yml:65-96`).

**Why it decided things.** This file is the first thing an agent or a maintainer-adjacent reader
loads. This review began by concluding that the C#/GDScript boundary was total and that the framework
was a four-test preview — both false, and both corrected only after reading `current-support.md`,
`CHANGELOG.md` and the workflow. A prospective adopter who stops at the front matter gets a strictly
worse impression than the software deserves. **This finding costs GodotCascade adoptions.**

**Fix.** Remove every version number and every count from `CLAUDE.md` and point at the two files that
are already maintained (`CHANGELOG.md`, `.github/workflows/ci.yml`). Numbers in a hand-maintained
guidance file are a liability at this release cadence — eight version lines landed between 2026-08-06
and 2026-08-08 (`CHANGELOG.md:7-89`). If a number must stay, add a CI step that greps `CLAUDE.md` for
a version string and fails when it disagrees with `plugin.cfg:6`.

**Cost:** under an hour.

---

### C2 · P0 — Generated C# bindings are unavailable exactly where repetition lives

`docs/current-support.md:116-126`: generated `@Name` bindings inside reusable component templates or
passed as component parameters "are not currently supported because one generated field cannot
identify multiple scoped instances", and the guidance is to fall back to runtime property paths.

**Why it matters.** Components and `Repeat` are where a real UI puts its repetition — menu cards,
leaderboard rows, inventory cells, record lists. That is also where hand-writing bindings hurts most.
So the typed path is offered precisely where it is least needed and withdrawn precisely where it is
most needed, and the adopter discovers this after committing to codegen for the easy screens.

**Fix.** The stated obstacle is real for a *field* and not for an *accessor*. Emit an indexed or
instance-scoped accessor rather than one field per binding — `Rows[i].Title`, or a generated
`IReadOnlyList<RowBindings>` refreshed alongside keyed reconciliation, keyed by the same `cascade_key`
the reconciler already maintains (`docs/architecture.md:78`). The identity mechanism exists; only the
codegen shape assumes cardinality one.

**In the meantime:** say this limit in the README's C# section, not only in the support matrix. It
changes whether codegen is worth adopting at all.

**Cost:** meaningful — this is the largest item on the list, and the highest value.

---

### C3 · P0 — There is no C# surface for the document itself, only string dispatch

`docs/bindings.md:382-417`: C# holds the document as a plain `Control` and drives it with
`Set("binding_context", model)` and `Call("refresh_bindings")`. `docs/bindings.md:370` states that
control lookup and native target assignment "still use Godot's dynamic `Call`/`Set` APIs, so a target
that is incompatible with its native control is diagnosed at runtime rather than by the C# compiler."
The generated partial does not change this — it subscribes to `"document_reloaded"` by string,
searches by `cascade_id` metadata, and connects signals by name
(`examples/codegen/SettingsBindings.g.cs.txt:41-77`, `:80-105`, `:129-145`).

Authored handlers are the same: `on-*` stores a method-name string
(`addons/godot_cascade/runtime/binding_compiler.gd:53-68`), checked at runtime with
`target.has_method(...)` (`addons/godot_cascade/runtime/cascade_document.gd:2035-2077`). Renaming a
C# handler does not rename the GXML, and the failure is a warning.

**Why it matters.** The evaluated client routes its whole UI through typed C# events —
`WorldChanged`, `ViewModeChanged`, `ResetRequested`, `MutationScaleChanged`, `CopyRequested`
(`ControlPanel.cs:26-66`) — wired straight into a running service. Adopting Cascade means either
maintaining a hand-written typed façade *anyway*, or spreading string dispatch through the
application. Both are costs the framework could absorb once instead of every adopter paying.

**Fix.** Ship a thin `CascadeDocument.cs` façade **inside the addon**: a C# class wrapping the
dynamic calls, exposing `BindingContext`, `RefreshBindings()`, `Diagnostics`, `DocumentReloaded`,
`Find<T>(string id)`. It is a few hundred lines, needs no engine work, and removes essentially all
day-one string dispatch from consumer code. This is the highest ratio of adopter-pain-removed to
maintainer-effort in the list.

**Cost:** low relative to impact.

---

### C4 · P0 — The C# gate compiles a checked-in snapshot, and never runs it

`docs/bindings.md:378-380`: the two C# samples are stored as `.cs.txt` "because its own showcase
project remains GDScript-only". `tests/codegen_compile/CodegenCompile.csproj` sets
`EnableDefaultCompileItems=false` and pulls those two files in explicitly by `<Compile Include=…
Link=…>`; `.github/workflows/ci.yml:82-83` builds it. So the generated partial and the user-owned
partial **are** compiled on every CI run — this review's first draft implied they were not, and that
was wrong.

**The accurate finding is sharper than the wrong one.** Two gaps remain, and they are the ones that
matter:

1. **The generator never runs in CI.** What is compiled is a *committed snapshot* of its output
   (`examples/codegen/SettingsBindings.g.cs.txt`). Change `csharp_binding_generator.gd` and the gate
   stays green against last month's output. `docs/bindings.md:332-338` and `:378` are explicit that
   changing a contract requires regenerating and then a normal .NET build — that is exactly the step
   nothing enforces, and it is the same class of failure as a stale lockfile.
2. **Nothing executes it.** Compiling proves the emitted signatures are well-formed C#. It cannot
   prove that `Set("binding_context", …)` reaches a native control, that the `cascade_id` lookup
   finds anything, or that `"document_reloaded"` is still the signal's name — and
   `docs/bindings.md:370` says precisely those are runtime-checked. Rename a metadata key in
   `cascade_builder.gd` and every C# consumer breaks with a green CI.

**Fix.** Two steps, in order:

- **Regenerate-and-diff:** run the generator over `examples/codegen/settings_bindings.gxml` in CI and
  fail if the output differs from the committed `.g.cs.txt`. This is the cheap half and it closes
  gap 1 outright.
- **Promote the project to a runtime test:** load one GXML document headless, set a binding context
  from C#, assert a bound value reached a native control, exit non-zero on any diagnostic. That
  closes gap 2 and turns the whole C# section of the docs from claim into evidence.

**Fix.** Promote `tests/codegen_compile` from a compile check to a Godot .NET project that loads one
GXML document headless, sets a binding context from C#, asserts a bound value reached a native
control, and exits non-zero on any diagnostic. Add it to the CI matrix beside the eleven GDScript
suites. That single test converts the whole C# section of the docs from claim to evidence, and it is
the prerequisite for **C2** and **C3** being trustworthy once built.

**Cost:** one day, and it is the item I would do first.

---

### C5 · P1 — `Window` is not implemented, and the docs present it as a gap rather than a seam

`docs/current-support.md:38`: "`Window` is not implemented", listed among unknown-element build
errors.

**Why it matters.** Dialogs are the structural unit of tool and settings UI — the exact category the
framework is otherwise aimed at. The evaluated client has a scrolling world dialog built on
`AcceptDialog` (`ControlPanel.cs:673-756`) and a records screen that *derives* from `AcceptDialog`
(`HallOfRecords.cs:21-52`). This finding invalidated this review's first choice of trial screen: the
natural "small, self-contained, low-risk slice" in a desktop UI is usually a dialog, and a dialog is
the one shape Cascade cannot host end to end.

**Fix, cheap version:** stop stating this as an absence. Document the supported pattern — a native
`Window`/`AcceptDialog` hosting a `CascadeDocument` as its content — with a worked example and a note
on sizing, since a dialog that sizes to its content is where the seam actually bites. One page turns
a perceived blocker into a known integration.

**Fix, real version:** a `Dialog` element that owns a native `Window`. Note that this interacts with
reconciliation: a window is not in the document's control tree, so keying and last-valid rendering
both need a decision.

---

### C6 · P1 — No `MenuButton` / `PopupMenu`

Not present in the element matrix (`docs/current-support.md:7-32`). The evaluated client uses a
`MenuButton` with a native popup dispatched by id (`ControlPanel.cs:302-310`, `:431-449`), adopted
for a documented reason: a menu is the one control that does not grow the panel when the application
grows a screen.

**Why it matters.** Same class as **C5** — a standard desktop control that any settings-heavy UI
reaches for, absent from the matrix and unmentioned in the escape-hatch documentation.

**Fix:** at minimum, document the `ComponentRegistry` route for hosting one
(`docs/markup-and-state.md:89-107`). Better, add `Menu`/`MenuItem` elements — the interaction model is
already close to `Select`, which is implemented.

---

### C7 · P1 — Selector lists are the most-missed CSS construct, and adding them changes no semantics

`docs/current-support.md:141`: "Selector lists, sibling combinators, attribute selectors, `:not()`,
and other functional selectors are not supported."

Of that set, **selector lists are qualitatively different from the rest.** Sibling combinators and
`:not()` require new matching semantics. A selector list requires none: it is `N` compound selectors
sharing a declaration block, and specificity is already per-selector.

**Why it matters, concretely.** The evaluated client's theme applies one identical rule across
`Button`, `OptionButton`, `MenuButton` and `CheckBox` (`Skin.cs:46-59`). In GCSS that is four
duplicated blocks that must be edited together — which is the precise failure the client's own theme
file was written to eliminate, reintroduced by the stylesheet language. Duplication that must stay in
sync is worse in a stylesheet than in code, because nothing type-checks it.

**Fix.** Parse `a, b, c { … }` into `N` `Rule` objects sharing one declaration set. Selector matching
lives on `Rule.matches()` (`CLAUDE.md:77-79`), so nothing downstream changes; specificity and source
order already work per rule. This looks like the best value-per-line item in the language surface.

---

### C8 · P1 — Divergent *defaults* are the real familiarity trap, and they are the one class diagnostics cannot catch

The framework's stated invariant is that "unsupported input produces a diagnostic, never a silently
stored value" (`CLAUDE.md:98`). That invariant is excellent and it does not cover this case, because
these inputs are **supported and valid** — they simply mean something different than the same source
means in a browser:

- **`flex-shrink` defaults to `0`, not `1`** (`docs/current-support.md:197`), "to preserve preview
  layouts". A CSS author's rows will not shrink, nothing is diagnosed, and the symptom is overflow
  rather than an error.
- Percentages, `em`/`rem` and browser value functions are absent (`:195`).
- Opacity is Godot modulation, not offscreen group compositing (`:197`).
- Transforms reject browser matrix ordering, skew, perspective, percentages and matrices (`:197`).

**Why it matters here specifically.** The premise that prompted this evaluation was "an LLM has seen
billions of lines of HTML/CSS and very little Godot". That premise is true, and **these findings are
the reason it does not transfer.** Familiarity with a lookalike subset produces *confident* errors,
and the confident errors concentrate exactly on layout defaults — the highest-frequency, lowest-
visibility part of the surface. `flex-shrink: 0` is the sharpest instance in the whole framework: the
authored source is valid, the rendered result is wrong, and the author's prior is what misled them.

**Fix.** A **`strict-web-compat` lint mode** that warns on constructs whose GCSS meaning differs from
their browser meaning — starting with a `flex` container that authors no explicit `flex-shrink`.
Off by default, on in CI and in the editor. This is the only mechanism that reaches the
valid-but-divergent class, and this framework's whole diagnostic philosophy says it should exist.

**Also cheap:** move the "do not infer support from CSS or HTML familiarity" warning out of
`CLAUDE.md` and `current-support.md` and into the top of `docs/getting-started.md`, which is where a
new adopter actually starts. Right now the warning is filed where the people who already know it will
find it.

---

### C9 · P1 — Source watching polls unconditionally, including in shipped builds

`addons/godot_cascade/runtime/cascade_document.gd:37-43`: `watch_sources := true`,
`watch_interval := 0.25`. `:108-109`: `_ready()` calls `set_process(watch_sources)` with no
editor, debug, or export gate. `:129-134`: `_process` polls sources every 0.25 s, forever, per
document.

**Why it matters.** Live reload is one of the framework's best properties in the editor and pure cost
outside it. In a shipped game every document stats the filesystem four times a second against sources
that are baked into the PCK and cannot change. In a headless acceptance run it is the same waste, on
a run whose entire purpose is a stable measurement.

**Fix.** Default to `OS.has_feature("editor")` rather than `true`, or gate `set_process` on it and
keep the export as an override. One line, plus a note on the shipping page. If the default must stay
`true` for preview ergonomics, the shipping documentation needs to say "turn this off" prominently —
it currently does not.

---

### C10 · P1 — Last-valid rendering is right for authoring and dangerous for automated acceptance

An error diagnostic aborts the swap and leaves the previous valid tree on screen
(`CLAUDE.md:130-134`). For live authoring this is the correct and generous behaviour.

**Why it matters.** Under automation it converts a broken UI into a **silently passing** one: the
acceptance run sees a rendered, interactive, entirely stale interface. The evaluated project has this
exact failure class already written down from its own history — a gated stage passes by not running,
so a clean log can mean skipped. Note also that the behaviour is *not uniform*: on first load there is
no previous tree, so the same authoring error fails loudly or silently depending on whether a valid
build preceded it. That asymmetry is the part most likely to be misdiagnosed.

**Fix.** A documented `strict` / `fail_fast` mode in which any `severity == "error"` diagnostic is
fatal, plus a five-line recipe in the testing documentation for "build a document headless and assert
zero diagnostics". **This is the single change I would want in hand before putting a Cascade document
behind a CI gate**, and it is small.

---

### C11 · P2 — The node-count multiplier is published but not explained in the terms that decide adoption

`docs/performance.md` sets node-count ceilings of 25–30× native for the settings, dashboard and
leaderboard fixtures, and is careful and honest that its millisecond figures are complete-operation
build costs rather than per-frame measurements.

**Why it matters.** For an adopter placing a document beside a 60 fps 3D viewport, the *steady-state*
cost is the question, and the docs answer the build-time one. A 30× node count is a layout-and-sort
cost every frame the tree is dirty, not only at build.

**Fix.** State what drives the multiplier (owned components wrap native controls, so one authored
`Button` is several `Control`s), and publish one steady-state number — idle frame cost for the
settings fixture with and without the document — even if it is "indistinguishable from native". If it
is indistinguishable, that is a strong selling point currently going unclaimed.

---

### C12 · P2 — The README does not tell an adopter whether they are the customer

`docs/performance.md`'s fixture list — settings, system status/dashboard, leaderboard, 10k virtual
inventory — is an exact and well-chosen description of who this framework is for. The README leads
with capability instead.

**Fix.** One paragraph near the top: *"GodotCascade is aimed at settings screens, dashboards, tool
panels, inventories and leaderboards — interfaces that are mostly structure, text and state. It is
not aimed at UI that is mostly custom `_Draw`, viewports or procedural meshes; those remain your
code, and Cascade will lay them out but not replace them."* This costs nothing, disqualifies the
wrong adopters early, and makes the right ones more confident. It would have saved this evaluation
most of its time.

---

## What is good, and should not change

These are load-bearing and worth protecting under refactoring pressure:

- **`docs/current-support.md` is unusually honest.** It states limits as decisions with reasons —
  "intentionally unsupported", "this is a semantic display table, not a data-grid widget", "not CSS
  family lookup or `@font-face`". Most preview frameworks describe what they do; this one describes
  its boundary, which is the more useful half and the harder one to write.
- **Diagnostics rather than silence**, as an invariant with a stated contract (`CLAUDE.md:98`,
  `:128-134`). **C8** is not a counterexample to this — it is the one class the invariant provably
  cannot reach, which is why it needs a separate mechanism.
- **The testable seams are real ones.** Parsers never create nodes; `FlexLayoutEngine` never touches
  the scene tree, so layout maths is tested with no scene at all (`CLAUDE.md:92-98`). That is a
  genuine architectural achievement and it is why the eleven-suite CI is credible.
- **`docs/performance.md` says "these are regression ceilings, not performance targets"** and
  explains what one sample measures. That is honest benchmarking, and it is rare.
- **`docs/external-evaluation.md` refuses to let an AI review count as external validation.** It was
  right, this document is an instance of exactly what it excludes, and the roadmap boxes stay
  unchecked. Keep that.

## Suggested order

1. **C4** — regenerate-and-diff in CI (cheap, closes generator drift on its own), then make the
   C# path *execute*. Everything else about C# is a compile-time claim until it does.
2. **C3** — the C# façade. Largest adopter-pain reduction per line of maintainer effort.
3. **C1** — fix the front matter. Under an hour, and it is currently costing adoptions.
4. **C10** and **C9** — strict mode and the watch gate. Both small, both required before a document
   goes behind anyone's CI or into anyone's shipped build.
5. **C7** — selector lists. Best value-per-line in the language.
6. **C12** and the `getting-started` half of **C8** — documentation, near-zero cost.
7. **C2** — scoped generated bindings. The big one, and worth scheduling deliberately rather than
   squeezing in.
8. **C5**, **C6**, **C8**'s lint mode, **C11** — as the roadmap allows.

## What would change the migration decision

For this project specifically, and stated so it is falsifiable:

- **C2** and **C3** shipped, so application-owned C# contains no runtime ID, property or method
  strings.
- **C4** green in CI, so the C# path is evidence rather than documentation.
- **C10**, so a document can sit behind a per-push gate without a broken UI reading as a pass.
- A stable release line with at least one external production-shaped customer that is not the
  maintainer — i.e. the ROADMAP items this document explicitly does not satisfy.

Absent those, the decision would still be no **even if every one of C5–C12 were fixed**, because the
70% figure at the top is a property of the project rather than of the framework. That is worth
stating plainly: **most of what is written above is not why this project declined.** The findings are
offered because they were found on the way, and because the ones that block a C# adopter — C1 through
C4 — will block the next one too.
