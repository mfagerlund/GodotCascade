# Adapted text input status and remaining plan

GodotCascade adapts native `LineEdit` for single-line text entry and native `TextEdit` when `multiline="true"` rather than owning text editing. Text entry has a much larger behavioral contract than labels and buttons, and visual ownership must not regress platform behavior.

## Compatibility boundary

`CascadeTextInput` is an **adapted** component:

- native controls own text storage, cursor movement, selection, undo/redo, clipboard commands, drag selection, and context menus;
- Godot's text server owns shaping, bidirectional text, language, and OpenType features;
- native IME composition and candidate-window positioning remain intact;
- GodotCascade owns the outer box, documented theme adapters, layout metadata, diagnostics, and GXML attributes;
- unsupported appearance declarations produce an adapted-compatibility warning rather than silently implying exact rendering.

## Implemented automated boundary

- single-line text, placeholder, read-only, disabled, secret, max-length, and accessibility attributes;
- native caret, selection, clipboard, undo/redo, context-menu, bidi, shaping, and IME ownership;
- required and regular-expression validation with `:invalid` styling;
- explicit `bind-text` write-back;
- text, caret, selection, focus, and native instance preservation during compatible keyed reload;
- hover, focused, disabled, invalid, and input-modality-aware `:focus-visible` adapted styles.
- multiline newline behavior, max length, writable binding, and primary caret/selection/scroll preservation on native `TextEdit`.

## Remaining certification matrix

The tracked release status is in the [TextInput certification matrix](text-input-certification.md). Headless automation cannot certify OS input methods, touch hardware, or assistive technology.

Before the adapter enters the public component set, automated and manual checks must cover:

1. Mouse, touch, keyboard, and controller focus entry and exit.
2. Character, word, line, and document selection in both directions.
3. Copy, cut, paste, undo, redo, and platform shortcut variants.
4. IME composition start/update/commit/cancel and candidate-window placement.
5. Left-to-right, right-to-left, and mixed-direction content.
6. Password masking without exposing text through accessibility metadata.
7. Read-only, disabled, invalid, placeholder, focused, and selection states.
8. Screen-reader name, description, value, selection, and validation announcements.
9. Multiline newline behavior on the native `TextEdit` adapter.
10. Hot reload without losing text, cursor, selection, scroll, or IME composition state.

## Source surface

The implemented GXML attributes are `text`, `bind-text`, `placeholder`, `read-only`, `disabled`, `secret`, `max-length`, `required`, `pattern`, `error-message`, `accessible-label`, `accessible-description`, and `multiline`. `multiline="true"` selects native `TextEdit`; password masking remains single-line-only. Event methods continue to use `on-*`; writable binding uses an exact existing property path and does not introduce expression syntax.

Exact ownership is intentionally deferred. Replacing native editing would require equivalent tests on every supported platform and input method, not merely matching its appearance.
