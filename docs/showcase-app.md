# Runnable showcase app

The project main scene is a native Godot application that reads `examples/showcase/manifest.json` and loads each registered showcase scene into its authored viewport. It exercises the same GXML, GCSS, scenes, and page order used by the generated [HTML parity showcase](showcase/index.html).

## Launch

Open the repository in Godot 4.7 and run the project, or use the launcher from the repository root:

```powershell
python tools/showcase/run_showcase.py --godot "C:\path\to\godot.exe"
```

Open a particular manifest page with its ID:

```powershell
python tools/showcase/run_showcase.py --godot "C:\path\to\godot.exe" --page settings-menu
```

Available IDs are `layout-foundation`, `system-status`, `settings-menu`, and `leaderboard`. Previous, Next, and the page picker change pages. Reload rebuilds the current GXML/GCSS document. The right side of the toolbar reports build errors and warnings for the mounted page.

## Manual connection checks

| Page | Action | Expected result |
| --- | --- | --- |
| Layout foundation | Select **Inspect layout** | The nearby status changes to **Layout inspection requested**. |
| System status | Select **Review route** | The sync status changes to **Route review requested**. |
| Settings menu | Edit the profile and session notes; toggle controls; move UI scale; choose a quality | Bound labels and the footer change to **Unsaved changes**. |
| Settings menu | Select **Apply settings** with a valid profile | The footer reports the selected quality and profile, for example **Applied ultra quality for Nova**. |
| Flight leaderboard | Select **Add pilot** | A keyed pilot row appears and the footer identifies the new pilot. |
| Flight leaderboard | Select a row's **Remove** control | That keyed row disappears and the remaining rows are reranked. |
| Flight leaderboard | Select **Sort by rating** | Rows reorder from highest to lowest rating and ranks update. |
| Flight leaderboard | Drag a row's **↕** handle onto another row | The dragged keyed row moves before the drop target and ranks update. |
| Any page | Select **Reload** | The document rebuilds and the toolbar returns to a **Connected** status when no errors exist. |

The automated equivalent visits all manifest pages and verifies their authored event and binding paths:

```powershell
godot --headless --path . --script res://tests/showcase_app_test.gd
```
