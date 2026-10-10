extends Node2D
## Persistent per-label glyph slots. A counter change uploads only its own quads.
const CAPACITY=4096
var instances=MultiMesh.new()
var free_slots: Array[int]=[]
var atlas: Texture2D
var writes=0
func _ready():
	instances.transform_format=MultiMesh.TRANSFORM_2D;instances.use_colors=true;instances.use_custom_data=true
	# Explicit canvas Y-down coordinates; a spatial QuadMesh would invert UV.y.
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector2Array([Vector2(-.5,-.5),Vector2(.5,-.5),Vector2(.5,.5),Vector2(-.5,.5)])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3])
	var quad=ArrayMesh.new();quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	instances.mesh=quad;instances.instance_count=CAPACITY
	var hidden=Transform2D(Vector2.ZERO,Vector2.ZERO,Vector2.ZERO)
	for i in range(CAPACITY-1,-1,-1):instances.set_instance_transform_2d(i,hidden);free_slots.append(i)
	var shader=Shader.new();shader.code="shader_type canvas_item;void vertex(){UV=INSTANCE_CUSTOM.xy+UV*INSTANCE_CUSTOM.zw;}"
	var ink=ShaderMaterial.new();ink.shader=shader;material=ink
func update_item(item: Dictionary,geometry):
	var count: int=geometry.vertices.size()/4
	if not item.has("glyph_slots"):item.glyph_slots=[]
	var slots: Array=item.glyph_slots
	while slots.size()>count:
		var index: int=slots.pop_back();instances.set_instance_transform_2d(index,Transform2D(Vector2.ZERO,Vector2.ZERO,Vector2.ZERO));free_slots.append(index)
	while slots.size()<count:
		assert(not free_slots.is_empty(),"HUD glyph pool exhausted")
		if free_slots.is_empty():return
		slots.append(free_slots.pop_back())
	for i in range(count):
		var index: int=slots[i];var base: int=i*4
		var a: Vector2=geometry.vertices[base];var b: Vector2=geometry.vertices[base+2];var size: Vector2=b-a
		var uv: Vector2=geometry.uvs[base];var uv_size: Vector2=geometry.uvs[base+2]-uv
		instances.set_instance_transform_2d(index,Transform2D(Vector2(size.x,0),Vector2(0,size.y),(a+b)*.5))
		instances.set_instance_color(index,geometry.colors[base]);instances.set_instance_custom_data(index,Color(uv.x,uv.y,uv_size.x,uv_size.y));writes+=1
func clear_item(item: Dictionary):
	for index in item.get("glyph_slots",[]):
		instances.set_instance_transform_2d(index,Transform2D(Vector2.ZERO,Vector2.ZERO,Vector2.ZERO));free_slots.append(index)
	item.glyph_slots=[];item.text_stamp=""
func _draw():
	if atlas!=null:draw_multimesh(instances,atlas)
