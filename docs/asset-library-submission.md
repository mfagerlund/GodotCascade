# Godot Asset Library submission

This is the copy-ready submission record for the GodotCascade 0.8.1 experimental preview. New community entries are published at the Asset Library's **testing** support level; that level is assigned by the library and is not a field in the public submission form.

## Submission fields

| Field | Value |
| --- | --- |
| Asset name | `GodotCascade` |
| Description | `GodotCascade is an experimental retained-mode UI framework for Godot 4.7. It builds native Control trees from focused GXML and GCSS, with deterministic flex, grid, stack, and table layout; typed collections and fixed-height virtualization; reusable components; explicit bindings; keyed hot reload; source diagnostics; and editor/language tools.` |
| Category | `Tools` |
| License | `The Unlicense License` (`Unlicense`) |
| Repository host | `Custom` |
| Repository URL | `https://github.com/mfagerlund/GodotCascade` |
| Issues URL | `https://github.com/mfagerlund/GodotCascade/issues` |
| Minimum Godot version | `4.7` |
| Asset version | `0.8.1` |
| Download URL | `https://github.com/mfagerlund/GodotCascade/releases/download/v0.8.1/godot-cascade-0.8.1.zip` |
| Icon URL | `https://raw.githubusercontent.com/mfagerlund/GodotCascade/main/icon.png` |

The custom provider deliberately points at the deterministic addon-only release archive instead of a generated repository snapshot. The archive installs only `addons/godot_cascade/` and retains the packaged README and license.

## Previews

Enable three image previews. The image and thumbnail URL can be the same direct PNG URL.

1. `https://raw.githubusercontent.com/mfagerlund/GodotCascade/main/docs/showcase/assets/settings-menu-godot.png`
2. `https://raw.githubusercontent.com/mfagerlund/GodotCascade/main/docs/showcase/assets/leaderboard-godot.png`
3. `https://raw.githubusercontent.com/mfagerlund/GodotCascade/main/docs/showcase/assets/layout-foundation-godot.png`

## Preflight

- [x] The public repository, issues page, icon, and preview URLs resolve without repository credentials.
- [x] The 0.8.1 release page, archive, and checksum URLs resolve publicly; the published archive digest matches the verified package.
- [x] The icon is a square 512×512 PNG, exceeding the required 128×128 minimum.
- [x] `LICENSE` and the copy packaged under `addons/godot_cascade/` contain the matching Unlicense text and the 2026 copyright statement.
- [x] `plugin.cfg` identifies version 0.8.1 and the release ZIP contains the complete addon directory.
- [x] The clean-install smoke test and all eleven native Godot suites pass against the packaged addon.
- [x] The name and plain-text description are English, describe the experimental status, and do not claim HTML/CSS compatibility.

The remaining maintainer-controlled step is to sign in at the [Godot Asset Library submission form](https://godotengine.org/asset-library/asset/submit), paste these values, and submit the entry for review. The [official submission guide](https://docs.godotengine.org/en/stable/community/asset_library/submitting_to_assetlib.html) is authoritative if the form changes.
