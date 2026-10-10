"""Prepare licensed field recordings offline; no network or game simulation.

Source takes and their verified hashes: qa/audio-free-sources/sources.json.
Each trigger plays one isolated shot, never the original multi-shot recording.
"""
import hashlib
import json
import re
import struct
import warnings
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, find_peaks, resample_poly, sosfilt

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'qa/audio-free-sources'
DEST = ROOT / 'assets/audio/free-firearms'
RATE = 48000
# Explicit assignments: related-cartridge/role substitutions are documented,
# not represented as recordings of the game's exact weapon model.
BANKS = {
    'ar15': dict(near='ar15_D_32P.wav', mid='ar15_D_24P.wav', gain=.82, cutoff=15500, tail=1.20,
        weapons='m16a4 m416 scar-l g36c qbz k2 aug famas mini14 mk12 galil-ar m4a4 sg-553 m249 negev'),
    'ak47': dict(near='ak47_C_28P.wav', mid='ak47_C_31P.wav', gain=.90, cutoff=15000, tail=1.25,
        weapons='akm beryl-m762 mk47-mutant groza ace32 ak-47 rpd'),
    'smg9': dict(near='smg9_G_31P.wav', mid='smg9_G_20P.wav', gain=.68, cutoff=15500, tail=1.05,
        weapons='micro-uzi vector mp5k mp9 js9 pp-bizon'),
    'pistol9': dict(near='pistol9_X_39P.wav', mid='pistol9_X_31P.wav', gain=.70, cutoff=16000, tail=1.05,
        weapons='p18c p92 skorpion glock-18 p2000 p250 tec-9 cz75-auto dual-berettas'),
    'pistol45': dict(near='pistol45_A_42P.wav', mid='pistol45_A_34P.wav', gain=.74, cutoff=14500, tail=1.0,
        weapons='tommy-gun ump ump-45 mac-10'),
    'shotgun': dict(near='shotgun_O_21P.wav', mid='shotgun_O_17P.wav', gain=.95, cutoff=15500, tail=.75,
        weapons='s1897 nova s12k o12 xm1014'),
    'pump': dict(near='pump_N_30P.wav', mid='pump_N_26P.wav', gain=.95, cutoff=14500, tail=.75,
        weapons='s686 dbs sawed-off mag-7'),
    'mosin': dict(near='mosin_M_21P.wav', mid='mosin_M_26P.wav', gain=.93, cutoff=15000, tail=1.35,
        weapons='kar98k dragunov slr mk14 g3sg1 scar-20 mg3'),
    'sks': dict(near='sks_U_14P.wav', mid='sks_U_19P.wav', gain=.86, cutoff=15000, tail=1.20,
        weapons='sks'),
    'tikka': dict(near='tikka_W_29P.wav', mid='tikka_W_24P.wav', gain=1.0, cutoff=15000, tail=1.35,
        weapons='m24 awm awp ssg-08'),
    'lever': dict(near='lever_L_23P.wav', mid='lever_L_17P.wav', gain=.85, cutoff=14500, tail=1.20,
        weapons='win94'),
    'revolver': dict(near='revolver_V_27P.wav', mid='revolver_V_22P.wav', gain=.78, cutoff=15500, tail=1.05,
        weapons='r1895 r8-revolver'),
}

def sha(data):
    return hashlib.sha256(data).hexdigest()

def pcm_import(target):
    """Keep these small preloaded one-shots free of runtime QOA decoding."""
    sidecar = target.with_suffix('.wav.import')
    if sidecar.exists():
        text = sidecar.read_text('utf-8')
        if 'compress/mode=' in text:
            text = re.sub(r'compress/mode=\d+', 'compress/mode=0', text)
        else:
            text += '\ncompress/mode=0\n'
    else:
        source = 'res://' + target.relative_to(ROOT).as_posix()
        imported = 'res://.godot/imported/' + target.name + '-' + hashlib.md5(source.encode()).hexdigest() + '.sample'
        text = ('[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\npath="'+imported+'"\n'
            '\n[deps]\n\nsource_file="'+source+'"\ndest_files=["'+imported+'"]\n'
            '\n[params]\n\nforce/8_bit=false\nforce/mono=false\nforce/max_rate=false\n'
            'edit/trim=false\nedit/normalize=false\nedit/loop_mode=0\ncompress/mode=0\n')
    sidecar.write_text(text, 'utf-8')

def description(raw):
    at = 12
    while at + 8 < len(raw):
        key = raw[at:at+4]
        size = struct.unpack_from('<I', raw, at+4)[0]
        if key == b'bext':
            return raw[at+8:at+264].split(b'\0')[0].decode('utf-8', 'replace')
        at += 8 + size + size % 2
    return ''

def prepare(bank, distance, spec, source):
    path = CACHE / 'raw' / source['file']
    raw = path.read_bytes()
    assert sha(raw) == source['sha256'], 'Unverified source: ' + str(path)
    with warnings.catch_warnings():
        warnings.simplefilter('ignore', wavfile.WavFileWarning)
        rate, data = wavfile.read(path)
    signal = data.astype(np.float64) / np.iinfo(data.dtype).max
    if signal.ndim == 1:
        signal = signal[:, None]
    # Find independent discharges, rejecting the loud 180-300 ms reflections.
    hop = rate // 1000
    envelope = np.max(np.abs(signal), axis=1)
    bins = np.max(envelope[:len(envelope)//hop*hop].reshape(-1, hop), axis=1)
    peaks, _ = find_peaks(bins, height=.25, distance=1500, prominence=.20)
    if len(peaks) < 2:
        raise ValueError('Not enough isolated shots in ' + path.name)
    output = []
    for variant, peak in enumerate(peaks[:3]):
        center = int(peak * hop)
        # Keep the attack; choose one real microphone, avoiding phase cancellation
        # when a stereo pair is folded into a positional mono sound.
        energy = np.mean(signal[center:center+int(rate*.04)]**2, axis=0)
        channel = int(np.argmax(energy))
        search_start = max(0, center-int(rate*.014))
        activity = np.flatnonzero(abs(signal[search_start:center+hop, channel]) > .018)
        onset = search_start + int(activity[0]) if len(activity) else center
        start = max(0, onset-int(rate*.003))
        seconds = spec['tail'] + (.35 if distance == 'mid' else 0)
        end = min(len(signal), start+int(rate*seconds))
        clip = signal[start:end, channel].copy()
        # Only low-frequency rumble removal; original timing/pitch are preserved.
        clip = sosfilt(butter(2, 55, btype='highpass', fs=rate, output='sos'), clip)
        clip = resample_poly(clip, RATE, rate)
        fade = min(int(RATE*.10), len(clip)//5)
        clip[-fade:] *= np.linspace(1, 0, fade)**2
        clip[:24] *= np.linspace(0, 1, 24)
        clip *= .82 / max(float(abs(clip).max()), 1e-9)
        pcm = np.rint(clip * 32767).astype('<i2')
        key = '%s_%s_%02d' % (bank, distance, variant+1)
        target = DEST / (key + '.wav')
        wavfile.write(target, RATE, pcm)
        pcm_import(target)
        output.append(dict(key=key, path='res://assets/audio/free-firearms/'+target.name,
            source=source['file'], source_sha256=source['sha256'], source_url=source['url'],
            microphone_channel=channel, source_start_sample=start, source_end_sample=end,
            source_sample_rate=rate, source_description=description(raw),
            sha256=sha(target.read_bytes()), frames=len(pcm), duration=len(pcm)/RATE,
            peak=float(abs(pcm.astype(float)).max())/32768,
            rms=float(np.sqrt(np.mean((pcm.astype(float)/32768)**2))),
        ))
    return output

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    sources = json.loads((CACHE/'sources.json').read_text('utf-8'))
    index = {x['file']: x for x in sources['files']}
    catalog = json.loads((ROOT/'data/original/catalog.json').read_text('utf-8'))['weapons']
    manifest = dict(origin=sources['origin'], license='CC0-1.0', mirror_commit=sources['commit'],
        authors=['Ben Jaszczak', 'Brian Nelson', 'Kevin Heras', 'Matthew Nanney'],
        processing='One discharge per clip, selected mono microphone, 55 Hz highpass, 48 kHz PCM16, fade out, -1.72 dBFS peak. No pitch change.',
        banks={}, weapons={}, assets={})
    for bank, spec in BANKS.items():
        record = dict(gain=spec['gain'], lowpass=spec['cutoff'], match='related weapon/cartridge/role; see mapping notes')
        for distance in ('near','mid'):
            clips=prepare(bank, distance, spec, index[spec[distance]])
            record[distance]=[x['key'] for x in clips]
            manifest['assets'].update({x['key']: x for x in clips})
        manifest['banks'][bank]=record
        for weapon in spec['weapons'].split():
            assert weapon not in manifest['weapons']
            assert any(w['id']==weapon for w in catalog)
            manifest['weapons'][weapon]=bank
    from extend_free_weapon_audio import extend
    extend(manifest, ROOT, pcm_import)
    (ROOT/'data/free-weapon-audio.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n','utf-8')
    report=dict(banks=len(manifest['banks']), clips=len(manifest['assets']), mapped_weapons=len(manifest['weapons']), mounted_modes=len(manifest['mounted']),
        fallback_weapons=manifest['fallback_weapons'], pcm_bytes=sum(p.stat().st_size for p in DEST.glob('*.wav')))
    (CACHE/'import-result.json').write_text(json.dumps(report,indent=2)+'\n','utf-8')
    print(json.dumps(report))

if __name__ == '__main__':
    main()
