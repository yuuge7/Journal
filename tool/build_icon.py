"""Builds the launcher icon layers into assets/icon/.

The icon is the app's feed drawn small: a page, a thread down its left with a
bead per day, a line of writing beside each, and today's bead in brass. The
thread changes thickness between beads for the same reason the feed's spine
does — it is set by how long that day was spent writing. That is the one thing
this journal knows that a cloud diary does not, and it is what keeps the icon
from reading as a task list.

Geometry follows the adaptive-icon spec: the 108dp layer is 1024px, launchers
show only the middle 72/108 and then mask it, so the page's diagonal (668px)
stays inside the 682px circle every mask can crop to. Padding is baked in here,
which is why pubspec sets `adaptive_icon_foreground_inset: 0`.

Needs Pillow:  python -m pip install pillow
Run:           python tool/build_icon.py && dart run flutter_launcher_icons
"""
import os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 4                      # supersample, downsampled at the end
ASSETS = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'assets', 'icon')

INK = (0x1B, 0x22, 0x30, 255)
PAPER = (0xF4, 0xF1, 0xE8, 255)
PAPER_DIM = (0xC6, 0xC1, 0xB2, 255)
BRASS = (0xE0, 0xA8, 0x4A, 255)
RULE = (0x6B, 0x72, 0x80, 255)
RULE_SOFT = (0xA8, 0xAD, 0xB5, 255)

PW, PH = 424, 516
PX, PY = (S - PW) / 2, (S - PH) / 2
PR = 32
SPINE_X = PX + 90
TOP, BOT = PY + 76, PY + PH - 76
YS = [TOP + (BOT - TOP) * f for f in (0.06, 0.5, 0.94)]
WEIGHTS = (26, 11)          # minutes written between one bead and the next
BLOCKS = ((2, 0.96, 0.58), (1, 0.72), (1, 0.88))


def canvas():
    return Image.new('RGBA', (S * SS, S * SS), (0, 0, 0, 0))


def done(im):
    return im.resize((S, S), Image.LANCZOS)


def rr(d, box, radius, fill, outline=None, width=0):
    d.rounded_rectangle([v * SS for v in box], radius=radius * SS, fill=fill,
                        outline=outline, width=int(width * SS) if width else 0)


def circle(d, cx, cy, r, fill):
    d.ellipse([(cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS], fill=fill)


def lines(d, colour):
    left = SPINE_X + 58
    avail = PX + PW - 48 - left
    h, gap = 22, 14
    for y, block in zip(YS, BLOCKS):
        n, *widths = block
        total = n * h + (n - 1) * gap
        for k in range(n):
            top = y - total / 2 + k * (h + gap)
            rr(d, (left, top, left + avail * widths[k], top + h), h / 2, colour)


def foreground():
    im = canvas()
    d = ImageDraw.Draw(im)
    rr(d, (PX, PY, PX + PW, PY + PH), PR, PAPER)
    for i, w in enumerate(WEIGHTS):
        rr(d, (SPINE_X - w / 2, YS[i], SPINE_X + w / 2, YS[i + 1]), w / 2,
           RULE if w >= 14 else RULE_SOFT)
    circle(d, SPINE_X, YS[0], 34, BRASS)
    for y in YS[1:]:
        circle(d, SPINE_X, y, 20, INK)
    lines(d, PAPER_DIM)
    return done(im)


def monochrome():
    """A themed icon is one colour, so the page becomes an outline and today's
    bead keeps its rank by being the largest mark rather than the brass one."""
    im = canvas()
    d = ImageDraw.Draw(im)
    W = (255, 255, 255, 255)
    rr(d, (PX, PY, PX + PW, PY + PH), PR, None, outline=W, width=21)
    for i, w in enumerate(WEIGHTS):
        rr(d, (SPINE_X - w / 2, YS[i], SPINE_X + w / 2, YS[i + 1]), w / 2, W)
    circle(d, SPINE_X, YS[0], 33, W)
    for y in YS[1:]:
        circle(d, SPINE_X, y, 20, W)
    lines(d, W)
    return done(im)


def background():
    g = Image.new('RGB', (S, S))
    px = g.load()
    c0, c1 = (0x2B, 0x33, 0x44), (0x0E, 0x12, 0x19)
    for y in range(S):
        for x in range(S):
            t = (x + y) / (2 * (S - 1))
            px[x, y] = tuple(round(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
    halo = Image.new('L', (S, S), 0)
    ImageDraw.Draw(halo).ellipse([S * 0.14, S * 0.10, S * 0.86, S * 0.90], fill=255)
    halo = halo.filter(ImageFilter.GaussianBlur(S * 0.11)).point(lambda v: v // 3)
    return Image.composite(Image.new('RGB', (S, S), (0x3A, 0x45, 0x5C)),
                           g, halo).convert('RGBA')


if __name__ == '__main__':
    import sys
    target = sys.argv[1] if len(sys.argv) > 1 else ASSETS
    os.makedirs(target, exist_ok=True)
    bg, fg = background(), foreground()
    bg.save(f'{target}/background.png')
    fg.save(f'{target}/foreground.png')
    monochrome().save(f'{target}/monochrome.png')
    Image.alpha_composite(bg, fg).convert('RGB').save(f'{target}/icon.png')
    print('wrote 4 layers to', target)
