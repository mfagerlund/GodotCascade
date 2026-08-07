# Representative workload benchmark — 2026-08-07

This report records the verified Phase 13 workload benchmark implemented by [`benchmarks/workload_benchmark.gd`](../../benchmarks/workload_benchmark.gd). It measures real GodotCascade showcase documents against explicitly defined native Godot alternatives. It does not contain GTML, RUITK, browser, or other unmeasured framework numbers.

## Timing semantics

Every timing below is a **total operation time**, never a per-frame time.

- Five fresh operations were measured for every implementation; tables report the median of those five samples.
- One cold workload operation begins immediately before a fresh scene/factory instantiation, includes tree entry and synchronous `_ready()`/document construction, and ends after two complete process/layout frames.
- The inventory collection operation changes a visible item through `CascadeArrayItemModel.update()` and likewise includes two complete process/layout frames.
- The benchmark viewport is 1280×800.
- Packed scenes and benchmark scripts are preloaded. Each Cascade document still reads and parses its GXML/GCSS sources inside the timed build. The interval excludes initial scene/script resource loading, import, editor startup, and application launch; filesystem caching can still influence the included source reads.
- Each result set is produced by one invocation of the harness. The harness emits exactly one JSON record and exits non-zero on diagnostics, invariant failures, or exceeded ceilings.

Ordinary rendered frames do not repeat these cold costs. GXML parsing, GCSS resolution, binding construction, and native-control creation occur during document construction/reload. The two frames in each sample allow Godot containers and deferred virtualization work to settle; dividing these totals by two would not produce a meaningful frame time.

## Compared implementations

| Workload | GodotCascade implementation | Hand-authored native baseline |
| --- | --- | --- |
| Settings | Actual `examples/settings_menu_showcase.tscn`, including GXML/GCSS parsing, typed state, owned controls, bindings, and layout | `VBoxContainer`/`HBoxContainer`/`PanelContainer` tree with equivalent headings, labels, check/radio controls, text fields, slider, select, binding monitor, and action |
| System status/dashboard | Actual `examples/system_status_showcase.tscn` | Native container/card tree with equivalent metrics, progress bars, tags, and action |
| Leaderboard | Actual `examples/leaderboard_showcase.tscn`, semantic table and five keyed rows | Native `ScrollContainer`/`GridContainer` with the same seven columns, five data rows, and row/footer actions |
| 10k virtual inventory | Actual `examples/collection_scale_showcase.tscn`, typed 10,000-item model and virtual semantic table | Native `ScrollContainer` with its own 10,000-Dictionary model, an unrealized extent spacer, and exactly the same 14 initially realized fixed-height rows as Cascade |
| 10k specialized alternative | The same virtual inventory scene | Native `ItemList` populated with all 10,000 records flattened to display strings |

The native workload baselines are executable in [`benchmarks/native_workload_baselines.gd`](../../benchmarks/native_workload_baselines.gd). They reproduce semantic content and native-control shape without GodotCascade or a custom visual theme; they are not claimed to be pixel-identical showcase implementations.

## Results: official Godot 4.7.1 stable standard build, Windows

Each time is the median **total cold construction plus two complete frames** across five samples.

| Workload | Cascade total | Native total | Cascade/native cold-cost ratio | Controls, Cascade/native |
| --- | ---: | ---: | ---: | ---: |
| Settings | 212.841 ms | 13.810 ms | 15.41× | 55 / 46 |
| System status/dashboard | 122.756 ms | 13.765 ms | 8.92× | 39 / 38 |
| Leaderboard | 168.019 ms | 13.791 ms | 12.18× | 76 / 53 |
| 10k virtual inventory | 549.285 ms | 119.344 ms | 4.60× | 82 / 61 |

The inventory collection update plus two complete frames had a 158.727 ms median total. It retained the stable key, visibly changed the first rendered record, and reported 10,000 model items, 14 realized rows, one repeat candidate, 59 candidate/reused controls, one changed key scanned, and zero full-document candidates. The native `ItemList` alternative had a 627.044 ms median total for construction, population with 10,000 strings, and two frames.

Result: pass, one JSON record, zero benchmark failures, and no warnings/errors outside the record.

## Results: official Godot 4.7.0 stable standard build, Windows

Each time is the median **total cold construction plus two complete frames** across five samples.

| Workload | Cascade total | Native total | Cascade/native cold-cost ratio | Controls, Cascade/native |
| --- | ---: | ---: | ---: | ---: |
| Settings | 219.262 ms | 13.797 ms | 15.89× | 55 / 46 |
| System status/dashboard | 133.277 ms | 13.782 ms | 9.67× | 39 / 38 |
| Leaderboard | 193.400 ms | 13.775 ms | 14.04× | 76 / 53 |
| 10k virtual inventory | 671.368 ms | 88.116 ms | 7.62× | 82 / 61 |

The inventory collection update plus two complete frames had a 270.577 ms median total and passed the same visible-output, model-count, bounded-window, one-key-scan, localized-reconciliation, and zero-full-document-candidate invariants. The native `ItemList` alternative had a 485.065 ms median total.

Result: pass, one JSON record, zero benchmark failures, and no warnings/errors outside the record.

## Regression ceilings

The harness fails above the following deliberately broad ceilings:

| Workload | Cascade total | Cold ratio vs native | Control count | Control ratio vs native | Collection total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Settings | 1200 ms | 30× | 180 | 3× | — |
| System status/dashboard | 1200 ms | 25× | 140 | 3× | — |
| Leaderboard | 1200 ms | 30× | 260 | 3× | — |
| 10k virtual inventory | 3000 ms | 25× | 320 | 3× | 1500 ms |

These ceilings allow substantial runner variance while still detecting unbounded materialization, multi-second regressions, or gross divergence from the native control trees. They are not target latency, throughput guarantees, or claims that a 10× cold-cost ratio is desirable. The observed ratios show a real construction cost for parsing, styling, binding, and producing the richer Cascade trees; they should remain visible rather than being presented as native-equivalent performance.

## Corrections and rejected early measurements

Three early harness results were rejected before this report was recorded:

1. Assigning an explicit size to showcase roots that already used opposite full-rect anchors caused Godot warnings. The final harness lets those roots inherit the benchmark `Window` size and only explicitly sizes equal-anchor native roots. Final runs emit no warnings.
2. The first native inventory baseline realized 22 rows while Cascade realized 14 at the benchmark viewport. That node comparison was not like-for-like. The final native factory receives Cascade's observed initial window size and realizes the same 14 rows; the harness asserts the counts match.
3. The first collection probe replaced item 0 with an identical Dictionary. It exercised reconciliation but did not prove visible output changed. The final probe preserves the key, changes the visible name, and searches the resulting native tree for the new rendered value before passing.

These were benchmark-design defects, not product failures, and none of their rejected timings are used in the result tables.

The first valid visible-update measurement still exposed a product hotspot: every typed update rescanned all 10,000 keys. A retained, validated typed-delta key cache was then added. Insert/update changes now read only their changed range, remove/move changes reuse keys without model reads, and reset deliberately rescans the collection. Duplicate or missing keys abort the complete collection transaction atomically and a later repairing delta performs a safe validation pass before recovery. The final tables record a one-key visible update plus the later fixed-height and transaction-safety checks. Because those safety checks changed the measured work and local machine load varied, the earlier and final elapsed totals are not presented as a clean optimization ratio; the verified algorithmic result is the reduction from 10,000 model-key reads to one.

## Interpretation limits

- Both verified result sets came from the same Windows development machine in headless mode. They establish Godot 4.7.0/4.7.1 compatibility and a local regression baseline, not cross-hardware or cross-platform performance.
- Five samples and a median reduce isolated noise but are not a statistically rigorous performance study.
- Headless elapsed time does not measure GPU draw cost, visual smoothness, input latency, or steady-state frame time.
- The native baselines omit custom showcase theming and source-language services. They are useful construction references, but not feature-identical substitutes.
- `ItemList` is specialized and stores its entries internally; its 13-node tree cannot be compared directly with the semantic table's native-control count. It also flattens three columns into one display string and does not provide the same table structure.
- Typed item-model deltas retain a validated key cache: inserts and updates read only the changed key range, removes and moves read no model keys, and reset performs a deliberate full scan. The visible update measured here reads one key. These bounds do not remove the cost of rebuilding and reconciling the realized Repeat window.
- Results may change with CPU load, debug/runtime configuration, renderer, Godot builds, and project changes. The checked ceilings, rather than these exact medians, are the automated regression contract.

## Reproduction

From the repository root, run either supported engine explicitly:

```powershell
& "C:\path\to\Godot_v4.7-stable_win64_console.exe" --headless --path . --script res://benchmarks/workload_benchmark.gd
& "C:\path\to\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script res://benchmarks/workload_benchmark.gd
```

Read the single JSON line whose schema is `godot-cascade-workload-benchmark/v1`. In particular, the timing fields are named `median_total_cold_build_plus_two_frames_ms` and `median_total_collection_patch_plus_two_frames_ms` to prevent a cold batch from being mistaken for per-frame work.
