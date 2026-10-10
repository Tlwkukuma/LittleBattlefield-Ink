extends RefCounted
## Only source animation rotations are layered. Locomotion/root/foot curves stay intact.
static var clips: Dictionary={}
static var pose_cache: Dictionary={}

static func info() -> Dictionary:
	if clips.is_empty():clips=JSON.parse_string(FileAccess.get_file_as_string("res://assets/tripo_source/combat-clips.json"))
	return clips

static func facing(u: Dictionary) -> Vector2:
	var velocity: Vector2=u.get("velocity",Vector2.ZERO)
	return velocity.normalized() if velocity.length()>.05 and not u.get("aiming",false) and float(u.get("shot_age",100))>.35 and u.stance!=2 else Vector2(u.facing)

static func register_hit(u: Dictionary,impulse: Vector3,region: String,amount: float,explosive: bool):
	var push=Vector2(impulse.x,impulse.z).normalized()
	if push.length_squared()<.01:push=-Vector2(u.facing)
	var heading=facing(u);var toward=-push;var right=Vector2(-heading.y,heading.x)
	var side=toward.dot(right);var front=toward.dot(heading)
	var direction="left" if side<-.55 else "right" if side>.55 else "front" if front>=0 else "back"
	var clip="hit_to_head" if region=="head" else "hit_to_side" if absf(side)>.55 else "hit_to_stomach" if region=="stomach" else "hit_to_body_02" if front<0 or explosive else "hit_to_body_01"
	var strength=clampf(.40+amount/110.0,.45,1.0)
	var previous: Dictionary=u.get("reaction",{})
	u.last_impact={"push":push,"region":region,"direction":direction}
	# Keep a running hit pose advancing during automatic fire and pellet clusters.
	# Stronger/head impacts can promote its response without resetting to frame zero.
	if not previous.is_empty() and float(previous.age)<minf(.24,float(previous.duration)*.72):
		var stronger=strength>=float(previous.strength)
		previous.strength=minf(1.0,maxf(previous.strength,strength)+.045)
		if region=="head" or stronger:
			previous.push=push;previous.direction=direction;previous.region=region
			if region=="head":previous.clip=clip
		return
	u.reaction={"clip":clip,"age":0.0,"duration":.30 if region!="head" else .38,"strength":strength,"push":push,"region":region,"direction":direction}

static func death_choice(u: Dictionary,impulse: Vector3) -> Dictionary:
	var push=Vector2(impulse.x,impulse.z).normalized()
	if push.length_squared()<.01:push=-Vector2(u.facing)
	var impact: Dictionary=u.get("last_impact",{})
	var clip="fall" if impact.get("direction","") in ["left","right"] or impact.get("region","")=="head" else "defeat_03"
	var data: Dictionary=info()[clip];var last: Dictionary=data.samples.back()
	var local_fall=Vector2(float(last.Head[0])-float(last.Hip[0]),float(last.Head[2])-float(last.Hip[2])).normalized()
	return {"clip":clip,"yaw":wrapf(local_fall.angle()-push.angle(),-PI,PI),"speed":2.2 if clip=="fall" else 2.8,"push":push}

static func clip_pose(view: Dictionary,clip: String,frame: int) -> Array:
	var key=clip+":"+str(frame)
	if pose_cache.has(key):return pose_cache[key]
	var animator: AnimationPlayer=view.animator;var name="Armature|"+clip
	if not animator.has_animation(name):return []
	animator.play(name);animator.seek(float(frame)/24.0,true);animator.advance(0)
	var poses=[]
	for i in range(view.skeleton.get_bone_count()):poses.append(view.skeleton.get_bone_pose(i))
	pose_cache[key]=poses;return poses

static func apply(view: Dictionary,u: Dictionary):
	var reaction: Dictionary=u.get("reaction",{})
	if reaction.is_empty() or not u.get("vault",{}).is_empty():return
	var t=clampf(float(reaction.age)/float(reaction.duration),0,1)
	if t>=1:return
	var rig: Skeleton3D=view.skeleton;var before=[]
	for i in range(rig.get_bone_count()):before.append(rig.get_bone_pose(i))
	var right=rig.find_bone("R_Hand");var hand_before=rig.global_transform*rig.get_bone_global_pose(right)
	var data: Dictionary=info()[reaction.clip]
	var reference=clip_pose(view,reaction.clip,int(data.start))
	var sampled=clip_pose(view,reaction.clip,clampi(roundi(lerpf(float(data.start),float(data.end),t)),int(data.start),int(data.end)))
	for i in range(before.size()):rig.set_bone_pose(i,before[i])
	if reference.is_empty() or sampled.is_empty():return
	var weight=smoothstep(0,.10,t)*(1-smoothstep(.72,1,t))*float(reaction.strength)
	if u.stance==2:weight*=.42
	for i in range(rig.get_bone_count()):
		var name=rig.get_bone_name(i)
		if not (name.begins_with("Spine") or name in ["Neck","Head"] or "Clavicle" in name or "Upperarm" in name or "Forearm" in name or "Hand" in name):continue
		var change: Quaternion=reference[i].basis.get_rotation_quaternion().inverse()*sampled[i].basis.get_rotation_quaternion()
		var pose: Transform3D=before[i];pose.basis=pose.basis*Basis(Quaternion.IDENTITY.slerp(change,weight));rig.set_bone_pose(i,pose)
	# Apply the actual impact direction in world space, including opposite-side hits.
	var push: Vector2=reaction.push;var axis=(rig.global_basis.inverse()*Vector3.UP.cross(Vector3(push.x,0,push.y))).normalized()
	for bone in [rig.find_bone("Spine01"),rig.find_bone("Head")]:
		var pose=rig.get_bone_global_pose(bone);pose.basis=Basis(Quaternion(axis,.15*weight))*pose.basis;rig.set_bone_global_pose(bone,pose)
	if view.has("held"):
		var hand_after=rig.global_transform*rig.get_bone_global_pose(right)
		view.rifle.global_transform=hand_after*hand_before.affine_inverse()*view.rifle.global_transform
