extends SceneTree
## Pure equipment dictionary transitions; no world.step, AI updates, movement or firing.
const AI=preload("res://scripts/campaign_ai.gd")
const Rules=preload("res://scripts/campaign_rules.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():run.call_deferred()
func run():
	var catalog=preload("res://scripts/source_catalog.gd").new()
	var world=preload("res://scripts/proving_world.gd").new()
	world.setup(preload("res://scripts/orchard_level.gd").plan(catalog),catalog)
	var u: Dictionary=world.units[1].duplicate(true)
	Rules.apply_loadout(world,u,["m416","portable-mortar","army-knife"])
	u.inventory.m416={"ammo":11,"reserve":22}
	u.weapon_id="portable-mortar";u.ammo=0;u.reserve=0;u.holstered=true;u.deployed_mortar=99
	u.loadout.erase("portable-mortar");u.quick_owned.erase("portable-mortar");u.inventory.erase("portable-mortar")
	AI.select_weapon(world,u,0)
	check(u.weapon_id=="m416" and not u.holstered,"mortar carrier draws actual carried rifle")
	check(u.ammo==11 and u.reserve==22,"stored finite rifle ammo survives return")
	check(not u.inventory.has("portable-mortar"),"deployed mortar is not recreated in carried inventory")
	check(u.deployed_mortar==99,"dismount preserves ownership of the current-life deployed mortar")
	check(not world.Equipment.busy(u),"holster no longer permanently blocks infantry fire")
	u.holstered=true;u.ammo=7;u.reserve=13
	AI.select_weapon(world,u,0)
	check(not u.holstered and u.ammo==7 and u.reserve==13,"same-weapon draw retains live ammo rather than stale inventory")
	u.reload=1.25;u.cooldown=.12
	AI.select_weapon(world,u,0)
	check(u.reload==1.25 and u.cooldown==.12,"ordinary same-weapon decision preserves in-progress reload and cooldown")
	u.loadout=[];u.holstered=true
	AI.select_weapon(world,u,0)
	check(u.holstered and u.loadout.is_empty(),"empty carried loadout cannot invent a replacement weapon")
	Rules.apply_loadout(world,u,["m416","army-knife"])
	u.ammo=0;u.reserve=0
	AI.select_weapon(world,u,0)
	check(u.weapon_id=="army-knife","exhausted firearm can select actual melee fallback")
	var source=FileAccess.get_file_as_string("res://scripts/campaign_vehicle_ai.gd")
	check(source.contains("world.campaign_ai.select_weapon(world,u,0.0)"),"AI dismount invokes carried-weapon restoration")
	var frontage: Vector2=world.campaign_ai.vehicle_ai.frontage()
	check(frontage==world.catalog.position([2350,1100],world.plan),"orchard frontage remains unchanged")
	world.plan.godot3d.campaign_tactics={"vehicle_frontage":[1200,900]}
	check(world.campaign_ai.vehicle_ai.frontage()==world.catalog.position([1200,900],world.plan),"authored generic frontage converts source coordinates")
	world.plan.godot3d.campaign_tactics={};world.plan.godot3d.campaign_chapter=2
	check(world.campaign_ai.vehicle_ai.frontage()==world.campaign.points[0].position,"generic frontage defaults to active objective")
	var replacement: Dictionary=world.units[1]
	var old_epoch=int(replacement.get("spawn_epoch",0));var vehicle_count=world.vehicles.size()
	var old_ammo: Dictionary=world.vehicles[0].states.duplicate(true)
	replacement.deployed_mortar=0;replacement.alive=false;replacement.death_age=1.0
	world.plan.deployment.blue.replacementLoadouts=[["portable-mortar","m416"]]
	var reinforced: Dictionary=world.campaign.reinforce(world,0,1)
	check(not reinforced.is_empty() and reinforced.id==replacement.id,"reinforcement reuses the dead actor slot")
	check(replacement.spawn_epoch==old_epoch+1 and not replacement.has("deployed_mortar"),"new life cannot inherit deployed mortar ownership")
	check("portable-mortar" in replacement.loadout and replacement.ammo>0,"newly issued mortar keeps its own finite loadout")
	check(world.vehicles.size()==vehicle_count and world.vehicles[0].states==old_ammo,"respawn does not delete or refill an old deployment")
	var controller=world.campaign_ai.vehicle_ai
	var mount: Dictionary=world.vehicles[0];var driver=mount.get("driver_id",-1)
	var mount_states: Dictionary=mount.states.duplicate(true);var health=float(mount.health)
	mount.ai_controlled=true;mount.ai_mission={"goal":Vector2(99,99)}
	controller.missions[mount.id]={"result":{"goal":Vector2(99,99)}}
	controller.mission_jobs[mount.id]={"done":false}
	controller.reservations[2]={"vehicle":mount.id,"epoch":world.units[2].get("spawn_epoch",0)}
	world.plan.godot3d.vehicleRoutes={str(mount.source_id):[{"x":1200,"y":900},{"x":1300,"y":900}]}
	var decision_budget=int(world.ai_budget_usec)
	controller.objective_changed()
	check(controller.missions.is_empty() and controller.mission_jobs.is_empty() and controller.reservations.is_empty(),"stage transition releases stale missions jobs and crew reservations")
	check(not mount.has("ai_mission") and mount.ai_force_replan,"old-stage vehicle goal is invalidated for bounded replanning")
	check(controller.routes.size()==1 and controller.routes[mount.source_id].size()==2,"only explicit new-stage vehicle routes are loaded")
	check(mount.get("driver_id",-1)==driver and mount.states==mount_states and float(mount.health)==health,"stage transition preserves occupant health and finite mounted ammo")
	check(world.ai_budget_usec==decision_budget,"stage reset does not execute a geometry job")
	check(world.time==0 and world.shots==0,"state checks never advance combat")
	print("AI_EQUIPMENT_LIFECYCLE checks=%d failures=%d; world.time=0 shots=0"%[checks,failures])
	quit(0 if failures==0 else 1)
