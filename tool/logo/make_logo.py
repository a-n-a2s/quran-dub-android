# شعار "آية ستوديو": موجة صوت ذهبية (خطوط طولية بأطوال مختلفة) وفوقها كلمة
# "آية" بلون عاجي، بخط Aref Ruqaa (OFL). بيطلّع:
#   - assets/branding/logo_mark.png      (الشعار بخلفية شفافة، للواجهة)
#   - assets/branding/logo_wave.png      (الموجة لحالها، للأيقونات الصغيرة بالواجهة)
#   - android mipmap ic_launcher.png      (أيقونة كاملة، كل الكثافات)
#   - android mipmap ic_launcher_foreground/background/monochrome (adaptive، أندرويد 8+)
#   - tool/logo/out/*.png                 (معاينات + 512 لجوجل بلاي)
# التشغيل: python3 tool/logo/make_logo.py  (بده Pillow مع raqm للتشكيل العربي)
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FONT = os.path.join(ROOT, 'tool/logo/fonts/ArefRuqaa-Bold.ttf')
OUT = os.path.join(ROOT, 'tool/logo/out')
RES = os.path.join(ROOT, 'android/app/src/main/res')
BRAND = os.path.join(ROOT, 'assets/branding')

GOLD_TOP = (250, 232, 170)
GOLD_MID = (222, 182, 92)
GOLD_BOT = (166, 118, 42)
IVORY = (252, 246, 228)
GREEN_C = (18, 98, 74)
GREEN_E = (4, 30, 23)

# أطوال الخطوط (نسبة من أطول خط): موجة صوت طبيعية، مش متماثلة تماماً.
BARS = [0.14, 0.30, 0.55, 0.34, 0.72, 0.95, 1.00, 0.68, 0.46, 0.84, 0.60, 0.32, 0.16]


def vertical_gradient(size, top, mid, bot):
    w, h = size
    g = Image.new('RGBA', (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        if t < 0.5:
            a, b, u = top, mid, t / 0.5
        else:
            a, b, u = mid, bot, (t - 0.5) / 0.5
        g.putpixel((0, y), tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3)) + (255,))
    return g.resize((w, h))


def wave_mask(size, box, bars=BARS, gap_ratio=0.64):
    """قناع الموجة داخل [box] = (x0, y0, x1, y1)، الخطوط بالنص عمودياً."""
    m = Image.new('L', size, 0)
    d = ImageDraw.Draw(m)
    x0, y0, x1, y1 = box
    n = len(bars)
    pitch = (x1 - x0) / n
    bw = pitch * gap_ratio
    cy = (y0 + y1) / 2
    hmax = y1 - y0
    for i, f in enumerate(bars):
        cx = x0 + pitch * (i + 0.5)
        h = max(bw, hmax * f)
        d.rounded_rectangle((cx - bw / 2, cy - h / 2, cx + bw / 2, cy + h / 2), radius=bw / 2, fill=255)
    return m


def text_mask(size, text, center, height_px):
    """قناع كلمة [text] بارتفاع حبر تقريبي [height_px]، متمركزة على [center]."""
    probe = ImageFont.truetype(FONT, 400, layout_engine=ImageFont.Layout.RAQM)
    bb = probe.getbbox(text, direction='rtl', language='ar', anchor='ls')
    ink_h = bb[3] - bb[1]
    fs = int(400 * height_px / ink_h)
    f = ImageFont.truetype(FONT, fs, layout_engine=ImageFont.Layout.RAQM)
    bb = f.getbbox(text, direction='rtl', language='ar', anchor='ls')
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    m = Image.new('L', size, 0)
    d = ImageDraw.Draw(m)
    x = center[0] - w / 2 - bb[0]
    y = center[1] - h / 2 - bb[1]
    d.text((x, y), text, font=f, fill=255, anchor='ls', direction='rtl', language='ar')
    return m


def glow(mask, radius, color, alpha):
    g = mask.filter(ImageFilter.GaussianBlur(radius))
    layer = Image.new('RGBA', mask.size, color + (0,))
    layer.putalpha(g.point(lambda v: int(v * alpha)))
    return layer


def mark(size, wave_box, text_center, text_h, text_color=IVORY, with_glow=True, mono=False):
    """الشعار (موجة + آية) على خلفية شفافة."""
    W, H = size
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    wm = wave_mask(size, wave_box)
    tm = text_mask(size, 'آية', text_center, text_h)
    if mono:
        both = Image.new('L', size, 0)
        both.paste(255, (0, 0), wm)
        both.paste(255, (0, 0), tm)
        img = Image.new('RGBA', size, (255, 255, 255, 0))
        img.putalpha(both)
        return img
    if with_glow:
        img = Image.alpha_composite(img, glow(wm, W * 0.03, GOLD_MID, 0.55))
        img = Image.alpha_composite(img, glow(tm, W * 0.02, (255, 240, 200), 0.25))
    grad = vertical_gradient(size, GOLD_TOP, GOLD_MID, GOLD_BOT)
    gl = Image.new('RGBA', size, (0, 0, 0, 0))
    gl.paste(grad, (0, 0), wm)
    img = Image.alpha_composite(img, gl)
    tl = Image.new('RGBA', size, text_color + (255,))
    tl.putalpha(tm)
    # ظل خفيف تحت الكلمة عشان تنفصل عن الموجة.
    sh = Image.new('RGBA', size, (0, 0, 0, 0))
    shm = tm.filter(ImageFilter.GaussianBlur(W * 0.006)).point(lambda v: int(v * 0.45))
    sh.paste((0, 20, 14, 255), (0, int(W * 0.006)), shm)
    img = Image.alpha_composite(img, sh)
    img = Image.alpha_composite(img, tl)
    return img


def background(size, corner=0.0, pattern=True):
    """خلفية زمردية بتدرّج دائري + نقش هندسي خفيف (نجمة ثمانية)."""
    W, H = size
    bg = Image.new('RGBA', size)
    px = bg.load()
    cx, cy = W * 0.5, H * 0.42
    rmax = math.hypot(W, H) * 0.62
    for y in range(H):
        for x in range(W):
            t = min(1.0, math.hypot(x - cx, y - cy) / rmax)
            t = t ** 1.15
            px[x, y] = tuple(int(GREEN_C[i] + (GREEN_E[i] - GREEN_C[i]) * t) for i in range(3)) + (255,)
    if pattern:
        # نجمة ثمانية (مربعين واحد مدوّر 45°) + دايرة، بذهبي خافت جداً.
        pat = Image.new('RGBA', size, (0, 0, 0, 0))
        d = ImageDraw.Draw(pat)
        lw = max(1, int(W * 0.0035))
        cxp, cyp = W / 2, H / 2
        for r, a in ((W * 0.40, 30), (W * 0.30, 20)):
            for sq in range(2):
                rot = math.pi / 4 * sq + math.pi / 4
                pts = [(cxp + r * math.cos(rot + math.pi / 2 * k), cyp + r * math.sin(rot + math.pi / 2 * k)) for k in range(4)]
                d.polygon(pts, outline=(222, 182, 92, a), width=lw)
        rr = W * 0.40 * 0.924
        d.ellipse((cxp - rr, cyp - rr, cxp + rr, cyp + rr), outline=(222, 182, 92, 18), width=lw)
        bg = Image.alpha_composite(bg, pat)
    if corner > 0:
        m = Image.new('L', size, 0)
        ImageDraw.Draw(m).rounded_rectangle((0, 0, W - 1, H - 1), radius=W * corner, fill=255)
        bg.putalpha(m)
    return bg


def compose_icon(S, corner):
    """أيقونة كاملة SxS (خلفية + شعار)."""
    big = 1024
    bg = background((big, big), corner=corner)
    m = mark((big, big), wave_box=(big * 0.20, big * 0.50, big * 0.80, big * 0.80),
             text_center=(big * 0.5, big * 0.335), text_h=big * 0.25)
    out = Image.alpha_composite(bg, m)
    if corner > 0:
        a = bg.getchannel('A')
        out.putalpha(a)
    return out.resize((S, S), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(BRAND, exist_ok=True)

    # 1) الشعار الكامل بخلفية شفافة (للواجهة).
    big = 1200
    logo = mark((big, big), wave_box=(big * 0.12, big * 0.50, big * 0.88, big * 0.86),
                text_center=(big * 0.5, big * 0.315), text_h=big * 0.30)
    logo = logo.crop(logo.getbbox())
    pad = int(logo.width * 0.06)
    framed = Image.new('RGBA', (logo.width + 2 * pad, logo.height + 2 * pad), (0, 0, 0, 0))
    framed.paste(logo, (pad, pad))
    framed.save(os.path.join(BRAND, 'logo_mark.png'))

    # الموجة لحالها (أيقونات صغيرة).
    wv = Image.new('RGBA', (600, 300), (0, 0, 0, 0))
    wm = wave_mask((600, 300), (20, 20, 580, 280))
    grad = vertical_gradient((600, 300), GOLD_TOP, GOLD_MID, GOLD_BOT)
    wv.paste(grad, (0, 0), wm)
    wv.save(os.path.join(BRAND, 'logo_wave.png'))

    # 2) الأيقونة الكاملة (legacy) بكل الكثافات + 512 لجوجل بلاي.
    dens = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    for name, s in dens.items():
        compose_icon(s, corner=0.22).save(os.path.join(RES, f'mipmap-{name}', 'ic_launcher.png'))
    compose_icon(512, corner=0.0).save(os.path.join(OUT, 'play_store_512.png'))
    compose_icon(1024, corner=0.22).save(os.path.join(OUT, 'icon_1024.png'))

    # 3) adaptive (108dp، المنطقة الآمنة 66dp بالنص).
    adapt = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
    A = 1296
    fgk = dict(wave_box=(A * 0.21, A * 0.475, A * 0.79, A * 0.695),
               text_center=(A * 0.5, A * 0.355), text_h=A * 0.17)
    fg = mark((A, A), **fgk)
    mono = mark((A, A), mono=True, **fgk)
    bgi = background((A, A))
    for name, s in adapt.items():
        d = os.path.join(RES, f'mipmap-{name}')
        fg.resize((s, s), Image.LANCZOS).save(os.path.join(d, 'ic_launcher_foreground.png'))
        bgi.resize((s, s), Image.LANCZOS).save(os.path.join(d, 'ic_launcher_background.png'))
        mono.resize((s, s), Image.LANCZOS).save(os.path.join(d, 'ic_launcher_monochrome.png'))

    # 4) معاينة: الأيقونة بأشكال القص الشائعة.
    prev = Image.new('RGBA', (1500, 560), (24, 24, 28, 255))
    full = Image.alpha_composite(bgi, fg).resize((420, 420), Image.LANCZOS)
    for i, shape in enumerate(['circle', 'squircle', 'legacy']):
        x = 60 + i * 480
        if shape == 'legacy':
            prev.alpha_composite(compose_icon(420, 0.22), (x, 70))
        else:
            m = Image.new('L', (420, 420), 0)
            dd = ImageDraw.Draw(m)
            if shape == 'circle':
                dd.ellipse((0, 0, 419, 419), fill=255)
            else:
                dd.rounded_rectangle((0, 0, 419, 419), radius=120, fill=255)
            t = full.copy()
            t.putalpha(m)
            prev.alpha_composite(t, (x, 70))
    prev.save(os.path.join(OUT, 'icon_shapes_preview.png'))
    print('ok')


if __name__ == '__main__':
    main()
