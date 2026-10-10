extends SceneTree
## Isolated movement and trigger-clock fixtures; no enemy AI, battle or projectiles.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Traversal=preload("res://scripts/soldier_traversal.gd")
const Fire=preload("res://scripts/weapon_fire_control.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;printerr("FAIL "+label)
func count_shots(weapon: Dictionary,mode: String,hz: int) -> int:
	var state={"ammo":10000,"reload":0.0,"cooldown":0.0,"fire_mode":mode};Fire.reset(state,weapon)
	var count=0
	for step in range(hz*10):
		Fire.tick_clock(state,1.0/hz)
		if Fire.wants_shot(state,weapon,true,step==0):Fire.committed(state,weapon);count+=1
	return count
func travel(world,hz: int,sprint: bool,jump: bool) -> Dictionary:
	var u: Dictionary=world.player;Traversal.reset(u);u.position=Vector2.ZERO;u.velocity=Vector2.ZERO;u.requested_velocity=Vector2.ZERO;u.stance=0;u.stance_blend=0;u.aiming=false;u.reload=0
	var peak=0.0
	for step in range(hz*3):
		Traversal.move(world,u,Vector2.RIGHT,1.0/hz,sprint,jump and step==hz/2)
		peak=maxf(peak,u.elevation)
	return {"distance":u.position.x,"peak":peak,"grounded":u.grounded}
func _initialize():
	var catalog=Catalog.new()
	for weapon in catalog.weapons.values():
		for mode in Fire.modes(weapon):
			check(absi(count_shots(weapon,mode,30)-count_shots(weapon,mode,60))<=1,"30/60 Hz trigger cadence "+str(weapon.id)+"/"+str(mode))
	var plan=catalog.range_plan();plan.instances=[];plan.looseSegments=[];plan.trees=[];plan.vehicles=[];plan.emplacements=[];plan.units.red=[];plan.deployment.player={"x":2000,"y":1400}
	var world=World.new();world.setup(plan,catalog)
	for flags in [[false,false],[true,false],[true,true]]:
		var high=travel(world,60,flags[0],flags[1]);var low=travel(world,30,flags[0],flags[1])
		check(absf(high.distance-low.distance)<.15,"movement distance remains time based "+str(flags))
		check(absf(high.peak-low.peak)<.075 and high.grounded and low.grounded,"jump height and landing "+str(flags))
	check(world.shots==0 and world.time==0,"no battle or projectiles advanced")
	print("TIMESTEP_CONTRACT checks=%d failures=%d"%[checks,failures]);quit(0 if failures==0 else 1)
