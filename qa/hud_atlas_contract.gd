extends SceneTree
## Font resources only; no battle, input or substitute visual acceptance.
func _initialize():run.call_deferred()
func run():
	var atlas=preload("res://scripts/hud_glyph_atlas.gd").new()
	var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
	var checks=0;var failures=0
	for size in [11,18,35,42]:
		for value in ["FPS 60 / 48","第一关：石墙果园","伤害 123"]:
			var shaped=atlas.layout(value,font,size)
			var paragraph=TextParagraph.new();paragraph.add_string(value,font,size)
			checks+=1
			if absf(shaped.width-paragraph.get_line_width(0))>.01 or absf(shaped.height-paragraph.get_line_size(0).y)>.01:failures+=1
			var glyphs=atlas.server.shaped_text_get_glyphs(paragraph.get_line_rid(0))
			for native in glyphs:
				for outline in [0,3]:
					var entry=atlas.glyph(native.font_rid,native.font_size,native.index,outline)
					if entry.is_empty():continue
					var cache=Vector2i(native.font_size,outline)
					var uv=Rect2i(atlas.server.font_get_glyph_uv_rect(native.font_rid,cache,native.index))
					var source=atlas.server.font_get_texture_image(native.font_rid,cache,atlas.server.font_get_glyph_texture_idx(native.font_rid,cache,native.index)).get_region(uv)
					source.convert(Image.FORMAT_RGBA8)
					var copied=atlas.image.get_region(Rect2i(Vector2i(entry.uv.position*atlas.SIZE),uv.size))
					checks+=1
					if source.get_data()!=copied.get_data():failures+=1
	atlas.upload()
	print("HUD_ATLAS_CONTRACT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
