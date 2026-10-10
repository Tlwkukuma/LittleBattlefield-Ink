extends RefCounted
## Local-player readability only. The world, room membership and combat never change.
const Pose=preload("res://scripts/combat_pose.gd")
const SHADER=preload("res://shaders/player_occlusion.gdshader")
const INTERVAL=.10
const CLEAR_HOLD=.18
const FADE_IN=.12
const FADE_OUT=.22
const MAX_PROBES=3
var view: Dictionary={}
var copies: Array[MeshInstance3D]=[]
var material: ShaderMaterial
var marker: MeshInstance3D
var marker_material: ShaderMaterial
var wait=0.0
var clear_age=0.0
var blocked=false
var opacity=0.0
var last_query_us=0
var last_probe_count=0
var total_probes=0

func configure(actor: Dictionary,stage: Node3D) -> void:
	view=actor
	material=ShaderMaterial.new();material.shader=SHADER;material.render_priority=20
	# Share the source mesh, Skin and live Skeleton3D. In campaign mode source
	# layers are zero for crowd batching; these two local draws keep their own layer.
	for source in [view.model.find_child("Source_Body",true,false),view.helmet]:
		var copy=MeshInstance3D.new();copy.name="PlayerOcclusion"
		copy.mesh=source.mesh;copy.skin=source.skin;copy.material_override=material
		if source.skin==null and source.mesh.get_surface_count()>1:
			# All helmet surfaces use this same visibility material. Preserve their
			# exact vertices while submitting the rigid helmet only once.
			var merged=SurfaceTool.new();merged.begin(Mesh.PRIMITIVE_TRIANGLES)
			for surface in range(source.mesh.get_surface_count()):merged.append_from(source.mesh,surface,Transform3D.IDENTITY)
			copy.mesh=merged.commit()
		copy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.extra_cull_margin=1.5;copy.hide();source.add_child(copy)
		if source.skin!=null:copy.skeleton=copy.get_path_to(view.skeleton)
		copies.append(copy)
	marker=MeshInstance3D.new();marker.name="PlayerOcclusionFootprint"
	marker.mesh=ring_mesh();marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker_material=ShaderMaterial.new();marker_material.shader=SHADER;marker_material.render_priority=21
	marker_material.set_shader_parameter("foot_marker",true);marker.material_override=marker_material
	marker.hide();stage.add_child(marker)

static func ring_mesh() -> ArrayMesh:
	var vertices=PackedVector3Array();var normals=PackedVector3Array()
	for i in range(32):
		var a=Vector3(cos(TAU*i/32.0),0,sin(TAU*i/32.0))
		var b=Vector3(cos(TAU*(i+1)/32.0),0,sin(TAU*(i+1)/32.0))
		for p in [a*.43,a*.48,b*.48,a*.43,b*.48,b*.43]:vertices.append(p);normals.append(Vector3.UP)
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return mesh

static func camera_ray(camera: Camera3D,point: Vector3) -> Dictionary:
	var screen=camera.unproject_position(point)
	var origin=camera.project_ray_origin(screen);var direction=camera.project_ray_normal(screen)
	return {"origin":origin,"direction":direction,"distance":maxf(0,(point-origin).dot(direction)-.12)}

func query(world,camera: Camera3D,unit: Dictionary,render_offset: Vector3) -> bool:
	var started=Time.get_ticks_usec();last_probe_count=0
	# Three bounded, indexed queries at 10 Hz, stop as soon as any body part is
	# covered. A small radius catches partial shoulder/edge coverage; the GPU
	# still discards every actually visible fragment using this frame's depth.
	var points=[Pose.chest(unit),Pose.head(unit),Pose.base(unit)+Vector3.UP*.28]
	for point in points:
		var ray=camera_ray(camera,point+render_offset)
		last_probe_count+=1;total_probes+=1
		if not world.trace_3d(ray.origin,ray.direction,ray.distance,{"camera_pick":true,"radius":.16},true).is_empty():
			last_query_us=Time.get_ticks_usec()-started;return true
	last_query_us=Time.get_ticks_usec()-started;return false

func advance(delta: float,covered: bool) -> void:
	if covered:blocked=true;clear_age=0
	elif blocked:
		clear_age+=delta
		if clear_age>=CLEAR_HOLD:blocked=false
	opacity=move_toward(opacity,1.0 if blocked else 0.0,delta/(FADE_IN if blocked else FADE_OUT))

func reset() -> void:
	wait=0;clear_age=0;blocked=false;opacity=0;last_probe_count=0
	view.player_occluded=false
	for copy in copies:copy.hide()
	marker.hide()

func stats() -> Dictionary:
	var surfaces=1 if marker.is_visible_in_tree() else 0
	for copy in copies:
		if copy.is_visible_in_tree():surfaces+=copy.mesh.get_surface_count()
	return {"opacity":opacity,"blocked":blocked,"visible_extra_surfaces":surfaces,"last_query_us":last_query_us,"last_probe_count":last_probe_count,"total_probes":total_probes}

func refresh(game,delta: float) -> void:
	var unit: Dictionary=game.world.player
	if game.editing or not unit.alive or game.world.enclosed(unit) or not view.root.is_visible_in_tree():
		reset();return
	var root: Vector3=view.root.global_position
	if game.camera.is_position_behind(root) or not game.get_viewport().get_visible_rect().grow(60).has_point(game.camera.unproject_position(root)):
		reset();return
	# Presentation uses real time even while the equipment wheel slows simulation.
	var elapsed=minf(delta/maxf(.001,Engine.time_scale),.10)
	wait-=elapsed
	if wait<=0:
		wait=INTERVAL
		view.player_occluded=query(game.world,game.camera,unit,root-Pose.base(unit))
	advance(elapsed,bool(view.get("player_occluded",false)))
	var active=opacity>.001
	for copy in copies:copy.visible=active
	marker.visible=active
	if not active:return
	material.set_shader_parameter("visibility",opacity)
	marker_material.set_shader_parameter("visibility",opacity)
	# Existing shadow already follows the real supporting floor/stair and the
	# interpolated player root. No additional support query or flat y=0 marker.
	marker.global_position=view.shadow.global_position+Vector3.UP*.012
