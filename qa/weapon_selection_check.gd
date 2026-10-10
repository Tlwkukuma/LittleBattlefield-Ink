extends SceneTree
## Ordered-slot and live-state fixtures only. No scene, input injection or world.step.
const Equipment=preload("res://scripts/quick_equipment.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Fire=preload("res://scripts/weapon_fire_control.gd")
const Wheel=preload("res://scripts/equipment_wheel.gd")
class GameFixture extends Node:
	var world
var checks=0
var failures=[]
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func selected_count(slots: Array) -> int:
	var result=0
	for entry in slots:
		if entry.selected:result+=1
	return result
func _initialize():
	var catalog=Catalog.new();var world=World.new();world.catalog=catalog
	world.player=world.add_unit(Vector2.ZERO,true)
	var u: Dictionary=world.player
	check(world.equipment_entries().size()==4,"Foot scroll exposes only equipped weapons and selected tactical")
	for index in [1,2,3,0]:
		check(world.next_equipment_slot(1)==index,"Forward cycle matches number slot "+str(index+1))
		check(world.equip_slot(index),"Shared selection accepts foot slot "+str(index+1))
	check(world.next_equipment_slot(-1)==3,"Reverse cycle wraps")
	world.clear_quick_slot(1);world.equip_slot(0)
	check(world.next_equipment_slot(1)==2,"Wheel skips empty equipment positions")
	world.holster()
	check(world.next_equipment_slot(1)==0 and world.next_equipment_slot(-1)==3,"Scrolling from holster draws the first/last available weapon")
	var empty=u.duplicate(true);empty.quick_slots=["","",""];empty.quick_tactical=""
	check(Equipment.next_slot(Equipment.entries(empty,catalog.weapons,[]),1)==-1,"Empty loadout cannot create a weapon")
	var personal={"weapon":u.weapon_id,"slots":u.quick_slots.duplicate(),"ammo":u.ammo,"reserve":u.reserve,"inventory":u.inventory.duplicate(true),"holstered":u.holstered}
	for fixed in [false,true]:
		var profiles: Dictionary=catalog.data.emplacements if fixed else catalog.data.vehicles
		for type in profiles:
			var profile: Dictionary=profiles[type];var modes: Array=["primary"] if fixed else profile.weaponOrder.duplicate()
			var v={"profile":profile,"modes":modes,"mode":0,"states":{},"emplacement":fixed,"destroyed":false,"driver":true}
			for mode in modes:
				var w: Dictionary=profile if fixed else profile.weapons[mode]
				var state={"ammo":maxi(0,int(w.mag)-1),"reserve":17,"reload":.8,"reload_duration":float(w.reload),"cooldown":.47}
				Fire.reset(state,w);v.states[mode]=state
			world.vehicles.append(v);u.mounted=world.vehicles.size()-1
			var slots=world.equipment_entries()
			check(slots.size()==modes.size() and selected_count(slots)==1,"Only actual mount channels, one active slot: "+type)
			check(Equipment.selection_available(u,world.vehicles),"Wheel accepts mount: "+type)
			check(not Equipment.available(u),"Personal inventory remains protected while mounted: "+type)
			for index in range(modes.size()):
				var angle=-PI*.5+index*TAU/modes.size()
				check(Equipment.sector(Vector2.from_angle(angle)*180,modes.size())==index,"Wheel/number sector agrees: "+type+" "+str(index))
				world.active_state().fire_pending=2
				var previous=int(v.mode)
				check(world.equip_slot(index) and v.mode==index,"Shared numeric/wheel selection reaches channel: "+type+" "+str(index))
				if previous!=index:
					check(v.states[modes[previous]].fire_pending==0 and world.active_state().fire_pending==0 and world.active_state().fire_lock,"No held trigger or burst leaks across channels: "+type)
				check(world.next_equipment_slot(1)==posmod(index+1,modes.size()) and world.next_equipment_slot(-1)==posmod(index-1,modes.size()),"Bidirectional mount scroll wraps: "+type)
				var entry: Dictionary=world.equipment_entries()[index]
				check(entry.state.ammo==world.active_state().ammo and entry.weapon==world.active_weapon(),"Wheel and HUD use active weapon/ammunition: "+type)
				check(is_equal_approx(entry.state.reload,.8) and is_equal_approx(entry.state.cooldown,.47) and entry.state.reserve==17,"Reload/cooldown/ammo survive selection: "+type)
			check(not world.equip_slot(-1) and not world.equip_slot(modes.size()),"Unavailable number slots never draw personal weapon: "+type)
			check(not world.holster() and not world.use_medicine("bandage"),"No personal holster/medical action inside mount: "+type)
			v.destroyed=true
			check(not Equipment.selection_available(u,world.vehicles) and not world.equip_slot(0),"Destroyed mount rejects all selectors: "+type)
			v.destroyed=false;u.alive=false
			check(not world.equip_slot(0),"Dead operator cannot switch: "+type)
			u.alive=true;world.campaign.active=true;world.campaign.phase="won"
			check(not world.equip_slot(0),"Ended round blocks mounted selection: "+type)
			world.campaign.active=false
	check(u.weapon_id==personal.weapon and u.quick_slots==personal.slots and u.ammo==personal.ammo and u.reserve==personal.reserve and u.inventory==personal.inventory and u.holstered==personal.holstered,"All mount switching leaves personal loadout untouched")
	var game=GameFixture.new();game.world=world;var overlay=Wheel.new();overlay.game=game;overlay.owner_id=u.id;overlay.owner_mount=u.mounted
	check(overlay.same_context(),"Wheel owns current operator and vehicle")
	u.mounted=-1
	check(not overlay.same_context(),"Dismount invalidates pending mounted selection")
	check(world.equipment_entries().size()==4 and world.equipment_entries()[0].id==personal.slots[0],"Dismount restores personal slot mapping")
	overlay.free();game.free()
	check(Equipment.sector(Vector2.ZERO,3)==-1 and Equipment.sector(Vector2(180,0),0)==-1,"Central dead zone and empty mounted layout cancel")
	print("WEAPON_SELECTION_CHECK checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
