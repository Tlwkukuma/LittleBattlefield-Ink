extends RefCounted
## Source clips drive locomotion. No procedural leg/ankle overrides while standing or walking.
const Style=preload("res://scripts/soldier_style.gd")
const WeaponProfile=preload("res://scripts/weapon_profile.gd")
const Traversal=preload("res://scripts/soldier_traversal.gd")
const Handling=preload("res://scripts/weapon_handling.gd")
const Reaction=preload("res://scripts/combat_reaction.gd")
const SpecialMotion=preload("res://scripts/special_weapon_motion.gd")
const Medical=preload("res://scripts/medical_motion.gd")
static func sample(view: Dictionary,clip: String,seconds: float,in_place: bool=true):
	view.model.position=Vector3.ZERO
	var player: AnimationPlayer=view.animator
	if player.current_animation!=clip:player.play(clip)
	# advance applies the seek once; seek(update=true) evaluated the same tracks twice.
	player.seek(seconds,false);player.advance(0)
	if in_place:
		var rig: Skeleton3D=view.skeleton
		var hip: Vector3=view.body.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin))
		view.model.position.z=-hip.z

static func global_rotation(rig: Skeleton3D,index: int,rotation: Quaternion):
	if rotation==Quaternion.IDENTITY:return
	var pose=rig.get_bone_global_pose(index);pose.basis=Basis(rotation)*pose.basis;rig.set_bone_global_pose(index,pose)

static func joint(origin: Vector3,target: Vector3,pole: Vector3,a: float,b: float) -> Vector3:
	var axis=(target-origin).normalized();var distance=clampf(origin.distance_to(target),absf(a-b)+.001,a+b-.002);var along=(a*a-b*b+distance*distance)/(2*distance);var perpendicular=(pole-origin)-axis*(pole-origin).dot(axis)
	if perpendicular.length_squared()<.000001:perpendicular=axis.cross(Vector3.UP if absf(axis.y)<.9 else Vector3.RIGHT)
	return origin+axis*along+perpendicular.normalized()*sqrt(maxf(0,a*a-along*along))

static func adjust_leg(view: Dictionary,side: String,target: Vector3,pole_world: Vector3=Vector3.INF,limit_reach: bool=false):
	# Only used for newly added crouch/vault states absent from the supplied FBX.
	var rig: Skeleton3D=view.skeleton;var hip=rig.find_bone(side+"_Thigh");var knee=rig.find_bone(side+"_Calf");var foot=rig.find_bone(side+"_Foot")
	var s=rig.get_bone_global_pose(hip).origin;var e=rig.get_bone_global_pose(knee).origin;var w=rig.get_bone_global_pose(foot).origin;var basis=rig.get_bone_global_pose(foot).basis
	if limit_reach:
		var reach=target-s;var a=(e-s).length();var b=(w-e).length()
		if reach.length_squared()>.000001:target=s+reach.normalized()*clampf(reach.length(),absf(a-b)+.008,(a+b)*.97)
	var forward=rig.global_basis.inverse()*view.body.global_basis*Vector3.FORWARD
	var elbow=joint(s,target,rig.to_local(pole_world) if pole_world.is_finite() else s+forward*2,(e-s).length(),(w-e).length())
	global_rotation(rig,hip,Quaternion((e-s).normalized(),(elbow-s).normalized()))
	var posed_knee=rig.get_bone_global_pose(knee).origin;var posed_foot=rig.get_bone_global_pose(foot).origin
	global_rotation(rig,knee,Quaternion((posed_foot-posed_knee).normalized(),(target-posed_knee).normalized()))
	var foot_pose=rig.get_bone_global_pose(foot);foot_pose.basis=basis;rig.set_bone_global_pose(foot,foot_pose)

static func adjust_arm(view: Dictionary,side: String,world_target: Vector3,pole_world: Vector3=Vector3.INF):
	var rig: Skeleton3D=view.skeleton;var arm=rig.find_bone(side+"_Upperarm");var forearm=rig.find_bone(side+"_Forearm");var hand=rig.find_bone(side+"_Hand")
	var s=rig.get_bone_global_pose(arm).origin;var e=rig.get_bone_global_pose(forearm).origin;var w=rig.get_bone_global_pose(hand).origin;var hand_basis=rig.get_bone_global_pose(hand).basis
	var target=rig.to_local(world_target);var pole=e+(e-(s+w)*.5).normalized()*.25
	if pole_world.is_finite():pole=rig.to_local(pole_world)
	var a=(e-s).length();var b=(w-e).length();var delta=target-s
	if delta.length_squared()<.000001:delta=w-s
	# Clamp the wrist as well as the elbow solve, retaining a small elbow bend.
	target=s+delta.normalized()*clampf(delta.length(),absf(a-b)+.015,(a+b)*.965)
	var bend=joint(s,target,pole,a,b)
	global_rotation(rig,arm,Quaternion((e-s).normalized(),(bend-s).normalized()))
	var elbow=rig.get_bone_global_pose(forearm).origin;var wrist=rig.get_bone_global_pose(hand).origin
	global_rotation(rig,forearm,Quaternion((wrist-elbow).normalized(),(target-elbow).normalized()))
	var pose=rig.get_bone_global_pose(hand);pose.basis=hand_basis;rig.set_bone_global_pose(hand,pose)

static func prone_body(view: Dictionary,u: Dictionary,weight: float,phase: float):
	var rig: Skeleton3D=view.skeleton;var yaw=atan2(-u.facing.x,-u.facing.y);var frame=Basis(Vector3.UP,yaw)
	var moving=clampf(u.velocity.length()/.62,0,1);var crawl=sin(phase)*moving
	var hip=rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin)
	var desired=view.root.global_position+frame*Vector3(0,.235+sin(phase*2)*.008*moving,.04)
	view.body.global_position+=(desired-hip)*weight
	# Arch the upper back independently, keeping the pelvis down and the face forward.
	var axis=(rig.global_basis.inverse()*frame.x).normalized()
	global_rotation(rig,rig.find_bone("Spine01"),Quaternion(axis,.16*weight))
	global_rotation(rig,view.bone_indices.Spine02,Quaternion(axis,.10*weight))
	global_rotation(rig,view.bone_indices.Head,Quaternion(axis,1.15*weight))
	for side in range(2):
		var name="L" if side==0 else "R";var sign_side=-1.0 if side==0 else 1.0;var alternating=crawl*sign_side
		var foot=rig.find_bone(name+"_Foot");var old=rig.to_global(rig.get_bone_global_pose(foot).origin)
		var target=view.root.global_position+frame*Vector3(sign_side*(.29+.035*maxf(0,alternating)),.15+.022*maxf(0,alternating),.55-alternating*.10)
		var knee=view.root.global_position+frame*Vector3(sign_side*(.27+.06*maxf(0,alternating)),.14,.28-alternating*.07)
		adjust_leg(view,name,rig.to_local(old.lerp(target,weight)),knee)
		global_rotation(rig,foot,Quaternion(axis,-1.22*weight))
		global_rotation(rig,foot,Quaternion((rig.global_basis.inverse()*Vector3.UP).normalized(),sign_side*.30*weight))

static func vault_body(view: Dictionary,u: Dictionary,delta: float):
	var path: Dictionary=u.vault;var t=float(u.vault_progress);var rig: Skeleton3D=view.skeleton
	var pose=Traversal.vault_pose(path,t);var timing=Traversal.vault_timing(path)
	var frame=Basis(Vector3.UP,atan2(-path.direction.x,-path.direction.y));var lead=float(path.get("lead",-1.0))
	var axis=(rig.global_basis.inverse()*frame.x).normalized()
	var roll_axis=(rig.global_basis.inverse()*frame.z).normalized()
	var pelvis=rig.get_bone_global_pose(view.bone_indices.Hip)
	pelvis.origin+=rig.global_basis.inverse()*Vector3.DOWN*float(pose.drop)
	rig.set_bone_global_pose(view.bone_indices.Hip,pelvis)
	# Weight shifts onto the supporting side before the leading knee clears the edge.
	global_rotation(rig,view.bone_indices.Hip,Quaternion(roll_axis,-lead*float(pose.roll)))
	global_rotation(rig,rig.find_bone("Spine01"),Quaternion(axis,-float(pose.lean)))
	global_rotation(rig,view.bone_indices.Spine02,Quaternion(axis,-.08*float(pose.compact)))
	global_rotation(rig,view.bone_indices.Head,Quaternion(axis,float(pose.lean)*.65))
	var retreat=0.0;var normal: Vector2=path.normal
	if t<timing.y:
		for part in [[view.bone_indices.Head,.40],[view.bone_indices.Spine02,.34],[view.bone_indices.Hip,.31]]:
			var at=rig.to_global(rig.get_bone_global_pose(part[0]).origin);var radius=float(part[1])
			if at.y-radius<path.height+.04:
				retreat=maxf(retreat,(Vector2(at.x,at.z)-path.hand_point).dot(normal)+radius+.04)
	# Keep required clearance immediately, but release it continuously as the head,
	# jacket and hips pass the ledge. Thresholds used to remove up to 22 cm at once.
	view.vault_retreat=maxf(retreat,lerpf(float(view.get("vault_retreat",0)),retreat,1-exp(-maxf(0,delta)*18)))
	view.body.global_position-=Vector3(normal.x,0,normal.y)*float(view.vault_retreat)
	view.vault_contacts={"hands":[],"feet":[]}
	for side in range(2):
		var name="L" if side==0 else "R";var sign_side=-1.0 if side==0 else 1.0
		var leading=sign_side==lead
		var foot=rig.find_bone(name+"_Foot")
		var start: Vector3=view.vault_entry_feet[side]
		var lift=float(pose.lead_lift if leading else pose.trail_lift)
		var landing=float(pose.lead_land if leading else pose.trail_land)
		var tucked=view.root.global_position+frame*Vector3(sign_side*.23,.18 if leading else .23,-.32 if leading else .14)
		var target=start.lerp(tucked,lift)
		var brace=float(pose.ledge_foot if leading else pose.wall_foot)
		var contact2: Vector2=path.hand_point+path.tangent*sign_side*.20+path.normal*(.14 if leading else -.20)
		var contact=Vector3(contact2.x,path.height+(.18 if leading else -.62),contact2.y)
		target=target.lerp(contact,brace)
		var land_at=Vector3(path.end.x,path.end_height+.14,path.end.y)+frame*Vector3(sign_side*.20,0,-.16 if leading else .12)
		target=target.lerp(land_at,landing)
		# The trailing boot pushes off later; the leading boot reaches the ground first.
		var pole=view.root.global_position+frame*Vector3(sign_side*.40,.48,-.62 if leading else -.30)
		if brace>.001:pole=pole.lerp(contact+frame*Vector3(sign_side*.12,.33,.22),brace)
		var toe_pitch=(1.40*brace if not leading else .15*pose.compact)*(1-landing)
		# Raise the boot before swinging it over the lip. The toe extends well ahead
		# of the ankle on this model, especially with its oversized boots.
		var boot_margin=.13+.22*maxf(0,cos(toe_pitch))
		target=vault_clear_point(path,target,boot_margin,.16)
		pole=vault_clear_point(path,pole,.23,.20)
		# Clearance constraints may release within one frame. Carry the ankle across
		# continuously rather than snapping it from the near face onto the ledge.
		var previous: Vector3=view.vault_foot_targets[side]
		var horizontal=Vector2(previous.x,previous.z).move_toward(Vector2(target.x,target.z),maxf(0,delta)*6.0)
		target.x=horizontal.x;target.z=horizontal.y
		view.vault_foot_targets[side]=target
		adjust_leg(view,name,rig.to_local(target),pole,true)
		var toe=rig.find_bone(name+"_ToeBase")
		var toe_axis=(rig.get_bone_global_pose(toe).origin-rig.get_bone_global_pose(foot).origin).normalized()
		var toe_direction=rig.global_basis.inverse()*(frame*Vector3(0,sin(toe_pitch),-cos(toe_pitch)))
		global_rotation(rig,foot,Quaternion(toe_axis,toe_direction.normalized()))
		view.vault_contacts.feet.append({"target":contact if brace>.5 else land_at,"weight":brace if brace>.5 else landing,"side":name})

static func vault_clear_point(path: Dictionary,at: Vector3,margin: float,top_margin: float) -> Vector3:
	if at.y>=float(path.height)+top_margin:return at
	var depth=(Vector2(at.x,at.z)-Vector2(path.hand_point)).dot(path.normal)
	if depth<=-margin or depth>=float(path.width)+margin:return at
	var to_face=-margin if depth<float(path.width)*.5 else float(path.width)+margin
	return at+Vector3(path.normal.x,0,path.normal.y)*(to_face-depth)

static func vault_hands(view: Dictionary,u: Dictionary):
	var path: Dictionary=u.vault;var t=float(u.vault_progress);var mode=str(path.get("mode","vault"));var rig: Skeleton3D=view.skeleton
	var pose=Traversal.vault_pose(path,t);var frame=Basis(Vector3.UP,atan2(-path.direction.x,-path.direction.y))
	var stow=float(pose.stow);var low=mode=="step"
	var chest=rig.to_global(rig.get_bone_global_pose(view.bone_indices.Spine02).origin)
	var old_gun=view.rifle.global_basis.orthonormalized()
	var carry_basis=frame*Basis(Vector3.RIGHT,-.55 if low else 1.25)*Basis(Vector3.FORWARD,.18 if low else .22)
	var carry_at=chest+frame*Vector3(.25,-.16,-.15) if low else chest+frame*Vector3(.38,-.17,.19)
	var profile=WeaponProfile.get_profile(view.weapon_profile)
	var grip: Vector3=profile.grip*view.held.scale
	var carry=Transform3D(carry_basis*Basis.from_scale(view.weapon_scale),carry_at-carry_basis*(grip*view.weapon_scale))
	view.rifle.global_transform=view.rifle.global_transform.interpolate_with(carry,stow)
	view.muzzle.hide()
	var gun_rotation=view.rifle.global_basis.orthonormalized()*old_gun.inverse()
	for side in range(2):
		var sign_side=-1.0 if side==0 else 1.0;var name="L" if side==0 else "R";var hand=rig.find_bone(name+"_Hand")
		var old=rig.to_global(rig.get_bone_global_pose(hand).origin)
		var hand_world=rig.global_basis*rig.get_bone_global_pose(hand).basis
		# Low obstacles retain the gun in the right hand. Higher obstacles sling it
		# and place the two palms in succession instead of mirrored simultaneous grabs.
		if low and side==1 and not u.get("holstered",false):
			var grip_basis=gun_rotation*hand_world
			var gun_hand=view.held.to_global(profile.grip)-grip_basis*Vector3(0,.035,0)
			adjust_arm(view,name,gun_hand,chest+frame*Vector3(.49,-.23,.14))
			var gun_pose=rig.get_bone_global_pose(hand);gun_pose.basis=rig.global_basis.inverse()*grip_basis;rig.set_bone_global_pose(hand,gun_pose)
			continue
		var delay=.025 if side==1 else 0.0
		var shifted=Traversal.vault_pose(path,clampf(t-delay,0,1))
		var weight=float(shifted.reach)
		var contact2: Vector2=path.hand_point+path.tangent*sign_side*.20+path.normal*.025
		var contact=Vector3(contact2.x,path.height+.055,contact2.y)
		var finger=(frame*Vector3(0,-.10,-1)).normalized()
		var desired=Basis(Quaternion(hand_world.y.normalized(),finger))*hand_world
		var wrist_target=contact-desired*Vector3(0,.035,0)
		var shoulder=rig.to_global(rig.get_bone_global_pose(rig.find_bone(name+"_Upperarm")).origin)
		var elbow=rig.to_global(rig.get_bone_global_pose(rig.find_bone(name+"_Forearm")).origin)
		var reach=shoulder.distance_to(elbow)+elbow.distance_to(old)
		weight*=1-smoothstep(reach*.96,reach*1.08,shoulder.distance_to(wrist_target))
		var recover=chest+frame*Vector3(sign_side*.31,-.17,-.02)
		var free_pole=chest+frame*Vector3(sign_side*.48,-.20,.16)
		var support_pole=contact+frame*Vector3(sign_side*.25,-.25,.20)
		adjust_arm(view,name,old.lerp(recover,stow).lerp(wrist_target,weight),free_pole.lerp(support_pole,weight))
		var hand_pose=rig.get_bone_global_pose(hand);hand_pose.basis=hand_pose.basis.slerp(rig.global_basis.inverse()*desired,weight);rig.set_bone_global_pose(hand,hand_pose)
		view.vault_contacts.hands.append({"target":wrist_target,"weight":weight,"side":name})

static func blend_vault_transition(view: Dictionary,u: Dictionary,delta: float):
	var rig: Skeleton3D=view.skeleton
	var previous: Array=[];var blend=1.0
	var previous_hip=Vector3.ZERO
	if not u.vault.is_empty():
		previous=view.get("vault_entry_pose",[]);blend=smoothstep(0,.12,float(u.vault_progress))
		previous_hip=view.get("vault_entry_hip",Vector3.ZERO)
	elif float(view.get("vault_exit_age",1))<.18:
		view.vault_exit_age+=delta;previous=view.get("vault_exit_pose",[]);blend=smoothstep(0,.18,view.vault_exit_age)
		previous_hip=view.get("vault_exit_hip",Vector3.ZERO)
	if previous.size()!=rig.get_bone_count() or blend>=1:return
	# Source walk/run bones contain metres of root travel, cancelled by model.position
	# in sample(). Blending raw bones without that compensation teleports the mesh.
	# Preserve the visible pelvis in body space, including authored crouch/landing
	# height, while the original bone rotations blend. Physics alone moves the root.
	var target_hip=view.body.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin))
	for i in range(rig.get_bone_count()):rig.set_bone_pose(i,previous[i].interpolate_with(rig.get_bone_pose(i),blend))
	var blended_hip=view.body.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin))
	view.model.position+=previous_hip.lerp(target_hip,blend)-blended_hip

static func pose_weapon(view: Dictionary,u: Dictionary,time: float,reload_seconds: float):
	var w: Dictionary=view.weapon_profile;var p=WeaponProfile.get_profile(w);var rig: Skeleton3D=view.skeleton
	if str(w.id)=="minigun":preload("res://scripts/minigun_visual.gd").pose(view.held,u,time)
	var prone=clampf(float(u.get("stance_blend",0))-1,0,1)
	if not view.get("weapon_world_pose",false):
		view.weapon_scale=view.rifle.global_basis.get_scale();view.rifle.reparent(view.body,true);view.weapon_world_pose=true
	if u.get("holstered",false) or not u.get("healing",{}).is_empty():
		pose_empty_hands(view,u);return
	if w.kind=="grenade":pose_grenade(view,u);return
	if w.kind=="melee":SpecialMotion.melee(view,u,load("res://scripts/source_rig_motion.gd"));return
	if w.kind in ["rocket","grenadeProjectile","mortar"]:SpecialMotion.launcher(view,u,time,load("res://scripts/source_rig_motion.gd"));return
	if str(w.id)=="minigun":preload("res://scripts/minigun_motion.gd").pose(view,u,time,load("res://scripts/source_rig_motion.gd"));return
	var elapsed=maxf(0,time-float(u.get("last_shot",-100)))
	var ready=bool(u.aiming) or elapsed<.7 or prone>.5
	var feedback=preload("res://scripts/combat_feedback_profile.gd").profile(w)
	var kick=preload("res://scripts/combat_feedback_profile.gd").pulse(elapsed,.018,feedback.recover)
	var shoulder_pulse=preload("res://scripts/combat_feedback_profile.gd").pulse(elapsed-.012,.025,feedback.recover+.04)
	var brace=Handling.support(w,u)
	kick*=lerpf(1.0,.35,brace);shoulder_pulse*=lerpf(1.0,.40,brace)
	var handling=Handling.profile(w);var recoil=Handling.offset(w,u,time)
	if not u.get("vault",{}).is_empty():kick=0.0;recoil=Vector2.ZERO;ready=false
	var yaw=atan2(-u.facing.x,-u.facing.y);var aim_basis=Basis(Vector3.UP,yaw)
	var recoil_axis=(rig.global_basis.inverse()*aim_basis.x).normalized()
	global_rotation(rig,view.bone_indices.Spine02,Quaternion(recoil_axis,minf(.09,recoil.y*.55+shoulder_pulse*float(feedback.shoulder)*float(handling.visual))))
	if p.family=="sniper" and ready:
		var lean_axis=(rig.global_basis.inverse()*aim_basis.x).normalized()
		global_rotation(rig,view.bone_indices.Spine02,Quaternion(lean_axis,-.04))
		global_rotation(rig,view.bone_indices.Head,Quaternion(lean_axis,-.08))
	var right=rig.get_bone_global_pose(rig.find_bone("R_Hand"));var left=rig.get_bone_global_pose(rig.find_bone("L_Hand"))
	var hands=[rig.global_transform*left,rig.global_transform*right]
	var source_gun=(rig.global_basis*rig.get_bone_global_pose(view.bone_indices.Spine02).basis*view.weapon_parent.transform.basis).orthonormalized()
	var offset: Vector3=p.offset
	if p.family=="sniper" and not ready:offset+=Vector3(.025,-.12,-.04)
	if p.family=="launcher" and not ready:offset+=Vector3(0,-.08,-.02)
	var anchor: Vector3=hands[1].origin+hands[1].basis*Vector3(0,.035,0)+aim_basis*offset
	if prone>.001:
		var low_grip=Vector3(.13,.285,-.73)
		if p.family=="pistol":low_grip=Vector3(.06,.26,-.79)
		if p.family=="launcher":low_grip=Vector3(.23,.39,-.64)
		anchor=anchor.lerp(view.root.global_position+aim_basis*low_grip,prone)
	var target2: Vector2=u.get("aim_point",u.position+u.facing*30)
	var target_height=float(u.get("aim_height",-1))
	var target=Vector3(target2.x,target_height if u.get("aim_valid",false) or target_height>=0 else anchor.y,target2.y)
	var delta=target-anchor
	# A cursor behind/inside the barrel must not reverse the gun. Preserve selected
	# height first, then derive a forward direction with a small close-range deadzone.
	var local=aim_basis.inverse()*delta
	local.z=minf(local.z,-.55);local.x=clampf(local.x,-absf(local.z)*.55,absf(local.z)*.55)
	var direction=(aim_basis*local).normalized()
	# The gun's -Z axis is the shot axis, independent of the animation's chest sway.
	var gun_basis=Basis.looking_at(direction,Vector3.UP)
	var grip: Vector3=p.grip*view.held.scale
	var muzzle_offset: Vector3=(view.muzzle_socket.position*view.held.scale-grip)*view.weapon_scale
	# Barrel-parallel offsets cannot change aim; correct only the lateral socket
	# offset once. Iterating with the whole barrel length used to flip near targets.
	var lateral=Vector3(muzzle_offset.x,muzzle_offset.y,0)
	var corrected=aim_basis*local-gun_basis*lateral
	if corrected.length_squared()>.01 and corrected.dot(direction)>.05:gun_basis=Basis.looking_at(corrected.normalized(),Vector3.UP)
	if not ready and p.family in ["sniper","launcher"]:gun_basis=gun_basis*Basis(Vector3.RIGHT,-.12)
	gun_basis=gun_basis*Basis(Vector3.UP,-recoil.x)*Basis(Vector3.RIGHT,recoil.y)
	var reload_phase=clampf(1-float(u.reload)/maxf(.05,float(u.get("reload_duration",reload_seconds))),0,1)
	var reload_weight=smoothstep(0,.14,reload_phase)*(1-smoothstep(.84,1,reload_phase)) if u.reload>0 else 0.0
	gun_basis=gun_basis*Basis(Vector3.FORWARD,reload_weight*.38)
	view.rifle.global_basis=gun_basis*Basis.from_scale(view.weapon_scale)
	view.rifle.global_position=anchor+aim_basis*Vector3(0,-reload_weight*.08,kick*p.recoil*float(handling.visual))-view.rifle.global_basis*grip
	var rotation_delta=gun_basis*source_gun.inverse()
	for side in range(2):
		var target_hand: Vector3=view.held.to_global(p.support if side==0 else p.grip)
		var sign_side=-1.0 if side==0 else 1.0
		var shoulder=rig.to_global(rig.get_bone_global_pose(rig.find_bone("L_Upperarm" if side==0 else "R_Upperarm")).origin)
		var elbow_pole=shoulder+aim_basis*Vector3(sign_side*.48,-.34,.12)
		if prone>.001:
			elbow_pole=elbow_pole.lerp(view.root.global_position+aim_basis*Vector3(sign_side*.32,.085,-.43),prone)
			if side==0 and u.velocity.length()>.05 and not u.aiming and elapsed>.35 and u.reload<=0:
				var pull=maxf(0,sin(float(view.get("crawl_phase",0))))*prone
				target_hand=target_hand.lerp(view.root.global_position+aim_basis*Vector3(-.28,.10,-.83+pull*.20),pull*.85)
		if side==0 and reload_weight>0:
			var reach=smoothstep(.12,.30,reload_phase)*(1-smoothstep(.48,.65,reload_phase))
			var insert=smoothstep(.48,.65,reload_phase)*(1-smoothstep(.77,.91,reload_phase))
			target_hand=target_hand.lerp(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin)+aim_basis*Vector3(-.12,.12,-.15),reach)
			target_hand=target_hand.lerp(view.held.to_global(Vector3(0,-.16,0)),insert)
		if side==1 and p.family=="sniper" and str(w.get("mechanics",{}).get("action",""))=="manualBolt" and u.reload<=0:
			var bolt=smoothstep(.16,.27,elapsed)*(1-smoothstep(.55,.78,elapsed))
			target_hand=target_hand.lerp(view.held.to_global(Vector3(.11,.035,.09)),bolt)
		var hand_basis: Basis=rotation_delta*hands[side].basis
		adjust_arm(view,"L" if side==0 else "R",target_hand-hand_basis*Vector3(0,.035,0),elbow_pole)
		var bone=rig.find_bone("L_Hand" if side==0 else "R_Hand");var pose=rig.get_bone_global_pose(bone);pose.basis=rig.global_basis.inverse()*hand_basis;rig.set_bone_global_pose(bone,pose)
	view.muzzle.visible=u.flash>0 and p.flash_length>0
	view.muzzle.rotation.z=float(u.shot_index)*2.4
	view.muzzle.scale=Vector3.ONE*lerpf(.55,1.15,clampf(float(u.flash)/maxf(.001,p.flash_time),0,1))

static func grenade_hand_offset(stance: int,low: bool,phase: String,age: float) -> Vector3:
	var idle=Vector3(.09,-.26,-.22)
	var ready=Vector3(.14,-.35,.05) if low else Vector3(.14,.09,.08)
	var release=Vector3(.06,-.25,-.40) if low else Vector3(.045,-.03,-.44)
	var hand_offset=idle
	if phase=="aim":hand_offset=idle.lerp(ready,smoothstep(0,.18,age))
	elif phase=="windup":hand_offset=ready.lerp(release,smoothstep(0,preload("res://scripts/grenade_throw_control.gd").RELEASE_TIME,age))
	elif phase=="recover":hand_offset=release.lerp(idle,smoothstep(.035,.30,age))
	if stance==2:hand_offset=Vector3(.08,-.03,-.28).lerp(Vector3(.05,-.06,-.41),1.0 if phase in ["windup","recover"] else .3)
	return hand_offset

static func grenade_release_origin(view: Dictionary,u: Dictionary,low: bool) -> Vector3:
	# Predict the release palm using the same offset and reach clamp as the live IK.
	# Read-only: preview must not advance animation or move the held grenade.
	var rig: Skeleton3D=view.skeleton;var frame=Basis(Vector3.UP,atan2(-u.facing.x,-u.facing.y))
	var shoulder=rig.get_bone_global_pose(rig.find_bone("R_Upperarm")).origin
	var elbow=rig.get_bone_global_pose(rig.find_bone("R_Forearm")).origin
	var hand=rig.get_bone_global_pose(rig.find_bone("R_Hand"))
	var offset=grenade_hand_offset(int(u.stance),low or u.stance==2,"windup",1.0)
	var delta=rig.to_local(rig.to_global(shoulder)+frame*offset)-shoulder
	var a=shoulder.distance_to(elbow);var b=elbow.distance_to(hand.origin)
	var target=shoulder+delta.normalized()*clampf(delta.length(),absf(a-b)+.015,(a+b)*.965)
	return rig.to_global(target)+rig.global_basis*hand.basis*Vector3(0,.035,0)

static func pose_grenade(view: Dictionary,u: Dictionary):
	# Original skin and bones, independent throwing hand instead of two rifle grips.
	var rig: Skeleton3D=view.skeleton;var frame=Basis(Vector3.UP,atan2(-u.facing.x,-u.facing.y))
	var state: Dictionary=u.get("throw_state",{});var phase=str(state.get("phase","idle"));var age=float(state.get("age",0))
	var low=bool(state.get("low",u.get("throw_low",false))) or int(u.stance)==2
	var hand_offset=grenade_hand_offset(int(u.stance),low,phase,age)
	for side in range(2):
		var name="L" if side==0 else "R";var sign_value=-1.0 if side==0 else 1.0
		var shoulder=rig.to_global(rig.get_bone_global_pose(rig.find_bone(name+"_Upperarm")).origin)
		var goal=shoulder+frame*(hand_offset if side==1 else Vector3(-.09,-.29,-.18))
		var pole=shoulder+frame*Vector3(sign_value*.42,-.23,.10)
		adjust_arm(view,name,goal,pole)
	# Attach the centre of the grenade to the evaluated palm, including reach limits.
	var right=rig.get_bone_global_pose(rig.find_bone("R_Hand"))
	var palm=rig.to_global(right.origin)+rig.global_basis*right.basis*Vector3(0,.035,0)
	view.rifle.global_basis=frame*Basis.from_scale(view.weapon_scale)
	view.rifle.global_position=palm;view.muzzle.hide()

static func ladder_transition(view: Dictionary,phase: String):
	if view.get("ladder_phase","")==phase:return
	var rig: Skeleton3D=view.skeleton;var bones=[]
	for i in range(rig.get_bone_count()):bones.append(rig.get_bone_pose(i))
	view.ladder_blend={"bones":bones,"hip":view.root.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin)),"body":view.body.transform,"age":0.0}
	view.ladder_phase=phase

static func blend_ladder(view: Dictionary,delta: float):
	var saved: Dictionary=view.get("ladder_blend",{})
	if saved.is_empty():return
	saved.age+=maxf(0,delta)
	var weight=smoothstep(0,.18,saved.age) if delta>0 else 1.0
	if weight>=1:view.ladder_blend={};return
	var rig: Skeleton3D=view.skeleton
	var target=view.root.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin))
	for i in range(rig.get_bone_count()):rig.set_bone_pose(i,saved.bones[i].interpolate_with(rig.get_bone_pose(i),weight))
	view.body.transform=saved.body.interpolate_with(view.body.transform,weight)
	var blended=view.root.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin))
	# Blend visible root compensation with the source walk, never its raw FBX travel.
	view.model.global_position+=view.root.global_basis*(saved.hip.lerp(target,weight)-blended)

static func ladder_pose(view: Dictionary,u: Dictionary,delta: float=0):
	# Keep the supplied rig/skin; only solve hands and feet for this new traversal state.
	var state: Dictionary=u.ladder;var ladder: Dictionary=state.spec
	var approaching=preload("res://scripts/terrain_ladder.gd").approaching(state)
	ladder_transition(view,"approach" if approaching else "climb")
	var yaw=atan2(-u.facing.x,-u.facing.y);var frame=Basis(Vector3.UP,yaw)
	view.body_yaw=yaw;view.body.rotation=Vector3(0,yaw,0);view.body.position=Vector3.ZERO
	if approaching:
		var walk: Dictionary=view.source_info.clips.walk
		sample(view,("Armature|" if u.get("holstered",false) else "Rifle_")+"walk",float(walk.start)/24.0+fposmod(float(state.entry_travel)/maxf(.1,float(walk.distance))*float(walk.duration),float(walk.duration)))
	else:sample(view,"Rifle_idle",float(view.source_info.clips.idle.start)/24.0)
	view.helmet.visible=not u.get("helmet_lost",false)
	var rig: Skeleton3D=view.skeleton;var foot: Vector3=view.root.global_position
	var forward=Vector3(u.facing.x,0,u.facing.y);var side=forward.cross(Vector3.UP)
	for i in range(2):
		if approaching:break
		var name="L" if i==0 else "R";var sign_value=-1.0 if i==0 else 1.0
		var hand=foot+forward*.38+side*sign_value*.26
		hand.y=ladder_rung(ladder.low.y,foot.y+1.32,i*.28)
		hand.y=minf(hand.y,ladder.high.y+1.02)
		adjust_arm(view,name,hand,foot+side*sign_value*.65+Vector3.UP*1.1)
		var toe=foot+forward*.34+side*sign_value*.15
		toe.y=ladder_rung(ladder.low.y,foot.y+.16,(1-i)*.28)
		adjust_leg(view,name,rig.to_local(toe),foot+forward*.9+side*sign_value*.22+Vector3.UP*.65,true)
	blend_ladder(view,delta)
	if view.has("held"):
		if not view.get("weapon_world_pose",false):
			view.weapon_scale=view.rifle.global_basis.get_scale();view.rifle.reparent(view.body,true);view.weapon_world_pose=true
		view.rifle.global_basis=frame*Basis(Vector3.RIGHT,-PI*.5)*Basis.from_scale(view.weapon_scale)
		view.rifle.global_position=foot+frame*Vector3(.34,.90,.25)
	view.muzzle.visible=false;view.foot_contact=[false,false]
	u.hit_shapes=hit_shapes(view);preload("res://scripts/combat_pose.gd").capture(u,view);Style.update_shadow(view)

static func ladder_rung(base: float,wanted: float,offset: float) -> float:
	# Hold a world-space rung during support, then lift to the next; reverses smoothly on descent.
	var step=(wanted-base+offset)/.56;var whole=floorf(step)
	return base+(whole+smoothstep(.52,1,step-whole))*.56-offset

static func update(view: Dictionary,u: Dictionary,delta: float,time: float,reload_seconds: float):
	Medical.begin(view,u,delta)
	if not u.get("vehicle_flight",{}).is_empty():impact_pose(view,u);return
	if view.get("impact_active",false):
		view.impact_active=false;view.source_clip="";view.transition_pose=[]
		for i in range(view.skeleton.get_bone_count()):view.transition_pose.append(view.skeleton.get_bone_pose(i))
		view.locomotion_pose=view.transition_pose.duplicate();view.transition=0.0
	if u.get("healing",{}).is_empty():Medical.hide_props(view)
	if not u.get("ladder",{}).is_empty():ladder_pose(view,u,delta);return
	ladder_transition(view,"")
	var speed: float=u.velocity.length();var blend=1-exp(-delta*12) if delta>0 else 1.0
	view.speed=lerpf(view.speed,speed,blend);view.sprint=lerpf(view.sprint,1.0 if u.get("sprinting",false) else 0.0,blend)
	view.helmet.visible=not u.get("helmet_lost",false)
	var stance=float(u.get("stance_blend",0));var crouch=clampf(stance,0,1)*(1-clampf(stance-1,0,1));var prone=clampf(stance-1,0,1)
	var holstered=bool(u.get("holstered",false))
	var free_hands=holstered or not u.get("healing",{}).is_empty()
	# Ground deployment is a persistent emplacement, not a carried idle pose.
	var deploy_target=0.0
	view.mortar_deploy=move_toward(float(view.get("mortar_deploy",deploy_target)),deploy_target,delta*4) if delta>0 else float(view.get("mortar_deploy",deploy_target))
	crouch=maxf(crouch,float(view.mortar_deploy)*.85)
	var grounded=bool(u.get("grounded",true));var vault: Dictionary=u.get("vault",{})
	var rig: Skeleton3D=view.skeleton
	if bool(view.get("vault_active",false))!=not vault.is_empty():
		var snapshot=[]
		for i in range(rig.get_bone_count()):snapshot.append(rig.get_bone_pose(i))
		var visible_hip=view.body.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin))
		if not vault.is_empty():
			view.vault_entry_pose=snapshot;view.vault_entry_hip=visible_hip;view.vault_entry_feet=[];view.vault_retreat=0.0
			for side in ["L","R"]:view.vault_entry_feet.append(rig.to_global(rig.get_bone_global_pose(rig.find_bone(side+"_Foot")).origin))
			view.vault_foot_targets=view.vault_entry_feet.duplicate()
		else:view.vault_exit_pose=snapshot;view.vault_exit_hip=visible_hip;view.vault_exit_age=0.0
	view.vault_active=not vault.is_empty()
	if not vault.is_empty():crouch=0.0
	# Keep the original source clips, with a small run threshold hysteresis so
	# collisions/acceleration around 4 m/s do not restart the transition every pose.
	var previous_locomotion=str(view.source_clip).trim_prefix("Rifle_").trim_prefix("Armature|")
	var run_threshold=3.75 if previous_locomotion=="run" else 4.15
	var locomotion="run" if speed>run_threshold else "walk" if speed>.05 else "idle"
	if prone>.001 or not vault.is_empty():locomotion="idle"
	var airborne=not grounded and vault.is_empty()
	if airborne:locomotion="jump"
	view.crawl_phase=float(view.get("crawl_phase",0))+speed*delta*8.0
	# The rifle variants bake a static fire pose into all upper-body tracks.
	# Empty hands must use the supplied clips, including their wrists and arm swing.
	var heavy_carry=str(view.get("weapon_profile",{}).get("id",""))=="minigun"
	var prefix="Armature|" if free_hands or heavy_carry else "Rifle_"
	var clip=prefix+locomotion;var data: Dictionary=view.source_info.clips[locomotion]
	if view.source_clip!=clip:
		# Blend source poses, never last frame's IK-adjusted arms (feedback/jitter).
		view.transition_pose=view.get("locomotion_pose",[]).duplicate()
		view.transition_hip=view.get("locomotion_hip",view.body.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin)))
		if previous_locomotion=="":view.transition_hip=view.body.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin))
		# Drawing/stowing retains the stride. Walk/run transfers normalized phase
		# instead of restarting at the same first footfall on every speed change.
		if previous_locomotion!=locomotion:
			if previous_locomotion in ["walk","run"] and locomotion in ["walk","run"]:
				var old_duration=float(view.source_info.clips[previous_locomotion].duration)
				view.animation_time=fposmod(float(view.animation_time),old_duration)/old_duration*float(data.duration)
			else:view.animation_time=0.0
		view.transition=1.0 if view.transition_pose.is_empty() else 0.0;view.source_clip=clip
	# Read the same real movement vector used by simulation. Reverse the supplied
	# stride when backpedalling; never author a second set of lower-body curves.
	var reverse=bool(view.get("stride_reverse",false))
	if free_hands:reverse=false
	elif speed>.05 and grounded and prone<=.001 and vault.is_empty():
		var forward_amount=u.velocity.dot(u.facing)/speed
		# A 0.20 directional deadband avoids forward/back flicker near pure strafe.
		if forward_amount<-.20:reverse=true
		elif forward_amount>.20:reverse=false
	view.stride_reverse=reverse
	var stride_target=-1.0 if reverse else 1.0
	view.stride_rate=move_toward(float(view.get("stride_rate",stride_target)),stride_target,maxf(0,delta)*12.0)
	if not airborne:
		if speed>.05 and locomotion in ["walk","run"]:
			var cycle_distance=maxf(.1,float(data.distance));view.animation_time+=speed*delta/cycle_distance*float(data.duration)*float(view.stride_rate)
		else:view.animation_time+=delta
	var phase=fposmod(view.animation_time,float(data.duration))
	if prone>.001:phase=0.0
	if airborne:
		# Same physics-driven source jump timing as before; no independent air clock.
		var air_phase=clampf((6.4-float(u.get("vertical_speed",0)))/12.8,0,1)
		phase=lerpf(.18,.80,air_phase)*float(data.duration)
	if not vault.is_empty():phase=0.0
	var facing: Vector2=u.velocity.normalized() if speed>.05 else u.facing
	# When armed, the hips follow travel within the existing 0.80 radian limit;
	# the upper-body twist and weapon solve retain the actual selected aim.
	if reverse and not free_hands and speed>.05:facing=-facing
	if prone>.001:facing=u.facing
	if not vault.is_empty():facing=vault.direction
	var yaw=atan2(-facing.x,-facing.y);var aim_yaw=atan2(-u.facing.x,-u.facing.y)
	if vault.is_empty() and not free_hands:yaw=aim_yaw-clampf(wrapf(aim_yaw-yaw,-PI,PI),-.80,.80)
	view.body_yaw=rotate_toward(float(view.get("body_yaw",yaw)),yaw,delta*20.0) if delta>0 else float(view.get("body_yaw",yaw))
	yaw=view.body_yaw;view.body.rotation=Vector3(-prone*PI*.5,yaw,0);view.body.position=Vector3.ZERO
	sample(view,clip,float(data.start)/24.0+phase)
	if airborne:
		# Physics owns airborne height. Compensate before blending so takeoff and
		# landing carry both the limb pose and its visible pelvis continuously.
		var hip_height: float=view.body.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin)).y
		view.model.position.y=.73-hip_height
	if view.get("transition",1.0)<1.0 and vault.is_empty():
		view.transition=minf(1,view.transition+maxf(0,delta)/.14)
		var weight=smoothstep(0,1,view.transition)
		var target_hip=view.body.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin))
		for i in range(rig.get_bone_count()):rig.set_bone_pose(i,view.transition_pose[i].interpolate_with(rig.get_bone_pose(i),weight))
		var blended_hip=view.body.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin))
		# Raw clips contain metres of forward travel. Blend their compensated
		# visible pelvis, never their uncancelled root displacement.
		view.model.position+=Vector3(view.transition_hip).lerp(target_hip,weight)-blended_hip
	view.locomotion_pose=[]
	for i in range(rig.get_bone_count()):view.locomotion_pose.append(rig.get_bone_pose(i))
	view.locomotion_hip=view.body.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin))
	if crouch>.001:
		var targets=[]
		for side in ["L","R"]:targets.append(rig.get_bone_global_pose(rig.find_bone(side+"_Foot")).origin)
		var pelvis=rig.get_bone_global_pose(view.bone_indices.Hip);pelvis.origin+=rig.global_basis.inverse()*Vector3.DOWN*.34*crouch;rig.set_bone_global_pose(view.bone_indices.Hip,pelvis)
		adjust_leg(view,"L",targets[0]);adjust_leg(view,"R",targets[1])
	if not vault.is_empty():vault_body(view,u,delta)
	if prone>.001:
		prone_body(view,u,prone,float(view.crawl_phase))
	blend_vault_transition(view,u,delta)
	blend_ladder(view,delta)
	if vault.is_empty() and grounded:
		var left=rig.to_global(rig.get_bone_global_pose(view.bone_indices.L_Foot).origin)
		var right=rig.to_global(rig.get_bone_global_pose(view.bone_indices.R_Foot).origin)
		u.traversal_lead=-1.0 if Vector2(left.x-right.x,left.z-right.z).dot(u.facing)>=0 else 1.0
	var aim=atan2(-u.facing.x,-u.facing.y);var twist=clampf(wrapf(aim-yaw,-PI,PI),-.9,.9)*(1-prone)
	if free_hands:twist=0.0
	if absf(twist)>.001:global_rotation(rig,view.bone_indices.Spine02,Quaternion((rig.global_basis.inverse()*Vector3.UP).normalized(),twist))
	if view.has("held"):
		pose_weapon(view,u,time,reload_seconds)
		Medical.finish(view,u,delta)
		if float(u.get("equip_remaining",0))>0 and not u.get("holstered",false) and u.get("healing",{}).is_empty():
			var progress=clampf(float(u.equip_remaining)/maxf(.01,float(u.get("equip_duration",.4))),0,1)
			var lowering=Vector3.DOWN*.18*smoothstep(0,1,progress)
			view.rifle.global_position+=lowering
			for side in ["L","R"]:
				var hand=rig.to_global(rig.get_bone_global_pose(rig.find_bone(side+"_Hand")).origin)
				adjust_arm(view,side,hand+lowering)
		if not vault.is_empty():vault_hands(view,u)
		else:Reaction.apply(view,u)
		u.hit_shapes=hit_shapes(view)
		preload("res://scripts/combat_pose.gd").capture(u,view)
		view.foot_contact=[false,false];Style.update_shadow(view);return
	view.rifle.position=Vector3.ZERO;view.rifle.rotation=Vector3.ZERO
	var grips=[]
	for side in ["L","R"]:grips.append(view.rifle.to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone(side+"_Hand")).origin)))
	var reload_phase=clampf(1-float(u.reload)/maxf(.05,float(u.get("reload_duration",reload_seconds))),0,1)
	var reload_weight=smoothstep(0,.14,reload_phase)*(1-smoothstep(.84,1,reload_phase)) if u.reload>0 else 0.0
	view.rifle.position=Vector3(0,-reload_weight*.06,float(u.flash)*.35);view.rifle.rotation=Vector3(reload_weight*.18,0,-reload_weight*.38)
	if reload_weight>.001 or u.flash>0:
		for side in range(2):
			var target: Vector3=view.rifle.to_global(grips[side])
			if side==0:
				var reach=smoothstep(.12,.30,reload_phase)*(1-smoothstep(.48,.65,reload_phase))
				var insert=smoothstep(.48,.65,reload_phase)*(1-smoothstep(.77,.91,reload_phase))
				target=target.lerp(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin)+view.body.global_basis*Vector3(-.12,.12,-.15),reach)
				target=target.lerp(view.rifle.to_global(Vector3(0,-.16,0)),insert)
			adjust_arm(view,"L" if side==0 else "R",target)
	view.muzzle.visible=u.flash>0 and str(view.get("weapon_profile",{}).get("kind","bullet")) not in ["grenade","melee"]
	view.foot_contact=[false,false]
	Style.update_shadow(view)

static func pose_empty_hands(view: Dictionary,u: Dictionary):
	var rig: Skeleton3D=view.skeleton;var frame=Basis(Vector3.UP,atan2(-u.facing.x,-u.facing.y))
	view.muzzle.hide()
	if not u.get("healing",{}).is_empty():Medical.apply(view,u,load("res://scripts/source_rig_motion.gd"));return
	var prone=clampf(float(u.get("stance_blend",u.stance))-1,0,1)
	# Preserve the original relaxed hands and opposite arm swing. The old fixed
	# shoulder-to-wrist IK suppressed the walk/run swing and retained rifle wrists.
	if prone<=.001:return
	for side in ["L","R"]:
		var sign_side=-1.0 if side=="L" else 1.0
		var shoulder=rig.to_global(rig.get_bone_global_pose(rig.find_bone(side+"_Upperarm")).origin)
		var offset=Vector3(sign_side*.10,-.44,-.02)
		offset=offset.lerp(Vector3(sign_side*.08,-.10,-.25),prone)
		var hand=rig.to_global(rig.get_bone_global_pose(rig.find_bone(side+"_Hand")).origin)
		var target=hand.lerp(shoulder+frame*offset,prone)
		adjust_arm(view,side,target,shoulder+frame*Vector3(sign_side*.38,-.28,.08))

static func hit_shapes(view: Dictionary) -> Array:
	# Muzzle evaluation can refresh the rig between render frames. Keep the shared
	# world-space hit shapes anchored there, avoiding a second translation later.
	view.pose_root_position=view.root.global_position
	var rig: Skeleton3D=view.skeleton
	if not view.has("hit_capsules"):
		view.hit_capsules=[]
		var parts=[["Hip","Spine02",.25,"body"],["Head","Head",.25,"head"]]
		for side in ["L","R"]:
			parts.append_array([[side+"_Thigh",side+"_Calf",.145,"leg"],[side+"_Calf",side+"_Foot",.125,"leg"],[side+"_Foot",side+"_ToeBase",.145,"foot"],[side+"_Upperarm",side+"_Forearm",.14,"body"],[side+"_Forearm",side+"_Hand",.12,"body"]])
		for part in parts:
			var a=rig.find_bone(part[0]);var b=rig.find_bone(part[1])
			if a>=0 and b>=0:view.hit_capsules.append({"bone_a":a,"bone_b":b,"a":Vector3.ZERO,"b":Vector3.ZERO,"radius":part[2],"region":part[3]})
	for shape in view.hit_capsules:
		shape.a=rig.to_global(rig.get_bone_global_pose(shape.bone_a).origin)
		shape.b=rig.to_global(rig.get_bone_global_pose(shape.bone_b).origin)
	return view.hit_capsules

static func impact_pose(view: Dictionary,u: Dictionary):
	var flight: Dictionary=u.vehicle_flight;var rig: Skeleton3D=view.skeleton
	var hand=rig.find_bone("R_Hand")
	if not view.get("impact_active",false):
		view.impact_active=true;view.impact_entry=[];view.impact_yaw=view.body.rotation.y
		for i in range(rig.get_bone_count()):view.impact_entry.append(rig.get_bone_pose(i))
		view.impact_weapon=(rig.global_transform*rig.get_bone_global_pose(hand)).affine_inverse()*view.rifle.global_transform
		view.vault_active=false;view.erase("vault_exit_pose");ladder_transition(view,"")
	view.body.rotation=Vector3(0,lerp_angle(float(view.impact_yaw),float(flight.choice.yaw),smoothstep(0,.28,float(flight.age))),0)
	view.body.position=Vector3.ZERO
	view.death_entry_pose=view.impact_entry;view.death_stance=0
	death(view,float(flight.age),flight.choice)
	view.erase("death_entry_pose");view.erase("death_stance")
	view.rifle.global_transform=rig.global_transform*rig.get_bone_global_pose(hand)*view.impact_weapon
	view.muzzle.visible=false;view.foot_contact=[false,false]
	u.hit_shapes=hit_shapes(view);preload("res://scripts/combat_pose.gd").capture(u,view);Style.update_shadow(view)

static func death(view: Dictionary,age: float,choice: Dictionary={}):
	Medical.hide_props(view)
	var clip=str(choice.get("clip","fall"));var data: Dictionary=Reaction.info()[clip]
	sample(view,"Armature|"+clip,minf(float(data.end)/24.0,float(data.start)/24.0+age*float(choice.get("speed",2.2))),false)
	var rig: Skeleton3D=view.skeleton
	if view.has("death_entry_pose"):
		var blend=smoothstep(0,.22,age)
		for i in range(rig.get_bone_count()):rig.set_bone_pose(i,view.death_entry_pose[i].interpolate_with(rig.get_bone_pose(i),blend))
	# Corpse displacement is handled by physics; don't also inherit a metre of FBX travel.
	var hip=view.body.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Hip).origin))
	view.model.position.x=-hip.x;view.model.position.z=-hip.z
	if int(view.get("death_stance",0))>0:
		var head=view.body.to_local(rig.to_global(rig.get_bone_global_pose(view.bone_indices.Head).origin))
		view.model.position.y-=maxf(0,head.y-(.43 if view.death_stance==2 else .98))
