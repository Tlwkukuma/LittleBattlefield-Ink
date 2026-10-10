extends SceneTree
func _initialize():
	var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei UI"])
	var text=TextLine.new();text.add_string("中文 HUD 60",font,14)
	print("GLYPH_LAYOUT ",TextServerManager.get_primary_interface().shaped_text_get_glyphs(text.get_rid())[0]);quit()
