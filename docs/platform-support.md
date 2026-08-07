# Platform and Godot-version support

GodotCascade is a GDScript addon targeting Godot 4.7 and later 4.x maintenance releases. “Supported” here means the repository’s executable gate passes; it does not imply that every operating-system input service has been manually certified.

## Support levels

- **Supported** — full automated suite or an equivalent recorded local gate passes.
- **Smoke-tested** — parser/runtime/editor-load and the highest-risk collection suites pass, but packaging or visual behavior is not exercised on that runner.
- **Expected** — uses native Godot APIs without a known incompatibility, but no current executable result exists.
- **Unverified** — no support claim.

## Current matrix

| Godot | Windows desktop | Linux desktop | macOS desktop | Android | iOS |
| --- | --- | --- | --- | --- | --- |
| 4.7 stable | Supported locally: import, eleven suites, and both benchmarks | Smoke-tested in current CI | Expected; no current 4.7 macOS job | Unverified | Unverified |
| 4.7.1 stable | Supported locally plus current CI smoke | Supported in the full release gate | Smoke-tested in current CI | Unverified | Unverified |
| Earlier than 4.7 | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported |
| Later 4.x | Expected, CI update required | Expected, CI update required | Expected, CI update required | Unverified | Unverified |

The full CI/release job runs on Ubuntu with Godot 4.7.1. A separate matrix runs the source pipeline, editor-tooling smoke, item-model, localized collection, virtualization, and side-by-side certification-fixture suites on the minimum Godot 4.7 Linux runner and current Windows/macOS runners. Tagged releases wait for both jobs.

The current matrix passed for commit `31557ac` in [GitHub Actions run 31220031925](https://github.com/mfagerlund/GodotCascade/actions/runs/31220031925): full Godot 4.7.1/Linux verification, Godot 4.7/Linux smoke, Godot 4.7.1/Windows smoke, and Godot 4.7.1/macOS smoke. Each downloaded official archive was checked against its published SHA-512 sum.

The local Windows results used SHA-512-verified official Godot 4.7 and 4.7.1 standard builds. The 500-control benchmark measures complete named operations; no reported value is a per-frame cost.

## Native service boundary

Layout, parsing, bindings, reconciliation, and owned-control behavior are portable GDScript and are covered by headless tests. Clipboard integration, IME candidate placement, touch selection, virtual keyboards, and screen-reader announcements are provided by Godot’s native `LineEdit`, `TextEdit`, input, display-server, and accessibility bridges. GodotCascade does not intercept those services, but that alone is not evidence that every platform combination works.

Use the [manual certification protocol](platform-certification.md) before upgrading a platform from automated-only to manually certified. Report the exact OS, Godot build, device/input method, assistive technology, rendering backend, and whether the equivalent plain Godot control reproduces a failure.
