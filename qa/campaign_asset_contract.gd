extends SceneTree
## Pure decision rules and frozen geometry; no AI update, movement or firing.
const Asset=preload("res://scripts/campaign_vehicle_ai.gd")
const Mission=preload("res://scripts/campaign_asset_mission.gd")
const Attack=preload("res://scripts/campaign_attack.gd")
const Suppression=preload("res://scripts/campaign_suppression.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():run.call_deferred()
func run():
	check(Suppression.machinegun({"mounted_fire_key":"hmg/primary"}),"fixed MG uses area fire")
	check(Suppression.machinegun({"mounted_fire_key":"armedJeep/mg"}),"jeep MG uses area fire")
	check(Suppression.machinegun({"archetype":"lmg"}),"handheld LMG uses area fire")
	check(not Suppression.machinegun({"mounted_fire_key":"tank/cannon"}),"cannon does not inherit machinegun suppression")
	check(Suppression.in_sector(.30),"MG fires while traversing through an observed sector, before precise aim")
	check(not Suppression.in_sector(.8),"suppression cannot fire into unrelated direction")
	check(not Suppression.in_sector(.1,.6),"suppression does not authorize a skyward barrel")
	check(Suppression.known({"source":"vision","at":0.0},1.5),"recent last-seen direction supports brief continuing fire")
	check(not Suppression.known({"source":"hearing","at":0.0},.2),"sound alone does not authorize blind suppression")
	check(not Suppression.known({"source":"vision","at":0.0},2.0),"last-seen area fire has finite expiry")
	check(Suppression.burst(.8,0) and not Suppression.burst(1.0,0),"aggressive burst still releases trigger for a rest interval")
	var catalog=preload("res://scripts/source_catalog.gd").new()
	var plan=preload("res://scripts/orchard_level.gd").plan(catalog)
	var world=preload("res://scripts/proving_world.gd").new();world.setup(plan,catalog)
	var controller=world.campaign_ai.vehicle_ai
	var jeep: Dictionary={}
	for v in world.vehicles:
		if not v.emplacement:jeep=v
	check(not jeep.is_empty(),"authored jeep exists")
	var u: Dictionary=world.units[1].duplicate(true);u.player=false;u.team=0;u.mounted=-1;u.ai_order={"task":"support"}
	check(Asset.eligible(u,jeep,0),"healthy actual infantry can become crew")
	u.network_peer_id=2;check(not Asset.eligible(u,jeep,0),"remote human never receives autonomous crew control");u.network_peer_id=0
	u.ai_order.breach_thrower=true;check(not Asset.eligible(u,jeep,0),"breaching specialist is not stolen for driving");u.ai_order.erase("breach_thrower")
	u.ai_order.bound_role="cover";check(not Asset.eligible(u,jeep,0),"committed overwatch member remains on mission");u.ai_order.erase("bound_role")
	var support_cost=Asset.crew_cost(u,jeep.position);u.ai_order.task="attack"
	check(support_cost<Asset.crew_cost(u,jeep.position),"crew selection prices disruption, not just distance")
	var stock=jeep.duplicate(true)
	for state in stock.states.values():state.ammo=0;state.reserve=0
	check(not Asset.has_ammo(stock),"empty asset cannot recruit another operator")
	var road: Array=controller.routes[jeep.source_id]
	var job=Mission.begin(world,jeep,road,controller.frontage());var slices=0;var max_slice=0
	while not job.done and slices<6000:
		var before=int(job.samples);Mission.pump(world,jeep,job,350,2)
		max_slice=maxi(max_slice,int(job.samples)-before);slices+=1
	check(job.done and not job.result.is_empty(),"real hull route reaches a useful firing post")
	check(max_slice<=2,"mission geometry never exceeds two pose queries per slice")
	if not job.result.is_empty():
		check(Mission.firing_lane(world,jeep,job.result.goal,controller.frontage()),"chosen parking post really covers the gate")
		check(job.result.goal!=road[-1],"vehicle mission does not end at unrelated original route endpoint")
		print("ASSET_STATIC_POST goal=",job.result.goal," route=",job.result.route," slices=",slices," samples=",job.samples)
	var reachable_mounts=0
	for v in world.vehicles:
		var points=controller.boarding_points(v);var found=false
		print("ASSET_BOARD_GEOMETRY id=",v.source_id," position=",v.position," elevation=",v.elevation," angle=",v.angle," points=",points)
		for at in points:
			var target=world.campaign_ai.point_cell(at)
			print("ASSET_BOARD_CONNECTOR at=",at," node=",world.campaign_ai.graph.get_point_position(target)," clear=",world.campaign_ai.traversable(world,world.campaign_ai.graph.get_point_position(target),at))
			if target<0 or not world.campaign_ai.traversable(world,world.campaign_ai.graph.get_point_position(target),at):continue
			for actor in world.units:
				if Asset.eligible(actor,v,0) and world.campaign_ai.same_component(actor.position,at):found=true;break
		check(found,"authored asset has a real connected boarding approach: "+str(v.source_id))
		if v.emplacement:
			for fraction in [-.9,-.5,0,.5,.9]:
				var aim: Vector2=v.position+Vector2.from_angle(v.angle+fraction*float(v.profile.traverse))*6
				print("ASSET_SECTOR id=",v.source_id," fraction=",fraction," clear=",Mission.firing_lane(world,v,v.position,aim))
			check(controller.prepare_mission(v),"original fixed weapon can actually cover a useful sector: "+str(v.source_id))
			var seat=preload("res://scripts/emplacement_profile.gd").operator_position(v)
			for at in points:
				check(at.distance_to(seat)<.5,"external approach stays within real operation reach")
				for i in range(1,9):check(not world.blocked(at.lerp(seat,float(i)/8),.31,1.95,v.id,0),"boarding does not pass through another wall")
		if found:reachable_mounts+=1
	check(reachable_mounts==3,"same three original assets remain usable")
	world.build_unit_index()
	var observer: Dictionary={}
	for ally in world.nearby_units(jeep.position,12.0):
		if ally.alive and ally.team==0 and ally.id!=u.id:observer=ally;break
	check(not observer.is_empty(),"authored deployment has a nearby real observer")
	if not observer.is_empty():
		var saved: Dictionary=observer.get("ai_contacts",{}).duplicate(true)
		observer.ai_contacts={900:{"source":"hearing","observed_at":0.0,"confidence":.7,"position":Vector2(jeep.position)+Vector2(-4,0)}}
		check(controller.reported_sector(jeep,u,20.0).is_empty(),"relayed sound cannot authorize area fire")
		observer.ai_contacts[900].source="vision"
		var relayed=controller.reported_sector(jeep,u,20.0)
		check(not relayed.is_empty() and relayed.at==0.0 and relayed.relay==observer.id,"real nearby visual report is copied without refreshing its age or looking up a target body")
		observer.ai_contacts=saved
	var point={"position":Vector2.ZERO,"radius":2.0,"elevation":0.0,"capture_height":1.8}
	var actor={"id":1,"alive":true,"mounted":-1,"position":Vector2(5,0),"elevation":0.0,"spawn_epoch":0,"ai_stress":0.0,"path":[],"ai_order":{"goal":Vector2.ZERO},"ai_goal":Vector2.ZERO}
	check(Attack.entry_priority([actor],point),"nearby attackers prioritize actual capture entry")
	actor.ai_order.mandatory_route=true;check(not Attack.entry_priority([actor],point),"trench approach is not prematurely skipped")
	actor.position=Vector2.ZERO;check(Attack.entry_priority([actor],point),"a real foothold is retained even when a route flag is stale")
	actor.position=Vector2(5,0);actor.ai_order.erase("mandatory_route")
	var q={};check(not Attack.checkpoint(q,[actor],point,0),"new attack has a progress grace interval")
	check(Attack.checkpoint(q,[actor],point,11),"ten seconds without actual movement triggers bounded replanning")
	check(not Attack.checkpoint(q,[actor],point,12),"replanning cannot churn every decision")
	actor.position=Vector2.ZERO;check(not Attack.checkpoint(q,[actor],point,30),"contesting troops are not pulled out by a stall timer")
	check(world.time==0 and world.shots==0,"QA never runs combat")
	print("CAMPAIGN_ASSET_CONTRACT checks=%d failures=%d"%[checks,failures]);quit(0 if failures==0 else 1)
