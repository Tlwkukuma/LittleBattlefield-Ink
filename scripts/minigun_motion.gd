extends RefCounted
## Hip-supported carry on the supplied skeleton; no rifle shoulder/wrist anchor.
const Profile=preload("res://scripts/weapon_profile.gd")
const Handling=preload("res://scripts/weapon_handling.gd")
const Feedback=preload("res://scripts/combat_feedback_profile.gd")

static func palm_frame(side: String) -> Basis:
	# Y is wrist-to-fingers on this source rig. Left palm closes over the bridge;
	# right fingers point down the rear grip, independently of the rifle clip.
	var fingers=Vector3(.80,-.48,-.32).normalized() if side=="L" else Vector3(-.12,-.93,-.35).normalized()
	var palm=Vector3.DOWN if side=="L" else Vector3.LEFT
	var across=fingers.cross(palm).normalized()
	return Basis(across,fingers,across.cross(fingers).normalized())

static func fit_origin(desired: Vector3,basis: Basis,scale: Vector3,arms: Array) -> Vector3:
	var at=desired
	# Project the common gun origin into BOTH wrist reach spheres. Moving the
	# complete gun preserves grip contacts; independently clamping wrists did not.
	for _pass in range(6):
		for arm in arms:
			var hand=basis*arm.local_basis
			var offset=basis*(arm.contact*scale)-hand*Vector3(0,.035,0)
			var center: Vector3=arm.shoulder-offset
			var delta=at-center
			if delta.length()>arm.reach:at=center+delta.normalized()*arm.reach
	return at

static func pose(view: Dictionary,u: Dictionary,time: float,motion):
	var rig: Skeleton3D=view.skeleton;var w: Dictionary=view.weapon_profile;var p=Profile.get_profile(w)
	var frame=Basis(Vector3.UP,atan2(-u.facing.x,-u.facing.y))
	var prone=clampf(float(u.get("stance_blend",0))-1,0,1)
	var age=maxf(0,time-float(u.get("last_shot",-100)));var kick=Feedback.pulse(age,.018,.16)
	var firing=(1-smoothstep(.10,.40,age)) if u.get("vault",{}).is_empty() else 0.0
	var lean=(.045+.025*firing)*(1-prone)
	var axis=(rig.global_basis.inverse()*frame.x).normalized()
	motion.global_rotation(rig,rig.find_bone("Spine01"),Quaternion(axis,-lean))
	motion.global_rotation(rig,view.bone_indices.Head,Quaternion(axis,lean*.50))
	var hip=rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin)
	var origin=hip+frame*Vector3(.10,.19,-.44)
	origin=origin.lerp(view.root.global_position+frame*Vector3(.04,.32,-.89),prone)
	origin+=frame*Vector3(0,-kick*.004,kick*.022)
	var arms=[]
	for side in ["L","R"]:
		var shoulder=rig.global_transform*rig.get_bone_global_pose(rig.find_bone(side+"_Upperarm"))
		var elbow=rig.global_transform*rig.get_bone_global_pose(rig.find_bone(side+"_Forearm"))
		var hand=rig.global_transform*rig.get_bone_global_pose(rig.find_bone(side+"_Hand"))
		arms.append({"side":side,"shoulder":shoulder.origin,"reach":(shoulder.origin.distance_to(elbow.origin)+elbow.origin.distance_to(hand.origin))*.945,
			"local_basis":palm_frame(side)*Basis.from_scale(hand.basis.get_scale()),"contact":p.support if side=="L" else p.grip})
	var point: Vector2=u.get("aim_point",u.position+u.facing*20)
	var height=float(u.get("aim_height",origin.y));var valid=bool(u.get("aim_valid",false)) or height>=0
	var target=Vector3(point.x,height if valid else origin.y,point.y)
	var recoil=Handling.offset(w,u,time)
	if not u.get("vault",{}).is_empty():recoil=Vector2.ZERO
	var phase=clampf(1-float(u.reload)/maxf(.05,float(u.get("reload_duration",w.reload))),0,1)
	var loading=smoothstep(0,.16,phase)*(1-smoothstep(.85,1,phase)) if u.reload>0 else 0.0
	var basis=frame;var scale: Vector3=view.held.scale*view.weapon_scale
	for _pass in range(2):
		var lateral=basis*Vector3(0,view.muzzle_socket.position.y*scale.y,0)
		var local=frame.inverse()*(target-origin-lateral)
		local.z=minf(local.z,-.70);local.x=clampf(local.x,-absf(local.z)*.55,absf(local.z)*.55)
		basis=Basis.looking_at((frame*local).normalized(),Vector3.UP)*Basis(Vector3.UP,-recoil.x)*Basis(Vector3.RIGHT,recoil.y)
		basis=basis*Basis(Vector3.FORWARD,-loading*.08)
		origin=fit_origin(origin,basis,scale,arms)
	view.rifle.global_basis=basis*Basis.from_scale(view.weapon_scale)
	view.rifle.global_position=origin
	for arm in arms:
		var side: String=arm.side;var hand_basis: Basis=basis*arm.local_basis
		var contact: Vector3=view.held.to_global(arm.contact)
		if side=="L" and loading>0:
			var retrieve=smoothstep(.15,.30,phase)*(1-smoothstep(.38,.54,phase))*loading
			var insert=smoothstep(.38,.58,phase)*(1-smoothstep(.75,.92,phase))*loading
			contact=contact.lerp(hip+frame*Vector3(-.27,.11,-.08),retrieve)
			contact=contact.lerp(view.held.to_global(view.held.get_meta("magazine_at")),insert)
		var pole: Vector3=arm.shoulder+frame*Vector3(-.30 if side=="L" else .30,-.32,.045)
		if prone>.001:pole=pole.lerp(view.root.global_position+frame*Vector3(-.34 if side=="L" else .34,.09,-.49),prone)
		motion.adjust_arm(view,side,contact-hand_basis*Vector3(0,.035,0),pole)
		var bone=rig.find_bone(side+"_Hand");var hand=rig.get_bone_global_pose(bone)
		hand.basis=rig.global_basis.inverse()*hand_basis;rig.set_bone_global_pose(bone,hand)
	view.muzzle.visible=u.flash>0 and p.flash_length>0
	view.muzzle.rotation.z=float(u.shot_index)*2.4
	view.muzzle.scale=Vector3.ONE*lerpf(.55,1.15,clampf(float(u.flash)/maxf(.001,p.flash_time),0,1))
	preload("res://scripts/minigun_visual.gd").align_flash(view,u)
