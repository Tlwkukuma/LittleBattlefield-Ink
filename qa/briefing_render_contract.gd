extends SceneTree
## Frozen native UI startup only; never advances the world or applies input.
var progress: FileAccess
func mark(value: String):
	progress.store_line(value);progress.flush()
func _initialize():
	progress=FileAccess.open("res://qa/performance/briefing-render-progress.log",FileAccess.WRITE)
	run.call_deferred()
func run():
	mark("before scene load")
	var game=load("res://proving_ground.tscn").instantiate()
	game.process_mode=Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	mark("ready "+root.title)
	game._process(0)
	mark("first presentation complete")
	for i in range(6):
		await process_frame
		mark("frame "+str(i))
	mark("complete world_time="+str(game.world.time)+" shots="+str(game.world.shots))
	quit()
