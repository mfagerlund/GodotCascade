# Godot community preview draft

This is the copy-ready announcement for the first GodotCascade community feedback round. Post it with the native live-reload GIF or link directly to the public demo.

The public live-reload URL below becomes valid only after the maintainer approves and pushes the prepared artifact. This document is not authorization to post it anywhere.

## Suggested title

GodotCascade 0.4: experimental GXML/GCSS UI that builds native Godot Controls

## Suggested post

I've published GodotCascade 0.4, an experimental retained-mode UI framework for Godot 4.7. It turns a deliberately focused GXML/GCSS language into ordinary Godot `Control` trees. The current preview includes flex, grid, stack, and semantic-table layout; native form controls; explicit one-way and writable bindings; optional typed C# binding generation; source diagnostics; and keyed hot reload.

The goal is not browser compatibility. The interesting trade-off is a constrained, diagnosable authoring model while retaining native nodes, input, focus, editing behavior, signals, and Inspector visibility.

The seven-second native recording shows GCSS and GXML edits rebuilding the card while its engine instance ID remains unchanged:

https://mfagerlund.github.io/GodotCascade/live-reload-demo.html

The HTML/native parity report and executable source are here:

https://mfagerlund.github.io/GodotCascade/showcase/

https://github.com/mfagerlund/GodotCascade

This is an experimental preview, not a production-ready replacement for Godot scenes or established projects such as GTML, Reactive UI Toolkit, GUML, or GDScriptUI. I'd especially value feedback from UI-heavy Godot developers on settings screens, inventories, dashboards, editors, and HUDs:

- Does the constrained markup/style surface make authoring faster or merely less flexible?
- Are diagnostics and live reload meaningfully better than the scene workflow for your UI?
- Where do bindings become awkward?
- Which missing controls or style primitives block a real interface?
- What runtime, accessibility, or platform evidence would you need before considering it?

The repository includes a reproducible addon ZIP, five native test suites, a clean-install smoke test, benchmark ceilings, explicit support boundaries, and The Unlicense. Honest failure reports and comparisons are more useful than general encouragement.

## Links to attach

- [Repository](https://github.com/mfagerlund/GodotCascade)
- [0.5.0 release](https://github.com/mfagerlund/GodotCascade/releases/tag/v0.5.0)
- [Native live-reload recording](live-reload-demo.md)
- [Public parity showcase](https://mfagerlund.github.io/GodotCascade/showcase/)
- [Current support reference](current-support.md)
- [Comparison and limitations](../README.md#comparison)
