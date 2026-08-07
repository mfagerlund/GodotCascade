# GodotCascade documentation

GodotCascade 0.5.0 is the current experimental preview; `main` additionally includes reusable typed GXML components with slots and scoped IDs. The preview includes targeted binding invalidation, native state bindings, exact boolean conditions, typed C# generation, semantic tables, native scrolling, and scoped repeated forms. Documentation distinguishes the supported focused surface from intentionally unsupported browser features.

## Start here

- [Project README](../README.md) — overview, setup, examples, and development commands
- [Getting started](getting-started.md) — installation, first document, bindings, and next references
- [Bindings](bindings.md) — dynamic paths, writable forms, typed C# partial generation, formatters/parsers, events, repeated scopes, validation, and limits
- [Current support reference](current-support.md) — exact GXML elements, GCSS properties, selectors, pseudo states, and known limits
- [Architecture](architecture.md) — runtime boundaries, reconciliation, binding, layout, and invalidation
- [Adapted text input plan](adapted-text-input-plan.md) — native editing boundary and required behavior matrix
- [TextInput certification matrix](text-input-certification.md) — automated evidence and platform-dependent limits
- [Native control compatibility tiers](compatibility-tiers.md) — exact, adapted, and layout-only classification and diagnostics
- [Style system](style-system.md) — token spans, typed values, selectors, inheritance, computed caching, and theme adapters
- [Markup and state](markup-and-state.md) — reusable typed GXML components, slots, scoped IDs, keyed repeats, events, and native custom-component lifecycle
- [Editor tooling](editor-tooling.md) — importers, live preview, generated-control Inspector, debugger, and source navigation
- [Production readiness](production-readiness.md) — transitions, responsive rules, navigation, accessibility, and release gates
- [Release process](release-process.md) — reproducible packaging, clean-install smoke testing, and tag publishing
- [Asset Library submission](asset-library-submission.md) — copy-ready 0.5.0 metadata, direct assets, and verified preflight
- [Changelog](../CHANGELOG.md) — versioned user-visible changes
- [Performance budgets](performance.md) — executable 500-item benchmark and allocation ceilings
- [Migration notes](migrations.md) — source/API compatibility and upgrade instructions
- [Public preview stability policy](api-stability.md) — current guarantees, unstable surfaces, and change process
- [Roadmap](../ROADMAP.md) — completed preview, typed-binding, semantic-table, and publication milestones plus ongoing platform certification
- [Publication-readiness review](artifacts/publication-readiness-review-2026-08-07.md) — independent structure, completeness, ecosystem, and release assessment
- [Logo development](artifacts/logo-concepts/README.md) — selected cascading-native-windows mark, vector master, size study, and earlier directions
- [Runnable showcase app](showcase-app.md) — launch and manually verify every manifest page and event connection
- [Native-tree live reload](live-reload-demo.md) — reproducible Godot recording of GXML/GCSS edits preserving native node identity
- [Godot community preview draft](community-preview.md) — copy-ready announcement and structured feedback questions
- [HTML parity showcase](showcase/index.html) — live HTML references beside captured native Godot output

## Decisions

- [ADR 0001: Own the core control implementations](decisions/0001-owned-core-controls.md)

## Documentation rule

Examples in the README and current-support reference must execute against the current parser and builder. Future syntax belongs in the roadmap and must be marked **proposed**.
