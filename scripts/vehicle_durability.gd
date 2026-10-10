extends RefCounted
## Runtime balance overrides; preserve the imported reference catalog verbatim.
## Running gear is one aggregate health pool, not independently simulated sides.
const RUNNING_GEAR={"armedJeep":180.0,"scoutCar":200.0,"apc":260.0}

static func bind(data: Dictionary):
	data.vehicles.armedJeep.health=1080.0
	for kind in RUNNING_GEAR:data.vehicles[kind].trackHealth=RUNNING_GEAR[kind]

static func gear_name(v: Dictionary) -> String:
	return "轮胎" if v.type in ["armedJeep","scoutCar"] else "履带"

static func ratio(v: Dictionary) -> float:
	return clampf(float(v.track_health)/maxf(1,float(v.max_track)),0,1) if v.max_track>0 else 1.0

static func mobility(v: Dictionary) -> Vector2:
	var remaining=ratio(v)
	# Shared with the HUD so a warning always matches actual driving penalties.
	return Vector2(.28,.24) if remaining<=.02 else Vector2(.48,.48) if remaining<.35 else Vector2(.72,.74) if remaining<.68 else Vector2.ONE

static func condition(value: float,gear: bool=false) -> String:
	if gear:
		return "重损 · 仅可缓行" if value<=.02 else "严重受损 · 机动下降" if value<.35 else "受损 · 机动下降" if value<.68 else "完好" if value>=.999 else "轻损"
	return "危急" if value<.30 else "受损" if value<.68 else "完好" if value>=.999 else "轻损"
