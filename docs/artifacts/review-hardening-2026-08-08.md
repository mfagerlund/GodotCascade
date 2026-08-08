# Independent review hardening — 2026-08-08

## Scope and method

GodotCascade 0.8.1 received iterative, independent reviews from a Codex subagent and multiple read-only Claude Code/Opus passes. Reviewers inspected the complete uncommitted delta from 0.8.0, reproduced suspected failures, challenged documented contracts, and reran focused tests. Fixes were returned to a fresh reviewer until the Codex pass reported only documented limits; a final Claude pass then found four additional reproducible edge cases, which were fixed and re-verified before release.

The review covered runtime lifecycle and reconciliation, parsing and validation, bindings and generated C#, components and slots, collections and virtualization, focus, accessibility, Godot/VS Code language tooling, benchmarks, CI, packaging, certification, documentation, and clean installation.

## Substantive findings closed

- Balanced component mount/unmount behavior across detach and tree re-entry; deferred mounting no longer runs against a detached generated tree, and writable diagnostics are republished consistently.
- Made collection/repeat changes atomic around focus traps, including Repeat-owned and registered custom-Container traps, same-key state changes, empty results, virtual scrolling, and truthful fallback statistics/traces.
- Restored focus outside the document viewport correctly, preserved authored directional neighbours outside traps, bounded visibility checks to the generated root, and made autofocus honor effective visibility/disabled state while retaining `tab-index="-1"` programmatic eligibility.
- Preserved compatible live checkbox, radio, switch, select, and slider state unless its authored declaration changes. Slider regressions cover unrelated reloads, changed bounds, changed values, Progress behavior, and bound refresh precedence.
- Added authoritative visual-root, root-conditional, focus-owner, Repeat-template, virtual-row, table, duplicate-ID, and built-in-attribute validation with matching runtime/Godot/VS Code tests.
- Corrected table diagnostics for reusable components, nested/default slots, fallback slot content, and component-instance-local IDs without weakening invalid-structure checks.
- Restored supported `Option` selector IDs/classes and completed generated `format-*`/`parse-*` attribute coverage so validation matches the C# generator.
- Hardened binding paths, dynamic property caches, retained invalidation metadata, parser quote/source handling, nested media intersections, style-cache bounds, C# identifier/escaping/collision handling, and generated lifecycle cleanup.
- Added owned-control accessibility roles/names plus global table row/column semantics under repeated and virtual windows. Screen-reader announcement behavior remains a manual platform gate.
- Corrected certification closure so evidence committed after a clean certified revision can still close deterministically, while explicit target-commit and dirty-tree safety remain available.
- Ensured every newly required runtime/tooling module is tracked before packaging; archives are produced from the Git index and verified in a clean Godot project.

## Experiments and verification

The final local gate ran all eleven headless suites on both official Godot 4.7 and 4.7.1 console builds: flex engine, layout smoke, components, source pipeline, showcase app, language service, editor tooling, item model, collection scaling, virtualization, and platform-certification fixture. Output was rejected on a nonzero exit or any `SCRIPT ERROR`/`ERROR:` marker.

Additional successful gates:

- Godot 4.7.1 editor import scan with the plugin enabled;
- dependency-free VS Code syntax/provider/structure/navigation tests;
- repository formatting, JSON, relative-link/image, license, and comparison-artifact verification;
- generated showcase parity check;
- Python certification unit tests;
- generated C# example compilation in Release with zero warnings/errors;
- deterministic tracked-file addon packaging and clean-install smoke test;
- synthetic 500-control and representative settings/dashboard/table/10,000-item virtual-list benchmarks.

The benchmark experiment confirmed that the roughly 500 ms reconciliation figure is the median elapsed time for one complete equivalent 501-control reconciliation, not time per frame. Representative workload results stayed inside every absolute, relative, node-count, and collection-patch ceiling.

Approaches that did not hold up under review were deliberately replaced: hand-maintained schema fragments drifted from generator/runtime behavior; shallow table-tag projection could not model slotted components; preserving all desired control properties erased live uncontrolled state; and certification closure against bare `HEAD` conflicted with committing evidence. Each failed approach now has a focused regression.

## Residual limits

The remaining items are documented product limits or manual gates rather than reproducible release defects:

- VS Code workspace class/ID/custom-property rename is textual and must be previewed; Godot's source panel remains same-file.
- Source-only diagnostics cannot evaluate application binding data or runtime-only custom component schemas.
- Platform accessibility announcements, IME composition, clipboard services, touch selection, and virtual keyboards require real desktop/mobile service certification.
- The focused GXML/GCSS language intentionally rejects browser-wide syntax and impossible nested media intersections.

No community message, Godot Asset Library submission, or other authenticated third-party communication was performed. Those remain maintainer-controlled actions.
