extends RefCounted
## Only offline retry is a normal-play function key; debug keys stay gated.
static func retry_shortcut(event: InputEvent,plan: Dictionary,network_active: bool,editing: bool,text_focus: bool,loot_open: bool,wheel_open: bool) -> bool:
	if not event is InputEventKey or event.keycode!=KEY_F5 or not event.pressed or event.echo:return false
	if network_active or editing or text_focus or loot_open or wheel_open:return false
	return bool(plan.get("godot3d",{}).get("campaign_offline",false))
