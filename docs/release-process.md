# Release process

GodotCascade releases are built from the exact tagged tree and are never assembled manually.

## Local release gate

Run the five headless suites and benchmark documented in the project README, then run:

```powershell
python tools/ci/verify_repo.py
python tools/showcase/generate_showcase.py --check
dotnet build tests/codegen_compile/CodegenCompile.csproj --configuration Release
python tools/release/package_addon.py
python tools/release/clean_install_smoke.py --godot path/to/godot
```

The package command creates a deterministic addon-only ZIP and SHA-256 checksum under `dist/`. Entries are stored with normalized timestamps, paths, and Unix file modes so the complete archive is reproducible across Windows and Linux instead of depending on the host's DEFLATE implementation. The smoke test extracts that archive into a new temporary Godot project and exercises GXML parsing, GCSS parsing, styling, and native control construction using only packaged files.

The showcase generator keeps superseded content-hashed HTML references as redirects to the current hash. This lets a cached `docs/showcase/index.html` continue resolving its iframe instead of producing a missing-file error.

## Publishing

Before creating `vX.Y.Z`:

1. Match `addons/godot_cascade/plugin.cfg`, `CHANGELOG.md`, and `docs/releases/X.Y.Z.md`.
2. Confirm `LICENSE` and `addons/godot_cascade/LICENSE` contain the same current license and copyright statement.
3. Commit a clean tree and push it to `main`.
4. Create and push the annotated version tag.
5. Confirm the tag workflow passes. It packages the addon again, verifies its checksum, and creates the GitHub release with the matching notes, ZIP, and checksum.

## Godot Asset Library

Use the custom repository host for public releases so the library downloads the deterministic addon-only ZIP rather than a generated repository snapshot. The [copy-ready submission record](asset-library-submission.md) contains the current form values, direct raw-GitHub icon and preview URLs, and the preflight evidence required for the 0.4.0 testing-level entry.

For a later release, update the version, release download URL, description, and `plugin.cfg` together. Re-run the complete local release gate before replacing the Asset Library download URL.
