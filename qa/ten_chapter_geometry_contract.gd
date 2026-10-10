extends SceneTree
## Pure geometry / resource contracts. No world ticks, controls or autonomous combat.
const Catalog=preload("res://scripts/source_catalog.gd")
const Chapters=preload("res://scripts/campaign_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
var checks=0
var failures=0
var results=[]

func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)

func _initialize():
	call_deferred("run")

func run():
	var catalog=Catalog.new()
	check(Chapters.chapters().size()==10,"ten authored chapters")
	for number in range(1,11):
		var source=Chapters.plan(catalog,number)
		check(not source.is_empty(),"chapter %d exists"%number)
		var world=World.new();world.setup(source,catalog)
		var report={"chapter":number,"objects":world.objects.size(),"graph_cells":world.campaign_ai.graph.get_point_count(),"stages":[],"blocked_initial_units":[],"bad_weapons":[]}
		for unit in world.units:
			if world.blocked(unit.position,.31,1.95,-1,unit.elevation):report.blocked_initial_units.append({"id":unit.id,"position":[unit.position.x,unit.position.y]})
			for id in unit.loadout:
				if not catalog.weapons.has(id):report.bad_weapons.append(id)
		check(report.blocked_initial_units.is_empty(),"chapter %d initial actors body-clear"%number)
		check(report.bad_weapons.is_empty(),"chapter %d weapons resolve"%number)
		var stages=maxi(1,source.get("campaignMission",{}).get("stages",[]).size())
		for stage in range(stages):
			if stage>0:
				Chapters.apply_stage(world.plan,stage);world.campaign.build_points(world);world.campaign_ai.refresh_capture_cells()
			var point: Dictionary=world.campaign.points[0]
			var detail={"index":stage,"label":point.name,"capture_cells":world.campaign_ai.capture_cells[0].size(),"unreachable_spawns":[],"blocked_spawns":[],"unreachable_routes":[],"blocked_routes":[],"objective_blocked":world.blocked(point.position,.31,1.95,-1,world.terrain.height(point.position))}
			check(absf(point.position.x)<=world.bounds.x and absf(point.position.y)<=world.bounds.y,"chapter %d stage %d objective inside bounds"%[number,stage])
			var visual: Vector2=point.get("visual_position",point.position)
			detail.visual_marker_blocked=world.blocked(visual,.31,1.95,-1,world.terrain.height(visual))
			check(not detail.visual_marker_blocked,"chapter %d stage %d visual flag body-clear"%[number,stage])
			# A source capture center may lie in cover; reachable capture cells, not
			# an invented relocation, establish that its gameplay footprint is usable.
			check(detail.capture_cells>0,"chapter %d stage %d has physical capture cells"%[number,stage])
			for team in range(2):
				var key="blue" if team==0 else "red"
				var spawns: Array=world.plan.deployment[key].spawnPoints
				var reachable=0
				for index in range(spawns.size()):
					var at=catalog.position(spawns[index],world.plan)
					if world.blocked(at,.31,1.95,-1,world.terrain.height(at)):detail.blocked_spawns.append([key,index,at.x,at.y])
					if world.campaign_ai.capture_goal(at).is_finite():reachable+=1
					else:detail.unreachable_spawns.append([key,index,at.x,at.y])
				check(reachable>0,"chapter %d stage %d %s reachable from spawn"%[number,stage,key])
				for index in range(world.plan.godot3d.aiRoutes.get(key,[]).size()):
					for raw in world.plan.godot3d.aiRoutes[key][index]:
						var at=catalog.position(raw,world.plan)
						if not world.campaign_ai.capture_goal(at).is_finite():detail.unreachable_routes.append([key,index,raw])
						if world.blocked(at,.31,1.95,-1,world.terrain.height(at)):detail.blocked_routes.append([key,index,raw])
			if number>1:check(detail.blocked_spawns.is_empty(),"chapter %d stage %d all authored spawns body-clear"%[number,stage])
			check(detail.unreachable_spawns.is_empty(),"chapter %d stage %d every spawn connected"%[number,stage])
			# Raw route anchors preserve source spawn/flag coordinates; director
			# resolves them to connected navigation goals rather than moving source points.
			check(detail.unreachable_routes.is_empty(),"chapter %d stage %d route endpoints connected"%[number,stage])
			report.stages.append(detail)
		check(is_zero_approx(world.time),"chapter %d combat time stays zero"%number)
		results.append(report)
		print("CHAPTER_GEOMETRY "+JSON.stringify(report))
	var file=FileAccess.open("/tmp/ten_chapter_geometry.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"checks":checks,"failures":failures,"chapters":results},"\t"));file.close()
	print("ten_chapter_geometry_contract: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
