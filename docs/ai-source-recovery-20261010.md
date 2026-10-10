# AI continuity and source deployment recovery

Restores lost behavior on the v3 baseline while retaining current collision indexing and shared AI budgets. This document records implementation boundaries; validation counts are recorded only after new runs.

## AI continuity

- `campaign_member_progress.gd` tracks each life and mission independently against a fixed route segment. Only a new best forward distance or actual reached waypoint counts. Lateral jitter, back-and-forth motion, route recomputation and another soldier's movement cannot reset the stalled member's timer
- `campaign_attack.gd` reports individual stalled IDs after ten seconds and retains a six-second per-member retry cooldown. The director replans only those IDs and does not tear down healthy, already accepted bounding/handoff commitments because an unrelated member stalled
- `campaign_support_wait.gd` limits ineffective support waiting to three seconds, followed by a four-second resumption window. Tactics use existing budgeted, collision-checked recovery, then continue the objective. A shot must belong to the current shooter life and observed target life, be recent, and have a current clear support ray. Sight, ammunition, or firing permission alone cannot prove active support
- The existing two muzzle/target rays now also retain whether the direct support lane is unobstructed. Penetration permission still enables the original shooting mechanic, but a first penetrable wall does not prove that a multi-layer lane supplies effective support. No additional rays are introduced
- Sparse objective reservations keep endpoints 1 m apart and store life, mission, arrival and expiry. Death, respawn, task changes, mounted/player takeover, leaving a reached endpoint and expiry release claims. Existing standpoints also prune stale owners and mission revisions
- Six-second visual reports and 2.8-second uncertain hearing reports are stored separately. Hearing never refreshes, replaces or outranks a still-valid visual report for that source, and hearing-only contacts do not authorize firing lanes

## Source layout and deployment

Offline source chapters are explicitly marked `source_layout`; chapter 1 no longer imports OrchardLevel's altered map, bounds, terrain overlays or deployment anchors. The original chapter 1 has ten anchors per side. Other chapters retain their original counts rather than being forced to ten. LAN/training orchard remains on its existing builder.

Initial placement is all-or-nothing. Every original identity, source coordinate and facing is retained in the placement record. Exact valid points are reserved before correcting invalid points, so a dense earlier actor cannot steal a later valid authored point. Native physical collision, bounds, slope and inter-person spacing are checked. A correction is bounded and records the original rejection reason, distance and attempts; failure is explicit rather than silently dropping troops or returning an illegal origin.

`CampaignRules.configure(world)` returns a boolean. Failure sets phase `placement_failed`, `reason`, `placement_report` and `last_spawn_failure`. `World.setup` retains its compiled-dictionary API and adds `setup_ok` and reports; it does not initialize AI or commit a partial roster after placement failure. The loading UI can roll back before advancing chapter progress. Reinforcement failure leaves finite reserves, deployment count and replacement cursor unchanged and emits `spawn_failed`.

## Validation boundary

New checks: `qa/ai_restored_continuity_contract.gd` (scalar states), `qa/campaign_source_placement_contract.gd` (all ten actual world initializations with no simulation ticks). Existing compatible state/frozen-world contracts are rerun; historical counts are not reused. The actual placement report records every correction for inspection, including dense chapters 05/06/09/10. No automatic battle, movement, firing or screenshot-based acceptance is performed. Real battle effectiveness and performance remain user-operated acceptance.

## New run results (2026-10-10, Godot 4.6.3)

- New AI continuity: 44/44, including same-life actual shot evidence, firing ray budgets, individual stall clocks, task/life cleanup and objective lease renewal beyond three seconds
- Existing AI/frozen contracts: 12 + 19 + 11 + 8 + 14 + 174 + 93 checks, all passing
- Source data: 11,332 checks passing; actual ten-world placement: 29,607 checks passing, all 680 actors retained, 660 exact authored positions and 20 recorded corrections of 0.36–0.72 m
- Total: 41,314 checks, zero failures in the final runs; import exit 0, no parse errors
- An initial 1.2 m goal-spacing attempt exhausted two legal Orchard slots. This was corrected to the original 1 m navigation-cell spacing (above 0.72 m body spacing), and the full 174-check frozen contract was rerun successfully
- Existing low-frequency order assignment renews a live mission's objective lease. Per-member stall replanning releases its previous claim; task/life/arrival/timeout cleanup remains bounded. No additional cooldown subsystem or per-frame full-roster sweep was introduced

Commands, engine identity and log hashes are saved in [verification.json](../qa/recovery-20261010/verification.json). Every source correction is saved in [campaign_source_placement_results.json](../qa/campaign_source_placement_results.json). These are fresh state/geometry checks, not historical pass counts or user-play/performance acceptance.
