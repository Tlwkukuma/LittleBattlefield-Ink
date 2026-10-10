# Pixi first-ten-chapter fidelity: current state

Updated 2026-10-09 16:03 UTC. This is the current comparison, replacing the initial discrepancy snapshot. The supplied source files remain unchanged. The current game uses their first ten chapters; invented sequential/hold missions and force curves are archived and are not loaded.

## Evidence boundaries

- `data/original/scenes.json` supplies authored layouts, deployment counts, source spawns/unit angles, objectives, vehicles, fixed weapons and finite special-weapon counts
- `data/campaign/level01_rules.json` is the only supplied verified final runtime export. Chapter 1 keeps the previously approved native orchard adaptation, including its deliberate courtyard/terrain/AI changes
- The original Pixi JavaScript runtime is absent. `compiled-scenes.json` was assembled without base LEVELS context and includes null ordinary loadouts; it does not establish final tactics, AI or reserve sequencing for chapters 2–10

## Current chapter matrix

All ten supplied source chapters specify one initially neutral point and 7-second capture. Current chapters 2–10 retain exact source point identity, center and radius, initial/total/max-active forces, spawn coordinates, initial unit positions/angles and authored object/vehicle placement. The current adapter has no timed hold or invented sequential objectives.

| Chapter | Blue active / total | Red active / total | Source spawn anchors B/R | Mortars B/R | Reachable physical capture cells | Current qualification |
| --- | --- | --- | --- | --- | ---: | --- |
| 01 石墙果园 | 30 / 120 | 30 / 120 | 10/10 | 3/2 | 74 | Approved native orchard retained |
| 02 装配厂区 | 30 / 120 | 30 / 120 | 10/10 | 2/3 | 65 | Source fields restored; explicit runtime fallback |
| 03 洪泛草甸 | 30 / 120 | 30 / 120 | 10/10 | 2/2 | 60 | Source fields restored; explicit runtime fallback |
| 04 双街小镇 | 30 / 120 | 50 / 200 | 10/10 | 0/0 | 43 | Source fields restored; explicit runtime fallback; mast-only display offset |
| 05 干溪通道 | 30 / 120 | 30 / 120 | 10/12 | 2/2 | 59 | Source fields restored; explicit runtime fallback |
| 06 要塞内院 | 30 / 120 | 30 / 120 | 5/5 | 2/2 | 53 | Source fields restored; explicit runtime fallback |
| 07 林间路口 | 30 / 120 | 50 / 200 | 14/12 | 2/4 | 53 | Source fields restored; explicit runtime fallback; wide-vehicle bridge limitation |
| 08 城郊医院区 | 30 / 120 | 50 / 200 | 9/11 | 3/0 | 61 | Source fields restored; explicit runtime fallback |
| 09 芦苇湿地 | 30 / 120 | 30 / 120 | 6/10 | 2/2 | 36 | Source fields restored; explicit runtime fallback |
| 10 谷仓村落 | 30 / 120 | 50 / 200 | 10/10 | 0/0 | 74 | Source fields restored; explicit runtime fallback |

## Restored and checked

- Source-data contract: 11,332 checks passed, including exact source gameplay centers, force counts, unit angles, equipment resolution, finite mortar totals, source identity and unchanged imported data
- Frozen native geometry: 120 checks passed across all ten chapters. Every actual starting actor is body-clear, every authored spawn anchor connects to capture navigation, and every chapter has usable physical capture cells. These are path/geometry checks, not completed combat runs
- Chapters 3, 7 and 9 now compile source blocked-water paths into the native collision index, using the same visible path outline and original gap/island/deck openings. Transformed bridge prefab metadata is recognized. Chapter 7 independent probes verify infantry connectivity and fresh full-jeep clearance at all four original bridge centers; unbridged water blocks bodies/vehicles without becoming raised ground
- Chapter 4 retains source gameplay center (2038,1181), even though it lies in cover; 43 capture cells are reachable. Only the visible mast moves to (2000,1200). A 1,030-check mesh test verifies perimeter vertices and gameplay-centered root do not move
- Native ten-chapter entry, retry, next-chapter, loss, final ending and isolated saves are implemented. Native UI flow passes 457 checks; persistence passes 61, including corruption and failed-write retry. LAN cannot award offline progress
- Source larger red rosters are retained. Native chapter 4 and 10 scenes register all actual muzzle pieces after the bounded muzzle-storage fix; no per-frame FX, AI or unit-count budget was raised

## Remaining differences and unavailable evidence

1. Ordinary chapter 2–10 loadouts are absent from the supplied source. Only missing values use verified first-chapter side-specific ordinary weapon pools. Authored finite portable-mortar counts are preserved, distributed through reserves; the original exact sequence remains unknown
2. T01/T02/T03 for later chapters use the existing native perception, squads, cover, suppression and pathfinding with public source spawn/objective metadata. Generic anchors are advisory rather than mandatory backtracking. This is a playable native adapter, not an exact recreation of unavailable Pixi tactical code
3. Later mobile vehicles retain source `aiControlled=false` and manual operation. Fixed mounts explicitly use the native bounded crew AI. Original runtime equipment assignment intent is unverified
4. Chapter 7 native IFV/light-tank widths exceed the intact bridge rail gap (about 2.146 m). All three original vehicle spawn poses are clear. No bridge or vehicle was resized; briefings recommend infantry/small-jeep crossings and wide-vehicle bank support. Original Pixi collision dimensions are unavailable; masked-rail diagnostic probes do not establish a live destruction route
5. Native alternate elimination victory, ally handoff and defeat behavior are retained from the approved campaign system. Exact Pixi alternate-rule parity and all 2D-to-3D collision details are unverified
6. Native screenshots and bounded combat diagnostics are tracked separately. This matrix does not claim all ten levels are fully playtested, balanced, or fast on the user's hardware

## Source needed to close runtime gaps

The original Pixi `src/` plus `package.json`, especially `src/levels.js`, `src/scenePlanLevel.js`, `src/map-kit/scenePlan.js`, `src/map-kit/scenes.json`, `src/assaultRules.js`, `src/Game.js`, `src/objectives.js`, `src/specialWeaponMigration.js`, and their imported tactics, command, perception, formation, cover, vehicle-AI and water-collision modules. The existing export tool documents the final-runtime export pattern. These files are not currently available in the upload.

See `ten-level-source-runtime.md` for current controls, save behavior and detailed geometry table. Machine-readable current comparison: `pixi-fidelity-matrix.json`. Historical invented draft: `data/campaign/drafts/chapters-designed-20261009-1402.json`, not the campaign specification.
