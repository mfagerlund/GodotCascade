# TextInput certification matrix

GodotCascade 0.3.0 adapts Godot 4.7 `LineEdit` and `TextEdit` for single-line and multiline input. Neither replaces the native editing engine. The release gate verifies the adapter boundary while platform services remain Godot's responsibility.

| Behavior | Automated evidence | 0.3.0 status |
| --- | --- | --- |
| Text, placeholder, read-only, disabled, secret, and max length | Component and source-pipeline suites | Verified |
| Required and regular-expression validation | Component and writable-binding pipeline suites | Verified |
| Mixed left-to-right/right-to-left Unicode storage | Component suite | Verified |
| Caret and selection preservation | Component capture/restore and keyed hot-reload tests | Verified |
| Writable text and dependent value refresh | Source-pipeline suite | Verified |
| Pointer versus keyboard/controller focus ring | Component suite | Verified |
| Accessible name, description, and validation message mapping | Source-pipeline and accessibility audit suites | Verified |
| Native selection, context menu, and password-mode availability | Component suite | Verified |
| Multiline newlines, max length, writable binding, and validation | Component and source-pipeline suites | Verified |
| Multiline primary caret, selection, and scroll preservation | Component and keyed hot-reload suites | Verified |
| Clipboard shortcuts and OS clipboard integration | Native `LineEdit`/`TextEdit`; not intercepted by the adapters | Platform-dependent; not certified headlessly |
| Undo/redo shortcut variants | Native `LineEdit`/`TextEdit`; not intercepted by the adapters | Platform-dependent; not certified headlessly |
| IME composition and candidate-window placement | Native `LineEdit`/`TextEdit` and Godot display server | Platform-dependent; not certified headlessly |
| Touch selection and virtual keyboard behavior | Native `LineEdit`/`TextEdit` and Godot display server | Hardware-dependent; not certified headlessly |
| Screen-reader value and selection announcements | Native Godot accessibility bridge | Assistive-technology-dependent; not certified headlessly |

The automated gate runs on the Windows development environment and a clean Ubuntu GitHub runner. Passing it proves that GodotCascade preserves and configures the native control without replacing these behaviors; it does not claim certification for every OS input method, clipboard manager, touch stack, or screen reader.

Report platform-specific failures with the OS, Godot build, input method or assistive technology, minimal GXML, and whether the equivalent plain `LineEdit` or `TextEdit` reproduces the issue.
