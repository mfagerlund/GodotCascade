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

`vw` and `vh` lengths resolve against the `CascadeDocument` viewport. A document resize builds a new candidate and reconciles it into the current tree, preserving compatible keyed controls. Each condition supports one non-negative `min-width` or `max-width` in pixels; nested blocks intersect their enclosing ranges. A nested intersection that can never match is a source error rather than a silently empty rule. Compound media queries and orientation conditions are not in the preview grammar.

## Keyboard and accessibility

After every successful build, `CascadeDocument` wires `focus_next` and `focus_previous` in authored tree order for enabled, visible, focusable controls. Set `wrap_focus_navigation` to wrap the ends. Active focus traps additionally wire every directional neighbor within the trap; outside traps Godot retains geometric directional/controller navigation and component-specific input behavior.

The accessibility audit warns when an interactive control or semantic progress indicator has no accessible name, or when an image lacks an explicit description. Visible control text becomes the default native accessibility name where supported. Owned checkbox, radio, switch, select, slider, progress, and table controls correct the generic native base-class role through Godot's accessibility server; platform announcement behavior remains a manual certification item. Set `audit_accessibility = false` only when an application runs its own equivalent audit.

## Verification gates

The public-preview gate consists of the complete CI-listed headless matrix: layout engine and native layout, components, source pipeline, showcase connections, language service, editor tooling, typed item models, localized collections, and virtualization. It also runs the 500-item pipeline and representative workload [performance gates](performance.md), a plugin-enabled editor import scan, native showcase recapture, generated report validation, relative documentation links, formatting checks, generated C# compilation, VS Code tooling checks, deterministic addon packaging, and a clean-project installation smoke test. The [release process](release-process.md) defines the executable commands and tag-publishing contract; the tagged release additionally waits for Linux, Windows, and macOS runtime smoke jobs.
