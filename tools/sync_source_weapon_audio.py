"""Import Little Battlefield's authored shot table and unchanged local WAV files."""
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parents[1] / 'web/Pixi-Battlefield1-Blue/src/audio.js'
LIBRARY = ROOT.parents[1] / 'web/Pixi-Pathogenic/reference/pathogenic-original/audio/sfx/shots'
text = SOURCE.read_text(encoding='utf-8')
rows = re.findall(r"^  (\w+): \{ sample:`\$\{SHOT_LIBRARY_ROOT\}([^`]+)`, group:'([^']+)', sampleGain:([\d.]+), lowpass:(\d+) \}", text, re.M)
if len(rows) != 32:
    raise ValueError(f'Unexpected source table: {len(rows)} profiles')
aliases = {'rifle': 'assaultRifle', 'mg': 'lightMachineGun', 'rocket': 'rocketLauncher'}
renames = {
    'ESM_GW_gun_one_shot_pistol_hi_tech_type_short_laser_tech_small_arm_short_4_long_deep.wav': 'pistol.wav',
    'ESM_GW_gun_one_shot_pistol_hi_tech_type_short_laser_tech_small_arm_short_5_long_deep.wav': 'machine_pistol.wav',
    'ESM_SFSG_cinematic_fx_science_fiction_weapon_firearm_launcher_buzz_smooth_recoil_01.wav': 'rocket.wav',
}
profiles = {}
assets = {}
for key, sample, group, gain, cutoff in rows:
    source = LIBRARY / sample
    if not source.is_file():
        raise FileNotFoundError(source)
    filename = renames.get(sample, sample)
    profiles[key] = {'sample': filename.removesuffix('.wav'), 'group': group, 'gain': float(gain), 'lowpass': int(cutoff)}
    assets[filename] = {'source': sample, 'sha256': hashlib.sha256(source.read_bytes()).hexdigest()}
profiles['melee'] = {'sample': '', 'group': 'melee', 'gain': 0.0, 'lowpass': 20000}
for filename, info in assets.items():
    target = ROOT / 'assets/audio/combat' / filename
    shutil.copyfile(LIBRARY / info['source'], target)
    settings = Path(str(target) + '.import')
    if settings.exists():
        settings.write_text(re.sub(r'compress/mode=\d+', 'compress/mode=0', settings.read_text(encoding='utf-8')), encoding='utf-8')
data = {'source': 'Pixi-Battlefield1-Blue/src/audio.js', 'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(), 'master_gain': 0.22, 'aliases': aliases, 'profiles': profiles, 'assets': assets}
(ROOT / 'data/source-weapon-audio.json').write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print(f'Imported {len(rows)} shot profiles; {len(assets)} unchanged WAVs')
