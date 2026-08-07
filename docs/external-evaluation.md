# External evaluator protocol

This protocol turns the public-validation roadmap item into a reproducible product test. It does not substitute an automated or AI review for experience from an external Godot developer.

## Evaluator brief

- Use GodotCascade 0.8.0 or the exact supplied commit with Godot 4.7.1.
- Start from the [README installation and quickstart](../README.md#install), not from a maintainer walkthrough.
- Spend 60–120 minutes building one real, non-showcase interface from your own project: a settings screen, inventory, dashboard, editor panel, HUD, or similarly representative surface.
- Use GXML/GCSS and whichever binding path you would genuinely choose: typed Godot objects, `ObservableBindingContext`, `CascadeItemModel`, or generated C# partials.
- Keep notes while working. Record commands, source or a minimal reproduction, and timings when a claim depends on runtime behavior.
- Do not smooth over missing controls or confusing diagnostics. Workarounds and abandonment points are primary results.

## Required response

Copy [the evaluation template](artifacts/external-evaluation-template.md) to `docs/artifacts/external-evaluation-YYYY-MM-DD-<handle>.md`, or return equivalent answers privately if public attribution is unwanted. The maintainer must obtain permission before publishing an evaluator's identity, source, or quotations.

An evaluation is complete when it records the attempted interface, time spent, outcome, and concrete observations about:

- authoring speed and source readability;
- diagnostics and recovery from mistakes;
- one-way/two-way binding ergonomics;
- runtime and reload behavior;
- missing controls, styles, tooling, or platform support;
- where GodotCascade helped, obstructed, or was abandoned;
- whether the evaluator would use it again, and for what scope.

One response is evidence, not consensus. Preserve negative and inconclusive findings alongside successful ones.
