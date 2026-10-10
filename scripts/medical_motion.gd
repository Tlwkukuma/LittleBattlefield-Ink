extends RefCounted
## A short upper-body action on the supplied skeleton; original locomotion stays intact.
const Style=preload("res://scripts/soldier_style.gd")
const Geometry=preload("res://scripts/loot_bag_visual.gd")
static var meshes: Dictionary={}

static func progress(action: Dictionary) -> float:
	return clampf(1-float(action.get("remaining",0))/maxf(.01,float(action.get("duration",1))),0,1)

static func weights(t: float) -> Dictionary:
	return {"reach":smoothstep(0,.12,t)*(1-smoothstep(.82,1,t)),"apply":smoothstep(.16,.30,t)*(1-smoothstep(.75,.88,t)),"open":smoothstep(.18,.29,t)*(1-smoothstep(.74,.84,t))}

static func resource(kind: String) -> ArrayMesh:
	if meshes.has(kind):return meshes[kind]
	var tool=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box=BoxMesh.new();box.size=Vector3.ONE
	var cloth=Color("ded8bb");var ink=Color("424a48");var canvas=Color("74866e")
	if kind=="case":
		Geometry.append_shape(tool,box,Vector3.ZERO,Vector3(.22,.115,.135),canvas)
		Geometry.append_shape(tool,box,Vector3(0,.058,0),Vector3(.19,.008,.108),ink)
		Geometry.append_shape(tool,box,Vector3(0,0,-.071),Vector3(.066,.022,.008),cloth)
		Geometry.append_shape(tool,box,Vector3(0,0,-.072),Vector3(.023,.070,.009),cloth)
	elif kind=="lid":
		Geometry.append_shape(tool,box,Vector3(0,0,-.065),Vector3(.225,.025,.14),canvas.lightened(.12))
		Geometry.append_shape(tool,box,Vector3(0,.015,-.065),Vector3(.070,.006,.024),cloth)
		Geometry.append_shape(tool,box,Vector3(0,.016,-.065),Vector3(.024,.006,.080),cloth)
	elif kind=="roll":
		var roll=CylinderMesh.new();roll.top_radius=.047;roll.bottom_radius=.047;roll.height=.07;roll.radial_segments=16;roll.rings=1
		Geometry.append_shape(tool,roll,Vector3.ZERO,Vector3.ONE,cloth)
		roll.top_radius=.019;roll.bottom_radius=.019;roll.height=.071
		Geometry.append_shape(tool,roll,Vector3.ZERO,Vector3.ONE,ink)
		Geometry.append_shape(tool,box,Vector3(.050,-.008,0),Vector3(.044,.062,.012),cloth)
	else:
		Geometry.append_shape(tool,box,Vector3.ZERO,Vector3(.093,.022,.082),cloth)
		Geometry.append_shape(tool,box,Vector3(0,.013,0),Vector3(.074,.006,.063),cloth.lightened(.1))
	meshes[kind]=tool.commit();return meshes[kind]

static func instance(parent: Node3D,kind: String) -> MeshInstance3D:
	var node=MeshInstance3D.new();node.name=kind;node.mesh=resource(kind)
	node.material_override=Style.material(Color.WHITE,true)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(node);return node

static func ensure(view: Dictionary):
	if view.has("medical_visual"):return
	var root=Node3D.new();root.name="MedicalAction";view.root.add_child(root)
	var bag=instance(root,"case");var lid=instance(bag,"lid");lid.position=Vector3(0,.07,.064)
	view.medical_visual={"root":root,"case":bag,"lid":lid,"roll":instance(root,"roll"),"pad":instance(root,"pad")}

static func hide_props(view: Dictionary):
	if view.has("medical_visual"):view.medical_visual.root.hide()

static func wrist(view: Dictionary,side: String) -> Transform3D:
	var rig: Skeleton3D=view.skeleton
	return rig.global_transform*rig.get_bone_global_pose(rig.find_bone(side+"_Hand"))

static func begin(view: Dictionary,u: Dictionary,delta: float):
	var active=not u.get("healing",{}).is_empty()
	if active and not view.get("medical_active",false):
		view.medical_entry={};view.medical_entry_age=0.0;view.medical_targets={}
		for side in ["L","R"]:
			view.medical_entry[side]=view.body.to_local(wrist(view,side).origin)
			view.medical_targets[side]=view.medical_entry[side]
	view.medical_delta=delta
	if active:view.medical_entry_age=float(view.get("medical_entry_age",0))+delta
	view.medical_active=active

static func apply(view: Dictionary,u: Dictionary,motion: Script):
	var action: Dictionary=u.get("healing",{})
	if action.is_empty():hide_props(view);return
	ensure(view)
	var props: Dictionary=view.medical_visual;var t=progress(action);var w=weights(t)
	var first_aid=str(action.id)=="first-aid"
	var rig: Skeleton3D=view.skeleton
	var frame=Basis(Vector3.UP,float(view.get("body_yaw",0)))
	var chest=rig.to_global(rig.get_bone_global_pose(view.bone_indices.Spine02).origin)
	var prone=clampf(float(u.get("stance_blend",0))-1,0,1)
	var pivot=chest+frame*Vector3(0,lerpf(-.13,.06,prone),lerpf(-.31,-.25,prone))
	var cycle=smoothstep(.28,.74,t)*TAU*2.0
	for side in ["L","R"]:
		var sign_side=-1.0 if side=="L" else 1.0
		var old=wrist(view,side);var shoulder=rig.to_global(rig.get_bone_global_pose(rig.find_bone(side+"_Upperarm")).origin)
		var retrieve=shoulder+frame*Vector3(sign_side*.03,lerpf(-.39,-.05,prone),lerpf(-.03,-.18,prone))
		var at=pivot+frame*Vector3(-.14,0,0)
		if side=="R":
			if first_aid:
				var press=.5-.5*cos(cycle)
				at=pivot+frame*Vector3(.065,.035+press*.055,.04+press*.09)
			else:at=pivot+frame*Vector3(-.20+cos(cycle)*.065,-.03+sin(cycle)*.055,.12)
		var target=old.origin.lerp(retrieve.lerp(at,float(w.apply)),float(w.reach))
		# Blend positions before the two-bone solve. Mixing already solved bone
		# rotations can sweep a bent elbow through the chest, especially when prone.
		target=view.body.to_global(view.medical_entry[side]).lerp(target,smoothstep(0,.28,float(view.medical_entry_age)))
		var previous: Vector3=view.body.to_global(view.medical_targets[side])
		target=previous.move_toward(target,maxf(0,float(view.medical_delta))*3.0)
		view.medical_targets[side]=view.body.to_local(target)
		motion.adjust_arm(view,side,target,shoulder+frame*Vector3(sign_side*.32,-.20,.13))
		# Align the palm to the work area rather than retaining the rifle wrist curl.
		var hand=rig.find_bone(side+"_Hand");var pose=rig.get_bone_global_pose(hand)
		var hand_world=rig.global_basis*pose.basis
		var fingers=(frame*Vector3(-sign_side*.45,.12,-1)).normalized()
		var desired=Basis(Quaternion(hand_world.y.normalized(),fingers))*hand_world
		pose.basis=pose.basis.slerp(rig.global_basis.inverse()*desired,float(w.apply)*.85);rig.set_bone_global_pose(hand,pose)
	props.root.visible=t>.07 and t<.95
	props.case.visible=first_aid;props.roll.visible=not first_aid;props.pad.visible=first_aid and float(w.apply)>.15

static func place_props(view: Dictionary,w: Dictionary):
	var props: Dictionary=view.medical_visual;var frame=Basis(Vector3.UP,float(view.get("body_yaw",0)))
	var left=wrist(view,"L");var right=wrist(view,"R")
	props.case.global_transform=Transform3D(frame,left.origin+left.basis*Vector3(0,.035,0)+frame*Vector3(0,.055,-.01))
	props.lid.rotation.x=-1.6*float(w.open)
	props.roll.global_transform=Transform3D(frame*Basis(Vector3.FORWARD,PI*.5),right.origin+right.basis*Vector3(0,.055,0))
	props.pad.global_transform=Transform3D(frame*Basis(Vector3.RIGHT,.7),right.origin+right.basis*Vector3(0,.045,0))

static func finish(view: Dictionary,u: Dictionary,delta: float):
	# Blend interrupted treatment back into the new action, without touching legs.
	var active=not u.get("healing",{}).is_empty()
	if active:
		place_props(view,weights(progress(u.healing)))
		view.medical_exit={};view.medical_exit_age=0.0
		for side in ["L","R"]:
			view.medical_exit[side]=view.body.to_local(wrist(view,side).origin)
	elif not view.get("medical_exit",{}).is_empty():
		view.medical_exit_age=float(view.get("medical_exit_age",0))+delta
		var weight=smoothstep(0,.16,float(view.medical_exit_age))
		if not u.get("vault",{}).is_empty() or not u.get("ladder",{}).is_empty():weight=1.0
		var motion=load("res://scripts/source_rig_motion.gd")
		for side in view.medical_exit:
			var target=view.body.to_global(view.medical_exit[side]).lerp(wrist(view,side).origin,weight)
			motion.adjust_arm(view,side,target)
		if weight>=1:view.medical_exit={}
