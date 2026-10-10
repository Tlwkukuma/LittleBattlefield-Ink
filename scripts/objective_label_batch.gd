extends MeshInstance3D
## One submission for the existing objective's glyphs and ink outline.
## Original Label3D remains the text/state owner; layout is rebuilt only on change.
var game
var source: Label3D
var stamp=""
var material=ShaderMaterial.new()
func _ready():
	name="ObjectiveLabelBatch";cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader=Shader.new()
	shader.code="shader_type spatial;render_mode unshaded,cull_disabled,depth_draw_never,depth_test_disabled;uniform sampler2D font_atlas : filter_linear,repeat_disable;void fragment(){ALBEDO=COLOR.rgb;ALPHA=COLOR.a*texture(font_atlas,UV).a;}"
	material.shader=shader;material_override=material
func _process(_delta: float):refresh()
func refresh():
	if not is_instance_valid(source) or game.hud_batches==null:return
	visible=source.is_visible_in_tree()
	if not visible:return
	global_transform=Transform3D(game.camera.global_basis,source.global_position)
	var signature=str(source.text,source.font_size,source.pixel_size,source.offset,source.modulate,source.outline_modulate,source.outline_size)
	if signature==stamp:return
	stamp=signature
	var atlas=game.hud_batches.atlas
	var vertices=PackedVector3Array();var colors=PackedColorArray();var uv=PackedVector2Array();var indices=PackedInt32Array()
	for outlined in [true,false]:
		var shaped=atlas.layout(source.text,source.font,source.font_size,-1,HORIZONTAL_ALIGNMENT_LEFT,false,source.outline_size if outlined else 0)
		var color: Color=source.outline_modulate if outlined else source.modulate
		if outlined:color.a*=source.modulate.a
		var middle=Vector2(shaped.width,shaped.height)*.5
		for item in shaped.items:
			var rect: Rect2=item.rect;var texture_rect: Rect2=item.uv;var base=vertices.size()
			for corner in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
				var point: Vector2=(rect.position+rect.size*corner-middle+source.offset)*source.pixel_size
				vertices.append(Vector3(point.x,-point.y,0))
				uv.append(texture_rect.position+texture_rect.size*corner);colors.append(color)
			indices.append_array(PackedInt32Array([base,base+1,base+2,base,base+2,base+3]))
	if vertices.is_empty():mesh=null;return
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
	var output=ArrayMesh.new();output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh=output
	atlas.upload();material.set_shader_parameter("font_atlas",atlas.texture)
