extends SceneTree
## Frozen mathematical handling and source-wiring contract; no battle simulation.
const H=preload("res://scripts/weapon_handling.gd")
const F=preload("res://scripts/weapon_fire_control.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;printerr("FAIL "+label)
func state() -> Dictionary:
	var s={"stance":0,"stance_blend":0.0,"grounded":true,"velocity":Vector2.ZERO,"mounted":-1,"aiming":false,"vault":{},"ladder":{},"ammo":30,"reserve":90,"reload":0.0,"alive":true}
	H.reset(s);return s
func advance(s: Dictionary,w: Dictionary,seconds: float,hz: float):
	var left=seconds
	while left>1e-10:
		var dt=minf(left,1.0/hz);H.tick(s,w,dt);left-=dt
func _initialize():run.call_deferred()
func run():
	var catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/original/catalog.json"))
	F.bind_mounted(catalog)
	var all: Array=catalog.weapons.duplicate(true)
	for v in catalog.vehicles.values():all.append_array(v.weapons.values())
	all.append_array(catalog.emplacements.values())
	check(all.size()==101,"101 source carried/mounted profiles")
	var direct=0;var ids=[];var yaw_values={};var rates={}
	for w in all:
		var p=H.profile(w);var active=not w.has("mounted_fire_key") and w.kind in ["bullet","hitscan","shotgun"]
		check(p.topdown==active,"explicit eligibility "+p.id)
		if not active:
			check(H.vertical_spread(w,.08)==-1.0,"legacy isotropic dispatch "+p.id);continue
		direct+=1;ids.append(p.id);yaw_values[p.yaw]=true;rates[F.rpm(w,{})]=true
		check(p.max_pitch<=.007 and p.max_pitch>=.003,"bounded pitch "+p.id)
		check(p.max_yaw>p.max_pitch,"horizontal dominant "+p.id)
		var s=state();H.tick(s,w,0)
		var last=0.0
		for n in range(24):
			H.fired(s,w,s,sin(n*1.9))
			check(signf(s.recoil_target.x)==p.shoulder_sign,"stable shoulder "+p.id)
			check(absf(s.recoil_target.x)+1e-8>=last,"accumulating burst "+p.id)
			check(s.recoil_target.y<=p.max_pitch+1e-8,"pitch target envelope "+p.id)
			last=absf(s.recoil_target.x)
		check(s.ammo==30 and s.reserve==90,"handling never grants ammo "+p.id)
		var a=s.duplicate(true);var b=s.duplicate(true)
		advance(a,w,.713,30);advance(b,w,.713,120)
		check(Vector2(a.kick_angle).distance_to(b.kick_angle)<.000002,"30/120 exact recovering spring "+p.id)
		check(Vector2(a.recoil_target).distance_to(b.recoil_target)<.000002,"30/120 split recovery target "+p.id)
		check(absf(a.bloom-b.bloom)<.000002,"30/120 bloom boundary "+p.id)
		advance(a,w,4,60)
		check(a.burst==0,"burst ends after release "+p.id)
		check(Vector2(a.kick_angle).length()<.000001,"smooth return "+p.id)
		for elevation in [-.55,0,.55]:
			var forward=Vector3(0,sin(elevation),-cos(elevation))
			var basis=Basis.looking_at(forward,Vector3.UP)
			for azimuth in [0.0,PI*.5,PI,PI*1.5]:
				var spread=.12;var vertical=H.vertical_spread(w,spread)
				var flight=H.cone_direction(forward,spread,azimuth,1.0,vertical)
				var local=basis.inverse()*flight
				check(absf(atan2(local.y,-local.z))<=vertical+.000001,"aim-relative vertical spread "+p.id)
				check(forward.dot(flight)>.98,"keeps elevated aim "+p.id)
				var pellet=H.cone_direction(forward,.14,azimuth,1.0,H.vertical_spread(w,.14,true))
				var local_pellet=basis.inverse()*pellet
				check(absf(atan2(local_pellet.y,-local_pellet.z))<=.006001,"pellet height envelope "+p.id)
		# At zero spread the exact physical muzzle direction must be retained.
		var axis=Vector3(.3,.4,-.8660254).normalized()
		check(H.shot_direction(axis,0,1,.5,0).distance_to(axis)<.000001,"zero spread physical axis "+p.id)
		var prone=state();prone.stance=2;prone.stance_blend=2.0
		H.tick(prone,w,.4)
		check(H.support(w,prone)==(1.0 if p.bipod else 0.0),"prone support "+p.id)
		prone.velocity=Vector2(.2,0)
		check(H.support(w,prone)==0,"moving immediately removes support "+p.id)
		prone.velocity=Vector2.ZERO;prone.grounded=false
		check(H.support(w,prone)==0,"air immediately removes support "+p.id)
		prone.grounded=true;prone.vault={"active":true}
		check(H.support(w,prone)==0,"vault removes support "+p.id)
		var switched=s.duplicate(true);switched.handling_weapon="other"
		H.tick(switched,w,.01)
		check(switched.kick_angle==Vector2.ZERO and switched.burst==0,"weapon switch resets "+p.id)
		H.reset(s)
		check(s.kick_angle==Vector2.ZERO and s.recoil_target==Vector2.ZERO and s.bipod_support==0,"death/reset contract "+p.id)
	check(direct==75,"75 carried direct-fire weapons")
	check(yaw_values.size()>15 and rates.size()>15,"source weapon yaw/rate diversity")
	var rest=state();rest.kick_velocity=Vector2(.2,.3);H._follow_target(rest,.016)
	check(rest.kick_angle!=Vector2.ZERO and rest.kick_velocity!=Vector2.ZERO,"zero angles retain nonzero spring velocity")
	var old_velocity=Vector2(.2,.3);var omega=55.0;var dt=.016
	check(rest.kick_angle==(old_velocity*dt)*exp(-omega*dt),"velocity-only original angle equation")
	check(rest.kick_velocity==(old_velocity-old_velocity*dt*omega)*exp(-omega*dt),"velocity-only original velocity equation")
	var tiny=state();tiny.kick_angle=Vector2(1e-12,0);H._follow_target(tiny,.016)
	check(tiny.kick_angle!=Vector2.ZERO,"tiny nonzero follows original spring")
	var world=FileAccess.get_file_as_string("res://scripts/proving_world.gd")
	check(world.count("Handling.vertical_spread(w,spread)")==1,"axis vertical scaling occurs once")
	check(world.count("Handling.vertical_spread(w,pellet_spread,true)")==1,"pellet vertical scaling occurs once")
	check(world.contains('if resolved.has("forward"):forward3=resolved.forward'),"real posed muzzle feeds shot")
	check(world.contains('state.ammo-=1') and world.contains('projectiles.append(p)') and world.contains('advance_round(p,barrel.length())'),"finite ammo and real projectile/barrel collision retained")
	var rig=FileAccess.get_file_as_string("res://scripts/source_rig_motion.gd")
	check(rig.contains('recoil=Handling.offset(w,u,time)') and rig.contains('gun_basis=gun_basis*Basis(Vector3.UP,-recoil.x)*Basis(Vector3.RIGHT,recoil.y)'),"rig and emission share offset")
	var input=FileAccess.get_file_as_string("res://scripts/proving_ground.gd")
	check(input.contains('if not Handling.is_topdown(world.active_weapon()) and'),"carried mouse compensation removed; special/mounted retained")
	print("TOPDOWN_RECOIL checks=%d failures=%d carried=%d ids=%s"%[checks,failures,direct,','.join(ids)])
	quit(1 if failures else 0)
