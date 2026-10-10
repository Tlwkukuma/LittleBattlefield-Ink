# Existing HUD readability and feedback cache

2026-10-09 integration changes, confined to `scripts/combat_hud.gd`.

- Keep the approved 300 × 104 weapon card, five compact slots, existing colors and batched drawing. Existing keycaps increase from 13 to 14 logical pixels and center using the font's measured width. Mode text increases from 12 to 14; shortcut numbers from 11 to 13; medicine stock keeps its original size to avoid crowding the narrow count area. Selected shortcut numbers use the existing paper color and the existing underline is 3 pixels rather than 2. No new instructions, status text, world labels, cameras, assets or shader changes.
- Fix cached medical graphics: the geometry signature now includes `medical_feedback`, including its disappearance. While an unmounted player's existing medical symbol is visible, rebuild the existing geometry batch so projection changes follow the actor. Once feedback/healing ends, normal fixed-card caching resumes. This does not change medical inventory, timings, health or input.
- Reference inspected: the supplied 1178 × 814 native proving-ground image has a letterboxed 1440 × 900 UI. Small labels are partly downscaled; these are modest text changes, not a global UI scale or scene palette redesign.

## Checks and limits

`qa/combat_hud_readability_check.gd` passes 17/17 isolated keycap sizing/centering, original card bounds and medical-graphics activation fixtures. `qa/hud_atlas_contract.gd` passes 180/180. No scene or input is simulated by the new check. Before maintenance, `qa/combat_hud_check.gd` returned the same 199/203 on baseline and integration, and `qa/debug_hud_contract.gd` failed its obsolete default-entry assumptions. The maintained checks now pass 204/204 and 39/39 respectively; their exact replacement assertions are documented below. The frozen Debug test reports zero diagnostic batch sources, zero shots and simulation time 0 on integration v2026.10.09.1.

No actual combat, medical action, or rendered post-change screenshot was automatically tested. User visual acceptance remains required. No frame-rate improvement is claimed.

## Scene proposal, not implemented here

For chapters 2–10, a modest objective apron could reuse the existing `world.groundFeatures` yard-polygon data used by chapter 1's `orchard-flag-apron`. Author each approximately 1.2 m apron under the physical flag, with subdued existing stone pigment, and keep it baked into the existing terrain mesh. Avoid altering walkability, material alpha classifier, world geometry, roads, walls or capture radius. Verify each objective first: indiscriminate ground paint would be inappropriate for a raised platform, bridge, water, or upper-floor objective. The current flag and near-zone dashes already have one shared mesh; retain them instead of adding floating labels or bright persistent outlines. This proposal is handed to the campaign owner, not silently applied.

## Maintained legacy assertions

The obsolete assertions are updated rather than removed:

- `combat_hud_check.gd`: all three viewport checks now require the original 300 × 104 compact card and exact 24-pixel bottom safe margin. The old 100-pixel footer clearance contradicted the removed persistent footer. Its HUD fixture now supplies a parent UI host, checks both the HUD and its one persistent reload-ring child ignore mouse input, and checks that ring starts hidden. Result: 204/204 with no previous fixture teardown warnings.
- `debug_hud_contract.gd`: explicitly prepares the existing first campaign if the default home/range was loaded, closes the home overlay, and checks valid force-summary fields before accessing them. Force totals come from the actual authored deployment. A missing summary fails and exits; a watchdog makes other failures terminal. The unchanged diagnostic-counter/text assertion no longer includes the always-on lightweight FPS frame counter, which instead has its own positive 12-frame advancement assertion. The removed-stat-footer assertion checks that the diagnostics node is hidden while the normal combat HUD is visible. Existing debug opening/closing, input blocking, profiling lifecycle, batching exclusion, resolution bounds, scene roundtrip and zero-simulation checks remain.
- `campaign_hud_readability_check.gd`: prepares actual plans and rule state for all ten chapters and each authored stage, passes the real presentation summary into the real normal HUD draw function, and records its text commands. It verifies force fields, visible objective and status, stage counts, and both ordinary/contested hold seconds. It never ticks the world, simulates input, or advances objectives through play. Chapter 1 keeps its original name/state format.

Final campaign draw-data result: 113/113 passed, including the actual target label after each authored stage change. Log: `../qa/hud/campaign_hud_readability_check.log`.

## Circular objective boundary and direction

A second review found two actual navigation gaps: circle-based chapters had an empty `zone` polygon, which yielded no perimeter triangles, and the ordinary HUD ignored the direction embedded in debug-summary text.

- `objective_flag.gd` now bakes circular dashes from the actual active point's radius into the existing flag mesh. Their endpoints lie on the same mathematical circle used by `capture_zone.gd`; the 7 cm strip follows terrain vertex heights. Circular geometry has 8–128 dashes, each at most roughly 48 cm long, with gaps. Original polygon dash placement, flag shading and radius + 3 m proximity visibility are retained. Rebuilding clears old arrays, so changing stages cannot accumulate geometry. No collision, capture radius, material marker, extra node, mesh surface, or per-frame perimeter generation is introduced.
- `battle_status_hud.gd` now includes an eight-way world compass direction in its existing outside-objective distance row, for example `北 30 m`. It reads only the public active control point and local player's actual position. Stage changes immediately target the replacement point; no enemy roster, camera-dependent projection, minimap or floating label is involved. Inside the objective, the original capture/hold status and percentage remain.
- `qa/objective_readability_check.gd`: 426/426 static checks, including exact radii, bounded dash count, terrain height, one mesh surface, repeat-build stability, stage replacement, original polygon layout, eight bearings and absence of enemy data in the fixture. The ten-chapter draw-data test additionally checks bearings actually reach the ordinary HUD text commands; this expanded pass is 132/132.

Visual acceptance of the subtle near-objective dashed circle and compass row remains pending coordinated native review. These checks do not establish frame-rate performance or battle feel.

Existing `capture_objective_contract.gd -- --level01 --qa` also passes 36/36 on the frozen first chapter: one surface, original 1,092 flag vertices, no world labels, original polygon containment and flag progression; zero shots and world time 0.
