# Manual platform certification protocol

This protocol covers behavior that a headless runner cannot prove. Run the native settings page because it contains single-line and multiline native editors, writable bindings, selection, validation, focus navigation, native popup/range/toggle controls, and accessibility labels.

```powershell
python tools/showcase/run_showcase.py --godot path/to/godot --page settings-menu
```

Record the OS/version, hardware, Godot version/hash, rendering backend, keyboard layout, IME, clipboard environment, touch/virtual-keyboard device, and screen reader before testing.

## Required checks

| Area | Procedure | Passing evidence |
| --- | --- | --- |
| Clipboard | Select part of the profile and multiline note; copy, cut, paste, then undo/redo with native shortcuts and context menus | Text, selection, caret, and writable bound echo remain correct |
| IME | Compose non-Latin text in both editors; move the candidate selection; commit and cancel composition | Candidate window tracks the native caret; commit occurs once; cancel leaves no partial write |
| Bidirectional text | Enter mixed Arabic/Hebrew, Latin, and numbers; select across direction boundaries | Native shaping, caret movement, selection, copy, and bound echo are coherent |
| Touch selection | Long-press, drag both selection handles, replace selection, and scroll multiline content | Handles remain usable and the page does not steal the gesture |
| Virtual keyboard | Focus each editor, change selection, submit/dismiss, rotate or resize where applicable | Keyboard appears/dismisses normally and focused content remains visible |
| Screen reader | Navigate every interactive control, edit both text fields, open Select, change Slider/toggles, trigger validation | Name, role, value/state, selection, invalid message, and changes are announced |
| Keyboard/controller | Traverse forward/backward, activate controls, operate Select/Slider/radios, and enter/leave text editing | Authored order is deterministic; focus ring modality and native operations are correct |
| Reload | Keep a caret/selection and a focused control, then use the showcase Reload action | Compatible keyed controls preserve focus and native editing state |

For every failure, repeat the same action in a minimal scene containing a plain Godot `LineEdit`, `TextEdit`, or corresponding native control. Classify the result as GodotCascade-specific, upstream-native, assistive-technology-specific, or inconclusive. Do not mark the platform certified from visual inspection alone.

## Result record

Store completed evidence under `docs/artifacts/platform-certification-YYYY-MM-DD-<platform>.md` with this shape:

```markdown
# Platform certification — <platform>

- OS/device:
- Godot build:
- GodotCascade commit:
- Rendering backend:
- Keyboard/IME:
- Clipboard environment:
- Touch/virtual keyboard:
- Screen reader:

| Check | Result | Notes/evidence |
| --- | --- | --- |
| Clipboard | Pass/Fail/Unavailable | |
| IME | Pass/Fail/Unavailable | |
| Bidirectional text | Pass/Fail/Unavailable | |
| Touch selection | Pass/Fail/Unavailable | |
| Virtual keyboard | Pass/Fail/Unavailable | |
| Screen reader | Pass/Fail/Unavailable | |
| Keyboard/controller | Pass/Fail/Unavailable | |
| Reload preservation | Pass/Fail/Unavailable | |
```

A platform is manually certified only when every applicable row passes and unavailable hardware/services are stated explicitly. Automated results remain valid even when a manual service is unavailable; the support matrix must keep that distinction visible.
