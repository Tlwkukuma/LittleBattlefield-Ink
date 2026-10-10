extends SceneTree
## Two mesh builds only: no World setup, gameplay, rendering loop or inputs.
const Flag=preload("res://scripts/objective_flag.gd")
class FlatGround:
	extends RefCounted
	func height(_point: Vector2) -> float:return 0.0
var checks=0
var failures=0
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize():
	var point={"position":Vector2(2,3),"elevation":0.0,"radius":4.5,"zone":PackedVector2Array(),"progress":0.0,"owner":-1,"contested":false}
	var host={"world":{"terrain":FlatGround.new(),"player":{"position":Vector2.ZERO}},"armory":{"visible":false}}
	var original=Flag.new();original.build(host,point)
	var moved_point=point.duplicate(true);moved_point.visual_position=point.position+Vector2(-.95,.475)
	var moved=Flag.new();moved.build(host,moved_point)
	check(original.position==moved.position and moved.position==Vector3(2,0,3),"mesh root remains exact gameplay center")
	check(Flag.boundary_segments(point)==Flag.boundary_segments(moved_point),"capture perimeter stays exact")
	check(original.vertices.size()==moved.vertices.size(),"no additional geometry")
	var offset=Vector3(-.95,0,.475);var perimeter=0;var marker=0
	for index in range(original.vertices.size()):
		if original.uv[index].x>1.5:
			check(original.vertices[index].is_equal_approx(moved.vertices[index]),"perimeter vertex unchanged");perimeter+=1
		else:
			check((moved.vertices[index]-original.vertices[index]).is_equal_approx(offset),"only mast/flag vertex receives visual offset");marker+=1
	check(perimeter>0 and marker>0,"both marker and boundary exercised")
	original.free();moved.free()
	print("objective_marker_offset_contract: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
