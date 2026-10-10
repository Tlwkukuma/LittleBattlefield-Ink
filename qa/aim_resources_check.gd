extends SceneTree
## Numeric and resource checks only: no player input, firing, or gameplay simulation.
const Geometry=preload("res://scripts/aim_geometry.gd")
const Handling=preload("res://scripts/weapon_handling.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const Art=preload("res://scripts/proving_art.gd")
var failures: Array=[]
var count=0
func _initialize():run.call_deferred()
func check(value: bool,label: String):
	count+=1
	if not value:failures.append(label);push_error(label)
func run():
	var low=Vector3(-1,0,-1);var high=Vector3(1,1,1)
	check(is_equal_approx(Geometry.box_hit(Vector3(0,2.4,3),Vector3(0,-.4,-1),low,high,10),3.5),"Descending ray enters wall top after passing above its front face")
	check(Geometry.box_hit(Vector3(2,.2,3),Vector3.FORWARD,low,high,10)==INF,"Parallel ray outside wall is not a hit")
	check(Geometry.box_hit(Vector3(0,.5,0),Vector3.RIGHT,low,high,10)==0,"Ray starting inside volume returns zero")
	var foot=Geometry.capsule_hit(Vector3(0,.1,2),Vector3.FORWARD,Vector3(0,.1,-.2),Vector3(0,.1,.2),.14)
	check(absf(foot-1.66)<.0001,"Low ray hits boot capsule at correct depth")
	check(Geometry.capsule_hit(Vector3(.5,.1,2),Vector3.FORWARD,Vector3(0,.1,-.2),Vector3(0,.1,.2),.14)==INF,"Ray beside boot does not hit an invisible body cylinder")
	check(is_equal_approx(Geometry.capsule_hit(Vector3(0,3,0),Vector3.DOWN,Vector3.ZERO,Vector3.UP,.2),1.8),"Capsule axis-parallel ray hits cap")
	for sample in [0.0,.1,.5,.9,1.0]:
		var direction=Handling.shot_direction(Vector3.FORWARD,.02,1.2,sample)
		check(direction.is_finite() and direction.angle_to(Vector3.FORWARD)<=.02001,"Bounded finite dispersion sample "+str(sample))
	var catalog=Catalog.new();var w: Dictionary=catalog.weapons.m416
	var state={"aiming":true,"stance":0,"grounded":true,"velocity":Vector2.ZERO}
	Handling.tick(state,w,0)
	for shot in range(5):
		Handling.fired(state,w,state)
		for i in range(6):Handling.tick(state,w,1.0/60)
	check(state.recoil_target.y>Handling.profile(w).pitch*3,"Recoil persists and accumulates between automatic shots")
	var before: float=state.recoil_target.y;Handling.compensate(state,.01)
	check(state.recoil_target.y<before and state.recoil_target.y>=0,"Mouse compensation reduces climb without reversing pitch")
	for i in range(240):Handling.tick(state,w,1.0/60)
	check(state.kick_angle.length()<.00001 and state.bloom==0,"Recoil and bloom recover after firing stops")
	check(Handling.profile(catalog.weapons.akm).pitch>Handling.profile(w).pitch,"AKM and M416 have distinct recoil")
	check(Handling.profile(catalog.weapons.awm).scope and not Handling.profile(w).scope,"Scope eligibility distinguishes sniper and rifle")
	var parent=Node3D.new();root.add_child(parent)
	for weapon in catalog.weapons.values():
		var profile=Handling.profile(weapon)
		check(is_finite(profile.pitch) and is_finite(profile.ads),"Finite handling "+weapon.id)
		var node=Art.weapon(parent,weapon)
		check(node.has_node("MuzzleSocket") and node.scale.is_finite() and node.scale.x>0 and node.scale.z>0,"Weapon mesh and muzzle load "+weapon.id)
		node.free()
	parent.free()
	print("AIM_RESOURCE_CHECK ",count-failures.size(),"/",count," passed; weapons=",catalog.weapons.size()," failures=",failures)
	quit(0 if failures.is_empty() else 1)
