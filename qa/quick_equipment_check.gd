extends SceneTree
## State and geometry fixtures only. No gameplay inputs, firing, movement or captures.
const Equipment=preload("res://scripts/quick_equipment.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Wheel=preload("res://scripts/equipment_wheel.gd")
var checks=0
var failures=[]
func check(ok: bool,description: String):
	checks+=1
	if not ok:failures.append(description);push_error(description)
func _initialize():
	var catalog=Catalog.new();var world=World.new();world.catalog=catalog
	world.player=world.add_unit(Vector2.ZERO,true)
	var u: Dictionary=world.player
	check(u.quick_slots==["m416","awm","army-knife"],"Three equipped weapons are independent of gun category")
	check(Equipment.options(u,catalog.weapons)==["he-grenade","smoke-grenade","rpg"],"Tactical wheel contains only carried equipment, including RPG")
	check(Equipment.slot_weapon(u,-1)=="" and Equipment.slot_weapon(u,8)=="","Invalid slot cannot equip anything")
	check(Equipment.sector(Vector2.ZERO)==-1 and Equipment.sector(Vector2(40,0))==-1,"Central dead zone cancels")
	for index in range(6):
		var angle=-PI*.5+index*TAU/6
		check(Equipment.sector(Vector2.from_angle(angle)*160)==index,"Stable wheel sector %d"%index)
	check(Equipment.slot_for_sector(5)==2 and Equipment.slot_for_sector(2)==3,"Wheel positions map to equipment slots")
	check(Equipment.cycle(["he-grenade","smoke-grenade","rpg"],"rpg",1)=="he-grenade","Tactical list wraps without reordering")
	check(Equipment.cycle([],"",1)=="","Empty category is safe")
	var overlay=Wheel.new();var original_scale=Engine.time_scale
	overlay.saved_time_scale=original_scale;overlay.active=true;Engine.time_scale=.2
	overlay._exit_tree();overlay.active=false;overlay.free()
	check(is_equal_approx(Engine.time_scale,original_scale),"Overlay destruction restores time scale")
	u.ammo=7;u.reserve=59;u.fire_mode="single";u.cooldown=1.4;u.reload=.8
	world.time=10.0
	check(world.equip_slot(1),"Range can equip second weapon")
	check(u.reload==0 and u.fire_pending==0 and u.fire_lock,"Switch cancels reload and pending trigger")
	check(u.equip_remaining>0 and Equipment.busy(u),"Draw transition prevents immediate attack")
	u.ammo=2;u.reserve=9;world.time=10.3
	check(world.equip_slot(0),"Return to original weapon")
	check(u.ammo==7 and u.reserve==59 and u.fire_mode=="single","Magazine, reserve and firing mode survive switching")
	check(is_equal_approx(u.cooldown,1.1),"Switching cannot bypass a weapon's remaining cycle time")
	check(world.equip_slot(1) and u.ammo==2 and u.reserve==9,"Second gun also preserves independent ammunition")
	u.throw_state={"phase":"aim","age":.1};u.melee={"phase":"windup"}
	check(world.equip_slot(3) and u.throw_state.is_empty() and u.melee.is_empty(),"Weapon selection cancels prepared throw and melee")
	var grenade_count=u.ammo+u.reserve
	check(world.equip("rpg") and world.equip("he-grenade") and u.ammo+u.reserve==grenade_count,"Browsing tactical weapons never spends or replenishes grenade stock")
	check(world.assign_quick_weapon("p92",0),"Armory can assign pistol to any free weapon position")
	check(u.quick_slots==["p92","awm","army-knife"],"Other equipment positions remain intact")
	check(world.assign_quick_weapon("awm",0),"Assign an already equipped gun by swapping")
	check(u.quick_slots==["awm","p92","army-knife"],"The same equipment is never duplicated across slots")
	world.assign_quick_weapon("katana",1)
	check(u.quick_slots[1]=="katana","Melee shares free weapon positions")
	world.assign_quick_weapon("grenade-launcher",2)
	check(u.quick_slots[2]=="army-knife" and u.quick_tactical=="grenade-launcher","Tactical launcher uses its own quick selector")
	check(world.holster() and u.holstered and Equipment.busy(u),"Holster prevents attacks without discarding weapon")
	check(world.equip_slot(0) and not u.holstered,"Number slot draws from holster")
	var remembered=u.weapon_id;var magazine=u.ammo;var reserve=u.reserve
	check(world.clear_quick_slot(0) and u.holstered and u.quick_slots[0]=="","Weapon position can be left empty")
	check(not world.equip_slot(0),"Empty shortcut never spawns a default weapon")
	check(world.assign_quick_weapon(remembered,0) and u.ammo==magazine and u.reserve==reserve,"Unequip and reassignment preserve ammunition")
	u.mounted=0
	check(not world.equip_slot(1) and not world.holster(),"Personal equipment cannot override vehicle controls")
	u.mounted=-1;u.vault={"mode":"climb"}
	check(not world.equip_slot(1),"Climbing protects current hand action")
	u.vault={};u.alive=false
	check(not world.equip_slot(1),"Dead character cannot equip")
	u.alive=true;u.health=100;u.grounded=true
	check(world.use_medicine("bandage"),"Medicine starts only with missing health")
	check(u.medical_stock.bandage==3 and u.reload==0 and u.fire_lock,"No charge consumed before treatment completes")
	Equipment.tick(u,.9)
	check(u.health==100 and u.medical_stock.bandage==3,"Treatment has a real duration")
	Equipment.tick(u,1.0)
	check(u.health==140 and u.medical_stock.bandage==2 and u.healing.is_empty(),"Completed treatment heals once and consumes one charge")
	Equipment.tick(u,10)
	check(u.medical_stock.bandage==2 and u.health==140,"Completed treatment cannot repeat")
	world.use_medicine("first-aid");u.health=130;Equipment.tick(u,.1)
	check(u.healing.is_empty() and u.medical_stock["first-aid"]==1,"Incoming damage interrupts treatment without consuming stock")
	world.use_medicine("bandage");world.equip_slot(1)
	check(u.healing.is_empty() and u.medical_stock.bandage==2,"Weapon switch cancels treatment")
	u.health=u.max_health
	check(not world.use_medicine("bandage"),"No medicine wasted at full health")
	u.health=190;world.use_medicine("first-aid");Equipment.tick(u,3.1)
	check(u.health==u.max_health and u.medical_stock["first-aid"]==0,"Healing capped at max HP and finite supply respected")
	u.health=100
	check(not world.use_medicine("first-aid"),"No use with empty medical stock")
	Equipment.initialize(u,catalog.weapons,["m416","p92","army-knife","he-grenade"])
	u.loadout=["m416","p92","army-knife","he-grenade"];world.campaign.active=true
	check(Equipment.options(u,catalog.weapons)==["he-grenade"],"Campaign wheel cannot grant training RPG")
	check(not world.assign_quick_weapon("awm",1),"Campaign cannot equip an unowned gun")
	world.campaign.phase="won"
	check(not world.equip_slot(0) and not world.use_medicine("bandage"),"Finished campaign cannot change combat equipment")
	print("QUICK_EQUIPMENT_CHECK checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
