extends SceneTree
const Pool=preload("res://scripts/fx_instance_batches.gd")
const Effects=preload("res://scripts/weapon_effects.gd")
const Ammo=preload("res://scripts/ammo_presentation.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;printerr(label)
func _initialize():call_deferred("run")
func run():
	var pool=Pool.new();root.add_child(pool);var catalog=Catalog.new();var handles=[]
	for key in ["m416","akm","s1897","o12","ump-45","awm"]:
		var mesh=Effects.casing_mesh(Ammo.profile(catalog.weapons[key]));var arrays=mesh.surface_get_arrays(0)
		var handle=pool.add_case(mesh,Effects.outlined_material(Color.WHITE,true),Transform3D.IDENTITY);handles.append(handle)
		var custom: Color=handle.custom;var base=int(custom.r)+int(custom.g)*512
		check(int(custom.b)==arrays[Mesh.ARRAY_VERTEX].size(),"unchanged caliber geometry size "+key)
		check(custom.r<512 and custom.g<256 and custom.b<=1020,"half-float-safe shader address "+key)
		for i in range(0,arrays[Mesh.ARRAY_VERTEX].size(),11):
			var pixel=base+i*3;var sample=pool.case_image.get_pixel(pixel%512,int(pixel/512))
			check(Vector3(sample.r,sample.g,sample.b).distance_to(arrays[Mesh.ARRAY_VERTEX][i])<.000001,"exact original case vertex "+key)
	check(pool.stats().batches==1 and pool.stats().surface_passes==2,"all case types share one mesh and original outline pass")
	pool.release([handles[1]])
	check(handles[-1].slot==1 and int(handles[-1].custom.b)>0,"compaction preserves geometry selection")
	print("FX_ATLAS checks=%d failures=%d"%[checks,failures]);pool.free();quit(0 if failures==0 else 1)
