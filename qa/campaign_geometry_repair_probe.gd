extends SceneTree
## Read-only nearest body-clear graph-cell proposals for authored metadata review.
const Catalog=preload("res://scripts/source_catalog.gd")
const Chapters=preload("res://scripts/campaign_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
func _initialize():call_deferred("run")
func run():
	var catalog=Catalog.new();var output=[]
	var report=JSON.parse_string(FileAccess.get_file_as_string("/tmp/ten_chapter_geometry.json"))
	for chapter in report.chapters:
		if int(chapter.chapter)==1:continue
		var pending=[]
		for stage in chapter.stages:
			if stage.objective_blocked:
				var point=Chapters.chapter(int(chapter.chapter)).stages[int(stage.index)].point
				pending.append([float(point.x),float(point.y)])
			for route in stage.blocked_routes:
				var at=[float(route[2].x),float(route[2].y)]
				if at not in pending:pending.append(at)
		if pending.is_empty():continue
		var world=World.new();world.setup(Chapters.plan(catalog,int(chapter.chapter)),catalog)
		for source in pending:
			var at=catalog.position(source,world.plan)
			var id=world.campaign_ai.graph.get_closest_point(at)
			var candidate=world.campaign_ai.graph.get_point_position(id)
			var pixel=catalog.original_point(candidate,world.plan)
			var entry={"chapter":chapter.chapter,"from":source,"to":[pixel.x,pixel.y],"distance_m":at.distance_to(candidate),"body_clear":not world.blocked(candidate,.31,1.95,-1,world.terrain.height(candidate))}
			output.append(entry);print("GEOMETRY_SUGGESTION "+JSON.stringify(entry))
	var file=FileAccess.open("/tmp/campaign_geometry_suggestions.json",FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close();quit()
