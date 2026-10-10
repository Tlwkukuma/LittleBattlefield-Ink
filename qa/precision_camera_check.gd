extends SceneTree
## Real Camera3D projection checks only; no gameplay, screenshots or player input.
const Scope=preload("res://scripts/scope_view.gd")
const Handling=preload("res://scripts/weapon_handling.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
class CameraContext extends RefCounted:
	var camera: Camera3D
	var camera_follow_position=Vector3(0,48,48)
var failures: Array=[]
var count=0
func _initialize():run.call_deferred()
func check(value: bool,label: String):
	count+=1
	if not value:failures.append(label);push_error(label)
func run():
	var viewport=SubViewport.new();viewport.size=Vector2i(1440,900);viewport.own_world_3d=true;root.add_child(viewport)
	var context=CameraContext.new();var camera=Camera3D.new();context.camera=camera;viewport.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20;camera.position=context.camera_follow_position;camera.look_at(Vector3.ZERO)
	var orientation=camera.basis
	var scope=Scope.new();scope.game=context;viewport.add_child(scope)
	check(scope.get_child_count()==1 and scope.get_child(0) is ColorRect,"Scope adds only a flat mask, without another world camera")
	for resolution in [Vector2i(1440,900),Vector2i(1920,1080)]:
		viewport.size=resolution
		for uv in [Vector2(.5,.5),Vector2(.18,.28),Vector2(.81,.66)]:
			camera.size=20;camera.position=context.camera_follow_position
			scope.view_ratio=1;scope.camera_offset=Vector3.ZERO;scope.active=true;scope.view_scale=2
			var mouse=Vector2(resolution)*uv
			var origin=camera.project_ray_origin(mouse);var direction=camera.project_ray_normal(mouse)
			var targets=[origin+direction*8,origin+direction*65,origin+direction*100]
			scope.capture_anchor(mouse)
			var max_error=0.0
			var monotonic=true;var previous_size=camera.size
			for frame in range(50):
				scope.apply_camera(1.0/60,context.camera_follow_position,20)
				monotonic=monotonic and camera.size>=previous_size and camera.size>=20;previous_size=camera.size
				for target in targets:max_error=maxf(max_error,camera.unproject_position(target).distance_to(mouse))
			check(monotonic and absf(camera.size-40)<.001,"Right hold expands visible world without a zoom-in frame")
			check(max_error<.02,"Same pixel across zoom at several world depths: "+str(resolution)+" "+str(uv)+" error="+str(max_error))
			check(camera.basis.is_equal_approx(orientation),"Zoom preserves camera pitch and yaw")
	# Change viewing range around a new cursor position while still expanding.
	camera.position=context.camera_follow_position;camera.size=20
	scope.view_ratio=1;scope.active=true;scope.view_scale=2
	scope.capture_anchor(Vector2(700,350));scope.apply_camera(.025,context.camera_follow_position,20)
	var cursor=Vector2(1230,620)
	var anchor=camera.project_ray_origin(cursor)+camera.project_ray_normal(cursor)*60
	scope.capture_anchor(cursor);scope.view_scale=2.5
	var max_error=0.0
	for frame in range(80):
		scope.apply_camera(1.0/60,context.camera_follow_position,20)
		max_error=maxf(max_error,camera.unproject_position(anchor).distance_to(cursor))
	check(max_error<.02,"Changing zoom mid-transition preserves the new anchor")
	check(absf(camera.size-50)<.001,"2.5x viewing range reveals more battlefield")
	var travel=Vector3(3,0,-2)
	context.camera_follow_position+=travel
	scope.apply_camera(1.0/60,context.camera_follow_position,20)
	check(camera.unproject_position(anchor+travel).distance_to(cursor)<.02,"Player following translates the zoomed view once without offset feedback")
	scope.active=false
	for frame in range(100):scope.apply_camera(1.0/60,context.camera_follow_position,20)
	check(absf(camera.size-20)<.001 and camera.position.distance_to(context.camera_follow_position)<.001,"Exit restores the original field of view and camera following")
	# Reopening during recovery must start from the visible camera, not its old anchor.
	scope.active=true;scope.view_scale=2;scope.capture_anchor(cursor)
	for frame in range(20):scope.apply_camera(1.0/60,context.camera_follow_position,20)
	scope.active=false;scope.apply_camera(.04,context.camera_follow_position,20)
	anchor=camera.project_ray_origin(cursor)+camera.project_ray_normal(cursor)*60
	scope.active=true;scope.capture_anchor(cursor)
	for frame in range(30):scope.apply_camera(1.0/60,context.camera_follow_position,20)
	check(camera.unproject_position(anchor).distance_to(cursor)<.02,"Rapid reopening does not jump the selected target")
	for frame in range(100):scope.apply_camera(1.0/60,context.camera_follow_position,5)
	check(absf(camera.size-10)<.001,"Inspection close-up also expands on right hold")
	var catalog=Catalog.new()
	check(is_equal_approx(Handling.profile(catalog.weapons.awm).scope_zoom,2.0),"AWM starts with the unified 2x view")
	for w in catalog.weapons.values():
		if Handling.profile(w).scope:check(Scope.VIEW_SCALES.has(Handling.profile(w).scope_zoom),"Supported precision view range for "+str(w.id))
	# Pure input decisions: no Input events are injected into a game or the OS.
	var press=Scope.input_decision(true,true,true,false,false,false,false)
	check(press.active and not press.latched,"Holding right mouse enters momentary scope")
	var release=Scope.input_decision(false,true,true,false,true,false,false)
	check(not release.active,"Releasing right mouse exits immediately")
	var interrupt=Scope.input_decision(true,false,true,false,true,false,false)
	check(not interrupt.active and interrupt.wait,"Reload/menu/other disallowed state cancels and requires release")
	var still_held=Scope.input_decision(true,true,true,false,false,false,interrupt.wait)
	check(not still_held.active,"Continuing to hold after interruption cannot reopen")
	var up=Scope.input_decision(false,true,true,false,false,false,still_held.wait)
	check(not up.wait and Scope.input_decision(true,true,true,false,false,false,up.wait).active,"Release then fresh hold opens again")
	var on_ui=Scope.input_decision(true,true,true,true,false,false,false)
	check(not on_ui.active and on_ui.wait,"Pressing over UI cannot leak into scope")
	check(not Scope.input_decision(true,true,true,false,false,false,on_ui.wait).active,"Dragging out of UI while holding does not activate scope")
	check(Scope.input_decision(false,true,true,false,false,true,false).active,"Existing V accessibility toggle remains available")
	var override_latch=Scope.input_decision(true,true,true,false,true,true,false)
	check(not override_latch.latched and not Scope.input_decision(false,true,true,false,true,override_latch.latched,false).active,"Right hold takes ownership from V toggle; release still exits")
	check(Scope.input_decision(true,true,false,false,false,false,false).active,"Ordinary gun supports hold-to-zoom")
	check(not Scope.input_decision(false,true,false,false,false,true,false).active,"Ordinary gun cannot latch the sniper circle")
	check(Scope.hold_view_scale(Handling.profile(catalog.weapons.m416))>1.0 and Scope.hold_view_scale(Handling.profile(catalog.weapons.m416))<1.5,"Rifle uses restrained view expansion")
	check(Scope.hold_view_scale(Handling.profile(catalog.weapons["army-knife"]))==1.0,"Melee retains its normal camera")
	for resolution in [Vector2(1440,900),Vector2(1920,1080),Vector2(900,1440)]:
		for uv in [Vector2(.02,.02),Vector2(.5,.5),Vector2(.98,.98)]:
			var mouse=resolution*uv;var layout=Scope.mask_layout(resolution,mouse,true)
			check(layout.center.is_equal_approx(mouse) and layout.radius>0,"Circle tracks absolute cursor without clamping target away: "+str(mouse))
	# Moving only the mask must never re-anchor or pan the camera.
	scope.active=true;scope.scope_available=true;scope.view_scale=2;scope.capture_anchor(cursor)
	for frame in range(100):scope.apply_camera(1.0/60,context.camera_follow_position,20)
	var still_camera=camera.position
	for mouse in [Vector2(70,110),Vector2(1400,750)]:
		var layout=Scope.mask_layout(Vector2(1440,900),mouse,true)
		scope.lens_center=layout.center;scope.apply_camera(1.0/60,context.camera_follow_position,20)
	check(camera.position.distance_to(still_camera)<.001 and camera.basis.is_equal_approx(orientation),"Moving circle alone never turns or pans the 2.5D camera")
	check(scope.mask_alpha>.999 and scope.circular_active(),"Sniper zoom activates circular mask")
	scope.scope_available=false;scope.view_scale=1.25;scope.capture_anchor(cursor)
	for frame in range(80):scope.apply_camera(1.0/60,context.camera_follow_position,20)
	check(absf(camera.size-25.0)<.001 and scope.mask_alpha==0 and not scope.circular_active(),"Ordinary rifle expands main view without a circle")
	scope.active=false
	for frame in range(80):scope.apply_camera(1.0/60,context.camera_follow_position,20)
	check(not scope.visible and scope.mask_alpha==0 and absf(camera.size-20)<.001,"Release restores field and fully removes overlay")
	# Scope visibility must follow the outward move, never precede it.
	scope.active=true;scope.scope_available=true;scope.view_scale=2;scope.capture_anchor(cursor)
	scope.apply_camera(1.0/60,context.camera_follow_position,20)
	check(camera.size>20 and scope.mask_alpha==0 and not scope.circular_active(),"Sniper first opens up the world while the circle remains hidden")
	for frame in range(40):scope.apply_camera(1.0/60,context.camera_follow_position,20)
	check(camera.size>39.9 and scope.mask_alpha>.99,"Circle fades in after battlefield expansion")
	scope.active=false
	for frame in range(100):scope.apply_camera(1.0/60,context.camera_follow_position,20)
	var resting_position=camera.position
	for frame in range(100):scope.apply_camera(1.0/60,context.camera_follow_position,20)
	check(camera.size==20 and camera.position.is_equal_approx(resting_position),"Normal view settles exactly to its fixed preset")
	check(scope.mouse_filter==Control.MOUSE_FILTER_IGNORE and scope.overlay.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Mask does not intercept aiming or HUD input")
	viewport.free()
	print("PRECISION_CAMERA_CHECK ",count-failures.size(),"/",count," passed; failures=",failures)
	quit(0 if failures.is_empty() else 1)
