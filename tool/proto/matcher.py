"""Python prototype of the Quran fuzzy matcher (mirrors lib/matching/*.dart)."""
import gzip, json, math, re
from collections import defaultdict

# ---------------- normalization ----------------
_REMOVE = set()
for r in [(0x064B, 0x065F), (0x0670, 0x0670), (0x06D6, 0x06ED), (0x08D3, 0x08FF),
          (0x0640, 0x0640), (0x200C, 0x200F), (0x0610, 0x061A)]:
    _REMOVE.update(range(r[0], r[1] + 1))
_MAP = {
    'ٱ': '', 'ا': '', 'أ': '', 'إ': '', 'آ': '', 'ء': '', 'ٲ': '', 'ٳ': '',
    'ؤ': 'و', 'ئ': 'ي', 'ى': 'ي', 'ی': 'ي', 'ة': 'ه', 'ک': 'ك', 'ۀ': 'ه',
}
_LETTERS = set('بتثجحخدذرزسشصضطظعغفقكلمنهوي')


def normalize(text, keep_spaces=False):
    """Return rasm skeleton key: no diacritics, no alef/hamza, folded letters."""
    out = []
    for ch in text:
        if ord(ch) in _REMOVE:
            continue
        ch = _MAP.get(ch, ch)
        for c in ch:
            if c in _LETTERS:
                out.append(c)
            elif keep_spaces and c.isspace():
                if out and out[-1] != ' ':
                    out.append(' ')
    return ''.join(out).strip()


# ---------------- index ----------------
K = 4


class QuranIndex:
    def __init__(self, ayahs):
        self.ayahs = ayahs  # list of (s, a)
        parts, self.starts = [], []
        pos = 0
        for s, a, t in ayahs:
            k = normalize(t)
            self.starts.append(pos)
            parts.append(k)
            pos += len(k)
        self.starts.append(pos)
        self.corpus = ''.join(parts)
        self.grams = defaultdict(list)
        c = self.corpus
        for i in range(len(c) - K + 1):
            self.grams[c[i:i + K]].append(i)
        self.n = len(c)

    def ayah_of(self, pos):
        import bisect
        return bisect.bisect_right(self.starts, pos) - 1


# تكلفة affine gap لحروف القرآن اللي أسقطها التعرف على الصوت (يوم 5). نفس
# القيم بـ lib/matching/quran_matcher.dart._gapOpen/._gapExtend — دقّقناها
# بسيناريو فاتحة العفاسي (مالك يوم الدين أسقطها التعرف) وبكل اختبارات
# test/matching بدون تراجع (شوف tool/proto/validate_affine.py).
GAP_OPEN = 1.5
GAP_EXTEND = 0.35


def semi_global(q, w, gap_open=GAP_OPEN, gap_extend=GAP_EXTEND):
    """Semi-global alignment cost of q vs best substring of w (free start/end
    on w's side). Returns (cost, start, end).

    حالتين لكل خلية: M (تطابق/استبدال، أو "حذف" حرف استعلام بتكلفة 1 موحّدة)
    و Dh (فجوة: حرف من w ناقص من q، بتكلفة affine عشان الفجوات الطويلة —
    آية كاملة أسقطها التعرف — ما توقّف المحاذاة قبلها). مطابق لـ
    `QuranMatcher._semiGlobal` بـ lib/matching/quran_matcher.dart.
    """
    m, n = len(q), len(w)
    INF = float('inf')
    prevM = [0.0] * (n + 1)          # بداية حرة: صفر لأي عمود
    prevMStart = list(range(n + 1))
    prevDh = [INF] * (n + 1)
    prevDhStart = [0] * (n + 1)

    for i in range(1, m + 1):
        curM = [0.0] * (n + 1)
        curMStart = [0] * (n + 1)
        curDh = [INF] * (n + 1)
        curDhStart = [0] * (n + 1)
        curM[0] = float(i)
        curMStart[0] = 0
        qi = q[i - 1]
        for j in range(1, n + 1):
            subCost = 0.0 if qi == w[j - 1] else 1.0
            if prevM[j - 1] <= prevDh[j - 1]:
                subBase, subStart = prevM[j - 1], prevMStart[j - 1]
            else:
                subBase, subStart = prevDh[j - 1], prevDhStart[j - 1]
            subVal = subBase + subCost

            if prevM[j] <= prevDh[j]:
                delBase, delStart = prevM[j], prevMStart[j]
            else:
                delBase, delStart = prevDh[j], prevDhStart[j]
            delVal = delBase + 1.0

            if subVal <= delVal:
                curM[j], curMStart[j] = subVal, subStart
            else:
                curM[j], curMStart[j] = delVal, delStart

            openVal = curM[j - 1] + gap_open
            extendVal = curDh[j - 1] + gap_extend
            if openVal <= extendVal:
                curDh[j], curDhStart[j] = openVal, curMStart[j - 1]
            else:
                curDh[j], curDhStart[j] = extendVal, curDhStart[j - 1]
        prevM, prevMStart, prevDh, prevDhStart = curM, curMStart, curDh, curDhStart

    best_j, best_cost, best_start = 0, INF, 0
    for j in range(n + 1):
        if prevM[j] <= prevDh[j]:
            c, s = prevM[j], prevMStart[j]
        else:
            c, s = prevDh[j], prevDhStart[j]
        if c <= best_cost:
            best_cost, best_j, best_start = c, j, s
    return best_cost, best_start, best_j


def match(idx, text, top_n=8, prev_end=None, ctx_bonus=0.08):
    q = normalize(text)
    m = len(q)
    if m < K:
        return None
    votes = defaultdict(float)
    B = 8
    for i in range(m - K + 1):
        occ = idx.grams.get(q[i:i + K])
        if not occ or len(occ) > 3000:
            continue
        wgt = 1.0 / math.log(2 + len(occ))
        for p in occ:
            votes[(p - i) // B] += wgt
    if prev_end is not None:
        votes[prev_end // B] += 1e6  # always verify the 'continues from previous' window
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
        dist, s0, e0 = semi_global(q, idx.corpus[lo:hi])
        sc = 1 - dist / m
        rank = sc
        if prev_end is not None and prev_end - m // 2 - 10 <= lo + s0 <= prev_end + 300:
            rank += ctx_bonus
        results.append((rank, lo + s0, lo + e0, sc))
        if len(seen) >= top_n:
            break
    results.sort(key=lambda r: -r[0])
    best = results[0]
    second = next((r for r in results[1:] if abs(r[1] - best[1]) > m // 2), None)
    margin = best[0] - (second[0] if second else 0)
    return dict(score=best[3], start=best[1], end=best[2],
                first=idx.ayahs[idx.ayah_of(best[1])][:2],
                last=idx.ayahs[idx.ayah_of(max(best[1], best[2] - 1))][:2],
                second=second and (second[0], idx.ayahs[idx.ayah_of(second[1])][:2]),
                margin=margin, qlen=m)


def load():
    d = json.load(gzip.open('/home/claude/quran-dub-android/assets/quran/quran_data.json.gz'))
    return [(a['s'], a['a'], a['t']) for a in d['ayahs']]
