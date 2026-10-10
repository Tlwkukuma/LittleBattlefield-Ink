extends Node3D
## Bake fixed whole props by 16 m sector. Gameplay objects stay independent.
## Cell-damaged walls and floor-cutaway furniture keep their own live renderers.
const INK=preload("res://shaders/ink_surface.gdshader")
var cell_size=16.0
var sectors: Dictionary={}
var members: Dictionary={}
var dirty: Dictionary={}
var source_surfaces=0

func configure(objects: Array,views: Dictionary):
	for object in objects:
		if not object.whole or object.has("house_role") or not views.has(object.id):continue
		var view: Dictionary=views[object.id]
		if view.mesh!=null:continue
		var parts=[];var accepted=true
		for child in view.root.get_children():
			if not child is MeshInstance3D or not child.visible:continue
			var material=child.material_override
			if child.skin!=null or not material is ShaderMaterial or material.shader!=INK or material.next_pass!=null:accepted=false;break
			if material.get_shader_parameter("garment") not in [null,0] or material.get_shader_parameter("cutaway_opacity") not in [null,1.0]:accepted=false;break
			var uniforms=[]
			for uniform in material.shader.get_shader_uniform_list():uniforms.append(material.get_shader_parameter(uniform.name))
			for surface in range(child.mesh.get_surface_count()):
				var primitive=child.mesh.surface_get_primitive_type(surface)
				if primitive not in [Mesh.PRIMITIVE_TRIANGLES,Mesh.PRIMITIVE_LINES]:accepted=false;break
				parts.append({"source":child,"mesh":child.mesh,"surface":surface,"pose":global_transform.affine_inverse()*child.global_transform,"material":material,"primitive":primitive,"key":str(primitive)+var_to_str(uniforms)})
		if not accepted or parts.is_empty():continue
		var cell=Vector2i(floori(object.position.x/cell_size),floori(object.position.y/cell_size))
		if not sectors.has(cell):sectors[cell]={"members":[],"nodes":{},"builds":0}
		members[object.id]={"cell":cell,"parts":parts,"alive":object.alive};sectors[cell].members.append(object.id)
		for part in parts:part.source.hide()
		source_surfaces+=parts.size();dirty[cell]=true
	flush()

func changed(object: Dictionary):
	if not members.has(object.id):return
	var member: Dictionary=members[object.id]
	if member.alive==object.alive:return
	member.alive=object.alive;dirty[member.cell]=true

func flush():
	for cell in dirty:
		var sector: Dictionary=sectors[cell];var surfaces={}
		for id in sector.members:
			var member: Dictionary=members[id]
			if not member.alive:continue
			for part in member.parts:
				if not surfaces.has(part.key):
					var builder=SurfaceTool.new();builder.begin(part.primitive)
					surfaces[part.key]={"builder":builder,"material":part.material}
				surfaces[part.key].builder.append_from(part.mesh,part.surface,part.pose)
		for key in sector.nodes.keys():
			if not surfaces.has(key):sector.nodes[key].queue_free();sector.nodes.erase(key)
		for key in surfaces:
			if not sector.nodes.has(key):
				var node=MeshInstance3D.new();node.name="BakedPropSector";add_child(node);sector.nodes[key]=node
			sector.nodes[key].mesh=surfaces[key].builder.commit()
			sector.nodes[key].material_override=surfaces[key].material
		sector.builds+=1
	dirty.clear()

func stats() -> Dictionary:
	var surfaces=0;var builds=0
	for sector in sectors.values():surfaces+=sector.nodes.size();builds+=sector.builds
	return {"props":members.size(),"sectors":sectors.size(),"source_surfaces":source_surfaces,"baked_surfaces":surfaces,"sector_builds":builds}
