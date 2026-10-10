extends SceneTree
## Actual setup, static geometry/query/retirement only. Never advances AI or combat.
const World=preload("res://scripts/proving_world.gd")
const Layout=preload("res://scripts/hanlue_layout.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
var checks=0
var failures=0
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize():call_deferred("run")
func run():
	var catalog=Catalog.new();var world=World.new();var plan=Layout.plan(catalog)
	var source_before=JSON.stringify(catalog.scenes)
	var compiled=world.setup(plan,catalog)
	check(compiled.get("setup_ok",false) and world.setup_ok,"H01 actual initialization")
	if not world.setup_ok:
		printerr(JSON.stringify(world.placement_report));printerr(world.campaign.reason);quit(1);return
	check(world.units.size()==24 and world.vehicles.size()==3,"finite 24 soldiers/3 trucks")
	check(world.campaign.active_counts()==[12,12] and world.campaign.reserves==[0,0],"force conservation/no reserves")
	check(world.campaign.hanlue.stage=="concealed" and world.campaign.phase=="playing","separate phase")
	check(world.units.filter(func(u):return u.team==0).all(func(u):return u.stance==2 and u.stance_blend==2.0),"all ambushers including player start physically prone")
	check(world.campaign.points.is_empty() and world.campaign_director.teams.is_empty(),"no capture director")
	for v in world.vehicles:
		check(v.type=="truck" and v.modes.is_empty() and v.states.is_empty(),"real unarmed truck")
		check(v.hanlue_crew.size()==4 and v.passenger_ids.size()==3,"finite unique crew")
		check(absf(world.terrain.height(v.position)+2.4)<.03,"truck on depressed road")
		check(world.VehicleGround.sample(world.terrain,v,v.position,v.angle,true,world).get("valid",true),"truck ground pose")
		for id in v.hanlue_crew:
			var u: Dictionary=world.units[id]
			check(u.mounted==v.id,"real seat binding")
			check(world.enclosed(u)==(id==v.driver_id),"open bed passengers vulnerable")
	for group in world.hanlue_tactics.groups:check(group.members.size()==3,"four true groups")
	for ramp in Layout.RAMPS:
		var a=catalog.position(ramp.points[0],plan);var b=catalog.position(ramp.points[1],plan)
		check(world.campaign_ai.same_component(a,b),"ramp navigation connectivity")
		check(not world.campaign_ai.path_between(a,b).is_empty(),"ramp real path exists")
	var unit: Dictionary=world.units[1];var before=unit.duplicate(true)
	world.build_unit_index();world.retire_mission_unit(unit,"extracted")
	check(unit.alive and unit.health==before.health and unit.inventory==before.inventory,"retirement preserves life/equipment")
	check(not world.nearby_units(unit.position,1).has(unit),"retired actor removed from local index")
	check(not world.unit_ray_index.nearby(unit.position,1).has(unit),"retired actor removed from ray tree")
	check(world.campaign.nearest_ally(world).get("id",-1)!=unit.id,"retired actor not takeover candidate")
	var effects=preload("res://scripts/vehicle_destruction_fx.gd").new();effects.world=world
	world.vehicles[0].hanlue_escaped=true
	check(not effects.near(world.vehicles[0]),"escaped truck cannot retain active smoke emitter")
	effects.free()
	check(JSON.stringify(catalog.scenes)==source_before,"original chapter data immutable")
	check(world.time==0 and world.simulation_tick==0 and world.shots==0,"zero battle simulation")
	print("HANLUE_DEPLOYMENT checks=%d failures=%d; zero battle ticks"%[checks,failures]);quit(1 if failures else 0)
