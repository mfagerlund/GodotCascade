# Adapted text input plan

GodotCascade will initially adapt Godot's native `LineEdit` and `TextEdit` rather than own text editing. Text entry has a much larger behavioral contract than labels and buttons, and visual ownership must not regress platform behavior.

## Compatibility boundary

The first `CascadeTextInput` will be an **adapted** component:

- native controls own text storage, cursor movement, selection, undo/redo, clipboard commands, drag selection, and context menus;
- Godot's text server owns shaping, bidirectional text, language, and OpenType features;
- native IME composition and candidate-window positioning remain intact;
- GodotCascade owns the outer box, documented theme adapters, layout metadata, diagnostics, and GXML attributes;
- unsupported appearance declarations produce an adapted-compatibility warning rather than silently implying exact rendering.

## Required behavior matrix

Before the adapter enters the public component set, automated and manual checks must cover:

1. Mouse, touch, keyboard, and controller focus entry and exit.
2. Character, word, line, and document selection in both directions.
3. Copy, cut, paste, undo, redo, and platform shortcut variants.
4. IME composition start/update/commit/cancel and candidate-window placement.
5. Left-to-right, right-to-left, and mixed-direction content.
6. Password masking without exposing text through accessibility metadata.
7. Read-only, disabled, invalid, placeholder, focused, and selection states.
8. Screen-reader name, description, value, selection, and validation announcements.
9. Single-line submit versus multiline newline behavior.
10. Hot reload without losing text, cursor, selection, scroll, or IME composition state.

## Initial source surface

The intended GXML attributes are `text`, `placeholder`, `multiline`, `read-only`, `disabled`, `secret`, `max-length`, `accessible-label`, and `accessible-description`. Event and two-way value binding wait for the event-binding milestone; the first adapter will not invent expression syntax.

Exact ownership is intentionally deferred. Replacing native editing would require equivalent tests on every supported platform and input method, not merely matching its appearance.
