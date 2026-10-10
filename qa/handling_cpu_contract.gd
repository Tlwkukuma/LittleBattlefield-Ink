extends SceneTree
## Compare against frozen post-topdown/pre-CPU code, never the v3 gameplay.
const H=preload("res://scripts/weapon_handling.gd")
const B=preload("res://qa/fixtures/weapon_handling_topdown_baseline.gd")
const F=preload("res://scripts/weapon_fire_control.gd")
const BASELINE_SHA256="66dc990cf8a14af702154a00d95f1644a811fe0e73bd3dcf641180b7140e2046"
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;printerr("FAIL "+label)
func state(variant: int) -> Dictionary:
	var s={"stance":variant%3,"stance_blend":float(variant%3),"grounded":true,"velocity":Vector2.ZERO,"mounted":-1,"aiming":variant%2==0,"vault":{},"ladder":{},"ammo":30,"reserve":90,"reload":0.0,"alive":true}
	B.reset(s)
	s.bipod_support=.47
	s.shot_age=[0.0,.04,.12,.17,.27,3.0][variant%6]
	s.bloom=.02;s.burst=9;s.aim_time=.23;s.motion_inaccuracy=.11
	match variant:
		0:pass
		1:s.kick_velocity=Vector2(.02,-.05)
		2:s.kick_angle=Vector2(1e-12,0)
		3:s.recoil_target=Vector2(0,1e-12)
		4:s.kick_angle=Vector2(-1e-8,1e-8);s.kick_velocity=Vector2(.03,-.07)
		5:s.velocity=Vector2(.119,0)
		6:s.velocity=Vector2(.12,0)
		7:s.velocity=Vector2(.121,0)
		8:s.grounded=false
		9:s.vault={"phase":.2}
		10:s.ladder={"id":"test"}
		11:s.mounted=0
		12:s.reload=2.0
		13:s.alive=false
		14:s.stance=2;s.stance_blend=1.94
		15:s.stance=2;s.stance_blend=1.95
		16:s.stance=2;s.stance_blend=2.0
		17:s.velocity=Vector2(3.5,1.2)
		18:s.aiming=true;s.aim_time=3.0
		19:s.handling_weapon="wrong-weapon"
	if variant>=5:s.kick_angle=Vector2(.027,.004);s.recoil_target=Vector2(.041,.006);s.kick_velocity=Vector2(.12,-.04)
	return s
func instrument(source: String,is_candidate: bool):
	var script=GDScript.new()
	source=source.replace('static var profiles:', 'static var profile_calls=0\nstatic var brace_calls=0\nstatic var follow_work_calls=0\nstatic var profiles:')
	source=source.replace('static func profile(w: Dictionary) -> Dictionary:\n','static func profile(w: Dictionary) -> Dictionary:\n\tprofile_calls+=1\n')
	var signature='static func _braced(p: Dictionary,u: Dictionary) -> bool:\n' if is_candidate else 'static func braced(w: Dictionary,u: Dictionary) -> bool:\n'
	source=source.replace(signature,signature+'\tbrace_calls+=1\n')
	source=source.replace('\tvar omega=55.0;var error=','\tfollow_work_calls+=1\n\tvar omega=55.0;var error=')
	script.source_code=source
	check(script.reload()==OK,"instrumentation compiles")
	return script
func bench(implementation,weapons: Array,mixed: bool) -> float:
	var states=[];var entries=[]
	for w in weapons:
		for variant in range(20 if mixed else 1):
			var item=state(variant)
			if not mixed:implementation.reset(item)
			item.handling_weapon=implementation.profile(w).id
			states.append(item);entries.append(w)
	var started=Time.get_ticks_usec()
	for iteration in range(25 if mixed else 500):
		for i in range(states.size()):implementation.tick(states[i],entries[i],1.0/60)
	return float(Time.get_ticks_usec()-started)/1000.0
func _initialize():run.call_deferred()
func run():
	check(FileAccess.get_sha256("res://qa/fixtures/weapon_handling_topdown_baseline.gd")==BASELINE_SHA256,"frozen post-gameplay baseline SHA256")
	var catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/original/catalog.json"));F.bind_mounted(catalog)
	var all: Array=catalog.weapons.duplicate(true)
	for vehicle in catalog.vehicles.values():all.append_array(vehicle.weapons.values())
	all.append_array(catalog.emplacements.values())
	check(all.size()==101,"101 actual profiles")
	for w in all:
		check(H.profile(w)==B.profile(w),"profile unchanged "+str(w.get("id",w.get("mounted_fire_key",""))))
		for variant in range(20):
			for dt in [0.0,.001,1.0/120,1.0/60,1.0/30,.23]:
				var a=state(variant);var b=a.duplicate(true)
				if variant!=19:a.handling_weapon=B.profile(w).id;b.handling_weapon=H.profile(w).id
				check(not is_same(a,b) and not is_same(a.vault,b.vault),"independent state dictionaries")
				for step in range(6):
					B.tick(a,w,dt);H.tick(b,w,dt)
					check(a==b,"strict whole state equality %s v%d dt%.9f step%d"%[B.profile(w).id,variant,dt,step])
					check(B.support(w,a)==H.support(w,b),"support equality")
					if step==1:
						B.fired(a,w,a,.37);H.fired(b,w,b,.37)
						check(a==b,"fired state equality")
					if step==2:
						a.velocity=Vector2(.5,0);b.velocity=a.velocity
					if step==3:
						a.grounded=false;b.grounded=false
				check(B.aim_spread(w,a,a)==H.aim_spread(w,b,b),"spread equality")
				check(B.offset(w,a,3.4)==H.offset(w,b,3.4),"pose offset equality")
	var baseline=instrument(FileAccess.get_file_as_string("res://qa/fixtures/weapon_handling_topdown_baseline.gd"),false)
	var candidate=instrument(FileAccess.get_file_as_string("res://scripts/weapon_handling.gd"),true)
	for tiny in [0.0,1e-12,-1e-12]:
		for velocity in [Vector2.ZERO,Vector2(.03,.04)]:
			var a=state(0);a.kick_angle=Vector2(tiny,0);a.kick_velocity=velocity
			var b=a.duplicate(true)
			baseline.follow_work_calls=0;candidate.follow_work_calls=0
			baseline._follow_target(a,.016);candidate._follow_target(b,.016)
			check(a==b,"exact-zero/tiny/velocity-only direct spring state equality")
			var idle=tiny==0 and velocity==Vector2.ZERO
			check(baseline.follow_work_calls==1 and candidate.follow_work_calls==(0 if idle else 1),"only exact rest skips spring arithmetic")
	var reference_calls=0;var reference_braces=0
	for w in all:
		for variant in range(20):
			var a=state(variant);var b=a.duplicate(true)
			baseline.profile_calls=0;baseline.brace_calls=0;candidate.profile_calls=0;candidate.brace_calls=0
			baseline.tick(a,w,1.0/60);candidate.tick(b,w,1.0/60)
			check(candidate.profile_calls==1 and candidate.brace_calls==1,"one profile and eligibility per tick")
			check(a==b,"instrumented equality")
			reference_calls+=baseline.profile_calls;reference_braces+=baseline.brace_calls
	# Alternate ordering after warmup; timings cover tick only, not fixture setup.
	for mixed in [false,true]:
		bench(B,all,mixed);bench(H,all,mixed)
		var before=[];var after=[]
		for repetition in range(5):
			if repetition%2==0:before.append(bench(B,all,mixed));after.append(bench(H,all,mixed))
			else:after.append(bench(H,all,mixed));before.append(bench(B,all,mixed))
		before.sort();after.sort()
		print("HANDLING_BENCH mode=%s ticks=50500 baseline_median_ms=%.3f candidate_median_ms=%.3f change_pct=%.2f baseline_samples=%s candidate_samples=%s"%["mixed" if mixed else "idle",before[2],after[2],(after[2]/before[2]-1)*100,str(before),str(after)])
	print("HANDLING_CPU checks=%d failures=%d profiles=%d tick_pairs=%d baseline_profile_calls=%d candidate_profile_calls=%d baseline_braces=%d candidate_braces=%d"%[checks,failures,all.size(),101*20*6*6,reference_calls,101*20,reference_braces,101*20])
	quit(1 if failures else 0)
