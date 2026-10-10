extends MeshInstance3D
## One depth-tested billboard mesh for all existing damage labels, including ink.
var game
var material=ShaderMaterial.new()
func _ready():
	name="DamageNumberBatch";cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader=Shader.new();shader.code="shader_type spatial;render_mode unshaded,cull_disabled,depth_draw_never;uniform sampler2D font_atlas : filter_linear,repeat_disable;void fragment(){ALBEDO=COLOR.rgb;ALPHA=COLOR.a*texture(font_atlas,UV).a;}"
	material.shader=shader;material_override=material
func _process(_delta: float):refresh()
func refresh():
	visible=not game.damage_labels.is_empty()
	if not visible:return
	var atlas=game.hud_batches.atlas;var vertices=PackedVector3Array();var colors=PackedColorArray();var uv=PackedVector2Array();var indices=PackedInt32Array()
	var camera_basis: Basis=game.camera.global_basis
	for outlined in [true,false]:
		for entry in game.damage_labels:
			var source: Label3D=entry.node
			var font: Font=source.font if source.font!=null else ThemeDB.fallback_font
			var shaped=atlas.layout(source.text,font,source.font_size,-1,HORIZONTAL_ALIGNMENT_LEFT,false,source.outline_size if outlined else 0)
			var color=source.outline_modulate if outlined else source.modulate
			if outlined:color.a*=source.modulate.a
			var middle=Vector2(shaped.width*.5,shaped.height*.5)
			for item in shaped.items:
				var rect: Rect2=item.rect;var texture_rect: Rect2=item.uv;var base=vertices.size()
				for corner in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
					var point=(rect.position+rect.size*corner-middle+source.offset)*source.pixel_size
					vertices.append(source.global_position+camera_basis.x*point.x-camera_basis.y*point.y)
					uv.append(texture_rect.position+texture_rect.size*corner);colors.append(color)
				indices.append_array(PackedInt32Array([base,base+1,base+2,base,base+2,base+3]))
	if vertices.is_empty():visible=false;return
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
	var output=ArrayMesh.new();output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh=output;atlas.upload();material.set_shader_parameter("font_atlas",atlas.texture)
