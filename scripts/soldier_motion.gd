extends RefCounted
const Traversal=preload("res://scripts/soldier_traversal.gd")
const Style=preload("res://scripts/soldier_style.gd")
## Original procedural pose layers: locomotion / aim / recoil / reload / hand IK.
## Uses real travelled distance, never animation time, to advance the walking cycle.

static func joint(origin: Vector3, target: Vector3, pole: Vector3, a: float, b: float) -> Vector3:
	var axis=(target-origin).normalized()
	var distance=clampf(origin.distance_to(target),absf(a-b)+0.001,a+b-0.002)
	var along=(a*a-b*b+distance*distance)/(2.0*distance)
	var perpendicular=(pole-origin)-axis*(pole-origin).dot(axis)
	if perpendicular.length_squared()<0.00001: perpendicular=Vector3.FORWARD
	return origin+axis*along+perpendicular.normalized()*sqrt(maxf(0,a*a-along*along))

static func update(view: Dictionary, u: Dictionary, delta: float, time: float, reload_seconds: float) -> void:
	view.render_pose_revision=int(view.get("render_pose_revision",0))+1
	if view.get("source_rig",false):
		preload("res://scripts/source_rig_motion.gd").update(view,u,delta,time,reload_seconds)
		return
	var skeleton: Skeleton3D = view.skeleton
	if view.has("helmet"):view.helmet.visible=not u.get("helmet_lost",false)
	var rig_points: Array=view.get("rig_points",[])
	var aim=atan2(-u.facing.x,-u.facing.y)
	var speed: float = u.velocity.length()
	var stance=float(u.get("stance_blend",0))
	var crouch=clampf(stance,0,1)*(1-clampf(stance-1,0,1))
	var prone=clampf(stance-1,0,1)
	var grounded=bool(u.get("grounded",true))
	var vault: Dictionary=u.get("vault",{})
	var vault_phase=float(u.get("vault_progress",0))
	var vault_weight=sin(vault_phase*PI) if not vault.is_empty() else 0.0
	var landing=clampf(float(u.get("landing",0))/.32,0,1)
	var weapon: Dictionary=view.get("weapon_profile",{})
	var pistol=bool(weapon.get("mechanics",{}).get("pistol",false))
	var kind=str(weapon.get("kind","bullet"))
	var shot_age=time-float(u.get("last_shot",-100))
	var gesture=sin(clampf(shot_age/.42,0,1)*PI)
	var blend=1.0-exp(-delta*12.0) if delta>0 else 1.0
	if not view.has("speed"):
		view.speed=0.0
		view.hip_yaw=aim
		view.turn_phase=0.0
		view.foot_plants=[Vector3.ZERO,Vector3.ZERO]
		view.foot_contact=[false,false]
		view.previous_root_position=view.root.global_position
		view.previous_stance=stance
		view.sprint=0.0
		view.carry=0.0
		view.was_grounded=grounded
	view.sprint=lerpf(view.sprint,1.0 if u.get("sprinting",false) and grounded else 0.0,blend)
	var sprint: float=view.sprint
	var translated=view.root.global_position.distance_squared_to(view.previous_root_position)>.000001
	var stance_changing=absf(stance-float(view.previous_stance))>.002
	view.previous_root_position=view.root.global_position;view.previous_stance=stance
	view.speed=lerpf(view.speed,speed,blend)
	var moving=smoothstep(0.03,.55 if stance>0 else 1.1,view.speed)
	var direction=atan2(-u.velocity.x,-u.velocity.y) if speed>.05 else aim
	var offset=wrapf(direction-aim,-PI,PI)
	# Backpedal faces the target; strafe rotates the hips only within a comfortable arc.
	if absf(offset)>PI*.65: offset=wrapf(offset+PI,-PI,PI)
	var desired_hip=aim+clampf(offset,-.65,.65)*(1-prone)
	desired_hip=lerp_angle(desired_hip,direction,sprint)
	var turn_error=wrapf(aim-view.hip_yaw,-PI,PI)
	var turning=absf(turn_error)>.65 and moving<.15
	if moving>.05 or turning or prone>.05:
		view.hip_yaw=lerp_angle(view.hip_yaw,desired_hip,1.0-exp(-delta*(8.0 if moving>.05 else 5.0))) if delta>0 else desired_hip
	view.body.rotation.y=view.hip_yaw
	view.body.rotation.x=lerpf(view.body.rotation.x,-crouch*.12-prone*PI*.5-sprint*.15-vault_weight*.38-landing*.10,blend)
	view.body.rotation.z=lerpf(view.body.rotation.z,sin(u.walk)*.018*moving*(1-prone),blend)
	if turning: view.turn_phase+=delta*8.0
	var phase: float = u.walk if moving>.05 else view.turn_phase
	var local_velocity=Vector3(u.velocity.x,0,u.velocity.y).rotated(Vector3.UP,-view.hip_yaw)
	var walk_direction=local_velocity.normalized() if speed>.05 else Vector3.FORWARD
	var breath=sin(time*2.3+float(u.id)*.73)*.004
	var drop=moving*(lerpf(.035,.13,clampf(speed/3.4,0,1))+absf(sin(phase))*.012)
	view.body.position.y=lerpf(view.body.position.y,breath-drop*(1-prone)*(1.0 if grounded else .25)-crouch*.44+prone*.30-landing*.12,blend)
	var prone_offset=Vector3(0,0,prone*.85).rotated(Vector3.UP,view.hip_yaw)
	view.body.position.x=prone_offset.x+sin(phase)*.012*moving*(1-prone);view.body.position.z=prone_offset.z
	if skeleton.get_bone_count()>12:skeleton.set_bone_pose_rotation(12,Quaternion(Vector3.RIGHT,prone*1.20+crouch*.08))
	var chest_yaw=clampf(wrapf(aim-view.hip_yaw,-PI,PI),-.9,.9)*(1-sprint)
	var lean=clampf(local_velocity.z*.014,-.065,.065)
	var recoil=sin(clampf(float(u.flash)/.06,0,1)*PI*.8)*.055
	skeleton.set_bone_pose_rotation(7,Quaternion.from_euler(Vector3((lean-recoil)*(1-prone)-crouch*.05,chest_yaw*(1-prone),-local_velocity.x*.012*(1-prone))))
	for side in [0,1]:
		var sign_side=-1.0 if side==0 else 1.0
		var hip=Vector3(sign_side*.115,.90,.03)
		var rest_knee=Vector3(sign_side*.16,.52,-.105 if side==0 else .015)
		var rest_ankle=Vector3(sign_side*.185,.15,-.02 if side==0 else .16)
		if not rig_points.is_empty():
			hip=rig_points[1+side*2];rest_knee=rig_points[2+side*2];rest_ankle=rig_points[5+side]
		var cycle=fposmod(phase/TAU+side*.5,1.0)
		var travel=0.0
		var lift=0.0
		var stride=Traversal.stride(speed)*(1-crouch*.3)
		if cycle<.50:
			travel=lerpf(stride*.25,-stride*.25,cycle/.50)
		else:
			var swing=(cycle-.50)/.50
			travel=lerpf(-stride*.25,stride*.25,smoothstep(0,1,swing))
			lift=sin(swing*PI)*lerpf(.055,.19,clampf(speed/5.8,0,1))
		var amount=maxf(moving,.4 if turning else 0)
		var target=rest_ankle+walk_direction*travel*amount
		target.y+=lift*amount-view.body.position.y
		var crawl=(.5+.5*sin(phase+side*PI))*.22*moving
		target=target.lerp(rest_ankle+Vector3(sign_side*(.08+absf(crawl)*.5),crawl,-.10+maxf(0,cos(phase+side*PI))*.08*moving),prone)
		if not grounded:
			var tuck=.20+clampf(float(u.get("vertical_speed",0))/6.4,0,1)*.12
			if not vault.is_empty():tuck=.65*smoothstep(.20,.39,vault_phase)*(1-smoothstep(.80,.99,vault_phase))
			var air_target=Vector3(sign_side*.18,rest_ankle.y+tuck,-.22 if side==0 else .10)
			target=view.body.to_local(view.root.to_global(air_target.rotated(Vector3.UP,view.hip_yaw)))
		if grounded!=view.was_grounded:view.foot_contact[side]=false
		var contact=grounded and cycle<.50 and translated and moving>.30 and prone<.02 and not stance_changing
		if contact:
			if not view.foot_contact[side]:
				view.foot_plants[side]=view.body.to_global(target);view.foot_plants[side].y=float(u.get("elevation",0))+rest_ankle.y
			target=view.body.to_local(view.foot_plants[side])
		view.foot_contact[side]=contact
		var knee=joint(hip,target,hip+Vector3(0,-.3,-1),hip.distance_to(rest_knee),rest_knee.distance_to(rest_ankle))
		var upper=Quaternion((rest_knee-hip).normalized(),(knee-hip).normalized())
		var lower_global=Quaternion((rest_ankle-rest_knee).normalized(),(target-knee).normalized())
		skeleton.set_bone_pose_rotation(1+side*2,upper)
		skeleton.set_bone_pose_rotation(2+side*2,upper.inverse()*lower_global)
		# Ankle compensation keeps the boot sole level during the planted phase.
		var sole_compensation=view.body.quaternion.inverse()*Quaternion(Vector3.UP,view.hip_yaw)
		skeleton.set_bone_pose_rotation(5+side,lower_global.inverse()*sole_compensation.slerp(Quaternion(Vector3.RIGHT,prone*.70),prone)*Quaternion(Vector3.RIGHT,-lift*.6))
	view.was_grounded=grounded
	# Recoil and weapon inertia are additive over the lower-body pose.
	var reload_phase=clampf(1.0-float(u.reload)/maxf(.05,float(u.get("reload_duration",reload_seconds))),0,1)
	var reload_weight=0.0
	if u.reload>0: reload_weight=smoothstep(0,.14,reload_phase)*(1-smoothstep(.84,1,reload_phase))
	view.rifle.position=view.rifle_rest+Vector3(sin(phase)*.012*moving,-reload_weight*.07, float(u.flash)*.4)
	if pistol:view.rifle.position=Vector3(.08,1.33,-.50)+Vector3(0,-reload_weight*.06,float(u.flash)*.4)
	if kind=="grenade":view.rifle.position=Vector3(.30,1.30,-.44)+Vector3(gesture*.10,gesture*.24,gesture*.02)
	if kind=="melee":view.rifle.position=Vector3(.19,1.25,-.42)+Vector3(-gesture*.22,gesture*.05,-gesture*.16)
	view.rifle.position=view.rifle.position.lerp(Vector3(.19,1.72,.005),prone)
	view.rifle.rotation=Vector3(reload_weight*.18+crouch*.17+prone*PI*.5,-.06+reload_weight*.12,-reload_weight*.38)
	if kind=="melee":view.rifle.rotation.y-=gesture*.85
	var carry=1.0 if not u.get("aiming",false) and u.flash<=0 and shot_age>.20 and u.reload<=0 and kind=="bullet" and prone<.1 else 0.0
	view.carry=0.0 if u.flash>0 else lerpf(view.carry,carry,blend)
	var carry_position=Vector3(.105,1.16,-.26) if rig_points.is_empty() else view.rifle_rest+Vector3(.015,-.07,.035)
	view.rifle.position=view.rifle.position.lerp(carry_position,view.carry)
	view.rifle.rotation=view.rifle.rotation.lerp(Vector3(-.20,.60,.04),view.carry)
	var lower_weapon=maxf(sprint,vault_weight)
	view.rifle.position=view.rifle.position.lerp(Vector3(.21,1.06,-.32),lower_weapon)
	view.rifle.rotation.x+=lower_weapon*.45
	view.rifle.rotation.z+=sprint*.10
	view.muzzle.visible=u.flash>0 and kind not in ["melee","grenade"]
	for side in [0,1]:
		var shoulder=Vector3(-.205,1.438,-.038) if side==0 else Vector3(.205,1.438,-.038)
		var elbow=Vector3(-.290,1.218,-.20) if side==0 else Vector3(.310,1.198,.006)
		var wrist=Vector3(.025,1.302,-.565) if side==0 else Vector3(.133,1.275,-.255)
		if not rig_points.is_empty():shoulder=rig_points[8+side*2];elbow=rig_points[9+side*2];wrist=rig_points[13+side]
		var rest_rifle=Transform3D(Basis(Vector3.UP,-.06),view.rifle_rest)
		var grip: Vector3=view.grips[side] if view.has("grips") else wrist
		var target: Vector3 = view.rifle.transform*(rest_rifle.affine_inverse()*grip)
		if side==0 and pistol:target=view.rifle.transform*Vector3(-.025,-.08,.04)
		if side==0 and kind in ["melee","grenade"]:target=Vector3(-.08,1.22,-.43)
		if side==0 and not vault.is_empty():
			var brace=(1-smoothstep(.26,.43,vault_phase))*smoothstep(0,.12,vault_phase)
			var sideways=Vector3(-.22,0,0).rotated(Vector3.UP,view.hip_yaw)
			var hand=view.body.to_local(Vector3(vault.hand_point.x,vault.height+.04,vault.hand_point.y)+sideways)
			target=target.lerp(shoulder+(hand-shoulder).limit_length(.49),brace)
		if side==0 and prone>.5 and moving>.2 and not bool(u.get("aiming",false)):
			var reach=(.5+.5*sin(phase))*moving*prone
			target=target.lerp(Vector3(-.30,1.68,-.18),reach*.8)
		if side==0 and u.reload>0:
			# Release support grip, retrieve magazine at belt, insert, return to fore-end.
			var reach=smoothstep(.12,.30,reload_phase)*(1.0-smoothstep(.48,.65,reload_phase))
			var insert=smoothstep(.48,.65,reload_phase)*(1.0-smoothstep(.77,.91,reload_phase))
			target=target.lerp(Vector3(-.13,1.07,-.24),reach)
			target=target.lerp(view.rifle.transform*Vector3(0,-.16,0),insert)
		var elbow_pole=Vector3(-.42 if side==0 else .42,-.06,-.08-prone*.18)
		# Relaxed carry drops the elbows; the sleeves remain round rather than
		# reading as raised biceps on either side of the chest.
		elbow_pole=elbow_pole.lerp(Vector3(-.20 if side==0 else .20,-.38,-.06),view.carry*(1-lower_weapon))
		var elbow_pose=joint(shoulder,target,elbow+elbow_pole,shoulder.distance_to(elbow),elbow.distance_to(wrist))
		var upper=Quaternion((elbow-shoulder).normalized(),(elbow_pose-shoulder).normalized())
		var lower_global=Quaternion((wrist-elbow).normalized(),(target-elbow_pose).normalized())
		skeleton.set_bone_pose_rotation(8+side*2,upper)
		skeleton.set_bone_pose_rotation(9+side*2,upper.inverse()*lower_global)
		if skeleton.get_bone_count()>14:
			# Hands have their own orientation, independent of elbow flexion.
			var free_hand=side==0 and (u.reload>0 or not vault.is_empty() or kind in ["grenade","melee"] or (prone>.5 and moving>.2 and not u.get("aiming",false)))
			var desired=lower_global if free_hand else view.rifle.quaternion*Quaternion(Vector3.UP,.06)
			skeleton.set_bone_pose_rotation(13+side,lower_global.inverse()*desired)
	Style.update_shadow(view)
