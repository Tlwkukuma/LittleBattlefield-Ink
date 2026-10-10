extends SceneTree
## Pure cosmetic geometry/contact math with fixed fixtures, never game input/firing.
const Catalog=preload("res://scripts/source_catalog.gd")
const Ammo=preload("res://scripts/ammo_presentation.gd")
const Effects=preload("res://scripts/weapon_effects.gd")
const Profile=preload("res://scripts/weapon_profile.gd")
const Motion=preload("res://scripts/spent_case_motion.gd")
const Mounted=preload("res://scripts/mounted_cases.gd")
class TerrainFixture extends RefCounted:
	var floor_height=0.0
	var material="concrete"
	func height(_at: Vector2) -> float:return floor_height
	func material_at(_at: Vector2) -> String:return material
class ContactFixture extends RefCounted:
	var terrain=TerrainFixture.new()
	var wall=false
	var traces=0
	func ground_height(_at: Vector2,_radius: float,_below: float) -> float:return terrain.floor_height
	func trace_3d(_at: Vector3,_dir: Vector3,length: float,_options: Dictionary,_walls: bool) -> Dictionary:
		traces+=1
		return {"type":"object","distance":length*.5} if wall else {}
var failures=[]
var checks=0
func _initialize():run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func particle(parent: Node3D,a: Dictionary) -> Dictionary:
	var node=Effects.casing(parent,a);node.scale=Ammo.case_scale(a,20.0/900);node.position=Vector3(0,1,0);node.rotation=Vector3(.7,.4,.9)
	return {"node":node,"presentation":a,"velocity":Vector3(1.8,2.2,.35),"spin":Vector3(6,-4,5),"gravity":9.8}
func run():
	var catalog=Catalog.new();var parent=Node3D.new();root.add_child(parent)
	# Empty cases now retain cartridge proportions instead of every caliber
	# being inflated to an unrelated minimum screen width.
	var pistol=Ammo.profile(catalog.weapons.p92);var rifle=Ammo.profile(catalog.weapons.m416)
	var ak=Ammo.profile(catalog.weapons.akm);var long_rifle=Ammo.profile(catalog.weapons.m24)
	var magnum=Ammo.profile(catalog.weapons.awm);var shell=Ammo.profile(catalog.weapons.s1897)
	for zoom in [3.6,7.0,13.0,20.0,32.0,45.0]:
		var pixel=zoom/900.0;var r=Ammo.case_scale(rifle,pixel)
		check(Ammo.case_scale(pistol,pixel).z<r.z and r.z<Ammo.case_scale(magnum,pixel).z,"Pistol / rifle / magnum empty-case length hierarchy")
		check(Ammo.case_scale(ak,pixel).z<Ammo.case_scale(long_rifle,pixel).z,"Short and long 7.62 cases remain distinguishable")
		check(r.is_equal_approx(Ammo.case_scale(Ammo.profile(catalog.weapons["scar-l"]),pixel)),"Same 5.56 cartridge stays same size across guns")
		check(Ammo.case_scale(long_rifle,pixel).is_equal_approx(Ammo.case_scale(Mounted.profile("tank","mg"),pixel)),"Same full-size 7.62 case on handheld and mounted weapons")
		check(Ammo.case_scale(Ammo.profile(catalog.weapons["lynx-amr"]),pixel).is_equal_approx(Ammo.case_scale(Mounted.profile("hmg","primary"),pixel)),"Heavy MG and anti-material case share caliber size")
		check(Ammo.case_scale(shell,pixel).is_equal_approx(Ammo.case_scale(Ammo.profile(catalog.weapons.o12),pixel)),"Buckshot and slug use same empty shell, irrespective of pellet count")
		var old_rifle=Vector3(.05,.05,.19)*maxf(1,pixel*4.2/.05)
		check(r.x<old_rifle.x*.68 and r.z<old_rifle.z*.68,"Rifle cases visibly reduced at both close and far zoom")
		for a in [pistol,rifle,ak,long_rifle,magnum,shell]:
			var size=Ammo.case_scale(a,pixel)
			check(is_equal_approx(size.z/size.x,a.case_size.z/a.case_size.x) and size.x<=a.case_size.x*1.601,"Zoom preserves shape and caps enlargement")
	for id in ["p92","vector","m416","akm","s1897","o12","awm","lynx-amr"]:
		var a=Ammo.profile(catalog.weapons[id]);var profile=Profile.get_profile(catalog.weapons[id])
		check(Effects.round_material(a).emission_enabled and not Effects.outlined_material(Color.WHITE,true).emission_enabled,"Flight readable; empty case unlit: "+id)
		for view in [.05,.5,1.0]:
			var dimensions=Effects.visible_dimensions(profile,"bullet",20.0/900,view)
			check(dimensions.is_finite() and dimensions.y/(dimensions.x*2)<5.5,"Compact flight body at oblique view: "+id)
		var parent_mesh=Effects.casing_mesh(a)
		check(parent_mesh==Effects.casing_mesh(a),"Casing resources reused: "+id)
		for fps in [30,60,120]:
			var p=particle(parent,a);var fixture=ContactFixture.new();var motion=Motion.new();var sounds=0;var clearance=true
			for i in range(fps*5):
				motion.begin_frame();var impact=motion.advance(p,1.0/fps,fixture)
				if not impact.is_empty():sounds+=1
				clearance=clearance and p.node.position.y>=Motion.extent(p.node)-.001
			check(p.settled and absf(p.node.basis.z.normalized().y)<.01 and clearance,"Case settles on its side above floor: "+id+" / "+str(fps))
			check(sounds<=2 and p.bounces<=3,"Finite bounces/sound contacts: "+id+" / "+str(fps))
			var resting=p.node.position
			for i in range(12):motion.begin_frame();motion.advance(p,.016,fixture)
			check(p.node.position.distance_to(resting)<.0001,"Resting case does not jitter: "+id+" / "+str(fps))
			fixture.terrain.floor_height=-1.0
			for i in range(fps*3):motion.begin_frame();motion.advance(p,1.0/fps,fixture)
			check(p.settled and p.node.position.y<-.5,"Destroyed support lets resting cases fall: "+id+" / "+str(fps))
			p.node.free()
	var data=Ammo.profile(catalog.weapons.m416);var motion=Motion.new();var fixture=ContactFixture.new();fixture.wall=true
	var p=particle(parent,data);motion.begin_frame();motion.advance(p,.016,fixture)
	check(p.velocity.x<0 and p.node.position.x<.029,"Airborne case deflects at fixed wall contact")
	p.node.free();fixture.wall=false;fixture.traces=0;motion.begin_frame()
	for i in range(40):p=particle(parent,data);motion.advance(p,.016,fixture);p.node.free()
	check(fixture.traces==12,"Cosmetic wall queries obey per-frame budget")
	check(Motion.soften("snow")<Motion.soften("grass") and Motion.soften("grass")<Motion.soften("concrete"),"Soft surfaces damp bounce and contact sound")
	for mount in Mounted.TYPES:
		for mode in Mounted.TYPES[mount]:
			var a=Mounted.profile(mount,mode)
			if a.case_shape=="none":continue
			p=particle(parent,a);fixture=ContactFixture.new();motion=Motion.new()
			for i in range(300):motion.begin_frame();motion.advance(p,1.0/60,fixture)
			check(p.settled,"Mounted case remains compatible: "+mount+" / "+mode);p.node.free()
	parent.free()
	print("AMMO_EXPERIENCE_CHECK ",checks-failures.size(),"/",checks," passed; failures=",failures)
	quit(0 if failures.is_empty() else 1)
