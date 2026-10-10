extends SceneTree
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():run.call_deferred()
func run():
	var zero=Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO)
	for kind in ["palette","rigid"]:
		var stage=Node3D.new();root.add_child(stage)
		var source=MeshInstance3D.new();source.mesh=BoxMesh.new();source.material_override=preload("res://scripts/ink_art.gd").ink_material(Color.WHITE);source.position=Vector3(2,1,3);stage.add_child(source)
		var batch=load("res://scripts/"+kind+"_"+("mesh_" if kind=="palette" else "")+"batches.gd").new();stage.add_child(batch);batch.process_mode=Node.PROCESS_MODE_DISABLED
		if kind=="palette":batch.configure([source])
		else:batch.register_tree(source)
		batch.refresh();check(batch.active_groups==1,kind+" original source visible")
		stage.remove_child(source);batch.refresh()
		check(batch.active_groups==0,kind+" detached source no longer draws")
		var pose: Transform3D=batch.entries[0].pose if kind=="palette" else batch.entries[source.get_instance_id()].handles[0].pose
		check(pose==zero,kind+" detached source collapses instead of falling back to identity at world origin")
		stage.add_child(source);batch.refresh();check(batch.active_groups==1,kind+" reattached source restores drawing")
		source.free();batch.refresh();check(batch.active_groups==0,kind+" freed source releases its drawing")
		stage.free()
	print("RENDER_BATCH_LIFECYCLE checks=",checks," failures=",failures);quit(0 if failures==0 else 1)
