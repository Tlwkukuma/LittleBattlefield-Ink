# First ten Pixi chapters: current Godot adaptation

This supersedes the invented sequential/hold design in `ten-level-campaign-plan.md`. The user prioritized the original Pixi levels, scenes and tactical AI on 2026-10-09. Imported source files remain unchanged.

## Gameplay specification grounded in supplied files

All first ten imported chapters specify one initially neutral control point and a 7-second capture time. The retained native campaign rules let blue win by capturing it or exhausting all red active/reserve forces; exact parity of alternate victory/defeat conditions with the unavailable Pixi runtime is unverified. The existing nearest-living-ally handoff and no-living-ally defeat remain. There are no invented timed-defense stages in the current campaign data.

| Chapter | Blue active / total | Red active / total | Source portable mortars B/R | Vehicles / fixed weapons |
| --- | --- | --- | --- | --- |
| 01 石墙果园 | 30 / 120 | 30 / 120 | 3 / 2 | 1 / 2 |
| 02 装配厂区 | 30 / 120 | 30 / 120 | 2 / 3 | 0 / 2 |
| 03 洪泛草甸 | 30 / 120 | 30 / 120 | 2 / 2 | 1 / 2 |
| 04 双街小镇 | 30 / 120 | 50 / 200 | 0 / 0 | 4 / 5 |
| 05 干溪通道 | 30 / 120 | 30 / 120 | 2 / 2 | 3 / 2 |
| 06 要塞内院 | 30 / 120 | 30 / 120 | 2 / 2 | 2 / 0 |
| 07 林间路口 | 30 / 120 | 50 / 200 | 2 / 4 | 3 / 3 |
| 08 城郊医院区 | 30 / 120 | 50 / 200 | 3 / 0 | 1 / 3 |
| 09 芦苇湿地 | 30 / 120 | 30 / 120 | 2 / 2 | 3 / 3 |
| 10 谷仓村落 | 30 / 120 | 50 / 200 | 0 / 0 | 4 / 3 |

Chapter 1 preserves the previously approved Godot orchard adaptation, including its exact exported runtime rules, modified courtyard, terrain and existing equipment AI. For chapters 2–10, source layout, dimensions, object/vehicle positions, unit/spawn coordinates, starting angles, objective identity/center/radius and force counts are retained. Chapter 4's original capture center (2038,1181) remains unchanged; an optional display-only mast position (2000,1200) avoids visually placing the mast through an obstacle. Capture geometry and boundary remain centered on the source point.

## Missing original runtime and compatibility behavior

The upload includes scene-plan data but not the original Pixi JavaScript runtime. `compiled-scenes.json` was produced without base LEVELS context and contains null weapon slots; it is not a valid final loadout or AI export. Only chapter 1 has a verified final runtime export.

For chapters 2–10, `campaign_source_adapter.gd` uses the verified first-chapter blue/red ordinary weapon pools only where source loadouts are absent. It preserves finite initial/total counts and each source side's specified portable-mortar count. Mortars are spaced through the finite reserve list; the exact original scheduling and per-chapter ordinary weapon composition are not claimed. Briefings disclose this compatibility fallback. No RPG/anti-tank primary specialists or invented weapon difficulty curve are added.

The current native tactical adapter uses public objective/spawn geometry, existing local perception, squads, cover, suppression and navigation. The three native tactic choices are not represented as an exact reconstruction of unavailable Pixi tactic code. Source spawn→objective route anchors are advisory; they do not force units to backtrack to a spawn. Orchard T03 keeps its approved mandatory trench approach. Fixed weapons are enabled for the native bounded crew AI; mobile vehicles retain source placement/ownership and remain player-operable until an explicit physical route is verified for AI.

## Source water and bridges

`campaign_water.gd` compiles source `surface:water, collision:blocked` paths in chapters 3, 7 and 9 into the existing static collision index. It uses the same sampled path/visible outline as terrain paint, clipped to world bounds. Original circular gaps and transformed bridge/island/deck polygons remain open; prefab decks are recognized by their actual renderLayer/mapKitPrefabId metadata, not just names. Water blockers are invisible because the existing ground pass draws the water; they are non-destructible and ballistic-transparent, and are excluded as raised walking support. No new bridge or island is authored. This is a source-based Godot collision adaptation, not a claim that missing original JavaScript collision code has been reproduced bit-for-bit.

## Campaign flow and persistence

Home → 十章战役 → unlocked chapter opens a frozen equipment/tactics briefing. Tab or 继续战斗 starts play. Victory unlocks the next chapter; retry restarts the current chapter in its briefing. The tenth chapter ends the campaign.

`user://campaign_10_v1.json` stores completed chapters, selected chapter and tactic, not mid-battle state. Its namespace is separate from legacy data. Type-safe loading, bounded unlocks, verified temporary writes, backup recovery and retryable dirty saves are included. Save failures are shown and never labeled successful. Existing first-chapter LAN remains separate and cannot unlock offline chapters.

Direct native review: `godot --path <project> res://proving_ground.tscn -- --campaign-chapter=N --briefing --startup-watch`. The chapter flag always opens a frozen briefing. Directly opening a still-locked chapter allows same-chapter retry but cannot save an unlock or offer the next chapter. Normal menu progression is unchanged.

## Evidence and limits

- `qa/campaign_source_data_contract.gd`: 11,332 source/layout/force/weapon/special-count/angle/identity checks passed at 14:48 UTC
- `qa/campaign_progress_contract.gd`: 61 checks passed, including wrong JSON types, failed-save retry and interrupted-replacement recovery
- `qa/campaign_flow_contract.gd`: 457 checks passed cleanly at 15:00 UTC with game processing disabled, including chapter 10's actual 435 flash registrations and every slot inside muzzle-specific bounded storage. The earlier 360-slot overflow was found and fixed; other FX pools and per-frame budgets are unchanged
- `qa/campaign_result_text_contract.gd`: 5 checks passed, including old-host empty reason fallback
- `qa/campaign_lifecycle_contract.gd`: 3,012 checks passed cleanly at 16:08 UTC over repeated chapter 1↔10 / retry / menu cycles, actual F5 handler calls, queued-free cleanup and stable logical scene counts; no simulation ticks or fabricated wins
- `qa/campaign_native_flash_contract.gd`: 446 checks passed cleanly at 15:03 UTC in the actual paused chapter 4 scene; all 440 modeled flash pieces registered and all slots fit storage
- `qa/objective_marker_offset_contract.gd`: 1,030 mesh checks passed; marker moves while every boundary vertex and gameplay-centered root remain unchanged
- `qa/ten_chapter_geometry_contract.gd`: 120 checks passed at 14:53 UTC with zero simulation ticks; all initial bodies clear, every source spawn connected to capture navigation, every visual mast clear
- Independent chapter 7 water/bridge review passed 38 checks after recognizing source prefab deck metadata: all authored infantry spawn anchors connect to capture cells; four original bridge centers admit a fresh full jeep; unbridged water blocks bodies and jeeps without becoming raised ground. A later frozen full-vehicle probe confirms all three original vehicle spawn poses clear. All four intact bridge crossings reject the native IFV and light-tank footprints: deck width is about 2.477 m and rail inner gap 2.146 m, versus IFV 2.54 m and light tank 2.35 m. Source vehicles remain manual-only. The briefing recommends infantry/small-jeep crossings and wide-vehicle bank support. Original Pixi vehicle footprint/crossing intent is unavailable; no bridge was widened or vehicle shrunk. Masked-rail counterfactuals are diagnostic only, not a claim of live destruction or a complete vehicle route.
- Native rendered startup review captured all ten chapters in frozen briefings with zero simulation time; the discovered chapter 8 heading overflow was fixed and visually rechecked. Ordinary released-trigger F5 retry was also physically verified in chapter 2. Continuous held-trigger retry and full campaign combat balance are not inferred from those observations
- All-chapter tactical geometry, exact river/bridge probes, native visual startup and authorized gameplay validation remain separately labeled. Static/resource passes do not establish combat balance or a frame-rate guarantee

## Frozen navigation checkpoint, 14:53 UTC

| Chapter | Navigation cells | Physical capture cells | Initial body conflicts | Unreachable source spawn anchors |
| --- | ---: | ---: | ---: | ---: |
| 01 | 3683 | 74 | 0 | 0 |
| 02 | 4983 | 65 | 0 | 0 |
| 03 | 3678 | 60 | 0 | 0 |
| 04 | 4690 | 43 | 0 | 0 |
| 05 | 5025 | 59 | 0 | 0 |
| 06 | 5252 | 53 | 0 | 0 |
| 07 | 3595 | 53 | 0 | 0 |
| 08 | 4992 | 61 | 0 | 0 |
| 09 | 3151 | 36 | 0 | 0 |
| 10 | 5295 | 74 | 0 | 0 |

Chapter 4 retains its exact source capture center inside cover; 43 reachable capture cells establish a usable capture footprint, while only its visible mast is offset. Chapter 1 retains one blocked raw red spawn anchor; the existing placement correction puts the actual actor in a body-clear position. These are navigation/geometry checks, not completed combat runs.
