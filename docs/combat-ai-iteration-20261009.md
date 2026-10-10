# Combat AI incremental fixes · 2026-10-09

## Confirmed behavior changes

- AI leaving a deployed mortar restores its actual carried loadout. Drawing the same holstered weapon also clears holster state, while ordinary same-weapon decisions leave an active reload/cooldown alone. Removed mortar inventory is not recreated; deployed weapon ammunition remains unique.
- Reinforcement clears prior-life deployed-mortar ownership immediately after `spawn_epoch` advances (implemented by the campaign integration worker). The old deployment remains in the world with its own ammunition.
- Infantry firing permission is tied to the observed target identity, life epoch, and selected weapon. A new target/life cannot use the previous target's cached clear lane during the tick before tactical reevaluation. This adds scalar comparisons, not observation or firing rays.
- Aim marks retain the report's identity and epoch, including remembered contacts without a current live selection. No hidden target position is read for this change.
- Cover-search cache identity includes observed elevation, quantized body/muzzle heights, threat penetration estimate, and life identity. Small animation-height jitter and report-clock refreshes alone do not restart the cache. Existing single cover-search quota and shared decision budget remain.
- Empty authored routes fall back to the actual order destination instead of indexing a nonexistent waypoint.
- Vehicle frontage reads live per-stage `campaign_tactics.vehicle_frontage` source coordinates. Generic chapters fall back to the active objective; the orchard keeps its original frontage.
- Public objective transitions clear vehicle mission jobs, stale route progress and recruitment reservations, then reread only explicit vehicle routes. Occupants, health, ammo and perception timing are preserved; no geometry work runs in the reset. Fixed-mount replanning flags clear once their bounded sector check completes.
- Generic-chapter vehicle parking candidates rotate around the actual approach direction. The same five posts and authored road combinations are retained. Chapter 01's world-space candidate geometry remains unchanged.

## Changed-file ownership ledger

Runtime changes owned by this worker:

- `scripts/campaign_ai.gd`
- `scripts/campaign_vehicle_ai.gd`
- `scripts/campaign_directional_aim.gd`
- `scripts/campaign_perception.gd`
- `scripts/campaign_tactics.gd`
- `scripts/campaign_asset_mission.gd`

Added focused checks:

- `qa/ai_equipment_lifecycle_contract.gd`
- `qa/ai_fire_context_contract.gd`
- `qa/ai_route_edge_contract.gd`
- `qa/ai_cover_context_contract.gd`

This report and this worker's named logs under `qa/iteration_20261009/` are supporting artifacts. `campaign_rules.gd` lifecycle edit belongs to the campaign worker. No source catalog, weapon statistics, network protocol, project version, scene assets, or player-control behavior is changed by this worker.

## Verification

Godot 4.6.3, headless, writable temporary HOME/XDG data directories:

- Equipment/lifecycle/stage reset: 23 assertions passed, including actual reinforcement rule-state reuse, finite mortar issuance, old-deployment preservation, and mission-cache reset without geometry work.
- Fire/report identity and deferred retry: 19 assertions passed, scalar state only; stable-target report timestamps are explicitly allowed to refresh without losing permission.
- Generic route/candidate math: 35 assertions passed.
- Cover cache identity: 12 assertions passed.
- Existing campaign assets: 93 assertions passed again after the stage hook and fixed-mount replan reset.
- Existing execution contract: 14 assertions passed again after the final cover-cache change.
- Existing 3D tactical contract: 174 assertions passed again after the final cover-cache change.

The historical `qa/directional_aim_contract.gd` cannot load because its `qa/performance/directional-before-source/` fixtures were not present in the imported project. It is not recorded as a pass. New report-identity assertions cover the changed aim state. Initial engine startup without writable userdata failed before test execution; subsequent checks use `/tmp` HOME/XDG paths.

The checks in this first verification tranche are state, source-contract, candidate-math, and frozen-geometry checks. Later authorized battle diagnostics and actual controlled firing are reported below. Full-battle P95/P99 and native practical combat effectiveness remain unaccepted.

## Deferred audit note

The maneuver coordinator synthesizes a handoff offset, but the director already snaps it to the connected graph and reserves it, with real movement collision and a timeout afterward. A proposed replacement by prechecked candidate reuse was paused pending a concrete frozen-geometry failure. No handoff behavior was changed merely on theoretical risk.

## Source-fidelity tactical review (later pass)

The imported first ten scenes have no explicit AI runtime/AI-route fields. Their geometry, road paths, spawns, force counts, objectives and special-weapon allocations are known inputs; generic tactical routes remain a labeled Godot adaptation.

- The provisional two-point spawn-to-objective routes are no longer mandatory T03 approaches. A source-coordinate regression found chapter 02's first blue unit could otherwise be sent 20.64 m toward another spawn, 5.48 m farther from its goal. The campaign owner added `CampaignPlan.mandatory_approach`; chapter 01 retains its authored approach, and future explicitly authored generic approaches can opt in. `derived_tactical_routes_contract.gd`: 802 checks passed.
- Frozen actual-geometry audit loaded all ten chapters after water collision restoration. All initial actors were body-clear. Chapter 07's entire blue spawn bank became disconnected from capture goals; this was reported immediately to the campaign owner/reviewer for crossing investigation. Chapters 03/09 had connected spawn-to-capture components. Chapter 03/04 derived raw support posts need existing connected-node correction, and chapter 09's second HMG had no passing sector among the current bounded preparation samples. These observations do not establish battle success.
- The stricter fire context now has a shared-budget retry gate. A report deferred because perception exhausted the budget can be checked on a later tick without requiring a new observation. A checked context stops retrying; no second budget or new ray quota was introduced. The budget is measured in microseconds, not a per-ray remaining counter.

Bounded headless battle diagnostics were subsequently authorized and performed. The original first-pass no-battle boundary above is historical; results below describe the additional scope.


## Bounded diagnostics and final narrow corrections

### Stable contact permission

The first implementation required observation timestamps to match exactly. This was too strict: a fresh observation of the same target could invalidate a previously checked lane during an active firing burst. Timestamp equality has been removed. Target ID, life epoch and weapon identity remain required; ordinary tactical checks and real muzzle/projectile collision remain unchanged. A mismatching live contact can retry through the existing shared budget; once checked, the retry stops.

`qa/ai_fire_lifecycle_integration.gd`: **11/11**, three actual shots and exactly three rounds consumed. It calls actual perception, actual muzzle/friendly-lane checks and AI fire. Stable-target observation refresh permits the next burst; an observed new life waits for a new check and ordinary trigger release; removing the observed contact prevents further shots. Budget availability is deliberately controlled between fixture phases. This is an integration logic check, not normal-budget combat or performance acceptance. The initial fixture used an insufficient 0.8-second wait for a randomized interval that can reach 0.83 seconds; the corrected 1.0-second fixture passed.

### Full legal fixed-gun sector, bounded scheduling

Chapter 09's second HMG had clear rays at legal bearings missed by the four existing fast probes. If all four fail, six remaining quarter/end-point bearings are queued through the existing vehicle mission scheduler, at most one ray per visit, instead of another synchronous full search. Completed jobs do not repeat work. Stage reset, destruction, removal, position/base-angle/traverse changes invalidate queued work; failed sectors expire after the existing five-second negative cache. This grants only equipment-use eligibility, never a target or firing permission.

- `qa/ai_sector_job_contract.gd`: **25/25** synthetic query/state assertions, including four-fast-probe prerequisite, one-query visits, finite completion, invalidation and negative-cache expiry
- `qa/chapter09_sector_contract.gd`: **8/8** actual frozen geometry. Four fast rays fail; three scheduled single-ray visits find **+25%** of the original mechanical traverse, **7 total rays**. `world.time=0`, `shots=0`

### Exploratory battle results, not a balance comparison

A 30 Hz stationary-player, nonrendered baseline completed capture at 46.33 simulated seconds with 319 shots. An initial integration sample produced only 61 shots in 120 seconds and very limited movement. These are retained as diagnostic evidence; the integration sample is not accepted as proof of playable AI.

Further investigation found the existing scheduler couples decision-budget resets to process frames, while physics catch-up ticks share that allowance. Four isolated baseline-derived copies were then tested at the original 60 Hz, with per-tick process/physics IDs and budget before/after:

| Variant | Shots in 20 simulated seconds | Moving lives | Catch-up ticks / 1200 | Budget resets |
| --- | ---: | ---: | ---: | ---: |
| Untouched baseline | 12 | 9 | 1014 | 186 |
| Holster-only | 0 | 4 | 1014 | 186 |
| Report/cover changes | 55 | 24 | 798 | 402 |
| Above + vehicle queue | 12 | 26 | 923 | 277 |

Every recorded physics-frame increment was exactly one; the harness calls `World.step` once from `_physics_process`, not from a tight simulation loop. The non-monotonic outcomes and large catch-up fractions prevent causal or balance conclusions from these cloud wall-clock-quota samples. No global budget, stat, ammo or scheduler change was made to force a better outcome. The cases showed no sampled nonfinite/out-of-world coordinates or same-life ammunition increases, but that limited diagnostic is not exhaustive gameplay acceptance.

Detailed summary: `qa/iteration_20261009/cadence-ablation-summary.json`; individual files include source hashes, samples and per-tick cadence. The stable-contact long rerun was intentionally interrupted after continued navigation starvation was established; its live snapshot/log remain diagnostic partial output.

## Additional files from the second pass

- `qa/derived_tactical_routes_contract.gd`
- `qa/ten_chapter_tactical_audit.gd`
- `qa/bounded_campaign_playcheck.gd`
- `qa/ai_sector_job_contract.gd`
- `qa/chapter09_sector_contract.gd`
- `qa/ai_fire_lifecycle_integration.gd`

Temporary baseline/ablation copies are outside the deliverable project. The immutable imported baseline was not edited. Full native player-input validation and representative bridge/town battles remain separate work; this report does not mark them complete.

## Final lightweight rerun and pending native checks

At 14:48 UTC, final pure fixtures passed again: fire context **19**, cover context **12**, route edge **35**, sector job **25**, derived routes **802**, all zero failures. No world simulation ran during this rerun. Runtime SHA-256 ledger and six failed/partial diagnostic artifacts are preserved outside the deliverable project under `validation/combat-ai/`; delivery must exclude `qa/iteration_20261009/` evidence from the game package.

Native visual/player acceptance is still pending and should capture these specific frames/actions once the shared test slot is available:

1. Chapter 01 normal entry: player move/fire and nearby AI moving and firing through refreshed observations, with ordinary ammunition consumption.
2. Mortar deployment, occupancy and dismount: the actor resumes its actual rifle; the deployed mortar keeps its separate ammunition. Reinforcement ownership must not point to the prior life.
3. Chapter 02 T03: infantry proceeds toward the source objective rather than being forced back through another spawn anchor.
4. Chapter 07 after the water-owner fix: actual player/AI bridge traversal and failed off-bridge water crossing; capture progress remains reachable.
5. Chapter 09 second HMG: reachable operator seat, legal quarter-traverse opening and ordinary visible-target bursts; geometric eligibility alone must not fire at an unseen target.

Native visual review later measured approximately one actual Engine FPS; the earlier seven-FPS HUD reading was historical and is not a measured performance result. Short input/visual checks cannot establish normal-machine performance or balance.

## Test-only fixed-frame diagnostics (15:58 UTC)

Installed Godot 4.6.3 help supports `--fixed-fps 60`, which disables real-time synchronization. An outside-project harness copy recorded actual callback delta alongside process/physics IDs. This invocation alone removes wall-clock catch-up; no product budget, physics setting, roster or statistics changed. Every recorded step in all five cases had a distinct process frame, a physics increment of one, a fresh ordinary decision-budget reset and engine delta 1/60. Zero catch-up ticks. The original microsecond quota still depends on host execution speed, so these are logical behavior samples, not deterministic outcome/performance comparisons.

| Case | Sim seconds | Shots | Moving lives | Cover lives | Objective entries | Peak mounted | Result |
|---|---:|---:|---:|---:|---:|---:|---|
| Imported baseline chapter 01 | 60.02 | 892 | 98 | 14 | 31 | 4 | Playing |
| Integration chapter 01 | 51.85 | 590 | 66 | 10 | 50 | 3 | Blue capture win |
| Integration chapter 02 | 60.02 | 535 | 86 | 14 | 51 | 2 | Playing |
| Integration chapter 07 | 60.02 | 952 | 88 | 14 | 62 | 2 | Playing |
| Integration chapter 09 | 46.20 | 566 | 85 | 8 | 51 | 3 | Blue capture win |

All five completed without sampled nonfinite/out-of-world coordinates or same-life ammunition increases. Their actual shots, deaths, replacements, cover states, mounting and capture entries demonstrate substantial functioning combat and route use under this logical cadence. They do not establish win rates or full native acceptance. Counts are unique sampled lives, not simultaneous units; replacements explain counts above the initial active roster.

One localized chapter 07 red-life stall was observed: unit37:0 requested motion while near (-1.60,-16.69) for22.17 seconds, state `hold`, one path node. It later moved slightly and acquired a target before dying; cause is not proven. Other cases had no sampled requested-motion stalls over six seconds. Chapters02/07 progress ranged -1 to0 during their bounded windows, so no blue capture completion is claimed.

Artifacts are outside the game package: `validation/combat-ai/fixed-cadence-summary.json`, `fixed-*.json`, logs and `fixed_cadence_playcheck.gd`. The earlier failed/starved diagnostics remain preserved.

### Chapter 07 localized stall classification

A subsequent35-second rich trace recorded actual tactic/goal/path/velocity/recovery fields and nearby actors. Unit37:0 reached goal(-2,-16), held by4.05 seconds, had `ai_stuck=0`, and then shifted with crowd pressure. Its sampled poses remained body-clear under the conservative0.30m probe. The exact earlier22.17-second episode did not reproduce; its original action/goal was not captured, so it remains an unproven localized congestion observation.

The rerun flagged two6.05-second motion-without-displacement sequences. Unit33:0 was deliberately holding with11–12 nearby actors; its requested motion matched zero-goal crowd separation and its stuck counter stayed zero. Unit71:0 hovered around the0.5m stopping threshold (roughly0.49–0.53m), with13–16 neighbors and stuck counter at most0.2 seconds in those samples. No repeated failed recovery or reproducible route deadlock was demonstrated. No hold, steering, collision or budget change was made.

The separate frozen sampled-pose probe reconstructs actors over intact geometry and assumes standing height; its blocked test uses0.30m while actual traversal uses0.28m. It explains possible crowd pressure beside walls but cannot prove original penetration or a deadlock. Preserved evidence: `chapter07-stall-trace.json`, `chapter07-stall-frozen.log`.

### Reproduce the fixed-cadence diagnostic

From the iteration directory containing `project/`, `baseline_playcheck/`, and `validation/`, choose a new output filename:

```sh
export HOME=/tmp/godot-ai-home
export XDG_DATA_HOME=/tmp/godot-ai-data
export XDG_CACHE_HOME=/tmp/godot-ai-cache
/usr/local/bin/godot --headless --fixed-fps 60 --path project \
  --script "$PWD/validation/combat-ai/fixed_cadence_playcheck.gd" -- \
  --chapter=1 --seconds=60 \
  --output="$PWD/validation/combat-ai/NEW-output.json"
```

For the preserved baseline use `--path baseline_playcheck --chapter=1`; integration cases use chapters2,7,9. Output must not already exist. The harness has a360-second wall cap and stops on match completion. Inspect cadence for process/physics increments1, `reset_due=true` each step and delta1/60 before interpreting behavior. Run sequentially with no competing native/import/world job. The harness and diagnostics are intentionally outside the shipped game package.

## All ten chapters: bounded dynamic coverage (16:35 UTC)

The remaining chapters03/04/05/06/08/10 completed the same test-only fixed60Hz invocation, maximum60 simulated seconds with natural match completion. All ten now have actual dynamic combat samples. No forced outcomes, source edits or budget changes were used. All six new cases had zero sampled nonfinite/out-of-world coordinates, ammunition increases or body overlap above the actual traversal collision skin at the actual0.28m radius. The additional body check was not recorded in the first four cases. Every process/physics cadence was verified1:1.

| Chapter | Sim seconds | Shots | Moving lives | Cover lives | Objective entries | Outcome |
|---|---:|---:|---:|---:|---:|---|
|03|60.02|934|97|19|35|Playing, blue progress0.129|
|04|47.35|759|76|9|43|Natural blue win|
|05|60.02|481|102|14|29|Playing, red control|
|06|60.02|787|91|19|48|Playing, blue progress0.748|
|08|51.27|881|81|18|35|Natural blue win|
|10|37.28|840|71|9|41|Natural blue win|

Chapter06's flagged6.05-second life55:0 hovered at the normal0.5m goal threshold with stuck counter near zero, consistent with goal-area crowd pressure. Chapter04's red36:0 is a different, genuine localized progress failure: after reaching the objective and taking a cover excursion it had an empty path, goal3.09m away, and stuck counter rising to17.63 seconds before changing to support and later dying. This observation is being isolated; it does not erase the chapter's completed objective or establish all actors stalled. A frozen intact-scene probe at its sampled position finds a real valid path and legal recovery candidates, so static disconnection is not the cause.

Machine-readable combined evidence: `validation/combat-ai/all-ten-dynamic-summary.json`. The six-case harness additionally captures hold flags, goal distances and recovery counters so separation-only motion is not automatically called navigation failure. These remain single stationary-player headless samples, not win-rate, performance or native-animation acceptance.

## Deferred-recovery route erasure fix (v3 candidate,16:46 UTC)

A second chapter04 trace reproduced the failure class on red42:0: goal2.34m away, empty path, stuck counter2.27→18.37 seconds, recovery search `next=0`. The cause is independent of source geometry: after route planning spends the shared budget, `recover()` can defer without evaluating candidates, but its caller previously cleared the existing path unconditionally. A fresh route could therefore be discarded before recovery produced any result.

The narrow `campaign_ai.gd` change adds `accept_recovery`: pending searches preserve the current path and repath timer; completed searches retain the old route invalidation,1.4-second cooldown and0.65-second checked escape duration. Pending retry remains0.04 seconds. No physical movement, candidate search, ray quota, per-frame recovery/cover quota, shared microsecond budget or scheduling order changed. No teleport or source geometry edits.

- Actual `AI.update` frozen-world regression: before patch two failures (four-node real route erased and repath reset); after patch all five checks pass, retaining three remaining route nodes and repath0.9667 with zero budget.
- New scalar completion contract:11/11, covering pending, partial candidate, successful completion and completed no-candidate cooldown.
- Affected reruns: fire19, cover12, route35, sector25, equipment/lifecycle23, all pass.
- Postpatch fixed-cadence chapters04/07/10:1182/986/987 shots,142/115/114 moving lives,64/67/53 objective entries. Chapter10 naturally captured at42.42 seconds;04/07 remained playing at60 seconds. All had zero sampled coordinate/ammo/body-overlap errors and verified1:1 cadence. Their raw requested-motion stall flags were hold/near-goal crowd pressure, not the erased-path signature.

### Remaining scheduler limitation

The richer fields expose an important limitation missed by the original requested-speed stall metric: some higher-index actors have a goal but no path or requested motion while their stuck counter grows. This occurs before and after the fix under the unchanged wall-clock microsecond budget. Chapter04's final prepatch sample had34 such lives waiting over10 seconds; the postpatch sample had18 (different trajectories/times, not a causal performance comparison). Postpatch07/10 had16/19. All-ten dynamic coverage therefore means every chapter showed real combat, movement and objective engagement, not that every individual actor advanced successfully. No broad scheduler redesign was attempted.

Precise patch: `validation/combat-ai/v3-recovery.patch`. Runtime `campaign_ai.gd` SHA256: `d4dda1647ddbdafca1f2d23485802cb33e2e3b647068f8cd75c070b07f72a27f`. Added QA files: `qa/ai_recovery_commit_contract.gd` and `qa/ai_deferred_recovery_integration.gd`. Old failing trace and prepatch source are preserved outside the package. Structured results: `validation/combat-ai/v3-recovery-summary.json`.

## Offline fair-service correction (17:09 UTC, lifecycle verified)

Read-only analysis confirmed the original unit loop always began at index0, after director/vehicle jobs; alternating NPC parity did not rotate priority. Higher-index actors repeatedly reached decision/path code after the shared allowance was spent. This persisted even with one process frame per physics tick.

With explicit approval, offline campaigns now fill a reused integer index buffer: humans first in their original order, then cyclic NPC indices. Each starting index is held for two ticks so both unchanged parity groups receive a first-service opportunity. Every actor still runs `UnitSchedule.elapsed` exactly once. No actor dictionaries or complete actor array are cloned. Training and all LAN modes retain original order, including a solo host, through an explicit authoritative-driver flag; remote input presence also disables rotation. World setup resets the new cursor/buffer. No source forces, tactics, movement/collision model or budget/quota changes. NPC relative update order is intentionally rotated, which can alter individual battle trajectories.

The pure contract passed492,812 integer-order/parity assertions over odd/even rosters1–128, both phase offsets, dead actors, life reuse, roster growth, humans-first, exactly-once, elapsed time and bounded first eligible service within2N ticks. This bounds ordering opportunity, not wall-clock job completion if earlier non-infantry work consumes the whole allowance. Existing schedule724, recovery11+actual5, actual firing11 and source-data11,332 checks passed.

| Chapter | Final pathless goal waiters >10s before→after | Maximum sampled pathless stuck age before→after | After shots / moving lives / objective entries |
|---|---|---|---|
|04|18→0|60.02s→1.87s|1125 /134 /66|
|07|16→0|32.87s→2.50s|1021 /119 /62|
|10|19→0|33.90s→1.40s|1667 /169 /74|

Both sides used the same test-only fixed cadence and original quotas. All post-fix cases ran60 simulated seconds, remained naturally contested, and recorded zero sampled ammo/coordinate/body-overlap errors. Every frame reset and process/physics increment was verified. Samples differ in battle trajectories, so the table supports removal of index bias, not a win-rate/performance assertion. Requested-speed stall flags mostly concern holds/near-goal crowd pressure; the largest flagged chapter04 goal-directed counter was3.03 seconds and did not remain pathless.

The real-scene lifecycle fixture's first run reached three rebuild checkpoints without failure but exceeded a240-second harness timeout. The600-second retry completed at17:09:17 UTC with **3012 checks, zero failures**, verifying repeated1↔10 scene cleanup and stable counts. The first attempt remains a timeout, not a pass. Evidence outside package: `fair-service.patch`, `fair-runtime-hashes.json`, `fair-service-comparison.json`, `fair-chapter*.json` and logs. Added focused test: `qa/offline_ai_order_contract.gd`. Runtime changes additionally include `scripts/unit_step_schedule.gd`, `scripts/proving_world.gd`, and the campaign owner's one-line `scripts/proving_ground.gd` offline flag.

## Current fair-runtime: all ten dynamic probes complete (17:33 UTC)

Every chapter now has a full60-second fixed-cadence dynamic sample on the final fair-order combat code hashes. All naturally remained in play during their window; no win was forced and source forces were unchanged. Every chapter recorded firing, movement, cover use and objective-zone entries. Final sampled pathless goal waits over10 seconds were zero in all ten. All traces verified process/physics1:1, fresh budget resets, no sampled nonfinite/out-of-world positions and no same-life ammo increase.

| Chapter | Shots | Moving lives | Cover lives | Objective entries |
|---|---:|---:|---:|---:|
|01|1061|109|24|32|
|02|638|95|13|29|
|03|1148|105|19|32|
|04|1125|134|24|66|
|05|620|115|21|33|
|06|668|106|29|30|
|07|1021|119|25|62|
|08|1018|140|31|61|
|09|759|124|24|70|
|10|1667|169|45|74|

One body-overlap sample was observed in chapter09: red54:0 at32.22s, depth0.003304m versus the0.001m collision skin, no requested movement. The same life was clear in the adjacent30.20s and34.23s samples and had resumed movement/path use by34.23s. This transient is retained as a limitation; zero body anomalies is not claimed for all ten. All other recorded body checks were clear. No collision rewrite followed this single self-resolving sample. The chapter09 raw8.03-second requested-motion flag concerned another unit48:0 whose maximum stuck counter was0.8s, not a route starvation recurrence.

Combined results: `validation/combat-ai/all-ten-fair-runtime-summary.json`. All counts are sampled lives, not simultaneous actors. These headless stationary-player cases establish dynamic engagement and service coverage; they do not establish difficulty balance, player-led victory, native animation fidelity or normal-machine FPS.

## Representative180-second natural contest (17:42 UTC)

Chapter04 continued for180 simulated seconds on the unchanged final fair-order runtime. It remained naturally contested at the end:3179 shots,218 deaths,213 replacements,291 moving lives,107 cover lives and198 objective entries. Blue had exhausted its finite reserve (0 reserve,28 active); red retained27 reserve and47 active. This establishes sustained engagement and finite reinforcement consumption, not an eventual winner or balanced difficulty.

All10,800 steps had1:1 process/physics cadence and ordinary budget resets. No sampled body overlap, ammunition increase or invalid coordinates occurred. Final pathless goal waits over10 seconds were zero; maximum sampled pathless stuck age was2.0 seconds. Raw requested-motion flags remain crowd/hold diagnostics and are not automatic deadlock claims.

Chapter09's earlier3.304mm transient remains the only body-overlap sample in these current-runtime checks. Static movement code rejects depth above1mm; crowd steering still uses that collision path. Existing NPC overlap correction is incremental and may defer under its separate unchanged budget, so a pre-existing overlap can persist until a later correction. This is compatible with the observed recovery but does not prove its cause. Exact recorded X/Z, radius/depth and neighboring samples are preserved in `chapter09-transient-overlap.json`; stance/elevation/source-object identity were not captured and are explicitly marked missing.

Long evidence: `validation/combat-ai/long-contest-summary.json`, `fair-chapter04-long.json` and log. Reproduce with `long_fair_playcheck.gd --chapter=4 --seconds=180` using the same fixed-frame command; its test-only wall cap is900 seconds. No runtime changes followed these probes.

## Final bounded600-second idle-player window (18:00 UTC)

A final chapter04 run stopped at its600-second cap (600.0167 simulated seconds), not at a terminal result. It recorded3510 shots,265 deaths and237 finite replacements. Final counts were blue2 active/0 reserve and red50 active/3 reserve. Objective progress was−1, which `CampaignRules.advance_point` deterministically maps to red ownership. The unchanged source-derived force totals are consistent: blue118 casualties+2 alive=120; red147 casualties+50 alive+3 reserve=200.

The two surviving blue lives were:

- Player0:0, still untouched at source spawn(42.425,4.05), no path or movement request, M41630+180 rounds.
- AI5:0, mounted-support on gun5 at(-13.103,-9.539), no visible target, carried Tommy Gun24+180; path0 and support goal(-12.541,-10.204).

Current Godot result rules permit this state: red ownership alone is defensive control, not automatic defeat. Blue wins by secured capture or exhausting enemy active/reserve forces; loss requires the player to die without a living takeover ally. Consequently the stationary living human prevents this sample from proving natural terminal completion. The final observation is **capped idle-player waiting**, not a demonstrated outcome bug or a completed match. No actor was moved, killed or granted progress to force an ending. These semantics are verified in current Godot source, not claimed recovered Pixi runtime behavior.

All36,001 ticks retained verified1:1 cadence. No sampled body overlap, coordinate error or ammo increase occurred, no final current carried weapon was empty, and final pathless goal waits over10 seconds were zero. The longest raw requested-speed flag belonged to near-goal crowd behavior: life77:2's maximum actual stuck counter was2.03 seconds, with no distant-goal stuck sample over3 seconds.

Evidence: `validation/combat-ai/terminal-match-summary.json`, `fair-chapter04-terminal.json`, log and `terminal-survivor-observation.json`. Reproduce with standalone `terminal_fair_playcheck.gd --chapter=4 --seconds=600`; test-only wall cap2400 seconds. No further extended match or balance search is implied by this bounded test.
