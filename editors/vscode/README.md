# GodotCascade for Visual Studio Code

Dependency-free, focused language support for GodotCascade source files:

- `.gxml`: syntax highlighting, element/attribute completion, hover, formatting, structural diagnostics, reusable-component definition/rename, and class/ID navigation;
- `.gcss`: syntax highlighting, selector/property/value completion, hover, formatting, focused property/pseudo/media diagnostics, and custom-property/class/ID definition/rename;
- workspace-aware selector vocabulary gathered from project-local `.gxml` and `.gcss` files.

The vocabulary deliberately follows GodotCascade's focused language rather than browser-wide HTML/CSS. The deterministic test suite checks its element, property, and pseudo-state lists against `addons/godot_cascade/tooling/language_service.gd`.

## Try from this repository

Open the repository in VS Code, then start an Extension Development Host with:

```powershell
code --extensionDevelopmentPath="C:\Dev\GodotCascade\editors\vscode" "C:\Dev\GodotCascade"
```

For a persistent local installation, copy `editors/vscode` to a directory under your VS Code extensions directory and reload VS Code. A distributable VSIX can optionally be made with the standard `@vscode/vsce` tool; the checked-in extension itself has no npm dependencies.

## Verify

Node.js 20 or newer is sufficient:

```powershell
cd editors/vscode
npm test
npm run check
```

Tests use only Node's built-in test runner. `extension.js` requires the `vscode` host only when activated; the parser, diagnostics, symbols, contexts, and formatters live in the independently testable `core.js` module.

## Navigation and rename contract

- A `.gcss` `.class` or `#id` goes to a matching GXML declaration.
- A GXML class or ID can go to its declaration and can be renamed across GXML/GCSS sources.
- A reusable component tag goes to `<Component name="…">`; rename updates its declaration and tags.
- `var(--name)` goes to the matching custom-property declaration; rename updates declarations and references.
- Built-in element names cannot be renamed.

The extension searches workspace files on demand. It does not start a language server, execute project code, infer binding-context object members, or claim browser CSS compatibility. Native components registered only at runtime remain valid even though the extension cannot discover their schema.

## Diagnostics

Diagnostics intentionally focus on errors that can be determined locally: malformed/unbalanced GXML, invalid Repeat/Select structure, invalid literal booleans, malformed GCSS blocks/declarations, unsupported properties, pseudo-states, and media-query shapes. Godot's importer and GodotCascade's runtime validator remain authoritative for complete build diagnostics.

Licensed under the [Unlicense](LICENSE), matching the repository root license.
