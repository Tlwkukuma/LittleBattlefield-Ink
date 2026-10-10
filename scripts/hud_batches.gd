extends Control
## Gameplay HUD only: original controls still own layout, input and text values.
## Menus retain native controls; gameplay panels/text share two mesh submissions.
const Geometry=preload("res://scripts/canvas_mesh_batch.gd")
const Glyphs=preload("res://scripts/hud_glyph_atlas.gd")
var game
var atlas=Glyphs.new()
var items: Array=[]
var shape_mesh: ArrayMesh
var text_mesh: ArrayMesh
var previous=""
var enabled=false
var last_ms=0.0
var previous_shapes=""
var shape_builds=0
var text_builds=0
var glyph_canvas
var dirty=true
func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE;name="BatchedBattleHUD";process_priority=100
	glyph_canvas=preload("res://scripts/hud_glyph_instances.gd").new();glyph_canvas.atlas=atlas.texture;add_child(glyph_canvas)
	collect(game.ui)
	# Warm the changing counters before play, rather than allocate/upload a font
	# page on the first new FPS digit or ammunition value during a firefight.
	for size in [11,12,13,14,15,16,17,18,21,30,35]:atlas.layout("0123456789 .,:/%—-+",game.ui.theme.default_font,size)
	atlas.upload()
func collect(node: Node):
	if node==self or node.get_meta("hud_native",false):return
	if node is Label or node is Button or node is PanelContainer:
		items.append({"node":node,"color":node.self_modulate,"text_stamp":"","geometry":null})
		node.draw.connect(func():
			dirty=true
			if enabled:RenderingServer.canvas_item_clear(node.get_canvas_item()))
		node.item_rect_changed.connect(func():dirty=true)
		node.visibility_changed.connect(func():dirty=true)
	for child in node.get_children():collect(child)
func _process(_delta: float):refresh()
func refresh():
	var started=Time.get_ticks_usec()
	var active=(game.world.campaign_active() or game.is_style_range()) and not game.armory.visible and not game.editing and not game.paused and not game.wheel_open()
	if active!=enabled:
		enabled=active;previous="";dirty=true
		for item in items:
			if is_instance_valid(item.node):item.node.queue_redraw()
	visible=active
	if not active:last_ms=0.0;return
	if not dirty:last_ms=(Time.get_ticks_usec()-started)/1000.0;return
	dirty=false
	var stamp="";var shape_stamp="";var live=[]
	for item in items:
		var node=item.node
		if not is_instance_valid(node) or not node.is_visible_in_tree():
			if not item.get("glyph_slots",[]).is_empty():glyph_canvas.clear_item(item)
			continue
		var state=node.get_draw_mode() if node is Button else 0
		var color=node.get_theme_color("font_color") if node is Label or node is Button else Color.WHITE
		var item_stamp=str(node.get_instance_id(),node.get_global_rect(),node.text if node is Label or node is Button else "",state,color)
		stamp+=item_stamp
		if node is PanelContainer or node is Button:shape_stamp+=str(node.get_instance_id(),node.get_global_rect(),state)
		live.append({"node":node,"color":color,"state":state,"cache":item,"stamp":item_stamp})
	if stamp==previous:last_ms=(Time.get_ticks_usec()-started)/1000.0;return
	previous=stamp;var shapes=Geometry.new();shapes.enabled=shape_stamp!=previous_shapes
	for item in live:
		var node=item.node;var rect: Rect2=node.get_global_rect();rect.position-=global_position
		if node is PanelContainer:shapes.style(node.get_theme_stylebox("panel"),rect)
		var part: Dictionary=item.cache
		if part.text_stamp==item.stamp and part.geometry!=null:
			if node is Button:
				var cached_state="disabled" if node.disabled else "pressed" if node.is_pressed() else "hover" if node.is_hovered() else "normal"
				shapes.style(node.get_theme_stylebox(cached_state),rect)
			continue
		var item_text=Geometry.new()
		if node is PanelContainer:pass
		elif node is Button:
			var state="disabled" if node.disabled else "pressed" if node.is_pressed() else "hover" if node.is_hovered() else "normal"
			var style=node.get_theme_stylebox(state);shapes.style(style,rect)
			var font=node.get_theme_font("font");var font_size=node.get_theme_font_size("font_size")
			var shaped=atlas.layout(node.text,font,font_size,rect.size.x,HORIZONTAL_ALIGNMENT_CENTER)
			atlas.append(item_text,shaped,rect.position+Vector2(0,(rect.size.y-shaped.height)*.5),node.get_theme_color("font_"+state+"_color") if state!="normal" else item.color)
		elif node is Label:
			var shaped=atlas.layout(node.text,node.get_theme_font("font"),node.get_theme_font_size("font_size"),rect.size.x,node.horizontal_alignment,node.autowrap_mode!=TextServer.AUTOWRAP_OFF)
			var y=maxf(0,rect.size.y-shaped.height)*(.5 if node.vertical_alignment==VERTICAL_ALIGNMENT_CENTER else 1.0 if node.vertical_alignment==VERTICAL_ALIGNMENT_BOTTOM else 0.0)
			atlas.append(item_text,shaped,rect.position+Vector2(0,y),item.color)
		part.text_stamp=item.stamp;part.geometry=item_text;glyph_canvas.update_item(part,item_text)
	if shapes.enabled:shape_mesh=shapes.mesh();previous_shapes=shape_stamp;shape_builds+=1
	text_builds+=1;atlas.upload();queue_redraw();last_ms=(Time.get_ticks_usec()-started)/1000.0
func _draw():
	if shape_mesh!=null and shape_mesh.get_surface_count()>0:draw_mesh(shape_mesh,null)
