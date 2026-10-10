extends SceneTree
func _initialize():
	var result=preload("res://qa/runtime_cost_workload.gd").new().run()
	print("RUNTIME_COST "+JSON.stringify(result));quit(0 if result.simulation_time==0 and result.shots==0 else 1)
