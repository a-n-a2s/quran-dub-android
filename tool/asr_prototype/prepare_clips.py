"""يوم 5: تجهيز مقاطع اختبار الدقة (بدل prepare_clips.sh تبع يوم 3).

كل مقطع مركّب من ملفات آيات everyayah.com (آية بملف)، فبنعرف بالضبط وين
بتبلّش كل آية ووين بتخلص → **حقيقة التوقيت** (truth) لقياس خطأ توقيت بداية
ونهاية كل آية. الكلام نفسه جوا كل ملف (بدون الصمت بأوله وآخره) بينحسب من
الطاقة (RMS) بإطارات 20ms.

أنواع العناصر بالمقطع:
  "S:A"          آية كاملة
  "S:A@F0-F1"    جزء من الآية (نسبة من طول ملفها)، مثلاً القارئ بيعيد أول نصها
  "tts:KEY"      كلام عادي مش قرآن (espeak-ng عربي) — مقدمة/دعاء
degrade: 0 نظيف، 1 محاكاة جوال (نطاق 300-3400Hz + ضجيج خفيف، نفس يوم 3)،
         2 ضجيج قوي (ضجيج أبيض 0.03) + نطاق جوال، 3 ضجيج شديد جداً (0.06،
         اختبار حدود بس: بأول تجربة يوم 5 الـ VAD ما لقط كلام تقريباً).

الملفات للاختبار بس (ما بتنضاف للمستودع ولا للـ APK).
usage: python prepare_clips.py OUT_DIR   → يكتب OUT_DIR/clips.json
"""
import json
import os
import shutil
import subprocess
import sys
import urllib.request

import numpy as np
import soundfile as sf

SR = 16000
BASE = 'https://everyayah.com/data'

TTS = {
    'intro': 'السلام عليكم ورحمة الله وبركاته، أهلا بكم، اليوم نستمع معا إلى آيات من سورة الملك.',
    'dua': 'اللهم اجعل القرآن ربيع قلوبنا ونور صدورنا وجلاء أحزاننا، وجزاكم الله خيرا.',
}

# id | reciter | items | expected | degrade
CLIPS = [
    # --- يوم 3 (نفس المقاطع) ---
    ('fatiha_alafasy', 'Alafasy_128kbps', '1:1-7', '1:1-1:7', 0),
    ('fatiha_husary', 'Husary_128kbps', '1:1-7', '1:1-1:7', 0),
    ('fatiha_abdulbasit', 'Abdul_Basit_Murattal_192kbps', '1:1-7', '1:1-1:7', 0),
    ('ikhlas_minshawy', 'Minshawy_Murattal_128kbps', '112:1-4', '112:1-112:4', 0),
    ('kursi_alafasy', 'Alafasy_128kbps', '2:255', '2:255-2:255', 0),
    ('kursi_husary', 'Husary_128kbps', '2:255', '2:255-2:255', 0),
    ('rahman_abdulbasit', 'Abdul_Basit_Murattal_192kbps', '55:13-18', '55:13-55:18', 0),
    ('yasin_ghamadi_lowbitrate', 'Ghamadi_40kbps', '36:1-12', '36:1-36:12', 0),
    ('kahf_husary_mid', 'Husary_128kbps', '18:10', '18:10-18:10', 0),
    ('mulk_alafasy_phone_noisy', 'Alafasy_128kbps', '67:1-5', '67:1-67:5', 1),
    ('kahf_alafasy_phone_noisy', 'Alafasy_128kbps', '18:1-4', '18:1-18:4', 1),
    # --- يوم 5: مقاطع جديدة ---
    # مقاطع طويلة من سور متوسطة
    ('qaf_alafasy_27_30', 'Alafasy_128kbps', '50:27-30', '50:27-50:30', 0),
    ('mulk_husary_long', 'Husary_128kbps', '67:1-12', '67:1-67:12', 0),
    ('yusuf_minshawy_long', 'Minshawy_Murattal_128kbps', '12:1-10', '12:1-12:10', 0),
    # قارئ بيعيد جزء من الآية (أول نص آية الكرسي، بعدين الآية كاملة)
    ('kursi_repeat_alafasy', 'Alafasy_128kbps', '2:255@0-0.45,2:255,2:256', '2:255-2:256', 0),
    ('rahman_repeat_husary', 'Husary_128kbps', '55:1-3,55:4@0-0.6,55:4-6', '55:1-55:6', 0),
    # ضجيج قوي
    ('rahman_husary_heavy_noise', 'Husary_128kbps', '55:1-12', '55:1-55:12', 2),
    ('ikhlas_alafasy_heavy_noise', 'Alafasy_128kbps', '112:1-4', '112:1-112:4', 2),
    ('ikhlas_alafasy_extreme_noise', 'Alafasy_128kbps', '112:1-4', '112:1-112:4', 3),
    # مقدمة ودعاء مش قرآن
    ('intro_mulk_alafasy', 'Alafasy_128kbps', 'tts:intro,67:1-4,tts:dua', '67:1-67:4', 0),
]


def expand(items):
    out = []
    for it in items.split(','):
        it = it.strip()
        if it.startswith('tts:'):
            out.append(('tts', it[4:], None))
            continue
        frac = None
        if '@' in it:
            it, f = it.split('@')
            a, b = f.split('-')
            frac = (float(a), float(b))
        s, a = it.split(':')
        if '-' in a:
            a0, a1 = a.split('-')
            for x in range(int(a0), int(a1) + 1):
                out.append(('ayah', (int(s), x), frac))
        else:
            out.append(('ayah', (int(s), int(a)), frac))
    return out


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def decode_16k(src, dst):
    run(['ffmpeg', '-loglevel', 'error', '-y', '-i', src, '-ac', '1', '-ar', str(SR),
         '-c:a', 'pcm_s16le', dst])


def speech_bounds(x):
    """(بداية، نهاية) الكلام بالثواني جوا قطعة صوت (طاقة > -30dB من أعلى إطار)."""
    hop = SR // 50
    n = len(x) // hop
    if n == 0:
        return 0.0, len(x) / SR
    rms = np.sqrt(np.mean(x[:n * hop].reshape(n, hop) ** 2, axis=1) + 1e-12)
    thr = rms.max() * 10 ** (-30 / 20)
    idx = np.nonzero(rms > thr)[0]
    if len(idx) == 0:
        return 0.0, len(x) / SR
    return idx[0] * hop / SR, (idx[-1] + 1) * hop / SR


def fetch(rec, s, a, cache):
    f = f'{s:03d}{a:03d}.mp3'
    mp3 = os.path.join(cache, f'{rec}_{f}')
    wav = mp3[:-4] + '.wav'
    if not os.path.exists(wav):
        if not os.path.exists(mp3) or os.path.getsize(mp3) == 0:
            for attempt in range(3):
                try:
                    with urllib.request.urlopen(f'{BASE}/{rec}/{f}', timeout=60) as r, \
                            open(mp3, 'wb') as o:
                        shutil.copyfileobj(r, o)
                    break
                except Exception as e:  # noqa: BLE001
                    if attempt == 2:
                        raise RuntimeError(f'missing {rec}/{f}: {e}')
        decode_16k(mp3, wav)
    x, sr = sf.read(wav, dtype='float32')
    assert sr == SR
    return x


def tts(key, cache):
    wav = os.path.join(cache, f'tts_{key}.wav')
    if not os.path.exists(wav):
        if shutil.which('espeak-ng') is None:
            raise RuntimeError('espeak-ng not installed')
        raw = wav + '.raw.wav'
        run(['espeak-ng', '-v', 'ar', '-s', '150', '-w', raw, TTS[key]])
        decode_16k(raw, wav)
    x, _ = sf.read(wav, dtype='float32')
    return x


# الضجيج بـ seed ثابت: نفس المقاطع بكل تشغيل، فالأرقام بتتقارن بين تشغيل
# وتشغيل (قبل يوم 7 كان عشوائي، فنتيجة مقاطع الضجيج الشديد كانت بتتغيّر).
NOISE_SEED = 20261124


def degrade(path, level, out):
    if level == 1:
        flt = ('[0:a]aresample=16000,highpass=f=300,lowpass=f=3400,volume=0.7[v];'
               '[v][1:a]amix=inputs=2:duration=first:normalize=0[o]')
        noise = f'anoisesrc=color=pink:amplitude=0.02:sample_rate=16000:seed={NOISE_SEED}'
    else:
        flt = ('[0:a]aresample=16000,highpass=f=250,lowpass=f=3600,volume=0.6[v];'
               '[v][1:a]amix=inputs=2:duration=first:normalize=0[o]')
        amp = 0.03 if level == 2 else 0.06
        noise = f'anoisesrc=color=white:amplitude={amp}:sample_rate=16000:seed={NOISE_SEED}'
    run(['ffmpeg', '-loglevel', 'error', '-y', '-i', path, '-f', 'lavfi', '-i', noise,
         '-filter_complex', flt, '-map', '[o]', '-ac', '1', '-ar', str(SR),
         '-c:a', 'pcm_s16le', out])


def main():
    out_dir = sys.argv[1]
    cache = os.path.join(out_dir, 'cache')
    os.makedirs(cache, exist_ok=True)
    gap = np.zeros(int(0.15 * SR), dtype=np.float32)  # فاصل صغير بين الملفات
    clips = []
    for n, (cid, rec, items, expected, level) in enumerate(CLIPS):
        try:
            parts, truth, t = [], [], 0.0
            for kind, ref, frac in expand(items):
                x = tts(ref, cache) if kind == 'tts' else fetch(rec, ref[0], ref[1], cache)
                if frac is not None:
                    x = x[int(frac[0] * len(x)):int(frac[1] * len(x))]
                s0, s1 = speech_bounds(x)
                truth.append({
                    'kind': 'non_quran' if kind == 'tts' else ('partial' if frac else 'ayah'),
                    'ref': None if kind == 'tts' else f'{ref[0]}:{ref[1]}',
                    'start': round(t + s0, 3), 'end': round(t + s1, 3),
                    'file_start': round(t, 3), 'file_end': round(t + len(x) / SR, 3),
                })
                parts += [x, gap]
                t += (len(x) + len(gap)) / SR
        except RuntimeError as e:
            print('WARN skip', cid, e)
            continue
        wav = os.path.join(out_dir, f'{cid}.wav')
        y = np.concatenate(parts)
        if level:
            clean = os.path.join(cache, f'{cid}_clean.wav')
            sf.write(clean, y, SR, subtype='PCM_16')
            degrade(clean, level, wav)
        else:
            sf.write(wav, y, SR, subtype='PCM_16')
        clips.append({'id': cid, 'reciter': rec, 'expected': expected,
                      'degraded': level > 0, 'noise_level': level, 'wav': wav,
                      'items': items, 'truth': truth,
                      'group': 'day3' if n < 11 else 'day5'})
        print(f'{cid}: {t:.1f}s, {len(truth)} items')
    with open(os.path.join(out_dir, 'clips.json'), 'w', encoding='utf-8') as f:
        json.dump(clips, f, ensure_ascii=False, indent=1)
    print(f'{len(clips)} clips → {out_dir}/clips.json')


if __name__ == '__main__':
    main()
