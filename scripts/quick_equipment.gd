extends RefCounted
## Three freely assigned weapons, a tactical selector, medicine and holster.
## This is a quick-access loadout, not an infinite-ammo replacement for inventory.
const MEDICINE={"bandage":{"name":"绷带","heal":40.0,"seconds":1.8},"first-aid":{"name":"急救包","heal":100.0,"seconds":3.0}}
const MEDICAL_IDS=["bandage","first-aid"]

static func tactical(w: Dictionary) -> bool:
	return str(w.get("kind","")) in ["grenade","rocket","grenadeProjectile","mortar"]

static func initialize(u: Dictionary,weapons: Dictionary,source: Array=[],training: bool=false):
	u.quick_owned=[];u.quick_slots=["","",""];u.quick_tactical="";u.quick_active_slot=0
	u.holstered=false;u.equip_remaining=0.0;u.equip_duration=.35;u.healing={}
	u.medical_selected="bandage";u.medical_stock={"bandage":3,"first-aid":1};u.medical_feedback={}
	u.weapon_copies={};u.loot_dropped=false
	var initial: Array=source.duplicate()
	if training:initial=["m416","awm","army-knife","p92","he-grenade","smoke-grenade","rpg"]
	var slot=0
	for value in initial:
		var id=str(value)
		if not weapons.has(id) or id in u.quick_owned:continue
		u.quick_owned.append(id)
		if tactical(weapons[id]):
			if u.quick_tactical.is_empty():u.quick_tactical=id
		elif slot<3:u.quick_slots[slot]=id;slot+=1
	var current=u.quick_slots.find(str(u.get("weapon_id","")))
	u.quick_active_slot=maxi(0,current)

static func options(u: Dictionary,weapons: Dictionary) -> Array:
	var result=[]
	for id in u.get("quick_owned",[]):
		if weapons.has(id) and tactical(weapons[id]):result.append(id)
	return result

static func assign(u: Dictionary,w: Dictionary,slot: int=-1) -> void:
	var id=str(w.id)
	if id not in u.quick_owned:u.quick_owned.append(id)
	if tactical(w):u.quick_tactical=id;return
	var index=clampi(int(u.quick_active_slot) if slot<0 else slot,0,2)
	var previous=u.quick_slots.find(id)
	if previous>=0:u.quick_slots[previous]=u.quick_slots[index]
	u.quick_slots[index]=id;u.quick_active_slot=index

static func slot_weapon(u: Dictionary,index: int) -> String:
	if index==3:return str(u.get("quick_tactical",""))
	var slots: Array=u.get("quick_slots",[])
	return str(slots[index]) if index>=0 and index<slots.size() else ""

static func available(u: Dictionary) -> bool:
	return bool(u.get("alive",false)) and int(u.get("mounted",-1))<0 and u.get("vault",{}).is_empty() and u.get("ladder",{}).is_empty()

static func selection_available(u: Dictionary,vehicles: Array) -> bool:
	if not u.get("alive",false) or not u.get("vault",{}).is_empty() or not u.get("ladder",{}).is_empty():return false
	var mount=int(u.get("mounted",-1))
	if mount<0:return true
	return mount<vehicles.size() and not vehicles[mount].get("destroyed",false) and vehicles[mount].get("driver",false)

static func entries(u: Dictionary,weapons: Dictionary,vehicles: Array) -> Array:
	# Wheel, numbers, scrolling and HUD read the same ordered slots and live states.
	var result=[];var mount=int(u.get("mounted",-1))
	if mount>=0:
		if mount>=vehicles.size():return result
		var v: Dictionary=vehicles[mount]
		for index in range(v.modes.size()):
			var mode=str(v.modes[index]);var w: Dictionary=v.profile if v.emplacement else v.profile.weapons[mode]
			result.append({"index":index,"id":mode,"weapon":w,"state":v.states[mode],"selected":index==int(v.mode),"mounted":true})
	else:
		for index in range(4):
			var id=slot_weapon(u,index);var w: Dictionary=weapons.get(id,{})
			var state: Dictionary=u if id==u.get("weapon_id","") else u.get("inventory",{}).get(id,{"ammo":w.get("mag",0),"reserve":w.get("reserve",0)})
			result.append({"index":index,"id":id,"weapon":w,"state":state,"selected":not w.is_empty() and id==u.get("weapon_id","") and not u.get("holstered",false),"mounted":false})
	return result

static func next_slot(slots: Array,direction: int) -> int:
	var choices=[];var current=-1
	for entry in slots:
		if entry.weapon.is_empty():continue
		if entry.selected:current=choices.size()
		choices.append(int(entry.index))
	if choices.is_empty() or direction==0:return -1
	if current<0:return choices[0] if direction>0 else choices.back()
	return choices[posmod(current+(1 if direction>0 else -1),choices.size())]

static func busy(u: Dictionary) -> bool:
	return bool(u.get("holstered",false)) or float(u.get("equip_remaining",0))>0 or not u.get("healing",{}).is_empty()

static func draw_time(w: Dictionary) -> float:
	if w.kind=="melee":return .26
	if tactical(w):return .28 if w.kind=="grenade" else .65
	return .25 if w.get("archetype","") in ["pistol","machinepistol"] else .42

static func begin_heal(u: Dictionary,id: String) -> bool:
	if not available(u) or not u.get("grounded",true) or not MEDICINE.has(id) or not u.get("healing",{}).is_empty():return false
	u.medical_selected=id
	if int(u.get("medical_stock",{}).get(id,0))<=0:
		u.medical_feedback={"kind":"empty","remaining":.8};return false
	if u.health>=u.max_health:
		u.medical_feedback={"kind":"full","remaining":.8};return false
	u.medical_feedback={}
	u.healing={"id":id,"remaining":float(MEDICINE[id].seconds),"duration":float(MEDICINE[id].seconds),"health":float(u.health)}
	return true

static func tick(u: Dictionary,delta: float):
	u.equip_remaining=maxf(0,float(u.get("equip_remaining",0))-delta)
	var feedback: Dictionary=u.get("medical_feedback",{})
	if not feedback.is_empty():
		feedback.remaining=maxf(0,float(feedback.remaining)-delta)
		if feedback.remaining<=0:u.medical_feedback={}
	var action: Dictionary=u.get("healing",{})
	if action.is_empty():return
	if not available(u) or not u.get("grounded",true) or float(u.health)<float(action.health):u.healing={};return
	action.remaining=maxf(0,float(action.remaining)-delta)
	if action.remaining>0:return
	var id=str(action.id)
	if int(u.medical_stock.get(id,0))>0 and u.health<u.max_health:
		u.medical_stock[id]-=1;u.health=minf(u.max_health,float(u.health)+float(MEDICINE[id].heal))
		u.medical_feedback={"kind":"complete","remaining":.65}
	u.healing={}

static func sector(offset: Vector2,count: int=6) -> int:
	# Clockwise: weapon 1, weapon 2, tactical, holster, medicine, weapon 3.
	if offset.length()<84 or count<=0:return -1
	return posmod(int(floor((offset.angle()+PI*.5+PI/count)/(TAU/count))),count)

static func slot_for_sector(index: int) -> int:
	return {0:0,1:1,5:2,2:3}.get(index,-1)

static func cycle(values: Array,current: String,direction: int) -> String:
	if values.is_empty():return ""
	return str(values[posmod(maxi(0,values.find(current))+direction,values.size())])
