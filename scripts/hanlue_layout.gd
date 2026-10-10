extends RefCounted
## Historical-inspired gameplay map; geometry, forces and kit are not a reconstruction.
## Positions/radii are source units (40 per metre), terrain dimensions use metres.
const ID="hanlue-h01"
const WORLD_SIZE=Vector2(3520,2240)
const ROAD_Y=1120
const ROAD_DEPTH=2.4
const CONVOY_IDS=["hanlue-truck-1","hanlue-truck-2","hanlue-truck-3"]
const RAMPS=[
	{"points":[[1080,1000],[1080,560]],"width_m":4.0,"landing_length_m":1.5},
	{"points":[[2360,1000],[2360,560]],"width_m":4.0,"landing_length_m":1.5},
	{"points":[[1080,1240],[1080,1680]],"width_m":4.0,"landing_length_m":1.5},
	{"points":[[2360,1240],[2360,1680]],"width_m":4.0,"landing_length_m":1.5}]
const GROUPS=[
	{"id":"head","label":"封头组","x":2660,"y":850,"angle":PI*.5},
	{"id":"tail","label":"断尾组","x":800,"y":1390,"angle":-PI*.5},
	{"id":"north","label":"北翼组","x":1640,"y":850,"angle":PI*.5},
	{"id":"south","label":"南翼组","x":1880,"y":1390,"angle":-PI*.5}]

static func plan(_catalog) -> Dictionary:
	var result={"format":"endless-war-scene-plan","version":"2.0.0","id":ID,"levelId":101,
		"title":"亮剑主题 · H01 韩略村伏击","enabled":true,
		"brief":"隐蔽待机，封头断尾，打击有限车队后撤离。历史背景启发，地图、兵力、装备与时长为玩法缩编。",
		"world":{"w":WORLD_SIZE.x,"h":WORLD_SIZE.y,"seed":19431024,"theme":"forest","groundFeatures":terrain()},
		"instances":[],"looseSegments":[],"trees":[],"vehicles":[],"emplacements":[],
		"units":{"blue":[],"red":[]},"controlPoints":[],"waves":[],"reinforcementStreams":[],
		"deployment":{"player":{},"blue":force(),"red":force()},
		"objective":{"type":"hanlueAmbush","label":"重创车队、有效打击并撤离"},
		"campaignRules":{"captureTime":7,"replacementWaveSeconds":1,"replacementWaveSize":0,"handoffSeconds":1.18,"blueCapIncludesPlayer":true},
		"campaignMission":{},
		"campaignSource":{"runtimeExportAvailable":false,"historicalReconstruction":false,"equipment":"existing verified gameplay kit; no exact historical model claim"},
		"godot3d":{"campaign":true,"range":false,"campaign_offline":true,"hanlue":true,"source_layout":true,
			"source_scale":40,"combat_camera_size":25.0,"battlefield_border":false,"layout_revision":2,
			"campaign_tactic":"T01","campaign_tactic_names":{"T01":"封头断尾","T02":"两翼分割","T03":"准备撤离"},
			"campaign_briefing":"韩略村附近公路伏击的历史骨架。两侧高坎与四处坡口均为真实地形；信号前友军隐蔽待机，完成打击后及时转移。人数、装备和地形为玩法缩编。",
			"aiRoutes":{"blue":[],"red":[]},"vehicleRoutes":{},"campaign_tactics":{}},
		"hanlueMission":mission_config()}
	add_roster(result)
	add_cover(result)
	return result

static func force() -> Dictionary:
	return {"initialCount":12,"totalForce":12,"maxActive":12,"spawnPoints":[],"replacementLoadouts":[],"specialWeaponPlans":[]}

static func mission_config() -> Dictionary:
	return {"id":"H01","convoyIds":CONVOY_IDS.duplicate(),"convoyRoute":[[200,ROAD_Y],[1760,ROAD_Y],[3320,ROAD_Y]],
		"convoyAssignments":[],"deploymentGroups":[],
		"extractionZones":[{"id":"north-extract","label":"北侧撤离点","x":1760,"y":220,"r":220},{"id":"south-extract","label":"南侧撤离点","x":1760,"y":2020,"r":220}],
		"escapeZones":[{"id":"east-escape","x":3320,"y":ROAD_Y,"r":140},{"id":"west-escape","x":80,"y":ROAD_Y,"r":60}],
		"ambushZone":{"x":1760,"y":ROAD_Y,"r":680},"rampRoutes":RAMPS.duplicate(true),
		"prepareSeconds":12.0,"convoyDeadlineSeconds":150.0,"combatSeconds":180.0,"withdrawalSeconds":90.0,
		"disruptedRequired":2,"strikeRequired":4,"extractedRequired":4,
		"historicalNote":"1943年韩略村伏击背景启发；地图、人数、装备、目标与时长均为玩法参数，不作精确历史复刻。"}

static func terrain() -> Array:
	# The same triangulated cut drives drawing, bullet cover, infantry and vehicles.
	# No level pad on the road: flattening would erase the depression and ramp ends.
	var features=[{"id":"hanlue-sunken-road","componentId":"landform.trench-network","kind":"path",
		"points":[[-320,ROAD_Y],[3840,ROAD_Y]],"depth_m":ROAD_DEPTH,"bottom_width_m":7.0,
		"bank_run_m":1.6,"corner_radius_m":0.0,"corner_widen_m":0.0,"ramps":RAMPS.duplicate(true),
		"mapKitVisual":{"fill":"#a49370","alpha":.85}},
		{"id":"hanlue-road-surface","kind":"path","surface":"track","pathMode":"polyline",
		"points":[[-320,ROAD_Y],[3840,ROAD_Y]],"width":200,"shoulderWidth":240,"seams":false,
		"mapKitVisual":{"fill":"#b69a6c","alpha":.96}}]
	# Low natural folds screen prone heads from road-level observation. Their
	# approach slope remains walkable and starting body cells stay flat. The
	# footprint ends before the ramp centre lanes; these are physical soil,
	# not visibility flags, walls or generated fortifications.
	var ridge_bounds=[[2504,860,2860,964],[600,1276,960,1380],
		[1440,860,1840,964],[1680,1276,2080,1380]]
	for index in range(ridge_bounds.size()):
		var b: Array=ridge_bounds[index]
		features.append({"id":"hanlue-concealment-"+str(GROUPS[index].id),"componentId":"landform.low-hill","kind":"area",
			"points":[[b[0],b[1]],[b[2],b[1]],[b[2],b[3]],[b[0],b[3]]],
			"height_m":.6,"plateau_size_m":[6.0,1.0],"slope_runs_m":[.4,.4,.8,.8],
			"mapKitVisual":{"fill":"#a49370","alpha":.85}})
	return features

static func infantry(id: String,x: float,y: float,angle: float,machinegun: bool=false) -> Dictionary:
	# Mature existing weapon behaviour; RPD is a gameplay stand-in, not 1943 issue.
	return {"id":id,"x":x,"y":y,"angle":angle,"label":"伏击队员",
		"loadout":["rpd" if machinegun else "kar98k","r1895","army-knife","he-grenade"]}

static func add_roster(result: Dictionary) -> void:
	for group_index in range(GROUPS.size()):
		var source: Dictionary=GROUPS[group_index];var group=source.duplicate(true);group.unitIds=[]
		for slot in range(3):
			var id="hanlue-blue-%02d"%(group_index*3+slot+1)
			var unit=infantry(id,float(source.x)+(slot-1)*44,float(source.y),float(source.angle),slot==2 and group_index>=2)
			group.unitIds.append(id)
			if group_index==0 and slot==0:result.deployment.player=unit
			else:result.units.blue.append(unit)
		result.hanlueMission.deploymentGroups.append(group)
	for index in range(CONVOY_IDS.size()):
		var x=960-index*320;var vehicle_id=CONVOY_IDS[index]
		result.vehicles.append({"id":vehicle_id,"type":"truck","team":"red","x":x,"y":ROAD_Y,"angle":0.0,"aiControlled":true})
		result.godot3d.vehicleRoutes[vehicle_id]=[[1760,ROAD_Y],[3320,ROAD_Y]]
		var assignment={"vehicleId":vehicle_id,"unitIds":[]}
		for slot in range(4):
			var id="hanlue-red-%02d"%(index*4+slot+1)
			# Legal road-shoulder staging outside hulls; transport boards this same
			# finite roster after placement rather than creating hidden extra troops.
			var unit=infantry(id,x-48+(slot%2)*96,ROAD_Y+(-100 if slot<2 else 100),0.0)
			unit.label="车队人员";result.units.red.append(unit);assignment.unitIds.append(id)
		result.hanlueMission.convoyAssignments.append(assignment)

static func add_cover(result: Dictionary) -> void:
	# Sparse trunks/rocks keep four ramp lanes and both extraction fans clear.
	var tree_points=[[400,420],[680,630],[1400,420],[2140,380],[2920,500],[3140,780],
		[420,1810],[660,1610],[1380,1850],[2150,1870],[2860,1660],[3140,1900]]
	for index in range(tree_points.size()):
		var at: Array=tree_points[index]
		result.trees.append({"id":"hanlue-tree-%02d"%index,"x":at[0],"y":at[1],"radius":48,"species":"broadleaf","mapKitComponentId":"tree.broadleaf"})
	for index in range(4):
		var source: Dictionary=GROUPS[index]
		var x=float(source.x)+100;var y=float(source.y)+(-100 if float(source.y)<ROAD_Y else 100)
		result.looseSegments.append({"id":"hanlue-rock-%d"%index,"componentId":"obstacle.rock-small","x1":x,"y1":y,"x2":x+36,"y2":y,"thickness":52,"godot3d":{"height":.85}})
