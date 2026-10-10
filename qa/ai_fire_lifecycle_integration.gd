extends SceneTree
## Controlled integration fixture, not normal-budget battle/performance acceptance.
## Calls real perception, lane checks and AI fire with explicit test budget phases.
const Aim=preload("res://scripts/campaign_directional_aim.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():run.call_deferred()
func run():
	var catalog=preload("res://scripts/source_catalog.gd").new()
	var world=preload("res://scripts/proving_world.gd").new();world.setup(preload("res://scripts/orchard_level.gd").plan(catalog),catalog)
	for actor in world.units:actor.alive=false
	var u: Dictionary=world.units[1];var target: Dictionary=world.units[30];var point: Vector2=world.campaign.points[0].position
	u.alive=true;target.alive=true;u.player=false;u.position=point-Vector2(1.5,0);target.position=point+Vector2(1.5,0)
	u.elevation=world.terrain.height(u.position);target.elevation=world.terrain.height(target.position)
	u.stance=0;u.stance_blend=0.0;target.stance=0;u.facing=Vector2.RIGHT;u.velocity=Vector2.ZERO
	preload("res://scripts/campaign_rules.gd").apply_loadout(world,u,["m416"])
	u.brain=100.0;u.ai_order={"task":"hold","goal":u.position,"direct":true};u.ai_task="hold";u.ai_contacts={};world.time=10.0;world.build_unit_index()
	var ai=world.campaign_ai;var selected=ai.perception.refresh(u)
	check(selected.get("id",-1)==target.id,"real bounded perception sees actual target in clear courtyard")
	u.ai_target=target.id;u.ai_visible=true;u.ai_reaction=0.0
	var contact: Dictionary=u.ai_contacts[target.id];var weapon: Dictionary=world.weapon_for(u)
	check(not Aim.fire_context_matches(u,contact,weapon),"observation alone does not invent a checked lane")
	world.ai_budget_usec=2000;ai.tactics.decide(u,u.position,contact,true)
	check(u.ai_fire_clear and Aim.fire_context_matches(u,contact,weapon),"actual muzzle/friendly-lane check grants matching context")
	# Hold movement to isolate firing; this is explicit fixture state, not gameplay AI.
	u.ai_tactic={"goal":u.position,"hold":true,"stance":0,"state":"hold"}
	Aim.observe(u,contact,weapon,Vector2.ZERO);Aim.track(u,1.0)
	world.FireControl.reset(u,weapon);u.cooldown=0.0;u.ai_fire_clock=0.0;u.ai_fire_time=0.0
	var ammo=int(u.ammo);world.ai_budget_usec=0;ai.update(u,1.0/60.0)
	check(world.shots==1 and u.ammo==ammo-1,"next AI firing opportunity uses actual fire and finite ammunition")
	world.time+=1.0;world.tick_state(u,weapon,1.0);ai.perception.remember_vision(u,target)
	check(Aim.fire_context_matches(u,u.ai_contacts[target.id],weapon),"new stable-target report timestamp retains checked identity")
	world.ai_budget_usec=0;ai.update(u,1.0)
	check(world.shots==2 and u.ammo==ammo-2,"fresh same-target report does not suppress the next real AI burst")
	target.spawn_epoch=int(target.get("spawn_epoch",0))+1;world.time+=1.0;world.tick_state(u,weapon,1.0);ai.perception.remember_vision(u,target)
	world.ai_budget_usec=0;ai.update(u,1.0)
	check(world.shots==2,"observed new life cannot reuse old-life firing permission")
	check(ai.tactics_due(u,u.ai_contacts[target.id],weapon,u.get("ai_tactic_signature",""),false,true,2000),"unchanged deferred new-life report requests a later budgeted lane check")
	world.ai_budget_usec=2000;ai.tactics.decide(u,u.position,u.ai_contacts[target.id],true)
	u.ai_tactic={"goal":u.position,"hold":true,"stance":0,"state":"hold"}
	check(Aim.fire_context_matches(u,u.ai_contacts[target.id],weapon),"actual repeated lane check resolves deferred context without new perception")
	# The normal trigger release gate remains in force after a rejected burst.
	u.ai_fire_time=0.0;u.ai_fire_clock=1.0;world.ai_budget_usec=0;ai.update(u,.1)
	u.ai_fire_clock=0.0;world.ai_budget_usec=0;ai.update(u,.1)
	check(world.shots==3 and u.ammo==ammo-3,"checked new life resumes only after ordinary trigger release")
	u.ai_contacts.clear();u.ai_visible=false;u.ai_target=-1;u.ai_fire_clock=0.0;world.tick_state(u,weapon,1);world.ai_budget_usec=0;ai.update(u,.1)
	check(world.shots==3,"removed observed contact does not resurrect shooting")
	print("AI_FIRE_LIFECYCLE_INTEGRATION checks=%d failures=%d actual_shots=%d; explicit fixture budgets, no battle/performance claim"%[checks,failures,world.shots])
	world.campaign_director.cancel();quit(0 if failures==0 else 1)
