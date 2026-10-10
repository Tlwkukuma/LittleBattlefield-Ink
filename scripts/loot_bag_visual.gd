extends MultiMeshInstance3D
## One shared mesh/material and one batch for all ground bags; no rigid bodies.
const Bags=preload("res://scripts/loot_bags.gd")
static var shared_mesh: ArrayMesh
var world
var revision=-1

static func append_shape(tool: SurfaceTool,mesh: PrimitiveMesh,at: Vector3,scale: Vector3,color: Color):
	var arrays=mesh.get_mesh_arrays();var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL];var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		tool.set_color(color);tool.set_normal((normals[index]/scale).normalized());tool.add_vertex(points[index]*scale+at)

static func mesh_resource() -> ArrayMesh:
	if shared_mesh!=null:return shared_mesh
	var tool=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rounded=SphereMesh.new();rounded.radial_segments=12;rounded.rings=5;rounded.radius=.5;rounded.height=1.0
	var cube=BoxMesh.new();cube.size=Vector3.ONE
	append_shape(tool,rounded,Vector3(0,.16,0),Vector3(.56,.30,.68),Color("7e8061"))
	append_shape(tool,rounded,Vector3(0,.27,-.15),Vector3(.48,.13,.32),Color("959779"))
	append_shape(tool,rounded,Vector3(0,.12,.28),Vector3(.40,.20,.17),Color("72775b"))
	for side in [-1,1]:
		append_shape(tool,cube,Vector3(side*.15,.29,.01),Vector3(.048,.025,.46),Color("46454a"))
		append_shape(tool,cube,Vector3(side*.15,.305,.12),Vector3(.067,.017,.055),Color("a9a99c"))
	append_shape(tool,cube,Vector3(0,.25,-.35),Vector3(.18,.045,.045),Color("46454a"))
	shared_mesh=tool.commit();return shared_mesh

func _ready():
	name="GroundLootBags";cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material=StandardMaterial3D.new();material.vertex_color_use_as_albedo=true;material.roughness=1.0
	material_override=material
	multimesh=MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_3D;multimesh.mesh=mesh_resource();multimesh.instance_count=Bags.LIMIT;multimesh.visible_instance_count=0

func refresh():
	if world==null or revision==world.loot.revision:return
	revision=world.loot.revision;var bags: Array=world.loot.bags
	multimesh.visible_instance_count=bags.size()
	for i in range(bags.size()):
		var bag: Dictionary=bags[i]
		multimesh.set_instance_transform(i,Transform3D(Basis(Vector3.UP,bag.angle),Vector3(bag.position.x,bag.elevation+.015,bag.position.y)))
