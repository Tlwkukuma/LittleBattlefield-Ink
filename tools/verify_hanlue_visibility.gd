extends SceneTree
## Frozen actual eyes, terrain rays and budget gating; no simulation/AI combat tick.
const World=preload("res://scripts/proving_world.gd")
var failures=0
var checks=0
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize():call_deferred("run")
func run():
	var catalog=preload("res://scripts/source_catalog.gd").new();var world=World.new()
	world.setup(preload("res://scripts/hanlue_layout.gd").plan(catalog),catalog)
	if not world.setup_ok:printerr("setup failed");quit(2);return
	# Sample each initial concealed group using a real nearby cargo-bed observer.
	var truck: Dictionary=world.vehicles[0];var observer: Dictionary=world.units[truck.passenger_ids[0]]
	for group in world.hanlue_tactics.groups:
		var target: Dictionary=group.members[1]
		var source=catalog.original_point(target.position,world.plan)
		truck.position=catalog.position([source.x,1120],world.plan)
		world.VehicleGround.initialize(world.terrain,truck,world);world.hanlue_transport.sync_passengers(truck)
		observer.facing=(target.position-observer.position).normalized()
		target.stance=2;target.stance_blend=2.0
		check(not world.campaign_ai.perception.can_see(observer,target),"real ridge hides prone "+str(group.id))
		target.stance=0;target.stance_blend=0.0
		check(world.campaign_ai.perception.can_see(observer,target),"standing above ridge is visible "+str(group.id))
	# A driver sees an exposed person in front; cargo observers are correctly
	# blocked toward the front by the actual cab and were used for side ridges.
	observer=world.units[int(truck.driver_id)]
	# A target explicitly placed on the open road at setup height is visible.
	var target: Dictionary=world.player
	target.position=truck.position+Vector2.RIGHT*6;target.elevation=world.terrain.height(target.position);target.stance=0;target.stance_blend=0.0
	observer.facing=(target.position-observer.position).normalized()
	check(world.campaign_ai.perception.can_see(observer,target),"open-road exposure visible from actual seat")
	world.profile_ai=true;world.campaign_ai.step_profile.clear();truck.hanlue_observe_at=0;world.ai_budget_usec=0
	world.hanlue_transport.observe_road(truck)
	check(int(world.campaign_ai.step_profile.get("vision_rays",0))==0 and truck.hanlue_observe_at==0,"zero budget performs no vision query")
	world.ai_budget_usec=100000;truck.hanlue_observer=0;world.campaign_ai.step_profile.clear()
	world.hanlue_transport.observe_road(truck)
	check(truck.get("hanlue_alerted",false) and world.campaign.hanlue.stage=="ambush","real open-road observation reveals ambush")
	check(int(world.campaign_ai.step_profile.get("vision_rays",0))<=2 and world.ai_budget_usec<100000,"mounted vision capped at two rays and charged to shared budget")
	# Event response is one local alarm only, without granting target records.
	for v in world.vehicles:v.hanlue_alerted=false
	world.vehicles[1].position=Vector2(-100,0);world.vehicles[2].position=Vector2(100,0)
	var contacts=observer.get("ai_contacts",{}).duplicate(true)
	world.hanlue_transport.observe_event({"type":"shot","unit":{"position":truck.position}})
	check(truck.hanlue_alerted and not world.vehicles[1].hanlue_alerted and not world.vehicles[2].hanlue_alerted,"audible shot alerts only nearby truck")
	check(observer.get("ai_contacts",{})==contacts,"sound alarm does not broadcast hidden target contacts")
	check(world.time==0 and world.simulation_tick==0 and world.shots==0,"no battle simulation")
	print("HANLUE_VISIBILITY checks=%d failures=%d; frozen geometry only"%[checks,failures]);quit(1 if failures else 0)
