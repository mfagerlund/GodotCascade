# GXML and GCSS language tooling

GodotCascade ships a focused source-language service plus Godot and VS Code surfaces. The service is source-only and never builds a scene tree, evaluates a binding, or executes a C# formatter/parser body.

## Godot editor

Enabling the addon adds **Cascade Source** to the bottom panel. Open a `res://` `.gxml` or `.gcss` path there, or activate an element in the live preview debugger: preview navigation opens the exact file, line, and column instead of only selecting it in the FileSystem dock.

The `CodeEdit` surface provides completion, vocabulary hover text, parser/schema diagnostics, conservative formatting, same-file component and custom-property definition lookup, previewable safe rename edits, and explicit save. Diagnostics mark affected lines and remain available in the status tooltip.

Formatting refuses to rewrite malformed GCSS, media-query stylesheets whose conditions would be lost, or GXML containing verbatim CDATA; returning the original source is safer than altering meaning. C# bodies inside `Formatter`/`Parser` therefore remain byte-for-byte unchanged.

## VS Code

The extension source is in `editors/vscode`. It registers `.gxml` and `.gcss`, syntax grammars, completion, hover, formatting, definitions, safe rename, and live diagnostics without starting a Godot process per request.

From that directory:

```bash
npm test
npm run check
npx @vscode/vsce package
```

The resulting VSIX is a release artifact for manual installation; publishing it to the VS Code Marketplace is a separate external action and is not implied by packaging it.

## Exact boundaries

- Definition and rename cover symbols that can be changed safely from exact source spans. Runtime binding paths and event-method names are not renamed because their owner may live in GDScript, C#, a Dictionary, or application code outside the paired sources.
- The Godot panel limits rename to the current file. VS Code can prepare workspace-wide class, ID, and custom-property edits, but those are textual: same-spelled symbols in independent component/runtime scopes cannot be proven related. Preview the edit before applying it. Reusable-component renames stay document-local.
- Formatting preserves meaning and declines ambiguous recovery instead of normalizing arbitrary XML/CSS.
- Diagnostics combine parser recovery with the documented supported vocabulary; runtime applicability and data-dependent binding diagnostics still come from the live preview.
- Godot's source panel is the supported integration surface because Godot 4.7 does not expose third-party completion/rename providers for arbitrary imported text files in the central Script Editor.

## Verification

`tests/language_service_test.gd` covers completion, hover, diagnostics, formatting idempotence and CDATA preservation, definition, and rename. `tests/editor_tooling_smoke_test.gd` instantiates the real `CodeEdit` surface headlessly and exercises opening, completion, formatting, and diagnostic display. The VS Code core has independent Node tests, and CI loads the Godot plugin in an editor import scan.

Headless tests do not certify tooltip placement, dock persistence, or keyboard shortcuts. Before a release that changes the editor surface, manually verify opening from the preview, completion display, hover text, definition movement, rename review, save/reimport, and plugin disable/re-enable in Godot 4.7.
