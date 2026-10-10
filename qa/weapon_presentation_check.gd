extends SceneTree
## Resource, geometry and pure scheduling checks only. No game input or world stepping.
const Catalog=preload("res://scripts/source_catalog.gd")
const Props=preload("res://scripts/proving_art.gd")
const Identity=preload("res://scripts/weapon_identity.gd")
const Profile=preload("res://scripts/weapon_profile.gd")
const Ammo=preload("res://scripts/ammo_presentation.gd")
const Effects=preload("res://scripts/weapon_effects.gd")
const Magazine=preload("res://scripts/weapon_magazine.gd")
const Ejection=preload("res://scripts/weapon_ejection.gd")
const Flight=preload("res://scripts/bullet_flight_visual.gd")
var failures=[]
var checks=0
func _initialize():run.call_deferred()
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func bounds(node: Node3D) -> AABB:
	var result=AABB();var first=true
	for child in node.get_children():
		if child is MeshInstance3D:
			result=child.mesh.get_aabb() if first else result.merge(child.mesh.get_aabb());first=false
	return result
func first_mesh(node: Node3D) -> Mesh:
	for child in node.get_children():
		if child is MeshInstance3D:return child.mesh
	return null
func winding(mesh: Mesh) -> float:
	var data=mesh.surface_get_arrays(0);var v: PackedVector3Array=data[Mesh.ARRAY_VERTEX];var n: PackedVector3Array=data[Mesh.ARRAY_NORMAL]
	var indices=data[Mesh.ARRAY_INDEX];var score=0.0
	var total=indices.size() if indices!=null and not indices.is_empty() else v.size()
	for i in range(0,total,3):
		var a=int(indices[i]) if indices!=null and not indices.is_empty() else i
		var b=int(indices[i+1]) if indices!=null and not indices.is_empty() else i+1
		var c=int(indices[i+2]) if indices!=null and not indices.is_empty() else i+2
		score+=(v[b]-v[a]).cross(v[c]-v[a]).dot(n[a]+n[b]+n[c])
	return score
func run():
	var catalog=Catalog.new();var parent=Node3D.new();root.add_child(parent)
	var snapshot=JSON.stringify(catalog.data)
	var sizes={};var triangle_max=0
	for w in catalog.weapons.values():
		var gun=Props.weapon(parent,w);var box=bounds(gun)
		check(box.size.is_finite() and box.size.length()>0 and gun.scale.is_finite(),"Finite gun bounds: "+w.id)
		check(gun.has_node("MuzzleSocket") and gun.has_node("MagazineSocket") and gun.has_node("EjectionSocket"),"Attachments: "+w.id)
		if Identity.LENGTHS.has(w.id):check(absf(box.size.z*gun.scale.z-float(Identity.LENGTHS[w.id]))<.001,"Actual total length: "+w.id)
		if w.kind in ["bullet","hitscan"]:
			check(gun.get_node("MuzzleSocket").position.z<=box.position.z+.025,"Muzzle remains at forward barrel tip: "+w.id)
			var vertices=0;var surfaces=0
			for child in gun.get_children():
				if child is MeshInstance3D:
					surfaces+=child.mesh.get_surface_count()
					for surface in range(child.mesh.get_surface_count()):vertices+=child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
			triangle_max=maxi(triangle_max,vertices/3)
			check(surfaces<=2,"Rigid detail batched: "+w.id)
			var p=Profile.get_profile(w);var a=Ammo.profile(w);sizes[w.id]=[]
			for zoom in [3.6,7.0,20.0,32.0]:
				var pixel=zoom/900.0;var casing=Ammo.case_scale(a,pixel)
				var data=Flight.geometry({"weapon":w,"origin":Vector2.ZERO,"start_height":1.0,"direction":Vector2.RIGHT,"speed":p.speed},Vector3(5,1,0),Basis.IDENTITY,pixel)
				var dim=Vector2(data.width*.5,data.length)
				check(dim.is_finite() and dim.x>0 and dim.y>0 and casing.is_finite(),"Finite displayed ammo: "+w.id+"/"+str(zoom))
				check(dim.x*2/pixel>=float(Flight.profile(w).width)-.001,"Readable flight core: "+w.id+"/"+str(zoom))
				if a.round_shape=="pellet":check(dim.y<dim.x*4 and dim.y<casing.z*.8,"Pellet stays compact, separate from casing: "+w.id+"/"+str(zoom))
				sizes[w.id].append([dim.x*2,dim.y,casing.z])
			var round_node=Effects.projectile(parent,w)
			check(round_node.get_node("VisibleBody").get_child_count()==1,"Legacy preview mesh remains available: "+w.id)
			var mesh=Effects.casing_mesh(a);var duplicate=Effects.casing_mesh(a)
			check(mesh==duplicate and mesh.get_surface_count()==1,"Cached single-surface casing: "+w.id)
			var retained=0;var emitted=0
			for cartridge in range(int(w.mag)):
				var plan=Ejection.shot(w,retained);retained=plan.retained;emitted+=plan.count
			emitted+=Ejection.reload_cases(w,retained)
			check(emitted==int(w.mag),"One casing per cartridge through reload: "+w.id)
			round_node.free()
		if Magazine.profile(w).detachable:
			var mag=Magazine.build(parent,w);var mag2=Magazine.build(parent,w)
			check(bounds(mag).size.length()>.05,"Nonempty feed geometry: "+w.id)
			check(first_mesh(mag)!=null and first_mesh(mag)==first_mesh(mag2),"Shared held/dropped magazine resource: "+w.id)
			mag.free();mag2.free()
		gun.free()
	check(sizes.p92[2][1]<sizes.m416[2][1] and sizes.m416[2][1]<sizes.awm[2][1],"Pistol/rifle/magnum visible length hierarchy")
	check(sizes.s1897[2][1]<sizes.o12[2][1]*.5,"Buckshot vs single O12 slug")
	check(Ammo.profile(catalog.weapons.s1897).case_color!=Ammo.profile(catalog.weapons.o12).case_color,"Buckshot and slug casing finish differs")
	check(Identity.pigment(catalog.weapons.m416,"metal",Color.WHITE)!=Identity.pigment(catalog.weapons["scar-l"],"metal",Color.WHITE),"SCAR and M416 have separate materials")
	check(Ejection.reload_cases(catalog.weapons.s1897,0)==0,"Pump reload does not invent already ejected cases")
	check(Ejection.reload_cases(catalog.weapons.dbs,1)==1,"Odd DBS cartridge retained until reload")
	var reference_winding=winding(CylinderMesh.new())
	for id in ["p92","m416","s1897","o12","awm"]:
		check(winding(Effects.casing_mesh(Ammo.profile(catalog.weapons[id])))*reference_winding>0,"Case faces use engine front-face winding: "+id)
		check(winding(Effects.round_mesh(Profile.get_profile(catalog.weapons[id])))*reference_winding>0,"Round faces use engine front-face winding: "+id)
	for vehicle in catalog.data.vehicles.values():
		for w in vehicle.get("weapons",{}).values():
			var profile=Profile.get_profile(w);var schedule=Ejection.shot(w,0)
			check(profile.ammo_visual.case_size.is_finite() and schedule.count>=0,"Vehicle weapons without item IDs remain compatible")
	check(JSON.stringify(catalog.data)==snapshot,"Original weapon data unchanged by presentation builders")
	parent.free()
	print("WEAPON_PRESENTATION_CHECK ",checks-failures.size(),"/",checks," passed; weapons=",catalog.weapons.size()," max rigid triangles=",triangle_max," failures=",failures)
	print("AMMO_REFERENCE_DIMENSIONS at 20m camera: ",{"p92":sizes.p92[2],"m416":sizes.m416[2],"awm":sizes.awm[2],"buckshot":sizes.s1897[2],"slug":sizes.o12[2]})
	quit(0 if failures.is_empty() else 1)
