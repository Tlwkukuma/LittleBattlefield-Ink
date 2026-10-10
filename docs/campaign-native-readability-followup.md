# Native campaign readability follow-up, 2026-10-09 15:13 UTC

## Truthful FPS and update cadence

The native software-rendered review exposed a real instrumentation bug: the always-visible HUD reported 30 FPS while actual rendered throughput was about 1 FPS. Its previous counter summed Godot's process delta, which can be clamped by the existing two-physics-steps-per-frame setting. Dividing that clamped value by time scale did not recover real elapsed time.

`wall_fps_counter.gd` now measures frame intervals with monotonic `Time.get_ticks_usec()`, retaining the existing half-second display window. `network_status_hud.gd` also schedules its quarter-second refresh using monotonic wall time. No simulation timing, catch-up limits, AI budgets or rendering budgets change. The normal counter does not start the Debug profiler.

The resource-only fake-clock contract passes 27 checks for time scales 1, 0.2 and 0, true 1 FPS and 60 FPS, and wall-clock quarter-second HUD refresh. Native refreshed screenshots confirm the corrected counter reports approximately 0–2 FPS (usually 1) in this llvmpipe environment, rather than the old 30 FPS floor. This is a truthful cloud observation, not a claim about target Windows hardware. Earlier chapter 1–4 screenshots predate the counter fix.

## Off-map background

The source-faithful chapter 2 screenshot shows its east-edge spawn with about half the camera viewport beyond the finite terrain. The armory's existing rightward camera offset keeps the soldier clear of the right-side panel; an inward camera clamp could instead obscure the soldier.

`campaign_background.gd` therefore changes only the empty WorldEnvironment background for chapters 2–10 to the existing ground BASE palette darkened by 12%. It adds no ground, geometry, collisions or apparent routes outside the actual map. Every scene rebuild reapplies the policy; orchard and training restore exact original lavender `c0bbcc`. Camera angle, zoom, aim projection, actor scale and all source coordinates remain unchanged.

The Environment-only contract passes 14 checks, including chapter 2 → orchard → chapter 9 reset and no plan mutation. The native chapter 3 recheck at 15:35 UTC confirms the same left map edge and unchanged source/camera placement, now with muted ground-derived background instead of lavender. Chapters 5–10 startup screenshots also use the new backdrop.

## Long chapter heading, 15:27 UTC

Native chapter 8 review at 1178×814 exposed a right-panel overflow: its longer 20px equipment heading imposed an unwrapped minimum width larger than the existing panel. The heading now word-wraps at the same 265px content minimum. Font size, panel width, camera composition and controls remain unchanged. A native Control-only layout fixture passes 300 checks across all ten chapter titles at 960, 1178 and 1440 pixel root widths, including default equipment controls remaining within the window. Native chapter 8 recheck at 15:33 UTC verifies the long heading wraps into two lines with full right padding, equipment dropdowns and Continue button inside the 1178×814 window. A separate actual chapter 2 resize to 960×600 confirms briefing and live health/ammo/objective HUD still fit.

## Offline retry shortcut, 15:46 UTC

Native live chapter 2 testing found F5 was still intercepted by the inherited debug-only function-key filter, despite the result UI advertising it. A narrow offline-campaign policy now allows only a fresh F5 press through that filter. Network play, editing, text entry, loot and equipment-wheel modals cannot use the new exception; the home menu still consumes input first. Other function keys retain the original Debug policy. Offline entry/retry clears transient trigger/jump flags and retains the existing held-fire latch until mouse release.

The pure key-policy fixture passes 16 checks. At 16:08 UTC, the actual-scene lifecycle fixture passes 3,012 checks cleanly: two 1↔10 cycles, eight rebuilds/retries, queued-free waits, actual F5 handler calls from briefing and constructed win/loss result states, zero simulation ticks, stable logical node/actor/flash counts, no stale-order sentinel or transient trigger/jump carryover, and no fabricated chapter unlocks. Chapter 1 stays at 6,876 stage nodes / 60 actors / 305 flash pieces; chapter 10 stays at 7,500 / 80 / 435. The separate physical-key native UI retest passed at 16:15 UTC: Debug-closed F5 returned chapter 2 to a fresh paused briefing, resuming showed 30/180 ammunition without an unexpected shot, and chapter selection remained 0/10 completed with later chapters locked.
