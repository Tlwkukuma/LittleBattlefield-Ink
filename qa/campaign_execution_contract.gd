extends SceneTree
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Orchard=preload("res://scripts/orchard_level.gd")
var checks=0
var failures=0
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize():
	var catalog=Catalog.new();var world=World.new();world.setup(Orchard.plan(catalog),catalog)
	var ai=world.campaign_ai;var point: Vector2=world.campaign.points[0].position
	for unit in world.units:unit.alive=false
	var blue: Dictionary=world.units[1];var red: Dictionary=world.units[30]
	blue.alive=true;red.alive=true;blue.position=point-Vector2(1,0);red.position=point+Vector2(1,0)
	blue.elevation=world.terrain.height(blue.position);red.elevation=world.terrain.height(red.position)
	blue.facing=Vector2.RIGHT;blue.stance=0;red.stance=0;blue.weapon_id="m416"
	check(ai.perception.can_see(blue,red),"front target visible on actual B terrain")
	var sensed=ai.perception.refresh(blue)
	check(sensed.get("id",-1)==red.id,"vision selects real visible target")
	var remembered: Vector2=blue.ai_contacts[red.id].position
	red.position=point-Vector2(3,0)
	check(ai.perception.confirm(blue,red.id).is_empty(),"target behind observer cannot be confirmed")
	check(blue.ai_contacts[red.id].position==remembered,"hidden target movement does not update report")
	world.time=7;ai.perception.tick(blue,.1)
	check(blue.ai_contacts.is_empty(),"old visual memory expires")
	ai.perception.emit_sound(red.position,red.elevation+1.3,1,red.id,32,.65)
	check(blue.ai_hearing_contacts.has(red.id) and blue.ai_hearing_contacts[red.id].source=="hearing","audible shot produces hearing report")
	check(blue.ai_hearing_contacts[red.id].position.distance_to(red.position)>.1,"hearing position has nonzero uncertainty")
	check(blue.ai_hearing_contacts[red.id].confidence<=.45,"hearing confidence is bounded")
	blue.ai_order={"task":"attack","goal":point,"route_index":2,"direct":false}
	check(ai.objective_goal(world,blue)==point,"near-point assault never returns to deep trench route")
	blue.position=Vector2(20,8);blue.ai_order={"task":"attack","goal":point,"route_index":0,"direct":false};blue.erase("ai_route_selected");blue.erase("ai_route_index");blue.ai_route_done=false
	check(ai.objective_goal(world,blue)!=point and int(blue.ai_route_index)<=ai.routes[0][0].size()-3,"southern assault preserves final gate approach outside capture vicinity")
	blue.position=world.units[2].spawn;blue.ai_order={"task":"attack","goal":point,"route_index":1,"direct":false};blue.erase("ai_route_index");blue.erase("ai_route_selected")
	var next=ai.objective_goal(world,blue)
	check(next.distance_to(point)<=blue.position.distance_to(point)+3.1,"route entry does not substantially backtrack from objective")
	blue.ai_contacts={red.id:{"source":"vision","position":red.position,"observed_at":world.time,"confidence":1}}
	blue.ai_stress=.9;world.event.emit({"type":"respawn","unit":blue})
	check(blue.ai_contacts.is_empty() and blue.ai_stress==0 and not blue.has("ai_order"),"new life clears memories stress and prior execution order")
	check(ai.tactics.take_budget(true) and not ai.tactics.take_budget(true),"one new cover search per physics frame")
	check(ai.tactics.take_budget(false) and not ai.tactics.take_budget(false),"one recovery search per physics frame")
	print("EXECUTION_CONTRACT checks=%d failures=%d; no battle steps or model requests"%[checks,failures])
	quit(0 if failures==0 else 1)
