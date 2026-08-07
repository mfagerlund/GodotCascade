# GCSS custom properties and typed `calc()` experiments

Date: 2026-08-07

Baseline: `98d74fe` (`main`, Godot 4.7 stable)

Status: implemented; final release-gate results are recorded below

## Question and conclusion

The experiment asked whether GodotCascade could add useful variables and arithmetic without turning GCSS into a browser-compatibility promise or weakening deterministic shorthand/cascade behavior.

The answer is **yes, for a focused typed subset**. Custom properties are useful for authored design tokens and responsive overrides. Typed arithmetic is useful for native layout values such as `calc(50vw - 20px)` and transition timing. The implementation remains small enough to diagnose precisely and does not require a DOM, a browser CSS engine, or a general expression runtime.

This is not CSS compatibility. The supported contract is deliberately narrower and is documented in [current support](../current-support.md#custom-properties-and-typed-calc).

## Semantics selected

- Names begin with `--` and remain case-sensitive.
- Custom declarations use normal selector specificity and source order, inherit through the authored element tree, and never reach native property application.
- A pseudo state starts from the element's resolved base environment and overlays custom declarations authored for that state. Parent pseudo-state environments do not propagate to children.
- `var(--name)` and `var(--name, fallback)` support transitive references, multiple substitutions, nested functions, and nested fallbacks.
- Values resolve lazily. Unused missing or cyclic tokens are silent. A consumed missing/cyclic winner produces one source-located error. Its conceptual longhands remain winners and are skipped, so an invalid high-specificity shorthand cannot expose a lower-specificity longhand.
- A fallback is attempted when its referenced value is missing or cyclic. This includes a consuming fallback recovering from a cycle.
- `calc()` supports NUMBER, LENGTH (`px`, `vw`, `vh`), and TIME (`ms`, `s`), parentheses, unary signs, and `+`, `-`, `*`, `/` precedence.
- Addition/subtraction require matching types. Multiplication requires at least one unitless number. Division requires a non-zero unitless divisor. Lengths normalize to native pixels and times to milliseconds.
- Bare numbers remain acceptable as pixels when a length property consumes the final result, matching the existing GCSS contract. Inside arithmetic they are dimensionless.
- Percentages, `em`, `rem`, `fr` arithmetic, dimensional multiplication/division, arbitrary functions, and partial `calc()` fragments are rejected.

## Experiments

| Experiment | Result | Decision or fix |
|---|---|---|
| Resolve `var()` only in `DeclarationApplier`, after cascade | Rejected in design review: `padding: var(--space)` would no longer compete as four conceptual longhands | Cascade/inherit custom properties first, resolve authored values, then expand shorthands before ordinary winner selection |
| Ignore a variable-backed declaration before winner selection | Rejected after a regression probe: an invalid high-specificity shorthand exposed a lower longhand | Invalid values expand to conceptual winners carrying cached error metadata; application skips them and emits one origin diagnostic |
| Cache by viewport width only | Failed the same-width/different-height `vh` probe | Computed-style keys now include both viewport dimensions |
| Use whitespace splitting for shorthands | Failed for `calc(4px + 6px)` and `var(--x, 8px)` | All scalar shorthands use a parentheses-aware top-level splitter |
| Use a NUL-prefixed internal invalid sentinel | Rejected during the first Godot run: the escaped NUL was retained in imported resources and produced Unicode warnings | Replaced with a non-NUL internal marker; moved the stale derived cache outside the workspace and rebuilt imports |
| Resolve/report every matched declaration eagerly | Rejected because an invalid declaration that loses the cascade should be inert | Resolution error metadata participates in winner selection; only winning consumed errors are reported, including on cache hits |
| Case-fold custom property names with ordinary properties | Failed the case-sensitivity probe | Parser preserves spelling for `--*` while continuing to normalize ordinary property names |
| State-only custom override | Worked | State declarations resolve against base environment plus that state's custom overlay |
| Nested fallback and transitive variables | Worked | Retained with a 64-level expansion guard |
| NUMBER/LENGTH/TIME arithmetic, viewport conversion, unary and precedence | Worked | Retained as the typed expression subset |
| Mixed types, dimensional products/divisors, division by zero, unsupported units, malformed/trailing syntax | Correctly rejected | Retained as recoverable value diagnostics |

## Coverage

The source-pipeline regression suite covers:

- parser spelling and locations;
- specificity, inheritance, local and state overrides;
- transitive values, nested fallback, case mismatch, self/mutual cycles, and unused cycles;
- arithmetic precedence, parentheses, unary signs, compact operators, viewport lengths, and time normalization;
- all rejected type/unit/operator/syntax cases listed above;
- multi-token `padding`, calc tokens inside shorthands, invalid shorthand precedence, and losing invalid declarations;
- source-located and cached diagnostic replay;
- cache separation for equal width but different viewport height;
- visible showcase use in both executable GCSS and the paired HTML reference.

## Verification results

Five consecutive local 500-control benchmark runs passed. Median literal parse/build was **143.526 ms**; median expression-heavy build was **187.157 ms**, a **43.631 ms / 30.4%** median increase for three variable/expression-backed properties on every item/root. This is one cold, complete stylesheet parse plus construction of all 500 native controls—not a per-frame or per-control cost. Expressions resolve only during document build/reload; native controls retain the resulting typed values and do no expression evaluation during ordinary frames. Observed expression-heavy builds ranged from 180.906 to 208.030 ms, far below the deliberately broad 2500 ms regression ceiling. This is an isolated microbenchmark cost, not a production throughput claim.

The manifest-driven native capture completed and the generated showcase stayed current; the layout screenshot remained byte-identical because the new variables and arithmetic intentionally reproduce the old literal values. Automated in-app browser visual inspection could not run because no browser backend was connected in the session. Static showcase generation/link checks and the existing paired HTML/Godot source/app suites remain the automated fallback; that browser availability limitation is not represented as visual certification.

Final suite, clean-install, packaging, and exact pushed CI/Pages evidence is added here after the commit completes its release gates.

## Known limits

This milestone does not add browser custom-property registration, `@property`, percentage resolution, `min()`/`max()`/`clamp()`, color arithmetic, arbitrary token execution, or runtime mutation of GCSS variables. Changing source still uses the existing transactional reload path. Custom properties are authored stylesheet values, not binding targets.
