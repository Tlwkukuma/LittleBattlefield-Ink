"""Complete the free combat palette offline. Never reads the legacy audio folder.

Requires soundfile for Kenney's Ogg sources (local cache/python-libs is supported).
Designed approximations are identified as such, never advertised as gun recordings.
"""
import hashlib
import io
import json
import math
import sys
import zipfile
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, resample_poly, sosfilt

RATE = 48000


def extend(manifest, root, pcm_import):
    cache = root / 'qa/audio-free-sources'
    dest = root / 'assets/audio/free-firearms'
    sys.path.insert(0, str(cache / 'python-libs'))
    import soundfile as sf

    def digest(data):
        return hashlib.sha256(data).hexdigest()

    downloads = json.loads((cache / 'additional-downloads.json').read_text('utf-8'))
    sources = {}
    for item in downloads:
        raw = (cache / item['file']).read_bytes()
        assert item['sha256'] and digest(raw) == item['sha256'], item['file']
        sources[item['file']] = item
    manifest['additional_sources'] = {
        'kenney': dict(author='Kenney', license='CC0-1.0', page='https://kenney.nl/assets/impact-sounds', **sources['kenney-impact.zip']),
        'swishes': dict(author='artisticdude', license='CC0-1.0', page='https://opengameart.org/content/swishes-sound-pack', **sources['swishes.zip']),
        'distant': dict(author='NenadSimic', license='CC0-1.0', page='https://opengameart.org/content/muffled-distant-explosion', **sources['distant-explosion.wav']),
    }
    impact_zip = zipfile.ZipFile(cache / 'kenney-impact.zip')
    swish_zip = zipfile.ZipFile(cache / 'swishes.zip')

    def decode(raw):
        samples, rate = sf.read(io.BytesIO(raw), always_2d=True)
        # Select a real channel, rather than cancelling opposed stereo transients.
        samples = samples[:, int(np.argmax(np.sum(samples ** 2, axis=0)))]
        divisor = math.gcd(RATE, rate)
        samples = resample_poly(samples, RATE // divisor, rate // divisor)
        active = np.flatnonzero(abs(samples) > max(.0002, float(abs(samples).max()) * .001))
        if len(active):
            samples = samples[max(0, int(active[0]) - 144):int(active[-1]) + 1]
        return samples / max(float(abs(samples).max()), 1e-9)

    def asset(key):
        return decode((dest / (key + '.wav')).read_bytes())

    def impact(kind, variant):
        name = 'Audio/%s_%03d.ogg' % (kind, variant)
        return decode(impact_zip.read(name)), 'kenney-impact.zip/' + name

    def swish(variant):
        name = 'swishes/swish-%d.wav' % (variant + 1)
        return decode(swish_zip.read(name)), 'swishes.zip/' + name

    def shape(samples, seconds, cutoff=0, decay=0):
        count = int(seconds * RATE)
        out = np.zeros(count)
        out[:min(count, len(samples))] = samples[:count]
        if cutoff:
            out = sosfilt(butter(2, cutoff, fs=RATE, output='sos'), out)
        if decay:
            out *= np.exp(-np.arange(count) / RATE * decay)
        return out

    def save(key, samples, parents, note):
        samples = sosfilt(butter(2, 40, btype='highpass', fs=RATE, output='sos'), samples)
        fade = min(2400, len(samples) // 6)
        samples[-fade:] *= np.linspace(1, 0, fade) ** 2
        samples[:24] *= np.linspace(0, 1, 24)
        samples *= .82 / max(float(abs(samples).max()), 1e-9)
        pcm = np.rint(samples * 32767).astype('<i2')
        path = dest / (key + '.wav')
        wavfile.write(path, RATE, pcm)
        pcm_import(path)
        manifest['assets'][key] = dict(key=key, path='res://assets/audio/free-firearms/' + path.name,
            license='CC0-1.0', parents=parents, source_description=note,
            processing='Offline crop, filter/envelope or mix as described; 48k mono PCM16; no runtime synthesis.',
            sha256=digest(path.read_bytes()), frames=len(pcm), duration=len(pcm) / RATE,
            peak=float(abs(pcm.astype(float)).max()) / 32768)
        return key

    def bank(name, gain, cutoff, make, note, distances=('near', 'mid')):
        record = dict(gain=gain, lowpass=cutoff, match=note)
        for distance in distances:
            record[distance] = []
            for variant in range(3):
                samples, parents = make(distance, variant)
                key = '%s_%s_%02d' % (name, distance, variant + 1)
                record[distance].append(save(key, samples, parents, note))
        if len(distances) == 1:
            record['mid'] = record['near']
        manifest['banks'][name] = record

    def parent_key(name, distance, variant):
        keys = manifest['banks'][name][distance]
        return keys[variant % len(keys)]

    # Suppressed variants are explicitly designed substitutes, not suppressed field recordings.
    for name, source, cutoff, gain in [('suppressed_rifle', 'ar15', 4400, .37),
            ('suppressed_smg', 'smg9', 3200, .30), ('suppressed_pistol', 'pistol45', 2800, .31)]:
        def make(distance, variant, source=source, cutoff=cutoff):
            key = parent_key(source, distance, variant)
            metal, ref = impact('impactMetal_light', variant)
            seconds = .38 if distance == 'near' else .55
            body = shape(asset(key), seconds, cutoff, 9)
            action = shape(metal, seconds, 6500, 30)
            return body + action * .035, [key, ref]
        bank(name, gain, 13000, make, 'Designed suppressed substitute: filtered field shot, shortened decay and quiet mechanical foley; no exact suppressor recording.')

    def pdw(distance, variant):
        key = parent_key('ar15', distance, variant)
        return shape(asset(key), .48 if distance == 'near' else .75, 0, 3), [key]
    bank('pdw', .60, 16000, pdw, 'Shortened AR-15 transient as small high-velocity PDW substitute; not 4.6/5.7 mm field recording.')

    body = decode((cache / 'distant-explosion.wav').read_bytes())
    for name, source, seconds, amount, cutoff, gain in [
        ('antimaterial', 'mosin', 1.45, .25, 1600, 1.0),
        ('heavy_mg', 'mosin', .85, .13, 2400, .88),
        ('autocannon', 'mosin', .95, .35, 1900, .95),
        ('cannon_light', 'mosin', 1.55, .60, 1400, 1.05),
        ('cannon_medium', 'tikka', 1.85, .85, 1100, 1.10),
        ('cannon_heavy', 'tikka', 2.15, 1.10, 850, 1.16),
        ('mortar', 'shotgun', .72, .80, 1000, .90),
        ('launcher', 'shotgun', .46, .50, 1500, .78),
    ]:
        def make(distance, variant, source=source, seconds=seconds, amount=amount, cutoff=cutoff, name=name):
            key = parent_key(source, distance, variant)
            duration = seconds + (.15 if distance == 'mid' else 0)
            shot_cutoff = cutoff * 2 if name in ('mortar', 'launcher') else (11000 if distance == 'near' else 6500)
            shot = shape(asset(key), duration, shot_cutoff, 4 if name in ('mortar', 'launcher') else 0)
            low = shape(body, duration, cutoff, 2 if seconds < 1 else .3)
            return shot + amount * low, [key, 'distant-explosion.wav']
        bank(name, gain, 16000, make, 'Designed heavy-weapon substitute: free field-shot transient plus NenadSimic low impact tail; not a recording of this cannon/caliber.')

    # A short gas launch is made from the CC0 launch source, not a pitched rifle shot.
    rocket_file = cache / 'rocket-launch.wav'
    rocket_meta = json.loads((cache / 'rocket-source.json').read_text('utf-8'))
    assert digest(rocket_file.read_bytes()) == rocket_meta['wav_sha256']
    manifest['additional_sources']['rocket'] = rocket_meta
    gas = decode(rocket_file.read_bytes())
    def rocket(distance, variant):
        key = parent_key('launcher', distance, variant)
        count = int(.78 * RATE)
        # Different portions of the free gas recording, with a fast launch envelope.
        start = min(int((.3 + variant * .2) * RATE), max(0, len(gas) - count))
        plume = shape(gas[start:start+count], .95, 6500, 3.5)
        plume[:240] *= np.linspace(0, 1, 240)
        return .40 * shape(asset(key), .95) + plume, [key, 'rocket-launch.wav']
    bank('rocket', .98, 14000, rocket, 'Designed short launcher using qubodup CC0 synthetic rocket gas plus free low-pressure launch transient; not RPG field recording.')

    def blast(distance, variant):
        key = parent_key('cannon_heavy', 'near', variant)
        rubble, ref = impact('impactMining', variant)
        return shape(body, 2.6) + .50 * shape(asset(key), 2.6, 9000) + .16 * shape(rubble, 2.6), ['distant-explosion.wav', key, ref]
    bank('blast', 1, 16000, blast, 'Designed detonation: low explosion tail, field-shot attack and stone debris; not a real explosive recording.', ('near',))

    event_sources = {'flesh':'impactPunch_heavy', 'stone':'impactMining', 'wood':'impactWood_medium',
        'earth':'impactSoft_medium', 'metal':'impactMetal_medium', 'glass':'impactGlass_light',
        'melee':'impactPunch_medium', 'case':'impactMetal_light', 'case_soft':'impactSoft_medium',
        'grenade_contact':'impactMetal_heavy'}
    for name, kind in event_sources.items():
        def make(distance, variant, kind=kind, name=name):
            samples, ref = impact(kind, variant)
            duration = min(len(samples) / RATE, .14 if name in ('case', 'case_soft') else .75)
            return shape(samples, duration), [ref]
        bank(name, 1, 18000, make, 'Kenney CC0 physical impact foley; material/role substitute.', ('near',))
    def swing(distance, variant):
        samples, ref = swish(variant)
        return samples, [ref]
    bank('swing', 1, 18000, swing, 'artisticdude CC0 recorded object swish, used for melee and throws.', ('near',))

    assignments = {'vss':'suppressed_smg', 'm4a1-s':'suppressed_rifle', 'mp5-sd':'suppressed_smg',
        'usp-s':'suppressed_pistol', 'p90':'pdw', 'mp7':'pdw', 'five-seven':'pistol9',
        'deagle':'pistol45', 'lynx-amr':'antimaterial', 'minigun':'mosin',
        'anti-tank-launcher':'rocket', 'rpg':'rocket', 'grenade-launcher':'launcher',
        'portable-mortar':'mortar', 'he-grenade':'swing', 'smoke-grenade':'swing',
        'army-knife':'swing', 'fire-axe':'swing', 'katana':'swing'}
    manifest['weapons'].update(assignments)
    manifest['event_only_weapons'] = ['army-knife', 'fire-axe', 'katana', 'he-grenade', 'smoke-grenade']
    manifest['mounted'] = {
        'armedJeep/mg':'heavy_mg', 'scoutCar/autocannon':'autocannon', 'scoutCar/mg':'mosin',
        'apc/mg':'heavy_mg', 'apc/grenade':'launcher', 'ifv/autocannon':'autocannon', 'ifv/grenade':'launcher',
        'lightTank/mg':'mosin', 'lightTank/cannon':'cannon_light', 'tank/cannon':'cannon_medium',
        'tank/mg':'mosin', 'tank/mortar':'mortar', 'heavyTank/cannon':'cannon_heavy',
        'heavyTank/mg':'mosin', 'heavyTank/canister':'cannon_light', 'hmg/primary':'heavy_mg',
        'fieldGun/primary':'cannon_medium', 'portableMortar/primary':'mortar'}
    manifest['events'] = {name: name for name in ['blast', 'flesh', 'stone', 'wood', 'earth', 'metal',
        'glass', 'melee', 'swing', 'case', 'case_soft', 'grenade_contact']}
    manifest['events'].update({'throw':'swing', 'shot':'ar15', 'heavy':'heavy_mg'})
    manifest['defaults'] = {'bullet':'ar15', 'shell':'cannon_medium', 'autocannon':'autocannon',
        'rocket':'rocket', 'mortar':'mortar', 'vehicleMortar':'mortar', 'vehicleGrenade':'launcher',
        'grenadeLauncher':'launcher', 'canister':'cannon_light', 'grenade':'swing', 'melee':'swing'}
    manifest['fallback_weapons'] = []
    catalog = json.loads((root / 'data/original/catalog.json').read_text('utf-8'))
    assert set(manifest['weapons']) == {w['id'] for w in catalog['weapons']}
    assert len(manifest['mounted']) == 18
    assert all(bank in manifest['banks'] for bank in list(manifest['weapons'].values()) + list(manifest['mounted'].values()) + list(manifest['events'].values()))
