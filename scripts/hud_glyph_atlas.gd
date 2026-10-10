extends RefCounted
## Copy the exact antialiased font glyph bitmaps once, preserving native shaping.
## All font sizes share a small atlas; no MSDF per-glyph draw splits on OpenGL.
const SIZE=2048
var image=Image.create(SIZE,SIZE,false,Image.FORMAT_RGBA8)
var texture=ImageTexture.create_from_image(image)
var glyphs: Dictionary={}
var layouts: Dictionary={}
var cursor=Vector2i(1,1)
var row_height=0
var dirty=false
var server=TextServerManager.get_primary_interface()
func glyph(font: RID,size: int,index: int,outline: int=0) -> Dictionary:
	var key=str(font.get_id(),"/",size,"/",index,"/",outline)
	if glyphs.has(key):return glyphs[key]
	var cache=Vector2i(size,outline);server.font_render_glyph(font,cache,index)
	var uv=Rect2i(server.font_get_glyph_uv_rect(font,cache,index));var texture_index=server.font_get_glyph_texture_idx(font,cache,index)
	if uv.size.x<=0 or uv.size.y<=0 or texture_index<0:glyphs[key]={};return {}
	if cursor.x+uv.size.x>=SIZE:cursor.x=1;cursor.y+=row_height+2;row_height=0
	if cursor.y+uv.size.y>=SIZE:push_error("HUD glyph atlas capacity exceeded");return {}
	var source: Image=server.font_get_texture_image(font,cache,texture_index).get_region(uv);source.convert(Image.FORMAT_RGBA8)
	image.blit_rect(source,Rect2i(Vector2i.ZERO,uv.size),cursor);dirty=true
	var entry={"uv":Rect2(Vector2(cursor)/SIZE,Vector2(uv.size)/SIZE),"offset":server.font_get_glyph_offset(font,cache,index),"size":server.font_get_glyph_size(font,cache,index)}
	cursor.x+=uv.size.x+2;row_height=maxi(row_height,uv.size.y);glyphs[key]=entry;return entry
func layout(text: String,font: Font,size: int,width: float=-1,alignment: int=HORIZONTAL_ALIGNMENT_LEFT,wrap: bool=false,outline: int=0) -> Dictionary:
	var key=str(font.get_instance_id(),"/",size,"/",width,"/",alignment,"/",wrap,"/",outline,"/",text)
	if layouts.has(key):return layouts[key]
	var paragraph=TextParagraph.new();paragraph.alignment=alignment;paragraph.width=width
	paragraph.break_flags=TextServer.BREAK_MANDATORY|TextServer.BREAK_WORD_BOUND if wrap else TextServer.BREAK_MANDATORY
	paragraph.add_string(text,font,size)
	var items=[];var y=0.0;var widest=0.0
	for line_index in range(paragraph.get_line_count()):
		var rid=paragraph.get_line_rid(line_index);var line_width=paragraph.get_line_width(line_index)
		widest=maxf(widest,line_width)
		var x=maxf(0,width-line_width)*(.5 if alignment==HORIZONTAL_ALIGNMENT_CENTER else 1.0 if alignment==HORIZONTAL_ALIGNMENT_RIGHT else 0.0)
		var baseline=y+paragraph.get_line_ascent(line_index)
		for shaped in server.shaped_text_get_glyphs(rid):
			for repeat in range(shaped.repeat):
				if shaped.font_rid.is_valid():
					var entry=glyph(shaped.font_rid,int(shaped.font_size),int(shaped.index),outline)
					if not entry.is_empty():items.append({"rect":Rect2(Vector2(x,baseline)+Vector2(shaped.offset)+entry.offset,entry.size),"uv":entry.uv})
				x+=shaped.advance
		y+=paragraph.get_line_size(line_index).y
	var result={"items":items,"height":y,"width":widest,"ascent":paragraph.get_line_ascent(0) if paragraph.get_line_count()>0 else 0}
	if layouts.size()>512:layouts.clear()
	layouts[key]=result;return result
func append(batch,shaped: Dictionary,at: Vector2,color: Color):
	for item in shaped.items:batch.quad(Rect2(item.rect.position+at,item.rect.size),item.uv,color)
func upload():
	if dirty:texture.update(image);dirty=false
