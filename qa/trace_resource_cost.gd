extends SceneTree
## Read-only ray geometry microbenchmark in the frozen original entry scene.
## No world.step, decisions, input, shots, damage or battle advancement.
func _initialize():run.call_deferred()

func run():
	var source=FileAccess.get_file_as_string("res://scripts/proving_world.gd").replace("\r\n","\n")
	var start=source.find("func trace_3d(");var end=source.find("\nfunc detonate(",start)
	var trace=source.substr(start,end-start)
	trace=trace.replace(" -> Dictionary:\n", " -> Dictionary:\n\tvar qa_start=Time.get_ticks_usec()\n")
	trace=trace.replace("\tvar start=Vector2(origin.x,origin.z)","\tqa_trace.terrain+=Time.get_ticks_usec()-qa_start;qa_start=Time.get_ticks_usec()\n\tvar start=Vector2(origin.x,origin.z)")
	trace=trace.replace("\tfor vehicle in vehicles:","\tqa_trace.objects+=Time.get_ticks_usec()-qa_start;qa_start=Time.get_ticks_usec()\n\tfor vehicle in vehicles:")
	trace=trace.replace("\tif walls_only:return best", "\tqa_trace.vehicles+=Time.get_ticks_usec()-qa_start;qa_start=Time.get_ticks_usec()\n\tif walls_only:return best")
	trace=trace.replace("\treturn best\n", "\tqa_trace.units+=Time.get_ticks_usec()-qa_start\n\treturn best\n")
	source=source.substr(0,start)+trace+source.substr(end)
	source=source.replace("var profile_ai=false", "var profile_ai=false\nvar qa_trace={\"terrain\":0,\"objects\":0,\"vehicles\":0,\"units\":0}")
	var measured=GDScript.new();measured.source_code=source
	if measured.reload()!=OK:quit(1);return
	var game=load("res://proving_ground.tscn").instantiate();game.world=measured.new();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	await process_frame
	var world=game.world;var records=[]
	for length in [.12,8.0,25.0]:
		for walls_only in [true,false]:
			var rays=[]
			for i in range(360):
				var unit=world.units[i%world.units.size()]
				var origin=Vector3(unit.position.x,unit.elevation+1.3,unit.position.y)
				var flat=Vector2.from_angle(float(i)*2.3999632297)
				var direction=Vector3(flat.x,-.08 if i%3==0 else 0.0,flat.y).normalized()
				rays.append([origin,direction,{"source":unit.id,"team":unit.team}])
			world.qa_trace={"terrain":0,"objects":0,"vehicles":0,"units":0}
			var began=Time.get_ticks_usec()
			for ray in rays:world.trace_3d(ray[0],ray[1],length,ray[2],walls_only)
			var total=Time.get_ticks_usec()-began
			records.append({"length_m":length,"walls_only":walls_only,"rays":rays.size(),"total_ms":total/1000.0,"stages_usec":world.qa_trace.duplicate()})
	var nodes={};var zero_layers=0;var pending=[game]
	while not pending.is_empty():
		var node=pending.pop_back();var kind=node.get_class();nodes[kind]=int(nodes.get(kind,0))+1
		if node is MeshInstance3D and node.layers==0:zero_layers+=1
		pending.append_array(node.get_children())
	var result={"records":records,"nodes":nodes,"source_meshes_layers_zero":zero_layers,"units":world.units.size(),"vehicles":world.vehicles.size(),"objects":world.objects.size(),"time":world.time,"shots":world.shots}
	var output=FileAccess.open("res://qa/performance/trace-resource-cost-v32.json",FileAccess.WRITE);output.store_string(JSON.stringify(result,"\t"));output.close()
	print("TRACE_RESOURCE_COST "+JSON.stringify(result))
	game.free();quit()
