extends SceneTree
## Cursor math, HUD lifecycle and static fixtures only; no game input or firing.
const Reticle=preload("res://scripts/weapon_reticle.gd")
const Display=preload("res://scripts/reticle_hud.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const Handling=preload("res://scripts/weapon_handling.gd")
const Scope=preload("res://scripts/scope_view.gd")
class WorldFixture extends RefCounted:
	var player={"id":0,"team":0,"mounted":-1,"alive":true,"vault":{},"ladder":{},"aim_height":1.0,"position":Vector2.ZERO,"stance":0,"grounded":true,"aiming":false}
	var weapon={"id":"reticle-fixture","kind":"bullet","archetype":"shotgun","spread":.03,"pellets":8,"range":2000}
	var hit: Dictionary={}
	var barrel_hit: Dictionary={}
	var ray_calls=0
	func active_weapon() -> Dictionary:return weapon
	func active_state() -> Dictionary:return {}
	func muzzle_height(_unit: Dictionary) -> float:return 1.0
	func ray(_at: Vector2,_direction: Vector2,_length: float,_height: float,_options: Dictionary,walls_only: bool=false) -> Dictionary:
		ray_calls+=1;return barrel_hit if walls_only else hit
class ScopeFixture extends RefCounted:
	var active=false
	func circular_active() -> bool:return active
class Context extends RefCounted:
	var world=WorldFixture.new()
	var scope_view=ScopeFixture.new()
	var camera: Camera3D
	var ui: Control
	var armory: Control
	var actors: Array=[]
	var vehicle_views: Array=[]
	var editing=false
	var paused=false
	var ui_hover=false
	var aim=Vector2(0,-8)
	var crosshair
	func over_ui() -> bool:return ui_hover
var failures=[]
var count=0
func _initialize():run.call_deferred()
func check(ok: bool,label: String):
	count+=1
	if not ok:failures.append(label);push_error(label)
func run():
	var viewport=SubViewport.new();viewport.size=Vector2i(1440,900);viewport.own_world_3d=true;root.add_child(viewport)
	var context=Context.new();var camera=Camera3D.new();context.camera=camera;viewport.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20;camera.position=Vector3(0,48,48);camera.look_at(Vector3.ZERO)
	var layer=CanvasLayer.new();viewport.add_child(layer);context.ui=Control.new();layer.add_child(context.ui)
	context.armory=Control.new();context.ui.add_child(context.armory);context.armory.hide()
	var stage=Node3D.new();viewport.add_child(stage)
	var socket=Node3D.new();stage.add_child(socket);socket.position=Vector3(0,1,0);context.actors=[{"muzzle_socket":socket}]
	var reticle=Reticle.new();reticle.game=context;context.crosshair=reticle;stage.add_child(reticle)
	check(reticle.get_child_count()==0 and reticle.overlay.get_parent()==context.ui,"Normal reticle uses UI canvas without depth-tested mesh")
	check(reticle.overlay.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Reticle does not intercept mouse input")
	for resolution in [Vector2i(1440,900),Vector2i(1920,1080),Vector2i(900,1440)]:
		viewport.size=resolution
		for angle in [0.0,PI*.25,PI*.5,PI,PI*1.5]:
			socket.rotation.y=angle
			var forward=-socket.global_basis.z;context.aim=Vector2(forward.x,forward.z)*8
			var mouse=Vector2(resolution)*Vector2(.22,.35)
			reticle.update_at_mouse(1.0/60,mouse)
			check(reticle.screen_point.is_equal_approx(mouse) and reticle.overlay.center.is_equal_approx(mouse),"Cursor center is exact despite muzzle direction: "+str(resolution)+" yaw="+str(angle))
			var box=Display.segments("shotgun",reticle.overlay.radius)
			var square=box.size()==8
			for i in range(0,box.size(),2):
				var edge=box[i+1]-box[i]
				square=square and is_equal_approx(edge.length(),reticle.overlay.radius*2) and (is_zero_approx(edge.x) or is_zero_approx(edge.y)) and box[i+1].is_equal_approx(box[(i+2)%8])
			check(square,"Shotgun square remains closed, axis aligned and equal sided from every direction")
	# Changes in accuracy must remain visible without restoring an oversized ellipse.
	check(Display.radius_for("shotgun",.10)<Display.radius_for("shotgun",.15),"Shotgun frame responds to increased dispersion")
	check(Display.radius_for("shotgun",0)==12 and Display.radius_for("shotgun",100)==32,"Shotgun frame has readable minimum and bounded maximum")
	var catalog=Catalog.new();var all_supported=true
	for weapon in catalog.weapons.values():
		var family=str(Handling.profile(weapon).family);var radius=Display.radius_for(family,Handling.spread(weapon,{},context.world.player))
		context.world.weapon=weapon;reticle.update_at_mouse(.016,Vector2(321,234))
		all_supported=all_supported and reticle.overlay.center==Vector2(321,234) and is_finite(radius) and radius>=0 and radius<=32 and Display.segments(family,radius).size()<=16
	check(all_supported,"All original weapon families use bounded, compact geometry")
	var stand={"stance":0,"grounded":true,"aiming":false};var aim=stand.duplicate();aim.aiming=true
	var shotgun=catalog.weapons.s1897
	check(Handling.spread(shotgun,{"aim_time":1.0},aim)>=float(Handling.profile(shotgun).pellet),"ADS preserves the shell's pellet dispersion")
	check(Handling.spread(shotgun,{"motion_inaccuracy":1.0,"bloom":.02},stand)>Handling.spread(shotgun,{},stand),"Movement and sustained firing drive the same spread model as projectiles")
	reticle.overlay.update_mark(Vector2.ZERO,"shotgun",40,Color.WHITE,0,.016)
	reticle.overlay.update_mark(Vector2.ZERO,"shotgun",12,Color.WHITE,0,.016)
	check(reticle.overlay.radius>12 and reticle.overlay.radius<40,"Dispersion contracts smoothly")
	reticle.overlay.update_mark(Vector2.ZERO,"rifle",4,Color.WHITE,0,.016)
	check(reticle.overlay.radius==4,"Weapon family switch does not inherit oversized shotgun frame")
	# Fixed obstruction results must have no influence on cursor position or color.
	var mouse=Vector2(300,240);context.world.weapon=shotgun;socket.rotation=Vector3.ZERO;context.aim=Vector2(0,-8)
	context.world.hit={"type":"object","distance":2.0};reticle.update_at_mouse(.016,mouse)
	check(reticle.overlay.center==mouse and reticle.ink.is_equal_approx(Color("f6edcf")),"Cover cannot move or recolor the mark")
	context.world.hit={"type":"unit","distance":3.0};reticle.hit_time=.14;reticle.update_at_mouse(.016,mouse)
	check(reticle.overlay.center==mouse and reticle.ink.is_equal_approx(Color("f6edcf")) and reticle.overlay.hit_time>0,"Hover stays neutral; confirmed hit still shows its brief marker")
	context.world.hit={};context.world.barrel_hit={"type":"object","distance":.2};socket.position.x=.6;reticle.update_at_mouse(.016,mouse)
	check(reticle.overlay.center==mouse and context.world.ray_calls==0,"No muzzle/barrel obstruction queries influence the HUD")
	context.world.barrel_hit={};socket.position.x=0
	reticle.update_at_mouse(10,mouse);var radius=reticle.overlay.radius
	var steady=true
	for zoom in [3.6,13.0,24.0]:
		camera.size=zoom
		for target in [Vector2(.1,-.1),Vector2(0,-8),Vector2(0,-35)]:
			context.aim=target;context.world.player.aim_height=3.0;reticle.update_at_mouse(.016,mouse)
			steady=steady and reticle.overlay.center==mouse and is_equal_approx(reticle.overlay.radius,radius)
	check(steady,"Near/far surfaces, target height and zoom cannot resize or displace the shotgun frame")
	context.vehicle_views=[{"muzzle_socket":socket}];context.world.player.mounted=0;reticle.update_at_mouse(.016,mouse)
	check(reticle.overlay.center==mouse,"Mounted weapons also follow the mouse")
	context.world.player.mounted=-1
	context.scope_view.active=true;context.world.hit={"type":"unit","distance":4.0};reticle.update_at_mouse(.016,mouse)
	check(reticle.visible and not reticle.overlay.visible and reticle.screen_point==mouse,"Scope suppresses the duplicate mark and receives the same mouse sample")
	context.scope_view.active=false;reticle.update_at_mouse(.016,mouse)
	check(reticle.overlay.visible,"Releasing scope restores the normal reticle")
	# Exercise the actual scope HUD with arbitrary mouse samples, without OS input.
	context.ui.size=Vector2(viewport.size)
	var scope=Scope.new();scope.game=context;context.ui.add_child(scope);context.scope_view=scope
	context.world.weapon=catalog.weapons.awm;scope.active=true;scope.scope_available=true;scope.mask_alpha=1;scope.show()
	var concentric=true
	for cursor in [Vector2(30,40),Vector2(420,260),Vector2(850,1400)]:
		reticle.update_at_mouse(.016,cursor);scope.refresh(.016)
		concentric=concentric and scope.reticle_point==cursor and scope.lens_center==cursor and not reticle.overlay.visible
	check(concentric,"Actual scope mask and reticle share the exact mouse center, including viewport edges")
	scope.active=false;scope.hide();context.armory.show();reticle.update_at_mouse(.016,mouse)
	check(not reticle.visible and not reticle.overlay.visible,"Armory hides the mark")
	context.armory.hide();context.ui_hover=true;reticle.update_at_mouse(.016,mouse)
	check(not reticle.visible and not reticle.overlay.visible,"Interactive UI hides the mark")
	context.ui_hover=false;context.world.player.vault={"mode":"vault"};reticle.update_at_mouse(.016,mouse)
	check(not reticle.visible and not reticle.overlay.visible,"Traversal hides the mark")
	context.world.player.vault={};context.world.player.ladder={"id":"static-fixture"};reticle.update_at_mouse(.016,mouse)
	check(not reticle.visible and not reticle.overlay.visible,"Ladder traversal retains its hide condition")
	context.world.player.ladder={};context.world.player.alive=false;reticle.update_at_mouse(.016,mouse)
	check(not reticle.visible and not reticle.overlay.visible,"Death hides the mark")
	var old_overlay=reticle.overlay;stage.free()
	check(not old_overlay.visible and old_overlay.is_queued_for_deletion(),"Range rebuild hides and frees its independently parented HUD")
	await process_frame
	check(not is_instance_valid(old_overlay),"No stale reticle survives range rebuild")
	viewport.free()
	print("RETICLE_PROJECTION_CHECK ",count-failures.size(),"/",count," passed; failures=",failures)
	quit(0 if failures.is_empty() else 1)
