"""يوم 5: تحقّق من إصلاح المحاذاة (affine gap) قبل نقلها لـ Dart، وبعد
النقل (كمرجع لإعادة الفحص). ما بيحتاج Flutter/sherpa-onnx — Python صافي
+ قاعدة بيانات القرآن الفعلية من assets/quran/quran_data.json.gz.

usage: python3 tool/proto/validate_affine.py
"""
import math
import os
import random
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from matcher import GAP_EXTEND, GAP_OPEN, QuranIndex, load, match, normalize


def ayah_text(ayahs, s, a):
    for ss, aa, t in ayahs:
        if ss == s and aa == a:
            return t
    raise KeyError((s, a))


def semi_global_uniform(q, w):
    """نسخة uniform قديمة (قبل يوم 5) للمقارنة بس."""
    m, n = len(q), len(w)
    prev = [0] * (n + 1)
    pstart = list(range(n + 1))
    for i in range(1, m + 1):
        cur = [i] + [0] * n
        cstart = [0] * (n + 1)
        qi = q[i - 1]
        for j in range(1, n + 1):
            sub = prev[j - 1] + (0 if qi == w[j - 1] else 1)
            dele = prev[j] + 1
            ins = cur[j - 1] + 1
            if sub <= dele and sub <= ins:
                cur[j], cstart[j] = sub, pstart[j - 1]
            elif dele <= ins:
                cur[j], cstart[j] = dele, pstart[j]
            else:
                cur[j], cstart[j] = ins, cstart[j - 1]
        prev, pstart = cur, cstart
    best_j = min(range(n + 1), key=lambda j: (prev[j], -j))
    return prev[best_j], pstart[best_j], best_j


def match_uniform(idx, text, top_n=8, prev_end=None, ctx_bonus=0.08):
    q = normalize(text)
    m = len(q)
    if m < 4:
        return None
    votes = defaultdict(float)
    B = 8
    for i in range(m - 4 + 1):
        occ = idx.grams.get(q[i:i + 4])
        if not occ or len(occ) > 3000:
            continue
        wgt = 1.0 / math.log(2 + len(occ))
        for p in occ:
            votes[(p - i) // B] += wgt
    if prev_end is not None:
        votes[prev_end // B] += 1e6
    if not votes:
        return None
    cands = sorted(votes.items(), key=lambda x: -x[1])[:top_n * 3]
    results, seen = [], []
    for bucket, v in cands:
        d = bucket * B
        if any(abs(d - s) < m // 2 + B for s in seen):
            continue
        seen.append(d)
        lo = max(0, d - m // 4 - 8)
        hi = min(idx.n, d + m + m // 4 + 8)
        dist, s0, e0 = semi_global_uniform(q, idx.corpus[lo:hi])
        sc = 1 - dist / m
        rank = sc
        if prev_end is not None and prev_end - m // 2 - 10 <= lo + s0 <= prev_end + 300:
            rank += ctx_bonus
        results.append((rank, lo + s0, lo + e0, sc))
        if len(seen) >= top_n:
            break
    results.sort(key=lambda r: -r[0])
    best = results[0]
    return dict(score=best[3], start=best[1], end=best[2],
                first=idx.ayahs[idx.ayah_of(best[1])][:2],
                last=idx.ayahs[idx.ayah_of(max(best[1], best[2] - 1))][:2])


def check(name, cond, detail=''):
    print(f'  [{"OK" if cond else "FAIL"}] {name} {detail}')
    return cond


def main():
    ayahs = load()
    idx = QuranIndex(ayahs)
    print(f'index: {idx.n} letters, {len(ayahs)} ayahs (gap_open={GAP_OPEN}, gap_extend={GAP_EXTEND})\n')
    ok_all = True

    print('=== سيناريو فاتحة العفاسي: "مالك يوم الدين" (1:4) أسقطها التعرف ===')
    text = ' '.join(ayah_text(ayahs, 1, a) for a in range(1, 8) if a != 4)
    ru = match_uniform(idx, text)
    ra = match(idx, text)
    print(f'  uniform: first={ru["first"]} last={ru["last"]} score={ru["score"]:.3f}')
    print(f'  affine : first={ra["first"]} last={ra["last"]} score={ra["score"]:.3f}')
    ok_all &= check('affine يصل لـ 1:7 (uniform كمان بيوصلها هون، لكن بثقة أقل)',
                     ra['last'] == (1, 7) and ra['score'] > ru['score'])

    print('\n=== سلسلة اختبارات test/matching (مطابقة uniform/affine، بدون تراجع) ===')
    r = match(idx, 'قل هو الله أحد')
    ok_all &= check('single ayah 112:1', r['first'] == (112, 1) and r['score'] == 1.0)

    r = match(idx, 'الحمد لله رب العالمين الرحمن الرحيم مالك يوم الدين إياك نعبد')
    ok_all &= check('multi-ayah span 1:2-1:5', r['first'] == (1, 2) and r['last'] == (1, 5))
    ok_all &= check('multi-ayah score > 0.9', r['score'] > 0.9, str(r['score']))

    r = match(idx, 'الله لا اله الا هو الحي القيم لا تاخذه سنت ولا نوم له ما في السماوات')
    ok_all &= check('ayat al-kursi 2:255', r['first'] == (2, 255))
    ok_all &= check('ayat al-kursi score > 0.85', r['score'] > 0.85, str(r['score']))

    prev_end = idx.starts[next(i for i, a in enumerate(idx.ayahs) if a[0] == 55 and a[1] == 15) + 1]
    r = match(idx, 'فبأي آلاء ربكما تكذبان', prev_end=prev_end)
    ok_all &= check('repeated ayah resolved by context -> 55:16', r['first'] == (55, 16))

    print('\n=== دقة عشوائية (300 محاولة، ~10% خطأ حروف، نفس test/matching) ===')
    rnd = random.Random(42)
    keys = [normalize(t) for _, _, t in ayahs]
    letters = 'بتثجحخدذرزسشصضطظعغفقكلمنهوي'
    ok = total = 0
    for _ in range(300):
        i = rnd.randrange(len(ayahs))
        j = min(len(ayahs), i + 1 + rnd.randrange(3))
        while j - 1 > i and ayahs[j - 1][0] != ayahs[i][0]:
            j -= 1
        s = ''.join(keys[i:j])
        if len(s) > 400:
            s = s[:400]
        if len(s) < 12:
            continue
        b = []
        for ch in s:
            r2 = rnd.random()
            if r2 < 0.05:
                b.append(letters[rnd.randrange(len(letters))])
            elif r2 < 0.08:
                pass
            elif r2 < 0.10:
                b.append(ch)
                b.append(letters[rnd.randrange(len(letters))])
            else:
                b.append(ch)
        noisy = ''.join(b)
        rr = match(idx, noisy)
        total += 1
        if rr is not None:
            got = idx.ayahs[idx.ayah_of(rr['start'])]
            if normalize(got[2]) in keys[i:j]:
                ok += 1
    acc = ok / total
    ok_all &= check('random noisy accuracy > 0.93', acc > 0.93, f'{ok}/{total}={acc:.3f}')

    print('\n' + ('ALL OK ✅' if ok_all else 'SOME FAILED ❌'))
    sys.exit(0 if ok_all else 1)


if __name__ == '__main__':
    main()
