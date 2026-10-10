extends RefCounted
static func inside(roof: Dictionary,point: Vector2,height: float) -> bool:
	var base=float(roof.elevation)
	if height<base-.05 or height>=base+float(roof.interior_height):return false
	return Geometry2D.is_point_in_polygon(point,roof.interior_points)

static func level(roof: Dictionary,height: float) -> int:
	return clampi(floori((height-float(roof.elevation)+.18)/float(roof.storey_height)),0,1)

static func state(roof: Dictionary,o: Dictionary,point: Vector2,height: float,editing: bool,roof_mode: int) -> Dictionary:
	return object_state(roof,o,inside(roof,point,height) and not editing,level(roof,height),editing,roof_mode)

static func object_state(roof: Dictionary,o: Dictionary,interior: bool,active: int,editing: bool,roof_mode: int) -> Dictionary:
	var role=str(o.get("house_role",""));var storey=int(o.get("storey",0))
	var opacity=1.0;var cut=INF
	if role=="roof":
		opacity=0.0 if not roof.enabled or roof_mode==1 or editing else .13 if interior and roof_mode==2 else 0.0 if interior else 1.0
	elif interior and storey>active:opacity=0.0
	if role=="wall" and interior and storey==active:cut=1.15
	return {"opacity":opacity,"cut":cut,"camera_hidden":opacity<.99}

static func apply(game,view: Dictionary):
	var roof: Dictionary=view.data
	# Evaluate the player's room once for the building and reuse it for the HUD.
	var interior=not game.editing and inside(roof,game.world.player.position,game.world.player.elevation)
	var active=level(roof,game.world.player.elevation)
	view.interior=interior;view.active_storey=active
	if not view.has("members"):
		view.members=[]
		for o in game.world.objects:
			if o.owner==roof.id:view.members.append(o)
	for o in view.members:
		var state=object_state(roof,o,interior,active,game.editing,game.roof_mode)
		o.camera_hidden=state.camera_hidden;o.draw_opacity=state.opacity
		var object_view: Dictionary=game.object_views[o.id]
		object_view.root.visible=o.alive and state.opacity>.015
		if object_view.get("draw_opacity",1.0)!=state.opacity:
			object_view.draw_opacity=state.opacity
			for material in object_view.get("materials",[]):material.set_shader_parameter("cutaway_opacity",state.opacity)
		if object_view.get("cut_height",INF)!=state.cut:
			object_view.cut_height=state.cut;o.aim_cut_height=state.cut;game.pending_rebuild[o.id]=o
	if interior:
		for u in game.world.units:
			if u.player or not inside(roof,u.position,u.elevation):continue
			if level(roof,u.elevation)>active:u.camera_hidden=true;game.actors[u.id].root.hide()
