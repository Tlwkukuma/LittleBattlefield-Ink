extends RefCounted
## Low-poly attached signage is collapsed into the existing prop geometry once.
## It hides/dies with its owning object, including the panel's actual collision body.
const Art=preload("res://scripts/ink_art.gd")
static var sign_mesh: TextMesh
static func decorate(root: Node3D,o: Dictionary):
	if o.component_id!="prop.container":return
	var w: float=o.size.x;var d: float=o.size.y;var h: float=o.height
	var ink=Color("303b3f");var paint=Color("c4ad70")
	for side in [-1,1]:
		Art.box(root,Vector3(0,h*.69,side*(d*.5+.05)),Vector3(w*.62,.67,.028),ink)
		Art.box(root,Vector3(0,h*.69-.26,side*(d*.5+.07)),Vector3(w*.59,.025,.012),paint)
		for i in range(6):Art.box(root,Vector3(-w*.4+i*.15,.22,side*(d*.5+.06)),Vector3(.075,.21,.015),paint if i%2==0 else ink)
		if sign_mesh==null:
			sign_mesh=TextMesh.new();sign_mesh.text="DEPOT / 02";sign_mesh.font_size=64;sign_mesh.pixel_size=.007;sign_mesh.depth=.004
		var sign=Art.mesh_node(root,sign_mesh,Vector3(0,h*.69+.02,side*(d*.5+.075)),paint)
		if side<0:sign.rotation.y=PI
