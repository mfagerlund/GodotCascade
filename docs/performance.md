# Performance budgets

The executable pipeline benchmark builds, lays out, snapshots, and reconciles a 500-item source-generated interface. It enforces deliberately broad preview budgets so accidental algorithmic regressions fail while normal machine variance does not:

| Stage | Budget |
| --- | ---: |
| Parse plus native build | 2000 ms |
| Two-frame layout | 1000 ms |
| Equivalent keyed reconciliation | 1000 ms |
| Native controls | 501 (one root plus 500 authored labels) |
| Equivalent reconcile allocation | zero created/replaced controls; 501 reused |

Run it with:

```powershell
godot --headless --path . --script benchmarks/pipeline_benchmark.gd
```

The script prints a JSON measurement record and exits non-zero when a budget is exceeded. These are regression ceilings, not performance targets. Changes that intentionally raise a budget require an explanation in the roadmap or migration notes and a new representative fixture.

Computed-style cache entries are shared by equivalent selector/ancestry signatures, property lookup lists are cached by native class/script, and compatible hot reloads mutate existing controls rather than rebuilding the scene subtree.
