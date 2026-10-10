extends Control
## Duckov-inspired contextual action progress + input hints, on the existing HUD.
const BattleStatus=preload("res://scripts/battle_status_hud.gd")
const Cues=preload("res://scripts/combat_cue_state.gd")
const Reticle=preload("res://scripts/reticle_hud.gd")
const Handling=preload("res://scripts/weapon_handling.gd")
const Equipment=preload("res://scripts/quick_equipment.gd")
const MountedIcon=preload("res://scripts/mounted_weapon_icon.gd")
const ProgressRing=preload("res://scripts/action_progress_ring.gd")
const Tactical=preload("res://scripts/tactical_ui.gd")
const INK=Tactical.INK
const MUTED=Tactical.MUTED
const GOLD=Color("e5bf79")
const FOCUS=Tactical.ACCENT
const DANGER=Color("e8957d")
const KEY_FONT_SIZE=14
const MODE_FONT_SIZE=14
const SLOT_FONT_SIZE=13
var game
var cue: Dictionary={}
var cursor=Vector2.ZERO
var cursor_visible=false
var cursor_radius=34.0
var icon: Texture2D
var icon_id=""
var quick_icons: Dictionary={}
var quick_slots: Array=[]
var card_style=Tactical.panel_style("panel")
var chip_style=Tactical.panel_style("chip")
var prompt_style=Tactical.panel_style("panel")
var text_commands: Array=[]
var icon_commands: Array=[]
var mounted_commands: Array=[]
var paint
var cached_text_mesh: ArrayMesh
var cached_shape_mesh: ArrayMesh
var text_stamp=""
var shape_stamp=""
var last_draw_ms=0.0
var reload_ring: ProgressRing

func _ready():
	name="CombatActionHUD";mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Above the scope mask, below interactive panels. All drawing ignores input.
	z_index=-1
	Tactical.apply(self)
	reload_ring=ProgressRing.new();add_child(reload_ring);reload_ring.hide()
	# Compile the same quad shader while the original entry is preparing, before
	# the user's first reload. Opacity is a shader uniform, so this draws invisibly.
	var warmup=ProgressRing.new();game.ui.add_child(warmup)
	warmup.shader_material.set_shader_parameter("opacity",0.0)
	warmup.refresh(Vector2(36,36),28,0,true)
	RenderingServer.frame_post_draw.connect(warmup.queue_free,CONNECT_ONE_SHOT)
	hide()

func refresh():
	if game==null:return
	var u: Dictionary=game.world.player
	visible=not game.editing and not game.paused and not game.armory.visible and u.alive
	visible=visible and not game.debug_open() and not game.wheel_open() and not game.loot_open()
	if game.world.campaign_active() and game.world.campaign.phase!="playing":visible=false
	if not visible:return
	quick_slots=game.world.equipment_entries()
	var w: Dictionary=game.world.active_weapon();var state: Dictionary=game.world.active_state();var scope=game.scope_view
	cue=Cues.snapshot(w,state,u,scope!=null and scope.active,scope!=null and scope.wait_for_release)
	if u.mounted<0 and u.get("holstered",false):
		cue.weapon="空手";cue.uses_ammo=false;cue.mode="";cue.mode_switch=false;cue.focus_available=false
	cue.medical=not u.get("healing",{}).is_empty()
	if cue.medical:
		cue.weapon=str(Equipment.MEDICINE[u.healing.id].name);cue.uses_ammo=false;cue.mode="";cue.mode_switch=false;cue.focus_available=false;cue.loading=false
	cue.view_scale=scope.view_ratio if scope!=null else 1.0;cue.latched=scope!=null and scope.latched
	cursor=game.crosshair.screen_point;cursor_visible=game.crosshair.visible and not game.has_text_focus()
	var gap=Reticle.radius_for(str(Handling.profile(w).family),Handling.spread(w,state,u))
	cursor_radius=maxf(28,gap*1.42+9)
	reload_ring.refresh(cursor,cursor_radius,float(cue.reload_progress),cursor_visible and cue.loading)
	var key=str(w.get("name",w.get("label","")))
	if key!=icon_id:
		icon_id=key;icon=null
		icon=preload("res://scripts/weapon_icon.gd").get_texture(w,game.atlas,game.catalog.atlas.frames)
	for id in u.get("quick_slots",[])+[u.get("quick_tactical","")]:
		if quick_icons.has(id) or not game.catalog.weapons.has(id):continue
		var texture=preload("res://scripts/weapon_icon.gd").get_texture(game.catalog.weapons[id],game.atlas,game.catalog.atlas.frames)
		if texture!=null:quick_icons[id]=texture
	queue_redraw()

func text_at(at: Vector2,value: String,font_size: int,color: Color=INK,width: float=-1):
	var font=get_theme_default_font();var shown=value
	if width>0 and font.get_string_size(shown,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width:
		while shown.length()>1 and font.get_string_size(shown+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width:shown=shown.left(shown.length()-1)
		shown+="…"
	text_commands.append({"at":at,"text":shown,"width":width,"size":font_size,"color":color})

func keycap(at: Vector2,key: String,enabled: bool=true):
	paint.style(chip_style,Rect2(at,Vector2(24,21)))
	var key_width=get_theme_default_font().get_string_size(key,HORIZONTAL_ALIGNMENT_LEFT,-1,KEY_FONT_SIZE).x
	text_at(at+Vector2((24-key_width)*.5,16),key,KEY_FONT_SIZE,INK if enabled else MUTED.darkened(.30))

func mouse_icon(at: Vector2,pressed: bool):
	paint.style(chip_style,Rect2(at,Vector2(19,24)))
	if pressed:paint.quad(Rect2(at+Vector2(10,2),Vector2(7,8)),Rect2(),FOCUS)
	paint.line(at+Vector2(9.5,1),at+Vector2(9.5,12),INK,1,true)
	paint.line(at+Vector2(1,12),at+Vector2(18,12),MUTED,1,true)

func _draw():
	if cue.is_empty():return
	var started=Time.get_ticks_usec()
	text_commands.clear();icon_commands.clear();mounted_commands.clear()
	paint=preload("res://scripts/canvas_mesh_batch.gd").new()
	var area=Cues.card_rect(get_viewport_rect().size);var at=area.position
	var selected=[]
	for slot in quick_slots:selected.append(bool(slot.get("selected",false)))
	var shape_key=str(area,cue.focusing,cue.uses_ammo,cue.mode_switch,cue.focus_available,cue.loading,selected,BattleStatus.signature(game),game.world.player.get("healing",{}),game.world.player.get("medical_feedback",{}),game.interaction_hint.text)
	# The medical symbol follows the projected actor, unlike the fixed cards.
	# Rebuild the existing batch only while it is present, so moving the camera
	# cannot leave a cached symbol behind; feedback removal also changes the key.
	paint.enabled=shape_key!=shape_stamp or cached_shape_mesh==null or medical_graphics_active(game.world.player)
	shape_stamp=shape_key
	paint.style(card_style,area)
	paint.line(at+Vector2(1,1),at+Vector2(1,103),FOCUS if cue.focusing else GOLD,2,true)
	text_at(at+Vector2(14,25),cue.weapon,18,INK,170)
	if game.world.player.mounted>=0:
		mounted_commands.append([game.world.active_weapon(),at+Vector2(245,27),Vector2(84,29)])
	elif cue.medical:medical_cross(at+Vector2(263,26),9,FOCUS)
	elif icon!=null and not game.world.player.get("holstered",false):
		var scale=minf(98.0/icon.get_width(),29.0/icon.get_height());var extent=icon.get_size()*scale
		icon_commands.append([icon,Rect2(at+Vector2(284-extent.x,12+(29-extent.y)*.5),extent),Color(1,1,1,.85)])
	if cue.medical:
		var u: Dictionary=game.world.player
		text_at(at+Vector2(14,66),"%d / %d"%[u.health,u.max_health],26,FOCUS)
		keycap(at+Vector2(14,79),"5");paint.line(at+Vector2(47,85),at+Vector2(57,95),MUTED,1.5,true);paint.line(at+Vector2(57,85),at+Vector2(47,95),MUTED,1.5,true)
		text_at(at+Vector2(238,66),"× %d"%int(u.medical_stock.get(u.healing.id,0)),16,MUTED)
	else:text_at(at+Vector2(14,67),"%02d"%cue.ammo if cue.uses_ammo else "—",35,DANGER if cue.ammo==0 and cue.uses_ammo else GOLD if cue.low else INK)
	if cue.uses_ammo:text_at(at+Vector2(91,65),"/ %d"%cue.reserve,18,MUTED)
	if cue.mode_switch:keycap(at+Vector2(157,46),"B")
	text_at(at+Vector2(190 if cue.mode_switch else 157,62),cue.mode,MODE_FONT_SIZE,MUTED,96 if cue.mode_switch else 127)
	if cue.uses_ammo:keycap(at+Vector2(14,79),"R",cue.reloadable or cue.loading)
	if cue.focus_available:mouse_icon(at+Vector2(54,77),cue.focusing)
	BattleStatus.draw(self)
	draw_quick_slots(at+Vector2(0,-43))
	draw_medical_action()
	if game.interaction_hint!=null and not game.interaction_hint.text.is_empty():
		var interaction: String=game.interaction_hint.text
		var extent=minf(get_theme_default_font().get_string_size(interaction,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x+24,get_viewport_rect().size.x-32)
		var origin=Vector2((get_viewport_rect().size.x-extent)*.5,get_viewport_rect().size.y-48)
		paint.style(prompt_style,Rect2(origin,Vector2(extent,23)))
		text_at(origin+Vector2(12,17),interaction,15,INK,extent-24)
	# Action feedback stays graphical. No countdown, status bubble or focus bar.
	# ADS already tightens the real reticle; the card's mouse icon marks the hold.
	# Reload progress is one persistent GPU quad, independent of cached card/slots.
	# These card/slot text regions never overlap. Order by font atlas instead of
	# alternating geometry, icons and several font sizes at every keycap.
	if paint.enabled:cached_shape_mesh=paint.mesh()
	draw_mesh(cached_shape_mesh,null)
	for command in mounted_commands:MountedIcon.draw(self,command[0],command[1],command[2],INK)
	for command in icon_commands:draw_texture_rect(command[0],command[1],false,command[2])
	var current=str(text_commands)
	if current!=text_stamp:
		text_stamp=current;var text_batch=preload("res://scripts/canvas_mesh_batch.gd").new()
		for command in text_commands:
			var shaped=game.hud_batches.atlas.layout(command.text,get_theme_default_font(),command.size,command.width)
			game.hud_batches.atlas.append(text_batch,shaped,command.at-Vector2(0,shaped.ascent),command.color)
		cached_text_mesh=text_batch.mesh();game.hud_batches.atlas.upload()
	if cached_text_mesh!=null:draw_mesh(cached_text_mesh,game.hud_batches.atlas.texture)
	last_draw_ms=(Time.get_ticks_usec()-started)/1000.0

func draw_quick_slots(at: Vector2):
	var u: Dictionary=game.world.player
	var mounted=int(u.mounted)>=0
	for i in range(quick_slots.size() if mounted else 5):
		var origin=at+Vector2(i*61,0);var area=Rect2(origin,Vector2(56,35))
		paint.style(card_style,area)
		var entry: Dictionary=quick_slots[i] if i<quick_slots.size() else {}
		var id=str(entry.get("id",""))
		var selected=bool(entry.get("selected",false)) and u.get("healing",{}).is_empty() if not entry.is_empty() else not u.get("healing",{}).is_empty()
		if selected:paint.line(origin+Vector2(3,32),origin+Vector2(53,32),FOCUS,3,true)
		text_at(origin+Vector2(5,14),str(i+1),SLOT_FONT_SIZE,INK if selected else MUTED)
		if mounted:
			mounted_commands.append([entry.weapon,origin+Vector2(33,19),Vector2(37,20)])
		elif i==4:
			var feedback: Dictionary=u.get("medical_feedback",{})
			var tint=DANGER if feedback.get("kind","")=="empty" else FOCUS if not feedback.is_empty() else INK
			medical_cross(origin+Vector2(28,16),7,tint)
			text_at(origin+Vector2(43,28),str(u.medical_stock.get(u.medical_selected,0)),11,MUTED)
			var action: Dictionary=u.get("healing",{})
			if not action.is_empty():paint.arc(origin+Vector2(28,17),14,-PI*.5,TAU*(1-action.remaining/action.duration)-PI*.5,32,FOCUS,2,true)
		elif quick_icons.has(id):
			var texture: Texture2D=quick_icons[id];var scale=minf(37.0/texture.get_width(),20.0/texture.get_height());var extent=texture.get_size()*scale
			icon_commands.append([texture,Rect2(origin+Vector2(33,19)-extent*.5,extent),INK])
	text_at(at+Vector2(-26,23),"G",14,MUTED)

func medical_cross(at: Vector2,radius: float,color: Color):
	paint.line(at-Vector2(radius,0),at+Vector2(radius,0),color,3,true)
	paint.line(at-Vector2(0,radius),at+Vector2(0,radius),color,3,true)

static func medical_graphics_active(u: Dictionary) -> bool:
	return int(u.get("mounted",-1))<0 and (not u.get("healing",{}).is_empty() or not u.get("medical_feedback",{}).is_empty())

func draw_medical_action():
	var u: Dictionary=game.world.player;var action: Dictionary=u.get("healing",{});var feedback: Dictionary=u.get("medical_feedback",{})
	if u.mounted>=0 or (action.is_empty() and feedback.is_empty()):return
	var actor: Node3D=game.actors[u.id].root
	var point=actor.global_position+Vector3.UP*(1.9-float(u.get("stance_blend",0))*.58)
	if game.camera.is_position_behind(point):return
	var at=game.camera.unproject_position(point)+Vector2(0,-29)
	var bad=feedback.get("kind","")=="empty";var color=DANGER if bad else FOCUS
	paint.circle(at,18,Color(.08,.10,.10,.8))
	var progress=preload("res://scripts/medical_motion.gd").progress(action) if not action.is_empty() else 1.0
	paint.arc(at,18,-PI*.5,TAU-PI*.5,40,Color(.34,.36,.34,.9),2,true)
	if progress>.001:paint.arc(at,18,-PI*.5,TAU*progress-PI*.5,40,color,2,true)
	if feedback.get("kind","") in ["full","complete"]:
		paint.line(at+Vector2(-7,0),at+Vector2(-2,5),color,2,true);paint.line(at+Vector2(-2,5),at+Vector2(8,-6),color,2,true)
	else:
		medical_cross(at,6,color)
		if bad:paint.line(at-Vector2(10,10),at+Vector2(10,10),color,2,true)
	var ratio=clampf(float(u.health)/maxf(1,float(u.max_health)),0,1)
	paint.quad(Rect2(at+Vector2(-29,25),Vector2(58,4)),Rect2(),Color(.10,.12,.11,.85))
	if not action.is_empty():
		var predicted=minf(1,ratio+float(Equipment.MEDICINE[action.id].heal)/float(u.max_health))
		paint.quad(Rect2(at+Vector2(-29,25),Vector2(58*predicted,4)),Rect2(),Color(.40,.52,.43,.65))
	paint.quad(Rect2(at+Vector2(-29,25),Vector2(58*ratio,4)),Rect2(),color)
