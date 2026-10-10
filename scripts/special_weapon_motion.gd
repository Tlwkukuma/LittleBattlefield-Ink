extends RefCounted
const Melee=preload("res://scripts/melee_action.gd")
const Reaction=preload("res://scripts/combat_reaction.gd")
const Profile=preload("res://scripts/weapon_profile.gd")
const Handling=preload("res://scripts/weapon_handling.gd")

static func grip(view: Dictionary,side: String,point: Vector3,hand_basis: Basis,frame: Basis,motion):
	var rig: Skeleton3D=view.skeleton;var bone=rig.find_bone(side+"_Hand")
	var shoulder=rig.to_global(rig.get_bone_global_pose(rig.find_bone(side+"_Upperarm")).origin)
	motion.adjust_arm(view,side,point-hand_basis*Vector3(0,.035,0),shoulder+frame*Vector3(-.40 if side=="L" else .40,-.23,.08))
	var pose=rig.get_bone_global_pose(bone);pose.basis=rig.global_basis.inverse()*hand_basis;rig.set_bone_global_pose(bone,pose)

static func source_slash(view: Dictionary,t: float,weight: float):
	if weight<.001:return
	var rig: Skeleton3D=view.skeleton;var before=[]
	for i in range(rig.get_bone_count()):before.append(rig.get_bone_pose(i))
	# Source clip contains a long lead-in/out. Use its actual 25..57 strike section,
	# without importing the clip's root translation, crouch or foot placement.
	var reference=Reaction.clip_pose(view,"slash",25)
	var cursor=lerpf(25,57,t);var a=Reaction.clip_pose(view,"slash",floori(cursor));var b=Reaction.clip_pose(view,"slash",mini(57,ceili(cursor)))
	for i in range(before.size()):rig.set_bone_pose(i,before[i])
	if a.is_empty() or b.is_empty():return
	for i in range(before.size()):
		var name=rig.get_bone_name(i)
		if not (name.begins_with("Spine") or "Clavicle" in name or "Upperarm" in name or "Forearm" in name):continue
		var q=a[i].basis.get_rotation_quaternion().slerp(b[i].basis.get_rotation_quaternion(),fposmod(cursor,1))
		var change=reference[i].basis.get_rotation_quaternion().inverse()*q
		var pose: Transform3D=before[i];pose.basis=pose.basis*Basis(Quaternion.IDENTITY.slerp(change,weight));rig.set_bone_pose(i,pose)

static func melee(view: Dictionary,u: Dictionary,motion):
	var rig: Skeleton3D=view.skeleton;var w: Dictionary=view.weapon_profile;var action: Dictionary=u.get("melee",{})
	var frame=Basis(Vector3.UP,atan2(-u.facing.x,-u.facing.y));var p=Melee.profile(w)
	var sample=Melee.sample(w,float(action.age)) if not action.is_empty() else Melee.sample(w,100)
	source_slash(view,sample.phase,sample.weight*(.18 if p.kind=="stab" else .38))
	var right_bone=rig.find_bone("R_Hand");var right=rig.global_transform*rig.get_bone_global_pose(right_bone)
	var left=rig.global_transform*rig.get_bone_global_pose(rig.find_bone("L_Hand"))
	var shoulder=rig.to_global(rig.get_bone_global_pose(rig.find_bone("R_Upperarm")).origin)
	var rest=Vector3(.06,-.23,-.22);var wind=Vector3(.16,-.10,-.05);var strike=Vector3(.01,-.12,-.49)
	var rest_angles=Vector3(.12,0,0);var wind_angles=Vector3(.35,-.20,-.10);var strike_angles=Vector3(-.10,.12,.05)
	if p.kind=="chop":
		rest=Vector3(-.02,-.23,-.28);wind=Vector3(.025,.09,-.16);strike=Vector3(-.10,-.30,-.43)
		rest_angles=Vector3(.35,-.15,0);wind_angles=Vector3(1.02,-.22,-.12);strike_angles=Vector3(-.48,.20,.06)
	elif p.kind=="slash":
		rest=Vector3(-.015,-.22,-.28);wind=Vector3(.16,-.08,-.14);strike=Vector3(-.15,-.20,-.39)
		rest_angles=Vector3(.18,-.12,0);wind_angles=Vector3(.35,-.93,-.18);strike_angles=Vector3(-.08,.95,.14)
	var at=rest.lerp(wind,sample.wind).lerp(strike,sample.strike).lerp(rest,sample.recover)
	var angles=rest_angles.lerp(wind_angles,sample.wind).lerp(strike_angles,sample.strike).lerp(rest_angles,sample.recover)
	if not action.is_empty():angles.x+=clampf(atan2(action.height-(u.elevation+1.0),float(w.range)/40),-.45,.35)*sample.weight
	if u.stance==2:at.y=maxf(-.06,at.y);angles.x=clampf(angles.x,-.15,.42)
	var rotation=frame*Basis.from_euler(angles);var hand_basis=rotation*frame.inverse()*right.basis
	grip(view,"R",shoulder+frame*at,hand_basis,frame,motion)
	var palm=rig.to_global(rig.get_bone_global_pose(right_bone).origin)+hand_basis*Vector3(0,.035,0)
	view.rifle.global_basis=rotation*Basis.from_scale(view.weapon_scale)
	view.rifle.global_position=palm-view.rifle.global_basis*(Vector3(0,0,.045)*view.held.scale)
	var left_shoulder=rig.to_global(rig.get_bone_global_pose(rig.find_bone("L_Upperarm")).origin)
	var guard=left_shoulder+frame*Vector3(-.02,-.18,-.24)
	var left_point=guard if p.kind=="stab" else view.held.to_global(Vector3(0,0,.16))
	grip(view,"L",left_point,rotation*frame.inverse()*left.basis if p.kind!="stab" else left.basis,frame,motion)
	view.muzzle.hide()

static func launcher(view: Dictionary,u: Dictionary,time: float,motion):
	var rig: Skeleton3D=view.skeleton;var w: Dictionary=view.weapon_profile;var p=Profile.get_profile(w)
	var frame=Basis(Vector3.UP,atan2(-u.facing.x,-u.facing.y));var mortar=w.kind=="mortar";var shoulder_weapon=w.kind=="rocket"
	var right=rig.global_transform*rig.get_bone_global_pose(rig.find_bone("R_Hand"));var left=rig.global_transform*rig.get_bone_global_pose(rig.find_bone("L_Hand"))
	var shoulder=rig.to_global(rig.get_bone_global_pose(rig.find_bone("R_Upperarm")).origin)
	var elapsed=maxf(0,time-float(u.get("last_shot",-100)))
	var kick=sin(clampf(elapsed/.055,0,1)*PI*.5)*exp(-elapsed/.13)
	var reload_phase=clampf(1-float(u.reload)/maxf(.05,float(u.get("reload_duration",w.reload))),0,1)
	# Keep the firing pose through the short launch impulse even with auto-reload.
	var load=smoothstep(.10,.22,reload_phase)*(1-smoothstep(.84,1,reload_phase)) if u.reload>0 else 0.0
	var anchor=shoulder+frame*Vector3(.035,.075,-.11) if shoulder_weapon else right.origin+right.basis*Vector3(0,.035,0)
	if u.stance==2:anchor=view.root.global_position+frame*Vector3(.10,.34 if shoulder_weapon else .26,-.49)
	var target2: Vector2=u.get("aim_point",u.position+u.facing*20)
	var target=Vector3(target2.x,float(u.aim_height) if u.get("aim_valid",false) else anchor.y,target2.y)
	var local=frame.inverse()*(target-anchor);local.z=minf(local.z,-.7);local.x=clampf(local.x,-absf(local.z)*.45,absf(local.z)*.45)
	local.y=clampf(local.y,-absf(local.z)*1.2,absf(local.z)*1.4)
	var basis=Basis.looking_at((frame*local).normalized(),Vector3.UP)
	if mortar:basis=frame*Basis(Vector3.RIGHT,-.60 if u.stance==2 else 0.0)
	var recoil=Handling.offset(w,u,time)
	basis=basis*Basis(Vector3.UP,-recoil.x)*Basis(Vector3.RIGHT,recoil.y)
	if not mortar:basis=basis*Basis(Vector3.FORWARD,load*-.28)*Basis(Vector3.RIGHT,load*.18+kick*(.014 if shoulder_weapon else .045))
	view.rifle.global_basis=basis*Basis.from_scale(view.weapon_scale)
	var anchor_local=Vector3(0,0,.06) if shoulder_weapon else p.grip*view.held.scale
	view.rifle.global_position=anchor-view.rifle.global_basis*anchor_local+frame*Vector3(0,-load*.10,kick*(.025 if shoulder_weapon else .055))
	if mortar:
		var carry=anchor+frame*Vector3(-.10,-.20,-.10)
		view.rifle.global_position=carry.lerp(view.root.global_position+frame*Vector3(.10,.23,.02),float(view.get("mortar_deploy",0)))
		if u.stance==2:view.rifle.global_position=view.root.global_position+frame*Vector3(.10,.20,-.12)
	var right_point=view.held.to_global(p.grip);var left_point=view.held.to_global(p.support)
	var reach=smoothstep(.18,.33,reload_phase)*(1-smoothstep(.42,.57,reload_phase))*load
	var insert=smoothstep(.39,.59,reload_phase)*(1-smoothstep(.73,.87,reload_phase))*load
	var feed=Vector3(0,.04,-.53) if w.id=="rpg" else Vector3(-.06,.02,.30) if shoulder_weapon else Vector3(0,.06,.03)
	if mortar:feed=view.muzzle_socket.position+Vector3(0,.08,0)
	left_point=left_point.lerp(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin)+frame*Vector3(-.12,.10,-.10),reach)
	left_point=left_point.lerp(view.held.to_global(feed),insert)
	var rotation_delta=basis*frame.inverse();var left_basis=rotation_delta*left.basis
	grip(view,"R",right_point,rotation_delta*right.basis,frame,motion);grip(view,"L",left_point,left_basis,frame,motion)
	var round=view.held.get_node_or_null("ReloadRound")
	if round!=null:
		round.visible=u.reload>0 and reload_phase>.30 and reload_phase<.73
		var palm=rig.to_global(rig.get_bone_global_pose(rig.find_bone("L_Hand")).origin)+left_basis*Vector3(0,.035,0)
		round.global_position=palm;round.global_basis=basis if not mortar else basis*Basis(Vector3.RIGHT,.92)
	view.muzzle.visible=u.flash>0;view.muzzle.scale=Vector3.ONE*lerpf(.5,1.0,clampf(u.flash/maxf(.001,p.flash_time),0,1))
