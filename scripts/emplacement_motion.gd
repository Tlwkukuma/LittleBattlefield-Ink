extends RefCounted
const Profile=preload("res://scripts/emplacement_profile.gd")
const Source=preload("res://scripts/source_rig_motion.gd")
const Style=preload("res://scripts/soldier_style.gd")
const Reaction=preload("res://scripts/combat_reaction.gd")
const Handling=preload("res://scripts/weapon_handling.gd")

static func update_weapon(view: Dictionary,v: Dictionary,time: float) -> void:
	if v.type=="portableMortar":
		preload("res://scripts/portable_mortar_art.gd").update(view,v,time);return
	var response=Profile.response(v,time)
	view.root.position=Vector3(v.position.x,float(v.get("elevation",0)),v.position.y)
	view.body.rotation.y=-v.angle-PI*.5
	view.turret.rotation=Vector3(0,-v.turret_angle-PI*.5,.09 if v.destroyed else 0.0)
	view.barrel.position.z=response.slide
	view.barrel.rotation.x=.16 if v.destroyed else 0.0
	if view.has("elevation"):
		var elevation=0.0
		if v.has("aim_target") and not v.destroyed:
			var target: Vector3=view.turret.to_local(v.aim_target)-view.elevation.position
			elevation=clampf(atan2(target.y,maxf(.15,-target.z)),deg_to_rad(-35),deg_to_rad(60))
		var kick=Handling.offset(v.profile,v.states.primary,time)
		view.elevation.basis=Basis(Vector3.UP,-kick.x)*Basis(Vector3.RIGHT,elevation+kick.y)
		v.gun_pitch=elevation+kick.y
	view.muzzle.visible=v.flash>0 and not v.destroyed
	var phase: float=response.reload
	var opening=smoothstep(.08,.20,phase)*(1.0-smoothstep(.72,.87,phase)) if response.loading and not v.destroyed else 0.0
	if response.cannon:
		view.mechanism.position.y=1.16-.20*opening
		var insert=smoothstep(.42,.68,phase)
		view.loading_round.visible=response.loading and phase>.27 and phase<.70 and not v.destroyed
		view.loading_round.position=Vector3(-.43,1.09,.73).lerp(Vector3(-.07,1.16,.66),insert)
		view.reload_right.position=view.loading_round.position+Vector3(-.015,0,.035)
	else:
		view.mechanism.rotation.x=-1.22*opening

static func foot_targets(view: Dictionary,frame: Basis,delta: float,mount_id: int) -> Array:
	var homes: Array=[]
	for side in range(2):
		var offset=Vector3(-.18 if side==0 else .18,.14,-.06 if side==0 else .13)
		homes.append(view.root.global_position+frame*offset)
	if view.get("operator_mount",-1)!=mount_id:
		view.operator_mount=mount_id;view.operator_feet=homes.duplicate();view.operator_step=-1;view.operator_step_age=0.0
	var targets: Array=view.operator_feet
	var stepping: int=view.operator_step
	if stepping<0:
		var left: float=targets[0].distance_to(homes[0]);var right: float=targets[1].distance_to(homes[1])
		if maxf(left,right)>.145:
			stepping=0 if left>right else 1
			view.operator_step=stepping;view.operator_step_from=targets[stepping];view.operator_step_to=homes[stepping];view.operator_step_age=0.0
	if stepping>=0:
		view.operator_step_age+=delta
		var t=clampf(float(view.operator_step_age)/.19,0,1)
		targets[stepping]=view.operator_step_from.lerp(view.operator_step_to,smoothstep(0,1,t))+Vector3.UP*sin(t*PI)*.065
		if t>=1.0:view.operator_step=-1
	return targets

static func update_operator(view: Dictionary,u: Dictionary,mount_view: Dictionary,v: Dictionary,delta: float,time: float) -> void:
	var response=Profile.response(v,time)
	var yaw: float=-v.turret_angle-PI*.5
	var frame=Basis(Vector3.UP,yaw)
	var rig: Skeleton3D=view.skeleton
	view.root.position=Vector3(u.position.x,float(u.get("elevation",0)),u.position.y)
	view.root.show();view.body.position=Vector3.ZERO;view.body.rotation=Vector3(0,yaw,0);view.body_yaw=yaw
	view.held.hide();view.muzzle.hide();view.helmet.visible=not u.get("helmet_lost",false)
	Source.sample(view,"Rifle_idle",float(view.source_info.clips.idle.start)/24.0)
	var feet=foot_targets(view,frame,delta,int(v.id))
	var axis=(rig.global_basis.inverse()*frame*Vector3.RIGHT).normalized()
	var up=(rig.global_basis.inverse()*Vector3.UP).normalized()
	var roll_axis=(rig.global_basis.inverse()*frame*Vector3.FORWARD).normalized()
	# Square the shoulders: the source rifle pose has a diagonal shoulder line.
	var left=rig.to_global(rig.get_bone_global_pose(rig.find_bone("L_Upperarm")).origin)
	var right=rig.to_global(rig.get_bone_global_pose(rig.find_bone("R_Upperarm")).origin)
	var shoulder_line=frame.inverse()*(right-left)
	Source.global_rotation(rig,rig.find_bone("Spine01"),Quaternion(up,atan2(shoulder_line.z,shoulder_line.x)))
	var phase: float=response.reload
	var loading=smoothstep(.12,.28,phase)*(1.0-smoothstep(.75,.94,phase)) if response.loading else 0.0
	var recoil: float=response.body
	if v.type=="hmg":recoil*=.45
	var cannon: bool=response.cannon
	var mortar: bool=v.type=="portableMortar"
	var pelvis=rig.get_bone_global_pose(view.bone_indices.Hip)
	var shift=Vector3(.18*loading if cannon else 0.0,-(.095 if cannon else .06)-recoil*(.046 if cannon else .014)-loading*.025,
			recoil*(.060 if cannon else .014)-loading*(.08 if cannon else .13))
	shift.y+=sin(time*2.1)*.002
	if mortar:shift=Vector3(0,-.36-recoil*.018,-loading*.025)
	pelvis.origin+=rig.global_basis.inverse()*frame*shift
	rig.set_bone_global_pose(view.bone_indices.Hip,pelvis)
	var lean=(-.13 if cannon else -.10)+recoil*(.25 if cannon else .065)-loading*.10
	if mortar:lean=-.16+recoil*.12-loading*.06
	Source.global_rotation(rig,rig.find_bone("Spine01"),Quaternion(axis,lean*.65))
	Source.global_rotation(rig,view.bone_indices.Spine02,Quaternion(axis,lean*.35))
	Source.global_rotation(rig,view.bone_indices.Spine02,Quaternion(roll_axis,recoil*(-.045 if cannon else sin(float(v.get("shot_sequence",0))*1.7)*.017)))
	Source.global_rotation(rig,view.bone_indices.Head,Quaternion(axis,-lean*.38))
	for side in range(2):
		var name="L" if side==0 else "R"
		var pole=view.root.global_position+frame*Vector3(-.22 if side==0 else .22,.40,-.70)
		Source.adjust_leg(view,name,rig.to_local(feet[side]),pole,true)
	var chest=rig.to_global(rig.get_bone_global_pose(view.bone_indices.Spine02).origin)
	view.operator_contacts={"hands":[],"feet":feet.duplicate()}
	for side in range(2):
		var grip: Vector3=mount_view.grips[side].global_position
		var target=grip
		if response.loading:
			var reach=smoothstep(.18,.36,phase)*(1.0-smoothstep(.73,.91,phase))
			if cannon and side==0:reach=0.0
			target=target.lerp(mount_view.reload_left.global_position if side==0 else mount_view.reload_right.global_position,reach)
		if cannon and side==1:
			# Momentarily release the trigger and absorb the report, then return to it.
			var release=Profile.pulse(response.age-.045,.07,.52)
			target+=frame*Vector3(-.04,.04,.07)*release
		var pole=chest+frame*Vector3(-.52 if side==0 else .52,-.18,.10)
		Source.adjust_arm(view,"L" if side==0 else "R",target,pole)
		view.operator_contacts.hands.append(target)
	Reaction.apply(view,u)
	u.hit_shapes=Source.hit_shapes(view)
	preload("res://scripts/combat_pose.gd").capture(u,view)
	Style.update_shadow(view)
	# This path bypasses SoldierMotion.update(). Publish the finished IK pose so
	# the crowd palette cannot retain the previous walking clip's root travel.
	view.render_pose_revision=int(view.get("render_pose_revision",0))+1

static func release(view: Dictionary) -> void:
	if not view.has("operator_mount"):return
	view.locomotion_pose=[]
	for i in range(view.skeleton.get_bone_count()):view.locomotion_pose.append(view.skeleton.get_bone_pose(i))
	view.source_clip=""
	for key in ["operator_mount","operator_feet","operator_step","operator_step_age","operator_contacts"]:view.erase(key)
