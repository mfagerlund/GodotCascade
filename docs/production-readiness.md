# Production-readiness behavior

## Transitions and interruption

`transition: <property> <time>` expands to `transition-property` and `transition-duration`. The focused surface animates CascadeStyle colors, border geometry, padding/margins, size constraints, and flex growth when reconciliation changes an authored target.

```css
.card { transition: background-color 150ms; }
```

Transitions use cubic ease-out. A new reload targeting a property with an active transition kills the old tween, samples the current value, and animates from that value to the replacement target. Unlisted properties update atomically. Pseudo-state changes still select their state drawing immediately; this transition contract applies to computed-style changes during reconciliation.

## Responsive styles

GCSS accepts top-level width conditions:

```css
@media (max-width: 700px) { .cards { grid-template-columns: 1fr; } }
@media (min-width: 701px) { .cards { grid-template-columns: 1fr 1fr 1fr; } }
```

`vw` and `vh` lengths resolve against the `CascadeDocument` viewport. A document resize builds a new candidate and reconciles it into the current tree, preserving compatible keyed controls. Conditions support one non-negative `min-width` or `max-width` in pixels; compound media queries and orientation conditions are not in the preview grammar.

## Keyboard and accessibility

After every successful build, `CascadeDocument` wires `focus_next` and `focus_previous` in authored tree order for enabled, visible, focusable controls. Set `wrap_focus_navigation` to wrap the ends. Godot retains directional/controller navigation and component-specific input behavior.

The accessibility audit warns when a button/range has no accessible name or an image lacks an explicit description. Visible control text becomes the default native accessibility name where supported. Set `audit_accessibility = false` only when an application runs its own equivalent audit.

## Verification gates

The public-preview gate consists of all four headless suites, the 500-item [performance benchmark](performance.md), a plugin-enabled editor import scan, native showcase recapture, generated report validation, relative documentation links, formatting checks, deterministic addon packaging, and a clean-project installation smoke test. The [release process](release-process.md) defines the executable commands and tag-publishing contract.
