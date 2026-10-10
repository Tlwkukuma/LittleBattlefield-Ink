# Persistent muzzle registration capacity

2026-10-09 integration fix. This is storage sizing, not a change to per-frame effects, combat, ammunition, AI, or spawn budgets.

## Cause and bounded fix

`flash_batches.gd` registers up to five cone pieces for every held/mounted gun, including hidden muzzles. All cones share one mesh/material, so they occupy one `fx_instance_batches.gd` group. Its historical 360 slots covered at most 72 five-piece guns, fewer than authored chapters with 80 infantry plus mounts. Assertion failures occurred during chapter 10 scene construction.

The FX pool now accepts a construction-time capacity; the default remains 360 for every existing non-muzzle caller. Only the muzzle batch chooses 880 = (128 existing crowd slots + 32 physical muzzle channels in the two-team seven-vehicle/fixed-weapon showcase + 16 existing portable-mortar deployment slots) × 5. The imported ten chapters need at most 80 infantry and 13 mounted channels. The broader bound also covers existing 50-versus-50 and range/showcase use; it does not impose a new population clamp. It is fixed at construction, with no incremental growth, extra batch, or changed overflow assertion. Future content beyond this supported bound must explicitly review storage sizing.

The same shared batch, transform updates, visible-muzzle counter, dense swap-delete release, and invalid-root cleanup remain unchanged. `visible_instance_count` follows the number of currently registered pieces, including zero-scaled hidden ones; it is never set to allocated capacity. Released entries compact and reuse slots, rather than retaining a historical high-water mark. Scene rebuild creates a fresh pool. No game roster or weapon is omitted.

The additional 520 allocated slots are approximately 33–41 KB of instance buffer storage (64–80 bytes per instance, depending on renderer packing), excluding renderer/driver bookkeeping. This is a storage estimate, not a measured GPU-memory or frame-rate claim.

## Frozen fixture

`qa/flash_registration_contract.gd` uses all ten imported source deployment maxima, real catalog mounted-weapon profiles, and a conservative five-piece M416 muzzle for every infantry slot. It exercises no world ticks, movement, shooting, or input. Report: `qa/flash_registration_contract.json`; engine log: `qa/flash_registration_contract.log`.

| Source | Infantry | Mounted channels | Registered pieces in conservative fixture |
|---|---:|---:|---:|
| 01 | 60 | 3 | 315 |
| 02 | 60 | 2 | 310 |
| 03 | 60 | 4 | 320 |
| 04 | 80 | 13 | 465 |
| 05 | 60 | 7 | 335 |
| 06 | 60 | 6 | 330 |
| 07 | 80 | 9 | 445 |
| 08 | 80 | 4 | 420 |
| 09 | 60 | 7 | 335 |
| 10 | 80 | 10 | 450 |

Result: **4,050 checks, zero failures**, clean Godot 4.6.3 headless log. Includes all source roots/pieces, 20 replacement generations per chapter, invalid-root tombstone release and reuse, every live handle's dense slot/index bounds, hide/show active counts, unchanged default capacity, fixed allocation, registered draw counts, whole-tree unregister, all 880 slots filled without dropping any of five pieces, one shared batch, and fresh-scene reset.

The table is a conservative isolated storage fixture, not a claim about every chapter's actual initial weapon selection. Native-scene integration/briefing lifecycle is separately rerun by the campaign integration test. This does not replace user visual/feel or combat performance acceptance.
