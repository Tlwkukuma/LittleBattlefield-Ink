extends SceneTree
func _initialize():
	for method in ClassDB.class_get_method_list("ImporterMesh"):
		if "lod" in method.name or "surface" in method.name:print("METHOD ",method)
	var scene=load("res://assets/tripo_source/source-rig-soldier.glb").instantiate()
	for node in scene.find_children("*","MeshInstance3D",true,false):
		var a=node.mesh.surface_get_arrays(0);print("SOURCE ",node.name," ",a[Mesh.ARRAY_VERTEX].size()," vertices ",a[Mesh.ARRAY_INDEX].size()/3," triangles")
	scene.free();quit()
