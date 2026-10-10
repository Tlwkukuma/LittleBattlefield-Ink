extends RefCounted
## Retired mission actors stay alive with their equipment but leave the battlefield.
static func active(unit: Dictionary) -> bool:
	return bool(unit.get("alive",false)) and not bool(unit.get("hanlue_extracted",false)) and not bool(unit.get("hanlue_escaped",false))
