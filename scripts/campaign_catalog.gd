extends RefCounted
## Offline chapters derive existing authored scenes without mutating their source.
const PATH="res://data/campaign/chapters.json"
const COUNT=10

static func chapters() -> Array:
	var document=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return document.get("chapters",[]) if document is Dictionary else []

static func chapter(number: int) -> Dictionary:
	for entry in chapters():
		if int(entry.get("id",0))==number:return entry.duplicate(true)
	return {}

static func plan(catalog,number: int,tactic: String="T01") -> Dictionary:
	var entry=chapter(number)
	if entry.is_empty():return {}
	var result: Dictionary={}
	if number==1:
		result=preload("res://scripts/orchard_level.gd").plan(catalog)
	else:
		for source in catalog.scenes:
			if str(source.id)==str(entry.sourceSceneId):result=source.duplicate(true);break
		if result.is_empty():push_error("Missing campaign scene: "+str(entry.sourceSceneId));return {}
		result.id="campaign-chapter-%02d"%number
		result.godot3d={"campaign":true,"range":false,"sourceSceneId":entry.sourceSceneId,"source_scale":40}
		for mount in result.get("emplacements",[]):mount.aiControlled=true
		result.campaignRules={"captureTime":7,"replacementWaveSeconds":.5,"replacementWaveSize":5,"handoffSeconds":1.18}
		preload("res://scripts/campaign_source_adapter.gd").apply_loadouts(result)
		result.campaignMission={"stages":entry.stages.duplicate(true),"eliminationCompletes":true}
		apply_stage(result,0)
	result.title="第 %02d 关 · %s"%[number,entry.title]
	result.levelId=number
	result.godot3d.campaign_chapter=number
	result.godot3d.campaign_offline=true
	result.godot3d.campaign_tactic=tactic if tactic in ["T01","T02","T03"] else "T01"
	result.godot3d.campaign_briefing=entry.briefing
	if number>1:result.godot3d.campaign_briefing+="\n配装暂用已核对的首关武器池；原版逐关运行时未包含在导入文件中。"
	result.godot3d.campaign_tactic_names=entry.tacticNames if number>1 else preload("res://scripts/campaign_plan.gd").NAMES.duplicate()
	return result

static func apply_stage(target: Dictionary,index: int) -> bool:
	var stages: Array=target.get("campaignMission",{}).get("stages",[])
	if index<0 or index>=stages.size():return false
	var stage: Dictionary=stages[index]
	target.controlPoints=[stage.point.duplicate(true)]
	target.godot3d.aiRoutes={}
	for side in ["blue","red"]:
		var routes=[]
		for source_route in stage.get("aiRoutes",{}).get(side,[]):
			var points=[]
			for point in source_route:points.append({"x":point[0],"y":point[1]})
			routes.append(points)
		target.godot3d.aiRoutes[side]=routes
	target.godot3d.campaign_tactics=stage.get("tactics",{}).duplicate(true)
	target.godot3d.campaign_stage=index
	return true
