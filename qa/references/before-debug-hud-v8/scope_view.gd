extends Control
## A circular HUD mask over one fixed-angle orthographic camera; absolute mouse aiming.
const Handling=preload("res://scripts/weapon_handling.gd")
const ReticleHUD=preload("res://scripts/reticle_hud.gd")
const MASK=preload("res://shaders/scope_mask.gdshader")
const VIEW_SCALES=[1.25,1.5,2.0,2.5]
var active=false
var latched=false
var wait_for_release=false
var scope_available=false
var follow_mouse=true
var weapon_id=""
var zoom_index=2
var view_scale=2.0
var view_ratio=1.0
var camera_offset=Vector3.ZERO
var anchor_relative=Vector3.ZERO
var anchor_screen=Vector3.ZERO
var settling=0.0
var distance=0.0
var mask_alpha=0.0
var lens_center=Vector2.ZERO
var lens_radius=260.0
var reticle_point=Vector2.ZERO
var reticle_gap=5.0
var reticle_color=Color.WHITE
var hit_time=0.0
var overlay: ColorRect
var mask_material: ShaderMaterial
var game

func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	# Keep the normal HUD and interactive panels above the mask.
	z_index=-1;visible=false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay=ColorRect.new();overlay.name="CircularScopeMask";overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;overlay.z_index=-1
	add_child(overlay);overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mask_material=ShaderMaterial.new();mask_material.shader=MASK;overlay.material=mask_material

static func hold_view_scale(p: Dictionary) -> float:
	match str(p.family):
		"pistol","smg":return 1.15
		"rifle","shotgun","heavy":return 1.25
		"launcher","launcher_low":return 1.18
	return 1.0

static func input_decision(held: bool,allowed: bool,scoped: bool,over_ui: bool,was_active: bool,latch: bool,wait_release: bool) -> Dictionary:
	if not held:wait_release=false
	# Holding through reload, a menu, or another interruption never reopens by itself.
	if not allowed:
		return {"active":false,"latched":false,"wait":held}
	if held:latch=false
	if not scoped:latch=false
	if held and over_ui and not was_active:wait_release=true
	return {"active":(latch or (held and not wait_release)) and (was_active or not over_ui),"latched":latch,"wait":wait_release}

func sync_input():
	var u: Dictionary=game.world.player;var p=Handling.profile(game.world.active_weapon())
	if weapon_id!=str(p.id):
		if not weapon_id.is_empty():cancel()
		weapon_id=str(p.id);latched=false;zoom_index=VIEW_SCALES.find(float(p.scope_zoom))
		if zoom_index<0:zoom_index=2
		scope_available=bool(p.scope)
		view_scale=VIEW_SCALES[zoom_index] if scope_available else hold_view_scale(p)
	var allowed=(scope_available or hold_view_scale(p)>1.0) and u.alive and u.mounted<0 and u.reload<=0 and u.vault.is_empty() and not game.editing and not game.paused and not game.armory.visible and not game.loot_open() and not game.has_text_focus()
	allowed=allowed and not game.wheel_open() and not preload("res://scripts/quick_equipment.gd").busy(u)
	var decision=input_decision(Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT),allowed,scope_available,game.over_ui(),active,latched,wait_for_release)
	if decision.active and not active:capture_anchor(get_viewport().get_mouse_position())
	active=decision.active;latched=decision.latched;wait_for_release=decision.wait

func toggle():
	if not Handling.profile(game.world.active_weapon()).scope:return
	if active:cancel()
	else:latched=true;sync_input()

func cancel():
	latched=false;active=false
	wait_for_release=Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

func change_view_scale(step: int):
	if not scope_available:return
	var next=clampi(zoom_index+step,0,VIEW_SCALES.size()-1)
	if next==zoom_index:return
	capture_anchor(get_viewport().get_mouse_position())
	zoom_index=next;view_scale=VIEW_SCALES[zoom_index]

func capture_anchor(mouse: Vector2):
	var camera: Camera3D=game.camera
	var ray_offset=camera.project_ray_origin(mouse)-camera.global_position
	var lateral=camera.global_basis.x*ray_offset.dot(camera.global_basis.x)+camera.global_basis.y*ray_offset.dot(camera.global_basis.y)
	anchor_relative=camera.global_position+lateral-game.camera_follow_position
	anchor_screen=lateral/camera.size

func apply_camera(delta: float,base_position: Vector3,base_size: float):
	var camera: Camera3D=game.camera
	var blend=1.0-exp(-delta*(14.0 if active else 18.0)) if delta>0 else 1.0
	# A larger orthographic size reveals MORE world. Right mouse expands the
	# battlefield, while the normal view stays at its fixed scene preset.
	var desired_ratio=maxf(1.0,view_scale) if active else 1.0
	view_ratio=lerpf(view_ratio,desired_ratio,blend)
	if absf(view_ratio-desired_ratio)<.00001:view_ratio=desired_ratio
	camera.size=base_size*view_ratio
	if active:
		# The camera anchor stays frozen; only the flat mask follows the mouse.
		camera_offset=anchor_relative-anchor_screen*camera.size
	else:
		camera_offset=camera_offset.lerp(Vector3.ZERO,blend)
		if camera_offset.length_squared()<.00000001:camera_offset=Vector3.ZERO
	camera.position=base_position+camera_offset
	# First reveal the wider field, then introduce the sniper circle. It must
	# not black out the surroundings at the instant right mouse is pressed.
	var expansion=clampf((view_ratio-1.0)/maxf(.001,desired_ratio-1.0),0,1)
	var target_alpha=smoothstep(.72,.96,expansion) if active and scope_available else 0.0
	mask_alpha=lerpf(mask_alpha,target_alpha,blend)
	if absf(mask_alpha-target_alpha)<.001:mask_alpha=target_alpha
	visible=active or mask_alpha>.001

func circular_active() -> bool:
	return active and scope_available and mask_alpha>.05

static func mask_layout(view_size: Vector2,mouse: Vector2,track_mouse: bool) -> Dictionary:
	return {"center":mouse if track_mouse else view_size*.5,"radius":clampf(minf(view_size.x,view_size.y)*.32,110.0,420.0)}

func refresh(_delta: float):
	if not visible:return
	var view_size=get_viewport_rect().size
	# Use the exact same mouse sample as the ordinary reticle this frame.
	var layout=mask_layout(view_size,game.crosshair.screen_point,follow_mouse)
	lens_center=layout.center;lens_radius=layout.radius
	reticle_point=lens_center
	mask_material.set_shader_parameter("viewport_size",view_size)
	mask_material.set_shader_parameter("lens_center",lens_center)
	mask_material.set_shader_parameter("lens_radius",lens_radius)
	mask_material.set_shader_parameter("opacity",mask_alpha)
	var state: Dictionary=game.world.active_state();var w: Dictionary=game.world.active_weapon();var p=Handling.profile(w)
	settling=clampf(float(state.get("aim_time",0))/maxf(.01,float(p.settle)),0,1)
	distance=game.crosshair.distance
	reticle_color=game.crosshair.ink;hit_time=game.crosshair.hit_time
	reticle_gap=ReticleHUD.radius_for("sniper",Handling.aim_spread(w,state,game.world.player))
	queue_redraw()

func fine_line(a: Vector2,b: Vector2,color: Color,width: float=1.0):
	draw_line(a,b,Color(.025,.035,.045,color.a*.75),width+2.0,true)
	draw_line(a,b,color,width,true)

func _draw():
	if not visible:return
	if mask_alpha>.01:
		var rim=Color(.11,.14,.17,mask_alpha)
		draw_arc(lens_center,lens_radius+3,0,TAU,128,rim,5.0,true)
		draw_arc(lens_center,lens_radius,0,TAU,128,Color(.72,.77,.78,mask_alpha*.60),1.0,true)
		# Scope and crosshair share the mouse center; collisions only affect bullets.
		if circular_active() and game.crosshair.visible:
			var color=Color(reticle_color,mask_alpha)
			for axis in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
				fine_line(reticle_point+axis*reticle_gap,reticle_point+axis*(reticle_gap+26),color,.9)
			draw_circle(reticle_point,1.5,color)
			if hit_time>0:
				for i in range(4):
					var axis=Vector2.from_angle(PI*.25+i*PI*.5)
					fine_line(reticle_point+axis*9,reticle_point+axis*15,Color("f3a398"),1.4)
