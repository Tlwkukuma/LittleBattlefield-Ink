extends RefCounted
## Family tags occupy unused opaque vertex alpha, without adding material draws.
## Only Range 2 objects are tagged. Physics, HP and topology remain unchanged.
static func family(o: Dictionary) -> int:
	var id=str(o.component_id);var material=str(o.material)
	if id.begins_with("rock.") or material=="stone":return 1
	if "metal" in material or id in ["prop.container","prop.barrel","prop.road-light","prop.utility-pole"]:return 3
	if "wood" in material:return 4
	if material in ["fabric","sandbag","sand"] or o.kind=="sandbag":return 6
	if material in ["brick","concrete"] or id.begins_with("wall."):return 2
	return 0

static func tag_colors(colors: PackedColorArray,kind: int) -> PackedColorArray:
	var result=colors.duplicate()
	for i in range(result.size()):result[i].a=float(kind)/8.0
	return result

static func tag_mesh(source: Mesh,kind: int) -> ArrayMesh:
	var result=ArrayMesh.new()
	for i in range(source.get_surface_count()):
		var arrays=source.surface_get_arrays(i)
		if arrays[Mesh.ARRAY_COLOR]!=null:arrays[Mesh.ARRAY_COLOR]=tag_colors(arrays[Mesh.ARRAY_COLOR],kind)
		result.add_surface_from_arrays(source.surface_get_primitive_type(i),arrays)
	return result

static func tag_tree(root: Node,kind: int):
	for node in root.get_children():
		if node is MeshInstance3D and node.mesh!=null and node.material_override is ShaderMaterial:
			node.mesh=tag_mesh(node.mesh,kind)
		tag_tree(node,kind)
