extends RefCounted
## Shared material registry and kinetic structure response; blast/penetration stay separate.
## Compiled once at startup, never parsed or searched in a projectile/AI loop.
static var loaded=false
static var load_count=0
static var materials: Dictionary={}
static var assemblies: Dictionary={}
const MATERIAL_ALIASES={"wood":"timber","brick":"brick","metal":"steel_plate","stone":"stone","concrete":"concrete","sandbag":"sandbag","soil":"soil","sand":"sand"}
static var ammo: Dictionary={}
static var weapon_ids: Dictionary={}
static var component_ids: Dictionary={}
static var component_materials: Dictionary={}
static var mounted_ids: Dictionary={}
static var config: Dictionary={}
static var errors: Array[String]=[]
static var grazing_cutoff=.15
static var terminal_structure_factor=.65
const ASSEMBLY_DAMAGE={"open_steel_frame":"steel_plate","open_timber_frame":"timber","timber_and_foliage":"timber","furniture_wood_parts":"wood_panel","foliage_and_pot":"rubble"}

static func ensure_loaded() -> void:
	if loaded:return
	loaded=true;load_count+=1
	config=JSON.parse_string(FileAccess.get_file_as_string("res://data/cover_rules.json"))
	grazing_cutoff=float(config.modifiers.grazing_cosine_cutoff)
	terminal_structure_factor=float(config.modifiers.terminal_structural_range_factor)
	var ids: Array=[]
	for source in config.materials:
		var profile: Dictionary=source.duplicate(true);profile.index=ids.size()
		ids.append(profile.id);materials[profile.id]=profile
	for id in config.assembly_profiles:assemblies[id]={"id":id,"index":-1,"assembly":config.assembly_profiles[id]}
	for lane in ["kinetic","blast"]:
		var names: Array=config[lane+"_columns"]
		for column in range(names.size()):
			var damage=PackedFloat32Array();damage.resize(ids.size())
			for material in materials.values():
				var count=int(material[lane][column]);damage[material.index]=100.0/count if count>0 else 0.0
			ammo[names[column]]={"id":names[column],"damage":damage,"lane":lane,"penetration":float(config.penetration_budget[column]) if lane=="kinetic" else 0.0}
	ammo.smoke={"id":"smoke","lane":"none","damage":PackedFloat32Array(),"penetration":0.0}
	for family in config.weapon_bindings:
		for id in config.weapon_bindings[family]:weapon_ids[id]=family
	mounted_ids=config.mounted_bindings.duplicate()

static func bind(catalog) -> void:
	ensure_loaded();errors.clear();component_ids.clear();component_materials.clear()
	for id in catalog.components:
		var family=str(config.component_overrides.get(id,""))
		if family.is_empty():
			for prefix in config.component_prefixes:
				if str(id).begins_with(prefix):family=config.component_prefixes[prefix];break
		if family.is_empty():errors.append("cover component missing: "+str(id));continue
		component_ids[id]=family
		component_materials[id]=str(catalog.components[id].get("material",""))
	for id in catalog.weapons:
		if not weapon_ids.has(id):errors.append("cover ammunition missing: "+str(id));continue
		catalog.weapons[id].cover_ammo=ammo[weapon_ids[id]]
	for id in catalog.data.vehicles:
		for mode in catalog.data.vehicles[id].weapons:
			var key=id+"/"+mode
			if not mounted_ids.has(key):errors.append("cover mounted mode missing: "+key);continue
			catalog.data.vehicles[id].weapons[mode].cover_ammo=ammo[mounted_ids[key]]
	for id in catalog.data.emplacements:
		var key="emplacement/"+id
		if not mounted_ids.has(key):errors.append("cover emplacement missing: "+key);continue
		catalog.data.emplacements[id].cover_ammo=ammo[mounted_ids[key]]
	for issue in errors:push_error(issue)

static func annotate(o: Dictionary) -> void:
	var family=str(component_ids.get(o.component_id,""))
	if str(o.get("material",""))!=str(component_materials.get(o.component_id,"")):
		family=MATERIAL_ALIASES.get(o.get("material",""),family)
	# One shared reference, rather than duplicated tables/strings on every wall.
	o.cover_profile=materials.get(family,assemblies.get(family,{}))
	var response: Dictionary=materials.get(ASSEMBLY_DAMAGE.get(family,family),{})
	o.cover_material=response
	o.cover_damage_index=int(response.get("index",-1))
	if response.is_empty() or o.whole:return
	# Convert the reference structural budget into the existing shared HP storage.
	# This keeps explosions/support on the same damage state without a second HP bar.
	var volume=float(o.cell_width)*float(o.cell_height)*float(o.size.y)
	var reference_volume=.25*float(response.thickness_m)
	o.cover_damage_scale=float(o.max_hp)/(100.0*maxf(.001,volume/reference_volume)*float(o.health_scale))
	if o.get("metal_fence",false):
		var volumes=PackedFloat32Array();volumes.resize(o.hp.size())
		for part in o.solid_parts:volumes[part.cell]+=part.size.x*part.size.y*part.size.z
		var scales=PackedFloat32Array();scales.resize(o.hp.size())
		for i in range(scales.size()):scales[i]=float(o.max_hp)/(100.0*maxf(.001,volumes[i]/reference_volume)*float(o.health_scale))
		o.cover_cell_scales=scales

static func kinetic_allowed(o: Dictionary,w: Dictionary,incidence: float=1) -> bool:
	var response: Dictionary=w.get("cover_ammo",{});var index=int(o.get("cover_damage_index",-1))
	return response.get("lane","")=="kinetic" and index>=0 and incidence>=grazing_cutoff and float(response.damage[index])>0

static func kinetic_damage(o: Dictionary,w: Dictionary,index: int,distance_m: float=0,incidence: float=1) -> float:
	var response: Dictionary=w.get("cover_ammo",{})
	var material_index=int(o.get("cover_damage_index",-1))
	if response.get("lane","")!="kinetic" or material_index<0 or incidence<grazing_cutoff:return 0.0
	var base=float(response.damage[material_index])
	if base<=0:return 0.0
	var maximum=float(w.get("range",1200))/40.0;var effective=float(w.get("effectiveRange",maximum*40*.72))/40.0
	if distance_m>maximum:return 0.0
	var attenuation=lerpf(1,terminal_structure_factor,smoothstep(effective,maximum,distance_m))
	var scale=float(o.cover_cell_scales[index]) if o.has("cover_cell_scales") else float(o.cover_damage_scale)
	return base*scale*attenuation*clampf(incidence,0,1)/maxi(1,int(w.get("pellets",1)))
