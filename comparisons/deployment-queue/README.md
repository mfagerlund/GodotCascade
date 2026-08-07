# Deployment queue comparison

This is a production-shaped operations screen implemented independently in GodotCascade and GTML. It is not part of the visual showcase and is not intended to make the two renderers pixel-identical.

Both implementations load the same 12-job JSON fixture and provide the same observable workflow:

1. edit operator, environment, concurrency, and paused-item visibility;
2. reject an invalid operator before queueing;
3. queue a deployment;
4. select and remove a deployment;
5. sort by priority while retaining the keyed row control;
6. update the status and summary;
7. expose a deliberately invalid source to record diagnostic and last-valid behavior.

The GodotCascade version uses its native semantic table and nested writable row binding. The GTML version uses an idiomatic flex list, top-level `v-model`, and `@click="select_job(job.id)"`. Those differences are part of the comparison rather than hidden by a common abstraction.

## Run

Requirements: Git, Python 3.11+, network access unless `--gtml-source` is supplied, and the official Godot 4.7.1 console executable.

```powershell
python comparisons/deployment-queue/run_comparison.py `
  --godot "C:\path\to\Godot_v4.7.1-stable_win64_console.exe" `
  --capture
```

The runner checks out GTML commit `7ddabfe3cffa69d7c8abd12b8d69bf80de49e59f` into a temporary directory, verifies the commit, overlays the comparison sources, and removes the temporary project afterward. GTML is not vendored here.

For an existing checkout at that commit:

```powershell
python comparisons/deployment-queue/run_comparison.py `
  --godot "C:\path\to\Godot_v4.7.1-stable_win64_console.exe" `
  --gtml-source "C:\path\to\godot-plugins-gtml" `
  --capture
```

Results are written to `docs/artifacts/deployment-queue-results.json`; optional native captures are written beside it. Every duration is labelled as a cold synchronous build, a complete batch, or process startup. None is a per-frame measurement.
