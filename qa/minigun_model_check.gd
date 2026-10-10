extends SceneTree
## Geometry/resource contracts only; user performs all live playtesting.
const Catalog=preload("res://scripts/source_catalog.gd")
const Props=preload("res://scripts/proving_art.gd")
const Visual=preload("res://scripts/minigun_visual.gd")
const Profile=preload("res://scripts/weapon_profile.gd")
const Effects=preload("res://scripts/weapon_effects.gd")
const Icons=preload("res://scripts/weapon_icon.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func run():
	var catalog=Catalog.new();var parent=Node3D.new();root.add_child(parent)
	var w: Dictionary=catalog.weapons.minigun;var original=JSON.stringify(w)
	var gun=Props.weapon(parent,w);var copy=Props.weapon(parent,w)
	var meshes=[];var vertices=0;var box=AABB();var first=true
	for node in gun.get_children():
		if not node is MeshInstance3D:continue
		meshes.append(node);box=node.mesh.get_aabb() if first else box.merge(node.mesh.get_aabb());first=false
		for s in range(node.mesh.get_surface_count()):vertices+=node.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
	check(meshes.size()==2,"One stationary body plus one shared rotor mesh")
	check(vertices<14000,"Minigun stays within existing weapon batch geometry budget")
	check(gun.get_child_count()==6,"No leftover per-detail scene nodes")
	check(is_equal_approx(box.size.z*gun.scale.z,1.32),"Final length remains 1.32 m")
	check(gun.scale.is_equal_approx(Vector3.ONE*gun.scale.z),"Barrel cluster stays round")
	check(box.size.x*gun.scale.x>.40 and box.size.x*gun.scale.x<.65,"Motor and ammunition box preserve broad silhouette")
	check(gun.get_node("BarrelRotor").mesh==copy.get_node("BarrelRotor").mesh,"Copies share rotor geometry")
	check(gun.get_node("MuzzleSocket").position.z<box.position.z,"Muzzle is in front of metal, not buried in body")
	var p=Profile.get_profile(w);var feed=preload("res://scripts/weapon_magazine.gd").profile(w)
	check(p.grip.distance_to(p.support)<.68,"Both hand contacts remain within a plausible arm span")
	check(p.grip==Visual.GRIP and p.support==Visual.SUPPORT,"Rig targets match the modeled handles")
	check(gun.get_node("MagazineSocket").position==feed.at,"Dropping feed box uses its actual attachment")
	check(feed.at.x<-.20 and feed.size.x>.14,"Side feed box remains distinct from rifle magazines")
	check(not preload("res://scripts/weapon_handling.gd").profile(w).bipod,"No bonus from an invisible rifle bipod")
	var rotor=gun.get_node("BarrelRotor");var muzzle: Vector3=gun.get_node("MuzzleSocket").position
	for shot in range(12):
		var state={"shot_index":shot,"last_shot":2.0}
		Visual.pose(gun,state,2.0)
		var nearest=INF
		for i in range(6):
			var angle=PI*.5+i*TAU/6;var at=rotor.basis*Vector3(cos(angle)*Visual.RADIUS,sin(angle)*Visual.RADIUS,0)
			nearest=minf(nearest,Vector2(at.x-muzzle.x,at.y-muzzle.y).length())
		check(nearest<.0001,"Real bore aligns with firing socket at shot "+str(shot))
		Visual.pose(gun,state,2.025);check(rotor.rotation.is_finite(),"Rotation interpolation stays finite")
	Visual.pose(gun,{"shot_index":2,"last_shot":2.0},3.0)
	var stopped=rotor.transform;Visual.pose(gun,{"shot_index":2,"last_shot":2.0},4.0)
	check(stopped.is_equal_approx(rotor.transform),"Rotor stops after firing")
	check(copy.get_node("BarrelRotor").rotation==Vector3.ZERO,"Rotating one soldier does not rotate shared instances")
	var socket=gun.get_node("MuzzleSocket");socket.scale=Vector3.ONE/gun.scale
	var flash=Effects.flash(socket,w)
	check(flash.get_child_count()==2,"Compact core and jet without off-axis rifle spurs")
	check(p.flash_time<60.0/float(w.rpm),"Flash ends before the next shot")
	var fixture={"held":gun,"muzzle":flash}
	# Exercise the actual socket parent/scale compensation used by replace_weapon.
	for angles in [Vector3.ZERO,Vector3(.6,1.2,0),Vector3(-.6,-2.4,.12)]:
		gun.rotation=angles;gun.position=Vector3(2,-.6,4)
		for shot in range(1,7):
			for age in [0.0,.008,.016,.024,.050]:
				var state={"shot_index":shot,"last_shot":2.0}
				Visual.pose(gun,state,2.0+age);Visual.align_flash(fixture,state)
				var local=rotor.to_local(flash.global_position);var nearest=INF
				for i in range(6):
					var a=PI*.5+i*TAU/6;var tip=Vector3(cos(a)*Visual.RADIUS,sin(a)*Visual.RADIUS,Visual.FRONT-.004)
					nearest=minf(nearest,local.distance_to(tip))
				check(nearest<.0001,"Flash stays on a real bore between shots, including pitched gun")
				if age==0:check(flash.global_position.distance_to(socket.global_position)<.0001,"Physical bullet and flash share emission position at shot time")
	gun.rotation=Vector3.ZERO;gun.position=Vector3.ZERO
	var atlas=load("res://assets/original/weapon_atlas.png")
	var icon=Icons.get_texture(w,atlas,catalog.atlas.frames)
	check(icon!=null and icon.get_width()==256 and icon.get_height()==128,"Native-model inventory icon imported")
	check(icon==Icons.get_texture(w,atlas,catalog.atlas.frames),"All UI surfaces reuse the same icon")
	check(Icons.get_texture(catalog.weapons.m416,atlas,catalog.atlas.frames) is AtlasTexture,"Other weapon icons keep original atlas")
	check(JSON.stringify(w)==original,"Original damage, RPM, ammunition and sound metadata preserved")
	parent.free()
	print("MINIGUN_MODEL_CHECK ",checks-failures.size(),"/",checks," passed; triangles=",vertices/3,"; failures=",failures)
	quit(0 if failures.is_empty() else 1)
