extends RefCounted
## Physical weapon channels: each muzzle belongs to its own elevation/recoil assembly.
const Effects=preload("res://scripts/weapon_effects.gd")
const Profile=preload("res://scripts/weapon_profile.gd")
const Handling=preload("res://scripts/weapon_handling.gd")
const Dimensions=preload("res://scripts/vehicle_dimensions.gd")
const Feedback=preload("res://scripts/combat_feedback_profile.gd")

static func node(parent: Node3D,title: String,at: Vector3=Vector3.ZERO) -> Node3D:
	var part=Node3D.new();part.name=title;part.position=at;parent.add_child(part);return part

static func marker(parent: Node3D,title: String,at: Transform3D) -> Marker3D:
	var part=Marker3D.new();part.name=title;part.transform=at;parent.add_child(part);return part

static func channel(parent: Node3D,mode: String,at: Vector3,w: Dictionary,external_cases: bool=false) -> Dictionary:
	var pivot=node(parent,mode+"_Elevation",at)
	var slide=node(pivot,mode+"_Recoil")
	return {"mode":mode,"pivot":pivot,"slide":slide,"weapon":w,"external_cases":external_cases}

static func finish(c: Dictionary,tip: Transform3D,port: Vector3) -> void:
	c.muzzle=marker(c.slide,"MuzzleSocket",tip)
	c.breech=marker(c.pivot,"BreechSocket",Transform3D.IDENTITY)
	c.ejection=marker(c.slide,"EjectionSocket",Transform3D(Basis.IDENTITY,port))
	c.flash=Effects.flash(c.muzzle,c.weapon)
	c.flash.hide()

static func recoil_distance(kind: String,age: float) -> float:
	var stroke=.23 if kind in ["shell","canister"] else .065 if kind=="autocannon" else .040 if kind=="vehicleGrenade" else .018
	var rise=.038 if kind in ["shell","canister"] else .015
	var settle=.62 if kind in ["shell","canister"] else .17 if kind=="autocannon" else .085
	if age<0 or age>rise+settle:return 0.0
	return stroke*sin(age/rise*PI*.5) if age<rise else stroke*(1.0-smoothstep(0,settle,age-rise))

static func update(view: Dictionary,v: Dictionary,time: float,render_pose: Dictionary={}) -> void:
	var wreck_age=maxf(0,time-float(v.get("destroy_time",0)))
	var wreck_pose=[v.position,v.angle,v.turret_angle,float(v.get("elevation",0)),Dimensions.body_basis(v),v.mode,render_pose]
	if v.destroyed and wreck_age>1.8 and view.get("settled_wreck_pose",[])==wreck_pose:return
	if not v.destroyed:view.erase("settled_wreck_pose")
	var scale: Vector3=Dimensions.for_vehicle(v).model_scale
	var body: Basis=render_pose.get("body",Dimensions.body_basis(v))
	view.root.position=render_pose.get("position",Vector3(v.position.x,float(v.get("elevation",0)),v.position.y))
	view.body.basis=body.scaled_local(scale)
	if not render_pose.is_empty() and not v.destroyed:
		var shot: Dictionary=v.profile.weapons[v.modes[v.mode]];var response=Feedback.profile(shot)
		var age=time-float(v.get("shot_time",-100))
		var carry=float(response.body)*Feedback.pulse(age-.025,.055,float(response.settle)+.10)
		var axis=Vector3(-sin(v.turret_angle),0,cos(v.turret_angle))
		view.body.basis=Basis(axis,carry)*view.body.basis
	view.turret.position=body*Dimensions.turret_offset(v)
	view.turret.basis=Basis(render_pose.get("turret",Dimensions.turret_basis(v))).scaled_local(scale)
	var active: String=v.modes[v.mode]
	var visited: Array=[]
	for mode in view.channels:
		var c: Dictionary=view.channels[mode]
		if c.pivot in visited:continue
		visited.append(c.pivot)
		# Cannon and canister share a tube; use the latest shot from either ammunition mode.
		var selected: String=active if view.channels[active].pivot==c.pivot else mode
		var shot_time: float=-100.0
		var fired_weapon: Dictionary=c.weapon
		for alias in view.channels:
			if view.channels[alias].pivot!=c.pivot:continue
			var at=float(v.states[alias].get("shot_time",-100.0))
			if at>shot_time:shot_time=at;fired_weapon=v.profile.weapons[alias]
		var age=time-shot_time
		var response=Feedback.profile(fired_weapon)
		c.slide.position.z=float(response.stroke)*Feedback.pulse(age,.028 if fired_weapon.kind in ["shell","canister"] else .012,float(response.settle))
		var elevation=0.0
		if v.has("aim_target") and not v.destroyed:
			var target: Vector3=c.pivot.get_parent().to_local(v.aim_target)-c.pivot.position
			var roof: bool=v.type in ["armedJeep","apc"]
			elevation=clampf(atan2(target.y,maxf(.15,-target.z)),deg_to_rad(-22 if roof else -12),deg_to_rad(60 if roof else 30))
			if c.weapon.kind=="vehicleMortar":
				var distance=Vector2(v.aim_target.x-c.pivot.global_position.x,v.aim_target.z-c.pivot.global_position.z).length()
				elevation=clampf(atan2(PI*float(c.weapon.get("arcHeight",420))/40.0-c.pivot.global_position.y,maxf(.5,distance)),deg_to_rad(25),deg_to_rad(85))
		elif c.weapon.kind=="vehicleMortar":elevation=deg_to_rad(55)
		var kick: Vector2=Handling.offset(v.profile.weapons[selected],v.states[selected],time)
		c.pivot.basis=Basis(Vector3.UP,-kick.x)*Basis(Vector3.RIGHT,elevation+kick.y)
		if v.destroyed:
			var settle_age=minf(1.8,wreck_age)
			c.pivot.rotation.x=-.29+sin(settle_age*15)*.10*exp(-settle_age*5)
			c.slide.position.z=.10+.10*exp(-settle_age*6)
		c.flash.visible=age>=0 and age<float(Profile.get_profile(fired_weapon).flash_time) and not v.destroyed
	var current: Dictionary=view.channels[active]
	view.muzzle_socket=current.muzzle;view.muzzle=current.flash;view.barrel=current.slide
	view.appearance.sync()
	if v.destroyed and wreck_age>1.8:view.settled_wreck_pose=wreck_pose

static func resolve(view: Dictionary,v: Dictionary,time: float) -> Dictionary:
	update(view,v,time)
	var c: Dictionary=view.channels[v.modes[v.mode]]
	return {"position":c.muzzle.global_position,"forward":-c.muzzle.global_basis.z.normalized(),
		"breech":c.breech.global_position,"ejection":c.ejection.global_position,
		"ejection_node":c.ejection,"ejection_direction":c.ejection.global_basis.x.normalized(),
		"eject_cases":c.external_cases,"posed_recoil":true}
