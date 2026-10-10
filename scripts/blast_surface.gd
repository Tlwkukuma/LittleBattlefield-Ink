extends RefCounted
## Shared pigments for the moving dust and the settled impact mark.
static func palette(world,at: Vector2) -> Dictionary:
	var id=str(world.terrain.profile_at(at).id)
	if "snow" in id:return {"dust":Color("d5ded7"),"soil":Color("a1b0aa"),"hard":false}
	if "sand" in id or "desert" in id:return {"dust":Color("c5af83"),"soil":Color("ab9268"),"hard":false}
	if "red" in id:return {"dust":Color("b18b70"),"soil":Color("98715b"),"hard":false}
	if "rock" in id or "stone" in id or "concrete" in id:return {"dust":Color("a6a69b"),"soil":Color("92928a"),"hard":true}
	return {"dust":Color("a9a38a"),"soil":Color("8f866b"),"hard":false}
