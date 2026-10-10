extends RefCounted
## Camera art dimensions, not ballistic radii or literal real-world measurements.
## A shared magnification keeps cartridge proportions intact at every zoom.
const SIZES={
	"9":Vector3(.028,.028,.058),"45":Vector3(.034,.034,.067),"357":Vector3(.031,.031,.100),
	"pdw46":Vector3(.022,.022,.078),"pdw":Vector3(.027,.027,.084),"vss":Vector3(.030,.030,.100),
	"556":Vector3(.028,.028,.110),"762short":Vector3(.033,.033,.100),"762":Vector3(.035,.035,.129),
	"762sidearm":Vector3(.029,.029,.068),"magnum":Vector3(.039,.039,.162),"50":Vector3(.056,.056,.225),
	"buckshot":Vector3(.047,.047,.146),"slug":Vector3(.047,.047,.146)}
static func apply(a: Dictionary,id: String,family: String,ammo: String):
	# Preserve the legacy projectile model's sizing; shrinking an empty case
	# must not secretly shrink the rocket/cannon or change a collision radius.
	a.round_size=a.case_size
	var key=str(a.key)
	if ammo.contains(".357"):key="357";a.case_shape="straight"
	elif ammo.contains("4.6"):key="pdw46"
	elif key=="762":
		if family in ["pistol","machinePistol"]:key="762sidearm";a.case_shape="straight"
		elif family=="assault" or id in ["sks","rpd"]:key="762short"
	if SIZES.has(key):a.case_size=SIZES[key];a.key=key
	else:a.case_size*=.75
	a.case_pixels=1.8*float(a.case_size.x)/.028
	a.case_max_scale=1.6

static func mounted_size(caliber: String,original: Vector3) -> Vector3:
	if caliber=="762":return SIZES["762"]
	if caliber=="127":return SIZES["50"]
	return original*.8
