import random, time, sys
sys.path.insert(0, '/home/claude/proto')
from matcher import *

random.seed(7)
ayahs = load()
t0 = time.time()
idx = QuranIndex(ayahs)
print('index built', round(time.time() - t0, 2), 's; corpus letters', idx.n, 'grams', len(idx.grams))
keys = [normalize(t) for _, _, t in ayahs]

CONF = ['سص', 'تط', 'ذزظ', 'دض', 'حه', 'كق', 'ثس', 'غخ', 'وي', 'نم']
CMAP = {}
for g in CONF:
    for c in g:
        CMAP[c] = g.replace(c, '')
LET = 'بتثجحخدذرزسشصضطظعغفقكلمنهوي'


def noisy(s, cer):
    out = []
    for c in s:
        r = random.random()
        if r < cer * 0.5:
            out.append(random.choice(CMAP.get(c, LET)))
        elif r < cer * 0.8:
            continue
        elif r < cer:
            out.append(c); out.append(random.choice(LET))
        else:
            out.append(c)
    return ''.join(out)


def sample():
    i = random.randrange(len(ayahs))
    n = random.choice([1, 1, 1, 2, 3])
    j = min(len(ayahs), i + n)
    # stay within one surah
    while j - 1 > i and ayahs[j - 1][0] != ayahs[i][0]:
        j -= 1
    s = ''.join(keys[i:j])
    # partial clip: drop up to 30% at the edges (simulates segment boundaries)
    if len(s) > 40 and random.random() < 0.5:
        a = random.randint(0, len(s) // 6)
        b = len(s) - random.randint(0, len(s) // 6)
        s = s[a:b]
    if len(s) > 400:
        s = s[:400]
    return i, j, s


for cer in [0.0, 0.05, 0.10, 0.20]:
    ok = amb = tot = 0
    lat = []
    fails = []
    for _ in range(400):
        i, j, s = sample()
        if len(s) < 12:
            continue
        q = noisy(s, cer)
        t = time.time()
        r = match(idx, q)
        lat.append(time.time() - t)
        tot += 1
        truth_first = ayahs[i][:2]
        got_ok = r and keys[idx.ayah_of(r['start'])] in keys[i:j]
        if got_ok:
            ok += 1
        else:
            fails.append((truth_first, r and r['first'], len(s), r and round(r['score'], 2)))
        if r and r['margin'] < 0.1:
            amb += 1
    lat.sort()
    print(f'CER {cer:.2f}: top1 {ok}/{tot} = {ok/tot:.3f}  low-margin {amb}  '
          f'p50 {lat[len(lat)//2]*1000:.0f}ms p95 {lat[int(len(lat)*.95)]*1000:.0f}ms')
    print('   sample fails:', fails[:5])
