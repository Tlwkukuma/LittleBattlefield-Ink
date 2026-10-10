extends Node3D
## All weapon marks follow the absolute mouse. Ballistics never move the HUD.
const Handling=preload("res://scripts/weapon_handling.gd")
const Display=preload("res://scripts/reticle_hud.gd")
var overlay: Control
var game
var point=Vector3.ZERO
var screen_point=Vector2.ZERO
var distance=0.0
var hit_time=0.0
var hit_fatal=false
var ink=Color("f6edcf")

func _ready():
	overlay=Display.new();overlay.name="WeaponReticleHUD";overlay.hide();game.ui.add_child(overlay)

func _exit_tree():
	# The HUD lives in the UI canvas. Rebuilding the range must also remove it.
	if is_instance_valid(overlay):overlay.hide();overlay.queue_free()

func refresh(delta: float):
	update_at_mouse(delta,get_viewport().get_mouse_position())

func update_at_mouse(delta: float,mouse: Vector2):
	if game==null:return
	screen_point=mouse
	hit_time=maxf(0,hit_time-delta)
	var u: Dictionary=game.world.player;var w: Dictionary=game.world.active_weapon();var state: Dictionary=game.world.active_state()
	visible=not game.editing and not game.paused and u.alive and not game.armory.visible and u.vault.is_empty() and u.ladder.is_empty() and not game.over_ui()
	visible=visible and not game.wheel_open() and not game.loot_open() and not (u.mounted<0 and (u.get("holstered",false) or not u.get("healing",{}).is_empty()))
	if u.mounted<0 and w.kind=="mortar":visible=false
	overlay.visible=visible and not (game.scope_view!=null and game.scope_view.circular_active())
	if not visible:return
	var socket: Node3D=game.vehicle_views[u.mounted].muzzle_socket if u.mounted>=0 else game.actors[u.id].muzzle_socket
	var origin=socket.global_position
	var height=float(u.get("aim_height",origin.y))
	point=Vector3(game.aim.x,height if height>=0 else origin.y,game.aim.y)
	distance=origin.distance_to(point)
	ink=Color("f6edcf")
	# The requested point is only used for the distance readout. No cover ray,
	# muzzle rotation, recoil or world projection is allowed to shift the cursor.
	if not overlay.visible:return
	var family=str(Handling.profile(w).family)
	var radius=Display.radius_for(family,Handling.spread(w,state,u))
	overlay.hit_fatal=hit_fatal;overlay.update_mark(screen_point,family,radius,ink,hit_time,delta)
