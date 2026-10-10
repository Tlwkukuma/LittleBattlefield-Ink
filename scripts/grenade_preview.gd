extends Node3D
const Ballistics=preload("res://scripts/grenade_ballistics.gd")
var game
var mesh=ImmediateMesh.new()
var readout=""
var refresh_age=0.0
var material=StandardMaterial3D.new()

func _ready():
	var mesh_view=MeshInstance3D.new();mesh_view.mesh=mesh;mesh_view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(mesh_view)
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.vertex_color_use_as_albedo=true
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.no_depth_test=false;hide()

func segment(a: Vector3,b: Vector3,width: float,color: Color):
	var direction=b-a
	if direction.length_squared()<.000001:return
	var side=direction.cross(game.camera.global_basis.z).normalized()*width
	mesh.surface_set_color(color)
	for point in [a-side,a+side,b+side,a-side,b+side,b-side]:mesh.surface_add_vertex(point)

func ring(at: Vector3,normal: Vector3,radius: float,width: float,color: Color,dashed: bool=false):
	var right=normal.cross(Vector3.RIGHT if absf(normal.x)<.85 else Vector3.FORWARD).normalized()
	var forward=normal.cross(right).normalized()
	for i in range(40):
		if dashed and i%2==1:continue
		var a=TAU*float(i)/40;var b=TAU*float(i+1)/40
		segment(at+(right*cos(a)+forward*sin(a))*radius,at+(right*cos(b)+forward*sin(b))*radius,width,color)

func refresh(delta: float):
	var u: Dictionary=game.world.player;var w: Dictionary=game.world.active_weapon();var state: Dictionary=u.get("throw_state",{})
	var allowed=w.kind=="grenade" and u.mounted<0 and u.alive and not game.paused and not game.editing and not game.armory.visible and not game.over_ui() and not game.has_text_focus() and game.get_window().has_focus()
	allowed=allowed and not game.wheel_open() and not game.loot_open() and not preload("res://scripts/quick_equipment.gd").busy(u)
	visible=allowed and not state.is_empty() and state.phase in ["aim","windup"] and u.ammo>0
	if not visible:
		refresh_age=0.0
		readout="";return
	refresh_age-=delta
	if refresh_age>0:return
	refresh_age=1.0/15.0
	var origin: Vector3=game.actors[u.id].held.global_position
	if game.actors[u.id].get("source_rig",false):origin=preload("res://scripts/source_rig_motion.gd").grenade_release_origin(game.actors[u.id],u,bool(state.low))
	var solution=game.world.grenade_solution(u,w,state.target,state.low,origin)
	var path=Ballistics.preview(game.world,solution)
	# Diagnostics remain available to Debug, without a permanent text overlay.
	readout="%s %.1f m/s %.1f m"%["低抛" if solution.low else "上抛",solution.speed,solution.distance]
	mesh.clear_surfaces();mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,material)
	var width=clampf(game.camera.size/game.get_viewport().get_visible_rect().size.y*.75,.009,.035)
	var points: PackedVector3Array=path.points
	for i in range(1,points.size()):segment(points[i-1],points[i],width,Color(.96,.92,.78,.83))
	var marker: Vector3=path.point+path.normal*.012
	ring(marker,path.normal,.25,width*1.25,Color(.97,.94,.80,.9))
	# Only mark first contact. A damage-radius ring here implied a guaranteed
	# detonation point even though the grenade still bounces and rolls afterwards.
	mesh.surface_end()
