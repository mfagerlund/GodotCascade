# Performance budgets

## Synthetic pipeline gate

The executable pipeline benchmark builds, lays out, snapshots, and reconciles a 500-item source-generated interface. It also cold-builds the same 500 controls with inherited custom properties and typed `calc()` on gap, height, and color, and with 500 unique selector rules to exercise computed-style cache pressure. Variables and arithmetic resolve during build/reload, not per frame. Reconciliation reports the median of three complete equivalent-tree operations so transient scheduler or antivirus activity during one measured interval does not decide the gate. It enforces deliberately broad preview budgets so accidental algorithmic regressions fail while normal machine variance does not:

| Stage | Budget |
| --- | ---: |
| Parse plus native build | 2000 ms |
| Expression-heavy parse plus native build | 2500 ms |
| 500-rule parse plus native build | 3000 ms |
| Two-frame layout | 1000 ms |
| Median equivalent keyed reconciliation (three samples) | 1500 ms |
| Native controls | 501 (one root plus 500 authored labels) |
| Equivalent reconcile allocation | zero created/replaced controls; 501 reused |

The scale suite separately exercises typed collection changes and fixed-height 10,000-item list/table windows. It asserts bounded realized controls, zero complete-document candidates, correct midpoint/end keys, overlapping keyed identity, key-based focus pinning, fractional anchors, effective native scrollbar viewport extent, invalid-cache scroll blocking, multi-Repeat transaction atomicity, and automatic recovery.

## Representative workload gate

`benchmarks/workload_benchmark.gd` measures the actual settings-menu, system-status/dashboard, leaderboard, and 10,000-item virtual-inventory showcase scenes. Each implementation is constructed from scratch five times and the median is reported. **Each millisecond sample is the total elapsed time for one complete operation: fresh instantiation, tree entry and ready/build, followed by two complete process/layout frames. It is not a per-frame measurement.** Packed scenes and scripts are preloaded, while each Cascade document still reads and parses its GXML/GCSS during the timed build. The interval excludes initial scene/script loading, import, and editor/application startup.

Every Cascade workload is compared with a clearly described, dependency-free, hand-authored native Godot `Control` tree containing equivalent semantic content. The inventory comparison uses a fixed-height native window whose initially realized row count is derived from and exactly matches the Cascade window at the 1280×800 benchmark viewport. It also measures a native `ItemList` populated with all 10,000 flattened record strings as the closest built-in specialized alternative.

The workload gate additionally records every native `Control`, rejects Cascade diagnostics or missing generated roots, requires stable node counts across runs, and probes an actual visible collection update. That probe retains item 0's key, changes its displayed name, verifies the rendered cell changed, and requires a successful collection-only reconciliation with zero full-document candidates.

| Workload | Total Cascade ceiling | Relative ceiling | Native controls ceiling | Additional ceiling |
| --- | ---: | ---: | ---: | ---: |
| Settings | 1200 ms | 30× native | 180; 3× native | — |
| System status/dashboard | 1200 ms | 25× native | 140; 3× native | — |
| Leaderboard | 1200 ms | 30× native | 260; 3× native | — |
| 10k virtual inventory | 3000 ms | 25× native | 320; 3× native | 1500 ms for collection patch plus two frames |

These are deliberately broad regression ceilings derived from verified Godot 4.7.0 and 4.7.1 results, not promises or marketing targets. The full methodology, both result sets, corrections made while validating the harness, and interpretation limits are recorded in the [2026-08-07 representative workload report](artifacts/representative-workload-benchmark-2026-08-07.md).

Run them with:

```powershell
godot --headless --path . --script benchmarks/pipeline_benchmark.gd
godot --headless --path . --script benchmarks/workload_benchmark.gd
godot --headless --path . --script tests/item_model_test.gd
godot --headless --path . --script tests/collection_scaling_test.gd
godot --headless --path . --script tests/virtualization_test.gd
godot --headless --path . --script tests/platform_certification_test.gd
```

Each benchmark prints one JSON measurement record and exits non-zero when a diagnostic, invariant, or budget fails. These are regression ceilings, not performance targets. Changes that intentionally raise a budget require an explanation in the roadmap or migration notes and a new representative fixture.

Computed-style cache entries are shared by equivalent selector/ancestry signatures, property lookup lists are cached by native class/script, and compatible hot reloads mutate existing controls rather than rebuilding the scene subtree.

A full `refresh_bindings()` intentionally validates the whole candidate when a document combines an active focus trap with a binding that can change `visible` or `disabled`. That conservative parse/build step prevents a failed update from partially changing focus containment. Prefer targeted invalidation for ordinary value changes; use the full refresh boundary when several related mutations must become visible atomically.
