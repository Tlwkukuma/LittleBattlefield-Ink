extends RefCounted
## One icon source for the armory, wheel, HUD and loot inventory.
static var cache: Dictionary={}
static func get_texture(w: Dictionary,atlas: Texture2D,frames: Dictionary) -> Texture2D:
	var key=str(w.get("id",w.get("name","")))+"/"+str(atlas.get_instance_id())
	if cache.has(key):return cache[key]
	var texture: Texture2D
	if str(w.get("id",""))=="minigun":texture=load("res://assets/weapons/minigun-icon.svg")
	else:
		var name=str(w.get("name",w.get("label","")))
		if not frames.has(name):return null
		var rect: Dictionary=frames[name].frame
		var region=AtlasTexture.new();region.atlas=atlas;region.region=Rect2(rect.x,rect.y,rect.w,rect.h);texture=region
	cache[key]=texture;return texture
