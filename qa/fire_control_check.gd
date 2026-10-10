extends SceneTree
## Pure trigger-clock and ammo arithmetic fixtures. No game scene, input injection,
## world.fire, projectiles, visual capture or automated playtest.
const Catalog=preload("res://scripts/source_catalog.gd")
const Fire=preload("res://scripts/weapon_fire_control.gd")
var checks=0
var failures=[]
func check(ok: bool,description: String):
	checks+=1
	if not ok:failures.append(description);push_error(description)
func state(w: Dictionary,mode: String="") -> Dictionary:
	var s={"ammo":int(w.mag),"reserve":int(w.reserve),"reload":0.0,"cooldown":0.0,"fire_mode":mode}
	Fire.reset(s,w);return s
func count_schedule(w: Dictionary,mode: String,fps: int,hold: bool=true) -> int:
	var s=state(w,mode);s.ammo=10000;var count=0
	for frame in range(fps*3):
		Fire.tick_clock(s,1.0/fps)
		if Fire.wants_shot(s,w,hold or frame==0,frame==0):
			count+=1;Fire.committed(s,w);s.ammo-=1
	return count
func _initialize():
	var catalog=Catalog.new();var serialized=JSON.stringify(catalog.data.weapons)
	check(catalog.weapons.size()==84 and Fire.MODES.size()==84,"All 84 original equipment entries have explicit modes")
	for id in catalog.weapons:
		var w: Dictionary=catalog.weapons[id];var s=state(w);var options=Fire.modes(w)
		check(Fire.MODES.has(id) and not options.is_empty(),"Explicit supported modes: "+id)
		check(Fire.default_mode(w) in options,"Valid default: "+id)
		check(not Fire.options_label(w).is_empty(),"Readable modes: "+id)
		var original=Fire.selected(s,w)
		for mode in options:Fire.cycle(s,w)
		check(Fire.selected(s,w)==original,"Mode cycle wraps: "+id)
		for mode in options:
			if mode.begins_with("auto"):
				for fps in [30,60,120]:
					var count=count_schedule(w,mode,fps);var reference=Fire.rpm(w,{"fire_mode":mode})*3.0/60.0
					check(absf(count-reference)<=1.01,"Cadence without frame rounding: %s %s @%d"%[id,mode,fps])
			else:
				var expected=2 if mode=="burst2" else 3 if mode=="burst3" else 1
				check(count_schedule(w,mode,60)==expected,"Holding cannot retrigger: "+id+" "+mode)
				check(count_schedule(w,mode,60,false)==expected,"Release completes exactly one selected group: "+id+" "+mode)
		if w.kind!="melee":
			s=state(w);s.ammo=0;s.reserve=2
			check(Fire.needs_reload(s,w) and Fire.begin_reload(s,w),"Empty auto reload eligible: "+id)
			check(not Fire.begin_reload(s,w),"Reload event cannot be repeated: "+id)
			s.reload=0;Fire.finish_reload(s,w)
			check(s.ammo+s.reserve==2 and s.ammo==mini(2,int(w.mag)),"Limited reserve conserved: "+id)
			s.ammo=0;s.reserve=0
			check(not Fire.needs_reload(s,w) and not Fire.begin_reload(s,w),"Dry reserve has no reload loop: "+id)
		else:check(not Fire.needs_reload(s,w) and not Fire.begin_reload(s,w),"Melee never reloads: "+id)
	check(Fire.modes(catalog.weapons["m16a4"])==["single","burst3"],"M16A4 has no full auto")
	check(Fire.modes(catalog.weapons["mk47-mutant"])==["single","burst2"],"Mutant uses two-round burst")
	check(Fire.modes(catalog.weapons["o12"])==["single","burst3","auto"],"O12 supports all three modes")
	check(Fire.modes(catalog.weapons["mg3"])==["auto660","auto990"],"MG3 changes cyclic rate, not single fire")
	check(Fire.modes(catalog.weapons["xm1014"])==["single"],"XM1014 corrected to semi-auto")
	var w: Dictionary=catalog.weapons["m16a4"];var s=state(w,"burst3")
	check(Fire.wants_shot(s,w,true,true),"Burst first edge accepted")
	Fire.committed(s,w);s.ammo-=1
	check(not Fire.wants_shot(s,w,true,true),"Extra click during cadence cannot duplicate a burst")
	Fire.cancel(s,true);s.cooldown=0
	check(not Fire.wants_shot(s,w,true,false) and s.fire_pending==0,"Cancellation discards remaining burst and held trigger")
	Fire.wants_shot(s,w,false,false)
	check(Fire.wants_shot(s,w,true,true),"Fresh edge after cancel works")
	Fire.committed(s,w);s.ammo=0
	check(Fire.begin_reload(s,w) and s.fire_pending==0,"Empty truncated burst clears before reload")
	s.reload=0;Fire.finish_reload(s,w);s.cooldown=0
	check(not Fire.wants_shot(s,w,true,false),"Burst cannot leak into next magazine")
	check(Fire.wants_shot(s,w,true,true),"Reloaded burst requires fresh click")
	for mode in ["single","auto"]:
		w=catalog.weapons["m416"];s=state(w,mode);s.ammo=0
		Fire.begin_reload(s,w)
		check(not Fire.wants_shot(s,w,true,true),"Click during reload is not queued: "+mode)
		s.reload=0;Fire.finish_reload(s,w)
		check(Fire.wants_shot(s,w,true,false)==(mode=="auto"),"Only full auto resumes held after reload: "+mode)
	w=catalog.weapons["m416"];s=state(w,"auto")
	check(not Fire.wants_shot(s,w,true,true,false),"UI/traversal gate denies shot")
	check(not Fire.wants_shot(s,w,true,false,true),"Leaving UI with mouse held cannot shoot")
	Fire.wants_shot(s,w,false,false,true)
	check(Fire.wants_shot(s,w,true,true,true),"Release then click re-arms after UI")
	Fire.committed(s,w);s.cooldown=.8;Fire.cycle(s,w)
	check(is_equal_approx(s.cooldown,.8) and not Fire.wants_shot(s,w,true,true),"Mode switch cannot bypass cooldown or fire while held")
	s=state(w);check(not Fire.begin_reload(s,w),"Full magazine ignores manual reload")
	s.ammo=9;s.reserve=5;Fire.begin_reload(s,w);s.reload=0;Fire.finish_reload(s,w)
	check(s.ammo==14 and s.reserve==0,"Tactical reload conserves remaining cartridges")
	s=state(w);Fire.tick_clock(s,20)
	check(s.cooldown==0,"Idle cannot bank negative cooldown")
	check(Fire.modes({"kind":"shell","automatic":false})==["single"],"Mounted cannon single trigger")
	check(Fire.modes({"kind":"bullet","automatic":true})==["auto"],"Mounted machinegun held trigger")
	check(JSON.stringify(catalog.data.weapons)==serialized,"Original imported weapon data remains unchanged")
	print("FIRE_CONTROL_CHECK ",checks-failures.size(),"/",checks," passed; no gameplay automation")
	quit(0 if failures.is_empty() else 1)
