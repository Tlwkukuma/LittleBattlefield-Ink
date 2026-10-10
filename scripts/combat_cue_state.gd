extends RefCounted
## Read-only presentation state; never starts a reload or changes aiming accuracy.
const Handling=preload("res://scripts/weapon_handling.gd")
const FireControl=preload("res://scripts/weapon_fire_control.gd")
const Scope=preload("res://scripts/scope_view.gd")

static func snapshot(w: Dictionary,state: Dictionary,u: Dictionary,focus: bool,wait_release: bool=false) -> Dictionary:
	var p=Handling.profile(w);var ammo=maxi(0,int(state.get("ammo",0)));var reserve=maxi(0,int(state.get("reserve",0)))
	var mag=maxi(1,int(w.get("mag",1)));var remaining=maxf(0,float(state.get("reload",0)))
	var blocked=not u.get("vault",{}).is_empty() or not u.get("ladder",{}).is_empty()
	var uses_ammo=w.kind!="melee";var loading=uses_ammo and remaining>0
	var reloadable=uses_ammo and ammo<mag and reserve>0 and not loading and not blocked
	var can_focus=(bool(p.scope) or Scope.hold_view_scale(p)>1) and int(u.get("mounted",-1))<0
	var focusing=can_focus and focus and not loading and not blocked
	var low=uses_ammo and ammo<=maxi(1,int(ceil(mag*.2)))
	var cue={"weapon":str(w.get("name",w.get("label","武器"))),"mode":FireControl.label(state,w),"mode_switch":FireControl.modes(w).size()>1,
		"ammo":ammo,"reserve":reserve,"mag":mag,"uses_ammo":uses_ammo,"low":low,"loading":loading,"remaining":remaining,
		"reloadable":reloadable,"reload_label":"换弹","reload_progress":0.0,"focus_available":can_focus,"focusing":focusing,
		"focus_label":"按住聚焦","focus_progress":0.0,"focus_ready":false,"prompt":"","prompt_kind":"","scoped":bool(p.scope)}
	if w.kind=="grenade" and int(u.get("mounted",-1))<0:
		cue.mode="低抛" if bool(u.get("throw_state",{}).get("low",u.get("throw_low",false))) or int(u.get("stance",0))==2 else "上抛"
	if loading:
		cue.reload_progress=clampf(1-remaining/maxf(.05,float(state.get("reload_duration",w.get("reload",1)))),0,1)
		cue.reload_label="换弹中 · %.1f s"%remaining;cue.prompt="换弹中  %.1f s"%remaining;cue.prompt_kind="reload"
	elif not uses_ammo:cue.reload_label="无需换弹"
	elif reserve<=0:cue.reload_label="弹药耗尽" if ammo==0 else "无备用弹药"
	elif ammo>=mag:cue.reload_label="弹匣已满"
	elif blocked:cue.reload_label="动作结束后换弹"
	else:cue.reload_label="换弹"
	if not loading and uses_ammo:
		if ammo==0:cue.prompt="弹药耗尽" if reserve==0 else "R 换弹";cue.prompt_kind="empty"
		elif low:cue.prompt="无备用弹药" if reserve==0 else "R 换弹 · 弹药偏少";cue.prompt_kind="low"
	if not can_focus:cue.focus_label="右键 高 / 低抛" if w.kind=="grenade" else "当前装备无聚焦"
	elif loading:cue.focus_label="换弹后可聚焦"
	elif blocked:cue.focus_label="动作结束后聚焦"
	elif wait_release:cue.focus_label="松开后重按聚焦"
	elif focusing:
		var stance=clampi(int(u.get("stance",0)),0,2)
		var ideal=maxf(.00001,float(p.ads)*[1.0,.78,.58][stance])
		cue.focus_progress=clampf(ideal/maxf(ideal,Handling.aim_spread(w,state,u)),0,1)
		cue.focus_ready=cue.focus_progress>.88
		if not u.get("grounded",true):cue.focus_label="腾空聚焦"
		elif float(state.get("motion_inaccuracy",0))>.10:cue.focus_label="移动聚焦"
		elif float(state.get("aim_time",0))<float(p.settle):cue.focus_label="聚焦中"
		else:cue.focus_label="聚焦就绪" if cue.focus_ready else "回稳中"
		if cue.prompt.is_empty():cue.prompt=cue.focus_label;cue.prompt_kind="focus"
	return cue

static func card_rect(view_size: Vector2) -> Rect2:
	return Rect2(Vector2(maxf(12,view_size.x-324),maxf(90,view_size.y-128)),Vector2(300,104))

static func prompt_position(mouse: Vector2,view_size: Vector2,width: float,offset: float=56.0) -> Vector2:
	var y=mouse.y+offset
	if y+42>view_size.y-98:y=mouse.y-offset-42
	return Vector2(clampf(mouse.x-width*.5,12,maxf(12,view_size.x-width-12)),clampf(y,86,maxf(86,view_size.y-140)))
