> Superseded as a design specification at 2026-10-09 14:04 UTC. The user requires original Pixi first-ten-chapter fidelity. The invented staged missions and force curve below are retained only as a draft record; see `pixi-fidelity-matrix.md`. Technical progression/save/UI verification remains useful.

# Ten-chapter campaign: implementation and verification plan

Scope: one continuous, offline ten-chapter campaign in the existing `proving_ground.tscn`, with chapter selection, briefing and tactics, retry, local chapter progress, and a final ending. This is an implementation plan, not a claim that all chapters have been play-balanced or visually accepted.

The immutable imported scene library already contains thirty authored layouts. Chapters 2–10 derive their corresponding source scenes rather than reskinning the orchard. Imported files remain unchanged. Chapter 1 retains its existing geometry, forces, equipment, destruction, local AI, and win/loss rules. The existing first-chapter LAN flow remains separate from offline chapter progression.

| Chapter | Space and tactical problem | Mission sequence |
| --- | --- | --- |
| 1 石墙果园 | Existing stone courtyard, western entrance, hill and trench alternatives | Existing orchard command-point assault |
| 2 装配厂区 | Asymmetric T-road, fenced loading approach, workshop rooms | Secure loading junction, then workshop relay |
| 3 洪泛草甸 | River and two genuine bridge approaches | Secure main bridge exit, then hold eastern bridgehead |
| 4 双街小镇 | Offset streets, short alleys, connected building approaches | Secure street crossing, then civic square |
| 5 干溪通道 | Diagonal creek with central road and eastern bridge alternatives | Secure creek crossing, then northern relay |
| 6 要塞内院 | Outer enclosure, central twin passages, inner command rooms | Secure outer court, then command post |
| 7 林间路口 | Forest visibility, drainage crossing, road junction | Capture and hold the junction through counterattack |
| 8 城郊医院区 | L-road, ward compounds, constrained courtyards | Secure southern approach, then hold evacuation yard |
| 9 芦苇湿地 | Water, island boardwalk and bridge bottlenecks | Secure southern crossing, then hold island signal point |
| 10 谷仓村落 | Three farmyards, discontinuous walls, diagonal village road | Secure approach, village green, then hold final command position |

## Interfaces and ownership

- `campaign_catalog.gd` and `data/campaign/chapters.json`: immutable-source derivation, mission stages, routes, public support positions and chapter descriptions
- `campaign_progress.gd`: versioned, new `user://campaign_10_v1.json` namespace; chapter checkpoints only, no claim of mid-battle resume
- `campaign_rules.gd`: finite-force rules plus sequential capture/hold progression; active objective stays `points[0]`
- `campaign_plan.gd` and `campaign_director.gd`: narrow authored-metadata generalization; original orchard behavior preserved
- `proving_ground.gd`, `home_screen.gd`, `campaign_presentation.gd`: chapter entry, pre-battle tactic selection, active objective and stage feedback, retry/next/final screens
- AI worker owns AI execution and vehicle tasks; animation worker owns character changes. Shared integrations are coordinated before changes

`godot3d.campaign_chapter` identifies the offline campaign chapter. `godot3d.campaign_tactics` supplies pixel-coordinate `support_posts`, `vehicle_frontage`, and optional explicit `breach_source_id`. Stage changes update public metadata, route arrays, capture-cell caches and squad orders, not perception or hidden enemy knowledge.

## Required checks

1. Baseline hashes: no modifications under `data/original`; first-chapter geometry unchanged
2. Every derived plan compiles; all weapons/components/vehicles resolve; unique objective and object IDs
3. Objective footprints have legal connected standpoints, spawns and route goals within world bounds; bridges/water retain real collision
4. Rules: capture stages, contested hold, finite reserves, no-living-ally defeat, elimination without hold deadlock, final chapter completion
5. Progress: initial unlock, sequential unlock, repeat wins, version validation, corrupt-file recovery, no writes to legacy progress
6. UI lifecycle: chapter selection, locked chapters, briefing/tactics before time advances, retry/next, repeated menu entry, final ending
7. Necessary headless/resource checks and source-level regressions only until the user explicitly authorizes automated combat. Actual feel, visuals, balance and performance are not inferred from static checks

## Checkpoints

- Initial ownership snapshot: `checkpoints/campaign_initial` outside the project (2026-10-09)
- Implementation and verification results will be appended below as they become available

## Force and equipment curve (design hypothesis; not combat-balanced yet)

Chapter 1 retains the exported original composition, including its finite mortar schedule. Chapters 2–10 use explicit authored weapon pools rather than the source scenes’ absent loadouts. Every soldier and replacement receives a finite ordinary magazine/reserve; no infinite ammunition or health scaling is introduced. New-chapter active caps are at most 30 per side. The player begins each chapter with its stated primary plus P92, knife and HE grenades; equipment does not transfer between chapters.

| Chapter | Blue active / reserve | Red active / reserve | Blue primary pool | Red primary pool | Capture / hold | Design reason |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 30 / 90 | 30 / 90 | Original exported roster | Original exported roster | Original 7s capture | Preserve approved first chapter |
| 2 | 24 / 60 | 22 / 50 | UMP, M416, SCAR-L, Tommy Gun, M249, SKS | AKM, UMP, AKM, S12K, RPD, SKS | capture 7s → capture 7s | 较小室内分队，短距离武器较多，降低第二章目标切换学习负担 |
| 3 | 26 / 78 | 26 / 78 | SCAR-L, M416, M16A4, UMP, M249, Mini14 | AKM, SKS, M416, Tommy Gun, RPD, Dragunov | capture 7s → capture 7s + hold 25s | 桥头长视线加入精确射手；双方兵力相等，25秒守点用于教学 |
| 4 | 28 / 84 | 28 / 92 | M416, UMP, SCAR-L, MP5K, M249, SKS | AKM, Tommy Gun, Beryl M762, S12K, RPD, SKS | capture 7s → capture 7s | 城市短巷强化近距交叉火力；少量敌军储备优势增加第二阶段压力 |
| 5 | 26 / 86 | 28 / 92 | SCAR-L, M16A4, M416, UMP, M249, Mini14 | AKM, M416, SKS, Tommy Gun, RPD, Dragunov | capture 7s → capture 7s | 干溪交叉点偏中远距离；保持可机动侧翼，避免仅增加敌军人数 |
| 6 | 30 / 90 | 30 / 102 | M416, UMP, SCAR-L, S12K, M249, SKS | AKM, UMP, Beryl M762, S12K, RPD, SKS | capture 9s → capture 9s | 要塞双通道与房间要求近距配装；储备差小于一波完整在场兵力 |
| 7 | 30 / 102 | 30 / 102 | M416, SCAR-L, UMP, M16A4, M249, Mini14 | AKM, M416, UMP, SKS, RPD, Dragunov | capture 9s + hold 40s | 40秒持续守点；双方总兵力相等，避免持守章节同时承受过大兵力劣势 |
| 8 | 30 / 102 | 30 / 114 | UMP, M416, MP5K, SCAR-L, M249, SKS | AKM, Tommy Gun, UMP, S12K, RPD, SKS | capture 9s → capture 9s + hold 30s | 医院院墙与病房用近距武器；30秒疏散守点比森林稍短 |
| 9 | 28 / 104 | 30 / 114 | SCAR-L, M416, M16A4, UMP, M249, Mini14 | AKM, SKS, M416, UMP, RPD, Dragunov | capture 9s → capture 9s + hold 35s | 桥口限制同时接敌规模，蓝军略少在场但保留充分有限储备 |
| 10 | 30 / 120 | 30 / 135 | M416, SCAR-L, UMP, M16A4, M249, Mini14 | AKM, Beryl M762, UMP, SKS, RPD, Dragunov | capture 9s → capture 9s → capture 9s + hold 45s | 三阶段终章提供较多有限储备；45秒最终持守，敌军耗尽可提前结束 |

Later difficulty combines different approach geometry, weapon distribution, sequential objectives and finite reserve pressure. Hold timers pause while contested and reset when the enemy fully retakes the point. Total enemy exhaustion remains an alternate win, preventing a completed battle from waiting forever on a hold timer. Original authored fixed mounts are AI-eligible in new chapters; moving vehicles remain usable by the player until a particular full-body route is validated and explicitly enabled for AI. This distinction is intentional and must not be represented as all-vehicle AI coverage.
