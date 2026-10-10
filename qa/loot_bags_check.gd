extends SceneTree
## Inventory conservation, reach and shared geometry; no live gameplay or input.
const Catalog=preload("res://scripts/source_catalog.gd")
const Equipment=preload("res://scripts/quick_equipment.gd")
const Bags=preload("res://scripts/loot_bags.gd")
const Visual=preload("res://scripts/loot_bag_visual.gd")
const LootPanel=preload("res://scripts/loot_panel.gd")
class GameFixture extends Control:
	var world
	var catalog
	var atlas
	func button(parent: Node,label: String,action: Callable) -> Button:
		var result=Button.new();result.text=label;parent.add_child(result);result.pressed.connect(action);return result
class Fixture extends "res://scripts/proving_world.gd":
	var occluded=false
	var floor_height=0.0
	var rays=0
	func ground_height(_point: Vector2,_radius: float,_ceiling: float,_predicate: Callable=Callable()) -> float:return floor_height
	func trace_3d(_origin: Vector3,_direction: Vector3,_distance: float,_options: Dictionary={},_walls: bool=false) -> Dictionary:
		rays+=1;return {"distance":.1,"type":"object"} if occluded else {}
var checks=0
var failures=[]
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func victim(world) -> Dictionary:
	var u=world.add_unit(Vector2(1,0),false)
	Equipment.initialize(u,world.catalog.weapons,["akm","p92","he-grenade"])
	u.weapon_id="akm";u.ammo=7;u.reserve=13;u.fire_mode="single";u.inventory={"p92":{"ammo":3,"reserve":11},"he-grenade":{"ammo":1,"reserve":2}}
	u.medical_stock={"bandage":2,"first-aid":0};u.weapon_copies={"akm":2};return u
func _initialize():call_deferred("run")
func run():
	var world=Fixture.new();world.catalog=Catalog.new();world.player=world.add_unit(Vector2.ZERO,true)
	var u: Dictionary=world.player
	var dead=victim(world);var bag=world.loot.drop_unit(world,dead)
	check(bag.items.size()==4,"One container holds guns, throwables and actual medicine")
	check(bag.items["w:akm"].ammo==7 and bag.items["w:akm"].reserve==13 and bag.items["w:akm"].amount==2,"Death keeps partial magazine, reserve and duplicate count")
	dead.ammo=30;dead.inventory.p92.ammo=15
	check(bag.items["w:akm"].ammo==7 and bag.items["w:p92"].ammo==3,"Corpse respawn state cannot refill the bag")
	check(world.loot.drop_unit(world,dead).is_empty() and world.loot.bags.size()==1,"Repeated death notification cannot duplicate loot")
	u.position=Vector2(10,0)
	check(world.loot.nearest(world,u).is_empty() and not world.loot.take_all(world,u,bag.id),"Remote pickup is rejected")
	u.position=Vector2.ZERO;u.elevation=3.4
	check(not world.loot.can_access(world,u,bag),"No pickup through another floor")
	u.elevation=0;world.occluded=true
	check(not world.loot.take(world,u,bag.id,"w:akm"),"Wall blocks transfer, not just the prompt")
	world.occluded=false
	check(world.loot.nearest(world,u).id==bag.id,"Nearby clear bag is selected")
	u.mounted=0
	check(not world.loot.take_all(world,u,bag.id),"Cannot loot from enclosed vehicle")
	u.mounted=-1;u.alive=false
	check(not world.loot.take_all(world,u,bag.id),"Dead operator cannot transfer contents")
	u.alive=true;u.ladder={"state":"climb"}
	check(not world.loot.take_all(world,u,bag.id),"Climbing blocks looting")
	u.ladder={};world.campaign.active=true;world.campaign.phase="won"
	check(not world.loot.take_all(world,u,bag.id),"Completed round rejects transfer")
	world.campaign.active=false;u.quick_slots[1]=""
	check(world.loot.take(world,u,bag.id,"w:akm"),"New gun can be picked up")
	check("akm" in u.quick_owned and u.quick_slots[1]=="akm" and u.weapon_id=="m416","Pickup fills empty slot without forced weapon change")
	check(u.inventory.akm.ammo==7 and u.inventory.akm.reserve==13 and u.weapon_copies.akm==2,"Pickup preserves stored ammo and count")
	check(world.equip_slot(1) and u.ammo==7 and u.reserve==13 and u.fire_mode=="single","Shared wheel/number slot equips actual looted magazine")
	check(not world.loot.take(world,u,bag.id,"w:akm"),"Repeated click cannot duplicate the item")
	var p92_total=int(world.catalog.weapons.p92.mag)+int(world.catalog.weapons.p92.reserve)
	check(world.loot.take(world,u,bag.id,"w:p92"),"Duplicate gun is collected")
	check(u.weapon_copies.p92==2 and u.inventory.p92.ammo+u.inventory.p92.reserve==p92_total+14,"Duplicate count and all ammunition conserved")
	var med_count=int(u.medical_stock.bandage)
	check(world.loot.take_all(world,u,bag.id),"Take remaining contents")
	check(u.medical_stock.bandage==med_count+2 and world.loot.find(bag.id).is_empty(),"Bag disappears only after emptying")
	check(not world.loot.take_all(world,u,bag.id),"Take-all cannot be replayed")
	# Campaign pickup adds real ownership, unlike the debug armory.
	world.campaign.active=true;world.campaign.phase="playing";u.loadout=["m416"];Equipment.initialize(u,world.catalog.weapons,u.loadout);u.weapon_id="m416"
	bag=world.loot.drop_unit(world,victim(world))
	check(world.loot.take(world,u,bag.id,"w:akm") and "akm" in u.loadout,"Loot grants campaign equipment ownership")
	check(world.assign_quick_weapon("akm",2) and u.ammo==7,"Campaign can equip legitimately looted weapon")
	world.campaign.active=false;world.floor_height=3.4
	var upper=victim(world);upper.elevation=3.4;var upstairs=world.loot.drop_unit(world,upper)
	check(is_equal_approx(upstairs.elevation,3.4),"Bag starts on real upper floor")
	world.floor_height=-1.0;world.topology_revision+=1
	world.loot.tick(world,.2)
	check(is_equal_approx(upstairs.elevation,-1.0),"Destroyed support moves bag to remaining surface, including trench depth")
	world.floor_height=0.0
	for i in range(Bags.LIMIT+12):
		var source=victim(world);source.position=Vector2(20+i,0);world.loot.drop_unit(world,source)
	check(world.loot.bags.size()==Bags.LIMIT,"Persistent bag count is bounded")
	world.rays=0;world.loot.nearest(world,u)
	check(world.rays<=2,"Proximity scan has a strict occlusion-ray budget")
	var mesh=Visual.mesh_resource();var arrays=mesh.surface_get_arrays(0)
	check(mesh==Visual.mesh_resource() and mesh.get_surface_count()==1,"All bags reuse one mesh surface")
	check(arrays[Mesh.ARRAY_VERTEX].size()/3<600,"Backpack geometry is bounded below 600 triangles")
	print("LOOT_BAG_GEOMETRY triangles=",arrays[Mesh.ARRAY_VERTEX].size()/3," surfaces=",mesh.get_surface_count())
	var stage=Node3D.new();root.add_child(stage);var visuals=Visual.new();visuals.world=world;stage.add_child(visuals);visuals.refresh()
	check(visuals.multimesh.instance_count==Bags.LIMIT and visuals.multimesh.visible_instance_count==Bags.LIMIT,"One MultiMesh holds every bag; no per-bag physics node")
	world.loot.clear();visuals.refresh()
	check(visuals.multimesh.visible_instance_count==0 and world.loot.bags.is_empty(),"Reset clears contents and rendering together")
	# Construct native widget resources and item rows without displaying/driving the game.
	var defeated=victim(world);world.damage_unit(defeated,1000,Vector3.ZERO,world.catalog.weapons.m416,false)
	bag=world.loot.bags.back()
	check(not defeated.alive and defeated.loot_dropped and bag.items.has("w:akm"),"Actual lethal-damage path creates the persistent bag")
	var game=GameFixture.new();game.world=world;game.catalog=world.catalog;game.atlas=load("res://assets/original/weapon_atlas.png");stage.add_child(game)
	var panel=LootPanel.new();panel.game=game;game.add_child(panel);panel.bag_id=bag.id;panel.owner_id=u.id;panel.refresh_rows()
	check(panel.nearby.get_child_count()==bag.items.size(),"Native nearby list represents actual bag contents")
	check(panel.carried.get_child_count()>=u.quick_owned.size() and panel.assignment.item_count==3,"Inventory list offers existing three equipment positions")
	var first_row=panel.nearby.get_child(0);panel.refresh_rows()
	check(panel.nearby.get_child(0)==first_row,"Unchanged inventory reuses its widgets")
	stage.free();print("LOOT_BAGS_CHECK checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
