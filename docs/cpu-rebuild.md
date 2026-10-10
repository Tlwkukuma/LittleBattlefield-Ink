# CPU/telemetry rebuild checkpoint · 2026-10-10

This small checkpoint is rebuilt against restored `fab9912` (`v2026.10.09.3`). It does not claim to recover the missing later commit history.

## Changes

- `build_unit_index()` calls `begin()` once, then refreshes steering cells without repeating each ray-index update. `index_unit(unit, refresh_ray=true)` retains the unconditional authority identity guard; all existing movement, death, seating, reinforcement and network callers retain their default ray refresh.
- Runtime telemetry sums only integer/float counters. Nested `unit_rays` and AI metadata are deep-copied into separate latest-value `unit_ray_metadata` / `ai_query_metadata`, published and reset with each reporting window. Nonnumeric millisecond values and render-batch values cannot enter numeric summaries.

## Fresh verification

`qa/cpu-rebuild-contract.gd` builds independent deep-cloned unit rosters. Its reference changes only the build loop back to the redundant default-refresh call in current source, rather than pretending a missing historical file is available. It verifies 120 versus 60 update calls for 60 units, exact tree/grid/steering order and query equality, movement, out-of-bounds expansion, death/revival, mounted state, reinforcements, same-size roster replacement, prediction-copy rejection with both flags, equal-distance hit order, hit exclusion, and nested telemetry copying/publishing/reset.

Initial Godot 4.6.3 headless run: **4,345 checks, zero failures**. No simulation steps or player input were driven.

The unchanged `qa/projectile_unit_index_contract.gd` completed a fresh successful rerun: **68,429 checks, 457 positive unit hits, zero failures**, exit 0. Combined with the focused contract: **72,774 checks, zero failures**. Its output directory `qa/performance/` must exist in a clean restored checkout; the first attempt reached output writing but could not create the missing parent directory. That infrastructure failure is not counted as a passing run.

Run commands (from the project root):

```sh
mkdir -p /tmp/cpu-rebuild-home /tmp/cpu-rebuild-xdg qa/performance
HOME=/tmp/cpu-rebuild-home XDG_DATA_HOME=/tmp/cpu-rebuild-xdg \
  /opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64 \
  --headless --path . --script qa/cpu-rebuild-contract.gd
HOME=/tmp/cpu-rebuild-home XDG_DATA_HOME=/tmp/cpu-rebuild-xdg \
  /opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64 \
  --headless --path . --script qa/projectile_unit_index_contract.gd
```

Headless editor import/parse also completed with exit 0 and no errors, using writable `HOME`, `XDG_DATA_HOME`, `XDG_CONFIG_HOME` and `XDG_CACHE_HOME` under `/tmp`. An earlier editor attempt inherited unwritable config/cache locations; it is not the clean verification run. No tracked asset/import files changed.

This checkpoint removes proven redundant work; it does not establish a whole-scene FPS gain. Earlier session microbenchmarks and full-scene runs are not presented as fresh evidence. Actual battle acceptance remains with the user in the normal Godot scene. No gameplay budgets, layout, weapons, damage, AI behavior or frame-rate target changed.
