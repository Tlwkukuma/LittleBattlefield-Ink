extends SceneTree
## Read-only HUD state / layout fixtures. Never simulates input, shooting or movement.
const Cues=preload("res://scripts/combat_cue_state.gd")
const HUD=preload("res://scripts/combat_hud.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const Handling=preload("res://scripts/weapon_handling.gd")
var checks=0
var failures=[]
func check(value: bool,label: String):
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
	var catalog=Catalog.new();var w: Dictionary=catalog.weapons.m416
	var u={"id":0,"alive":true,"mounted":-1,"vault":{},"ladder":{},"stance":0,"grounded":true,"aiming":false}
	var state={"ammo":30,"reserve":180,"reload":0.0,"reload_duration":2.0,"aim_time":0.0,"motion_inaccuracy":0.0,"bloom":0.0}
	var cue=Cues.snapshot(w,state,u,false)
	check(not cue.reloadable and cue.reload_label=="弹匣已满" and cue.focus_available,"Full magazine shows inactive reload and available focus")
	state.ammo=12;cue=Cues.snapshot(w,state,u,false)
	check(cue.reloadable and cue.prompt.is_empty(),"Partial magazine offers reload without nagging at cursor")
	state.ammo=4;cue=Cues.snapshot(w,state,u,false)
	check(cue.low and cue.prompt_kind=="low" and cue.reloadable,"Low magazine provides contextual R hint")
	state.reload=1.5;cue=Cues.snapshot(w,state,u,true)
	check(cue.loading and is_equal_approx(cue.reload_progress,.25) and not cue.focusing,"Reload wins over focus; progress comes from actual duration")
	state.reload=.02;cue=Cues.snapshot(w,state,u,false)
	check(cue.reload_progress<1 and cue.reload_progress>.98,"Cannot claim finished before the reload ends")
	state.reload=0;state.ammo=30;cue=Cues.snapshot(w,state,u,false)
	check(not cue.loading and cue.prompt.is_empty(),"Finishing removes progress rather than leaving stale timer")
	state.ammo=4;state.reserve=0;cue=Cues.snapshot(w,state,u,false)
	check(not cue.reloadable and cue.reload_label=="无备用弹药" and cue.prompt=="无备用弹药","No R invitation without reserve")
	state.ammo=0;cue=Cues.snapshot(w,state,u,false)
	check(cue.prompt=="弹药耗尽" and not cue.reloadable,"Empty weapon and no reserve have distinct warning")
	state.reserve=30;state.reload=2;cue=Cues.snapshot(w,state,u,false)
	check(cue.loading and cue.prompt_kind=="reload" and cue.reload_progress==0,"Empty automatic reload uses same real progress")
	state.reload=0;state.ammo=30;u.aiming=true;state.aim_time=.04
	cue=Cues.snapshot(w,state,u,true)
	check(cue.prompt_kind=="focus" and not cue.focus_ready and cue.focus_label=="聚焦中","Fresh right hold shows focus acquisition")
	state.aim_time=1;cue=Cues.snapshot(w,state,u,true)
	check(cue.focus_ready and is_equal_approx(cue.focus_progress,1),"Stationary settled focus reaches ready")
	state.motion_inaccuracy=.7;cue=Cues.snapshot(w,state,u,true)
	check(not cue.focus_ready and cue.focus_label=="移动聚焦" and cue.focus_progress<.2,"Movement cannot masquerade as stable aim")
	state.motion_inaccuracy=0;state.bloom=.015;cue=Cues.snapshot(w,state,u,true)
	check(not cue.focus_ready and cue.focus_label=="回稳中","Shot bloom is reflected by the recovery hint")
	state.bloom=0;u.grounded=false;cue=Cues.snapshot(w,state,u,true)
	check(cue.focus_label=="腾空聚焦" and not cue.focus_ready,"Airborne accuracy remains visible")
	u.grounded=true;cue=Cues.snapshot(w,state,u,false,true)
	check(cue.focus_label=="松开后重按聚焦" and not cue.focusing,"Interrupted hold explains release requirement")
	u.ladder={"phase":"climb"};state.ammo=5;cue=Cues.snapshot(w,state,u,true)
	check(not cue.reloadable and not cue.focusing,"Traversal cannot offer unavailable reload or focus")
	u.ladder={};u.mounted=0;cue=Cues.snapshot(w,state,u,true)
	check(cue.reloadable and not cue.focus_available,"Mounted ammo state supports reload without inventing focus")
	u.mounted=-1
	for weapon in catalog.weapons.values():
		var before=weapon.duplicate(true);var before_state=state.duplicate(true);var before_u=u.duplicate(true)
		cue=Cues.snapshot(weapon,state,u,false)
		check(cue.reload_progress>=0 and cue.reload_progress<=1 and cue.focus_progress>=0 and cue.focus_progress<=1,"Finite cue state for "+str(weapon.id))
		check(weapon==before and state==before_state and u==before_u,"HUD cannot mutate simulation: "+str(weapon.id))
		if weapon.kind=="melee":check(not cue.uses_ammo and not cue.reloadable and not cue.focus_available,"Melee has no bogus ammo/focus hints")
		if weapon.kind=="grenade":check(not cue.focus_available and cue.focus_label.contains("高 / 低抛"),"Grenade right button retains throw meaning")
	for viewport in [Vector2(960,540),Vector2(1440,900),Vector2(1920,1080)]:
		var rect=Cues.card_rect(viewport)
		check(Rect2(Vector2.ZERO,viewport).encloses(rect) and is_equal_approx(rect.end.y,viewport.y-24) and rect.size==Vector2(300,104),"Compact card preserves 24-pixel bottom safe margin without removed footer")
		for uv in [Vector2.ZERO,Vector2(.5,.5),Vector2.ONE]:
			var pos=Cues.prompt_position(viewport*uv,viewport,210)
			check(Rect2(Vector2.ZERO,viewport).encloses(Rect2(pos,Vector2(210,38))),"Cursor text stays within screen at borders")
	var host=Control.new();root.add_child(host)
	var hud=HUD.new();hud.game={"ui":host};host.add_child(hud)
	check(hud.mouse_filter==Control.MOUSE_FILTER_IGNORE and hud.get_child_count()==1 and hud.reload_ring.mouse_filter==Control.MOUSE_FILTER_IGNORE,"HUD and its single persistent reload ring never capture aim/clicks")
	check(not hud.reload_ring.visible,"Reload ring starts hidden")
	host.free()
	print("COMBAT_HUD_CHECK ",checks-failures.size(),"/",checks," passed; no gameplay automation; failures=",failures)
	quit(0 if failures.is_empty() else 1)
