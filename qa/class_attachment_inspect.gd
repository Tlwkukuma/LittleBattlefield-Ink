extends SceneTree
const Source=preload("res://scripts/source_rig_character.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
func _initialize():run.call_deferred()
func run():
	var stage=Node3D.new();root.add_child(stage);var view=Source.soldier(stage,0,true)
	Motion.sample(view,"Rifle_idle",1.0/24)
	for label in ["Helmet_Detachable","Backpack","Source_Body"]:
		var node=view.model.find_child(label,true,false)
		print(label," local bounds=",node.mesh.get_aabb()," body transform=",view.body.global_transform.affine_inverse()*node.global_transform," parent=",node.get_parent().name)
	for label in ["Hip","Spine02","Head","L_Upperarm"]:
		var index=view.skeleton.find_bone(label)
		print(label," body pose=",view.body.global_transform.affine_inverse()*view.skeleton.global_transform*view.skeleton.get_bone_global_pose(index))
	stage.free();quit()
