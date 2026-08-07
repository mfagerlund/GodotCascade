# GodotCascade versus GTML: deployment queue

Date: 2026-08-07

This is an intentionally candid comparison of one production-shaped operations screen, not a showcase scene. Independent GodotCascade and GTML implementations load the same 12-job fixture and expose the same tested workflow: editable deployment settings, validation, filtering, queue/add/remove, row selection and writeback, keyed priority sorting, status summaries, and malformed-source behavior.

The complete fixture, implementations, verification scripts, and runner live in [`comparisons/deployment-queue`](../../comparisons/deployment-queue/README.md). GTML is not vendored: the runner checks out and verifies upstream commit `7ddabfe3cffa69d7c8abd12b8d69bf80de49e59f` (`plugin.cfg` version `0.8.4`) in a temporary directory. Both sides were executed with the SHA-verified official Godot 4.7.1 Windows console build.

## Native captures

| GodotCascade | GTML |
|---|---|
| ![GodotCascade deployment queue](deployment-queue-godotcascade.png) | ![GTML deployment queue](deployment-queue-gtml.png) |

The visual designs are deliberately comparable rather than pixel-identical. GodotCascade uses its semantic native table; GTML uses an idiomatic flex row list.

## Functional result

Both implementations passed the complete scripted workflow:

- 12 fixture jobs loaded, with 10 initially visible and all 12 visible after enabling paused items;
- operator/environment/concurrency form values wrote back;
- an invalid operator prevented queueing;
- add then remove returned the queue to 12 rows;
- row state wrote back;
- priority sorting produced the expected order and preserved the keyed row control's native identity;
- the final rendered endpoint matched the mutated state.

The diagnostic behavior differs. GodotCascade rejected an unsupported GXML element and retained the last valid native tree. GTML warned about the deliberately mismatched closing tag and recovered a new parsed tree rather than retaining its previous tree. Both behaviors are usable, but GodotCascade's last-valid policy is safer for live source editing.

## Measurements

All values below are complete synchronous operations in milliseconds—never per-frame values. Cold build is the median of ten samples. Batch endpoints were rendered and checked. See the machine-readable [result file](deployment-queue-results.json) for every sample, process diagnostic count, and capture size.

| Measurement | GodotCascade | GTML | Interpretation |
|---|---:|---:|---|
| Cold build median | 185.360 ms | 39.452 ms | GTML was 4.7× faster in this fixture |
| 100 individually rendered scalar updates | 4,357.338 ms total | 1.045 ms total | Cascade's current explicit per-update Repeat refresh is the wrong granularity for high-frequency scalar changes |
| 100 scalar mutations, one Cascade refresh | 40.894 ms total | n/a | Coalescing cuts Cascade's measured batch by about 99.06%, but it remains an explicit application responsibility |
| 40 keyed priority reorders | 12,109.040 ms total | 23.772 ms total | GTML's retained reactive list path was about 509× faster |
| Native controls after build | 103 | 132 | Neither implementation materializes a browser DOM; the structures differ |
| Nonblank runtime UI source | 381 lines | 329 lines | Cascade used about 16% more physical source in this implementation |

The extreme scalar ratio needs context. The GodotCascade implementation deliberately rendered each mutation through its current localized Repeat-candidate/reconciliation path; GTML updated its retained reactive tree. The coalesced Cascade sample demonstrates the supported mitigation, but does not erase the architectural gap. This experiment therefore closes a roadmap validation item while also creating a clear optimization target: property-only changes inside retained rows must avoid rebuilding a Repeat candidate.

These are local microbenchmarks of one screen, not general throughput rankings. They exclude import/editor startup, use one Windows machine, and do not measure GPU frame time, memory, authoring time, or team familiarity. GTML's HTML-like authoring and reactive updates are materially more mature for frequently changing retained lists. GodotCascade's advantages in this fixture are native semantic table structure, stricter source diagnostics, last-valid reload behavior, explicit fixed contracts, and a dependency-free addon surface.

## Conclusion

The comparison does not make GodotCascade pointless, but it does rule out claiming that it is already a faster or more ergonomic general replacement for GTML. GodotCascade is useful when a project values native Godot controls, GCSS-style owned layout components, semantic tables/forms, deterministic diagnostics, and last-valid source reloads. GTML is the stronger choice today when HTML familiarity and fine-grained reactive update performance dominate.

Publishing GodotCascade as an experimental project remains worthwhile if communication is equally direct about this performance gap and asks the Godot community to validate the authoring model on real interfaces. The next technical response should be retained property-level row invalidation, followed by rerunning this exact pinned comparison—not a new showcase benchmark.

## Reproduce

```powershell
python comparisons/deployment-queue/run_comparison.py `
  --godot "C:\path\to\Godot_v4.7.1-stable_win64_console.exe" `
  --capture
```

The runner verifies the GTML commit, functional assertions, rendered endpoints, identity retention, diagnostics, source metrics, captures, and JSON output. Its temporary GTML checkout is removed after the run.
