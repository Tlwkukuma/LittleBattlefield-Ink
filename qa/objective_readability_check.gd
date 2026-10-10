extends SceneTree
## Static geometry and public-objective HUD fixtures; no scene or combat input.
const Flag=preload("res://scripts/objective_flag.gd")
const HUD=preload("res://scripts/battle_status_hud.gd")
const Zone=preload("res://scripts/capture_zone.gd")
class FlatTerrain extends RefCounted:
	func height(at: Vector2):return at.x*.01+at.y*.02
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():
	var point={"position":Vector2(12,18),"elevation":0.0,"radius":4.5,"zone":PackedVector2Array(),"progress":0.0}
	for radius in [.1,4.5,6.5,1000.0]:
		point.radius=radius
		var before=point.duplicate(true);var segments=Flag.boundary_segments(point)
		check(segments.size()>=8 and segments.size()<=128,"Circular dash count stays bounded: "+str(radius))
		check(segments.all(func(s):return is_equal_approx(s[0].distance_to(point.position),radius) and is_equal_approx(s[1].distance_to(point.position),radius)),"Dash endpoints use exact real capture radius: "+str(radius))
		check(point==before,"Boundary preparation never mutates capture rules")
	point.radius=4.5
	check(Zone.contains(point,point.position+Vector2(4.49,0),0) and not Zone.contains(point,point.position+Vector2(4.51,0),0),"Displayed radius matches actual capture containment")
	var host={"world":{"terrain":FlatTerrain.new(),"player":{"position":point.position}},"armory":{"visible":false}}
	var flag=Flag.new();flag.build(host,point)
	var count=flag.vertices.size();var boundary_vertices=0
	for i in range(flag.uv.size()):
		if flag.uv[i].x>1.5:
			boundary_vertices+=1
			var q=Vector2(flag.vertices[i].x,flag.vertices[i].z)+point.position
			check(absf(q.distance_to(point.position)-point.radius)<.05,"Circle strip remains within 5 cm of true capture radius")
			check(is_equal_approx(flag.vertices[i].y,host.world.terrain.height(q)+.028),"Boundary vertex follows the actual terrain sampler")
	check(boundary_vertices==Flag.boundary_segments(point).size()*6,"Circular dashes are present in the existing flag mesh")
	check(flag.mesh.get_surface_count()==1 and flag.get_child_count()==0,"Flag boundary adds no mesh surface or child instances")
	flag.build(host,point)
	check(flag.vertices.size()==count,"Rebuilding the same flag never accumulates perimeter geometry")
	var moved=point.duplicate(true);moved.position=Vector2(-20,40);moved.radius=6.5
	flag.build(host,moved)
	check(flag.position==Vector3(-20,0,40) and flag.point==moved,"Next active objective replaces position/radius")
	check(flag.material.get_shader_parameter("show_zone")==false,"Distant next target keeps original near-boundary visibility rule")
	moved.zone=PackedVector2Array([Vector2(0,0),Vector2(4,0),Vector2(4,4),Vector2(0,4)])
	var polygon_segments=Flag.boundary_segments(moved)
	check(polygon_segments.size()==20 and polygon_segments[0][0]==Vector2.ZERO and polygon_segments[0][1].is_equal_approx(Vector2(.48,0)),"Authored polygon dash placement remains unchanged")
	flag.free()
	# Deliberately no units, enemy roster, visibility or camera data in this host.
	var navigation={"world":{"player":{"position":Vector2.ZERO},"campaign":{"points":[{"position":Vector2(10,0)}]}}}
	var directions=["东","东南","南","西南","西","西北","北","东北"]
	for i in range(8):
		navigation.world.campaign.points[0].position=Vector2.from_angle(i*PI/4)*10
		check(HUD.objective_direction(navigation).begins_with(directions[i]+" "),"Public objective compass sector "+directions[i])
	navigation.world.campaign.points=[{"position":Vector2(0,-30)}]
	check(HUD.objective_direction(navigation)=="北 30 m","Stage switch reads the new active point immediately")
	navigation.world.player.position=Vector2(0,-40)
	check(HUD.objective_direction(navigation)=="南 10 m","Direction and distance use actual local-player position")
	navigation.world.campaign.points=[]
	check(HUD.objective_direction(navigation).is_empty(),"No stale navigation when objective list is empty")
	print("OBJECTIVE_READABILITY_CHECK ",checks-failures,"/",checks," passed; static geometry/public-target data only")
	quit(0 if failures==0 else 1)
