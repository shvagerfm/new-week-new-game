"""Draws the placeholder sprite sheets: facades, window scenes, the courier's
trick poses and the puzzle points.

Each sheet has the exact size and grid of the final art (see the art list),
so the placeholders double as templates: open one, paint over it, save it
under the same name, and the game picks it up. Rerunning this script
overwrites the sheets, so only run it while they are still placeholders:

    python3 art/make_placeholders.py facade window-rooms window-scenes window-props

With no names it draws only the sheets that do not exist yet.
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "sprites")

# The rooftop.png palette.
INK = "#0e1021"
MORTAR = "#111634"
MORTAR_HI = "#171e47"
BRICK = "#212956"
STONE = "#39447c"
STONE_HI = "#5869ac"
STONE_TOP = "#91a8e7"
SILL = "#485493"
WARM = ["#ffc24a", "#ed8b3f", "#df782e", "#8f4731"]
SKIN = "#f4c49c"
RUST = (1.25, 0.82, 0.8)


def hexc(c):
    c = c.lstrip("#")
    return (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16), 255)


class Sheet:
    def __init__(self, w, h):
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.ox = 0
        self.oy = 0

    def cell(self, x, y):
        self.ox, self.oy = x, y
        return self

    def px(self, x, y, c):
        x += self.ox
        y += self.oy
        if 0 <= x < self.img.width and 0 <= y < self.img.height:
            self.img.putpixel((x, y), hexc(c) if isinstance(c, str) else c)

    def rect(self, x, y, w, h, c):
        for j in range(y, y + h):
            for i in range(x, x + w):
                self.px(i, j, c)

    def box(self, x, y, w, h, c, edge=INK):
        """A filled rectangle with a one-pixel outline."""
        self.rect(x, y, w, h, edge)
        if w > 2 and h > 2:
            self.rect(x + 1, y + 1, w - 2, h - 2, c)

    def clear(self, x, y, w, h):
        self.rect(x, y, w, h, (0, 0, 0, 0))

    def save(self, name):
        path = os.path.join(OUT, name + ".png")
        self.img.save(path)
        print("wrote", os.path.relpath(path))


# --- facade.png --------------------------------------------------------------
# 256x128, 64x64 cells. Row 0: left end, wall with window, plain wall,
# right end. Row 1: the same, cracked and rust-tinted for crumbling roofs.
# The window opening (x 16-47, y 12-51) is see-through.

def brick(s, x0, x1):
    for y in range(64):
        for x in range(x0, x1):
            r = y % 8
            if r == 0:
                c = MORTAR
            elif r == 1:
                c = MORTAR_HI
            else:
                shift = 8 if (y // 8) % 2 else 0
                c = MORTAR if (x + shift) % 16 == 0 else BRICK
            s.px(x, y, c)


def pillar(s, left):
    xs = range(0, 7) if left else range(57, 64)
    for y in range(64):
        for x in xs:
            edge = x == 0 if left else x == 63
            inner = x == 6 if left else x == 57
            s.px(x, y, INK if edge else (MORTAR if inner else STONE))
        # a drain pipe clamp every floor
    hx = 2 if left else 58
    s.rect(hx, 30, 4, 3, STONE_HI)


def window(s):
    # lintel, frame and sill around the opening at (16, 12) 32x40
    s.box(13, 8, 38, 5, STONE)
    s.rect(14, 9, 36, 1, STONE_HI)
    s.rect(14, 12, 2, 41, STONE)
    s.rect(48, 12, 2, 41, STONE)
    s.rect(13, 12, 1, 41, INK)
    s.rect(50, 12, 1, 41, INK)
    s.box(11, 52, 42, 5, SILL)
    s.rect(12, 53, 40, 1, STONE_TOP)
    s.clear(16, 12, 32, 40)


def crack(s, seed):
    x, y = 20 + seed * 7 % 24, 0
    while y < 40:
        s.px(x, y, INK)
        s.px(x + 1, y, MORTAR)
        y += 1
        x += (1 if (y * 7 + seed) % 5 < 2 else -1 if (y * 3 + seed) % 7 < 2 else 0)


def tint(img, box, mul):
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            r, g, b, a = img.getpixel((x, y))
            if a:
                img.putpixel((x, y), (min(255, int(r * mul[0])), min(255, int(g * mul[1])),
                                      min(255, int(b * mul[2])), a))


def facade():
    s = Sheet(256, 128)
    for row in range(2):
        for col in range(4):
            s.cell(col * 64, row * 64)
            brick(s, 0, 64)
            if col == 0:
                pillar(s, True)
            if col == 3:
                pillar(s, False)
            if col == 1:
                window(s)
            if row == 1:
                crack(s, col + 1)
    tint(s.img, (0, 64, 256, 128), RUST)
    s.save("facade")


# --- window-rooms.png ------------------------------------------------------------
# 160x40, 32x40 cells: kitchen, bedroom, living room with curtains, stairs,
# dark window. What shows through a window with no scene.

def wall(s, top, bottom="#5a2f2a"):
    s.rect(0, 0, 32, 40, top)
    s.rect(0, 30, 32, 10, bottom)
    s.rect(0, 30, 32, 1, INK)


def lamp(s, x, y):
    s.rect(x, 0, 1, y, INK)
    s.rect(x - 3, y, 7, 3, WARM[0])
    s.rect(x - 2, y + 3, 5, 1, "#fff0b0")


def rooms():
    s = Sheet(160, 40)
    # kitchen: warm wall, shelves, kettle
    s.cell(0, 0)
    wall(s, WARM[2])
    lamp(s, 16, 6)
    s.rect(3, 14, 26, 2, WARM[3])
    for x in (5, 11, 19):
        s.box(x, 10, 4, 4, "#e8ecff")
    s.box(2, 24, 28, 7, "#8796c8")
    # bedroom: orange wall, bed, picture
    s.cell(32, 0)
    wall(s, WARM[1], WARM[3])
    lamp(s, 24, 4)
    s.box(5, 8, 10, 8, WARM[0])
    s.box(2, 25, 22, 6, "#e8ecff")
    s.rect(2, 22, 6, 4, "#4a78ff")
    # living room, curtains half drawn
    s.cell(64, 0)
    wall(s, WARM[2], WARM[3])
    lamp(s, 16, 8)
    s.box(8, 22, 16, 9, "#4b5788")
    s.rect(0, 0, 7, 40, "#c85a1c")
    s.rect(25, 0, 7, 40, "#c85a1c")
    for x in (2, 5, 27, 30):
        s.rect(x, 0, 1, 40, "#8f4731")
    # stairwell: dim, a railing going up
    s.cell(96, 0)
    wall(s, WARM[3], "#3a2230")
    for i in range(8):
        s.rect(4 + i * 3, 34 - i * 4, 4, 1, WARM[1])
    s.rect(14, 3, 3, 3, WARM[0])
    # dark window
    s.cell(128, 0)
    s.rect(0, 0, 32, 40, "#161c3e")
    s.rect(0, 30, 32, 10, "#10142e")
    s.rect(20, 18, 6, 12, "#10142e")
    s.save("window-rooms")


# --- window-scenes.png -----------------------------------------------------------
# 192x240: six scenes, one per row, six 32x40 frames each.

def person(s, x, y, body, head=SKIN, hair="#3a2230", arms=(0, 0), legs=True, w=8):
    """A small figure, feet on y. arms: raise of each arm in px (negative = down)."""
    top = y - 24
    s.box(x - w // 2, top + 8, w, 10, body)          # torso
    s.box(x - 3, top, 7, 8, head)                     # head
    s.rect(x - 3, top, 7, 2, hair)
    s.px(x + 1, top + 4, INK)
    for side, raise_ in zip((-1, 1), arms):
        ax = x - w // 2 - 2 if side < 0 else x + w // 2
        if raise_ > 0:
            s.rect(ax, top + 9 - raise_, 2, raise_ + 2, head)
        else:
            s.rect(ax, top + 9, 2, 7, head)
    if legs:
        s.rect(x - 3, top + 18, 2, 6, "#232a55")
        s.rect(x + 1, top + 18, 2, 6, "#232a55")


def scene_cat(s, f):
    wall(s, WARM[2], WARM[3])
    lamp(s, 22, 5)
    s.rect(0, 33, 32, 2, SILL)
    cx = 8 + min(f, 3) * 2
    s.box(cx, 25, 10, 8, "#3a3a46")           # body
    s.box(cx + 7, 20, 7, 7, "#3a3a46")        # head
    s.px(cx + 8, 19, "#3a3a46")
    s.px(cx + 12, 19, "#3a3a46")
    s.px(cx + 11, 23, "#ffd27a")
    if f in (2, 3):
        s.rect(cx + 13, 28, 4, 2, "#3a3a46")  # paw out
    if f < 4:
        px = 24 if f < 3 else 26
        s.box(px, 26, 6, 7, "#c85a1c")       # pot
        s.rect(px + 1, 22, 4, 4, "#4caf50")
    if f == 5:
        s.rect(cx, 26, 2, 4, "#e8ecff")       # licking a paw


def scene_disco(s, f):
    s.rect(0, 0, 32, 40, "#2a1440")
    s.rect(0, 30, 32, 10, "#1a0c2a")
    s.box(13, 1, 6, 6, "#c9d4ff")
    cols = ["#ff4d5e", "#4a78ff", "#ffd27a", "#4caf50", "#ff8a3d", "#8a66b8"]
    for i in range(5):
        x = (i * 7 + f * 5) % 30
        y = (i * 11 + f * 3) % 26
        s.rect(x, y, 2, 2, cols[(i + f) % 6])
    poses = [(8, 0), (0, 0), (0, 8), (4, 4), (8, 8), (10, -1)]
    dx = [0, 2, 0, -2, 0, 1][f]
    person(s, 16 + dx, 36 - (2 if f == 3 else 0), "#f4c49c", arms=poses[f])
    s.rect(13 + dx, 26 - (2 if f == 3 else 0), 8, 3, "#ff4d5e")  # shorts


def scene_granny(s, f):
    wall(s, WARM[3] if f < 5 else WARM[0], "#3a2230")
    if f >= 2:
        person(s, 16, 40, "#8a66b8", hair="#c9d4ff", arms=(6, 6) if f >= 3 else (0, 0))
        if f >= 3:
            s.box(12, 18, 9, 4, INK)
            s.px(14, 19, "#c9d4ff")
            s.px(18, 19, "#c9d4ff")
    open_ = [0, 6, 10, 10, 10, 10][f]
    s.rect(0, 0, 16 - open_, 40, "#7a3a8a")
    s.rect(16 + open_, 0, 16 - open_, 40, "#7a3a8a")
    if f == 5:
        lamp(s, 26, 4)


def scene_couple(s, f):
    wall(s, WARM[1], WARM[3])
    lamp(s, 16, 4)
    shout = (f in (1, 3))
    person(s, 9, 38, "#ff4d5e", hair="#c85a1c", arms=(6, 0) if shout else (0, 0))
    person(s, 23, 38, "#4a78ff", arms=(0, 6) if f == 2 else (10, 0) if f == 3 else (0, 0))
    if f == 3:
        s.box(18, 6, 9, 6, "#e8ecff")   # pillow raised
    if f == 4:
        s.box(2, 8, 9, 6, "#e8ecff")    # pillow flying out
    if f in (1, 2):
        s.rect(13 if f == 1 else 17, 6, 3, 3, "#ffd27a")


def scene_grandpa(s, f):
    s.rect(0, 0, 32, 40, "#1c2a5a")
    s.rect(0, 30, 32, 10, "#141c3e")
    s.box(1, 22, 9, 8, "#4b5788")       # TV, glowing
    s.rect(2, 23, 7, 6, "#7fd0ff" if f % 2 else "#4a78ff")
    lift = [0, 5, 10, 9, 4, 0][f]
    person(s, 20, 38, "#e8ecff", hair="#c9d4ff", arms=(lift, lift))
    y = 23 - lift
    for x in (13, 26):
        s.box(x, y, 4, 3, INK)
    if f == 2:
        s.rect(17, 15, 7, 2, "#ff4d5e")   # red in the face
    if f == 5:
        s.rect(23, 16, 2, 2, "#7fd0ff")   # sweat


def scene_dog(s, f):
    wall(s, WARM[2], WARM[3])
    lamp(s, 8, 5)
    nose_x = [18, 18, 22, 24, 29, 28][f]
    s.box(nose_x - 16, 26, 14, 9, "#b8733a")            # body
    s.box(nose_x - 6, 18 if f else 26, 9, 8, "#b8733a")  # head
    if f == 0:
        s.rect(nose_x - 4, 22, 4, 1, INK)               # asleep
    else:
        s.rect(nose_x - 5, 16, 3, 4, "#8f4731")          # ear up
        s.px(nose_x - 1, 20, INK)
        s.rect(nose_x + 1, 22, 2, 2, INK)               # nose
    if f in (2, 3):
        s.rect(nose_x - 2, 24, 4, 2, "#ff4d5e")          # barking
    if f == 5:
        for i in range(10):
            s.px(20 + i, 14 + (i * 7) % 12, (232, 236, 255, 140))  # fogged glass


def scenes():
    s = Sheet(192, 240)
    for row, fn in enumerate([scene_cat, scene_disco, scene_granny, scene_couple, scene_grandpa, scene_dog]):
        for f in range(6):
            s.cell(f * 32, row * 40)
            fn(s, f)
    s.save("window-scenes")


# --- window-props.png ------------------------------------------------------------
# 128x32, 16x16 cells. Row 0: pot falling (2), pot broken, pillow spinning
# (4), feather. Row 1: disco ball (2), light spot, WOOF (2), binocular glint.

def props():
    s = Sheet(128, 32)
    s.cell(0, 0)
    s.box(5, 7, 7, 8, "#c85a1c")
    s.rect(6, 2, 5, 5, "#4caf50")
    s.cell(16, 0)
    s.box(4, 6, 8, 7, "#c85a1c")
    s.rect(11, 4, 4, 5, "#4caf50")
    s.cell(32, 0)
    for x, y in ((2, 12), (6, 13), (10, 12), (13, 13)):
        s.box(x, y, 3, 3, "#c85a1c")
    s.rect(6, 10, 4, 3, "#4caf50")
    for i in range(4):
        s.cell(48 + i * 16, 0)
        if i % 2 == 0:
            s.box(2, 4, 12, 8, "#e8ecff")
            s.rect(3, 9, 10, 2, "#c9d4ff")
        else:
            s.box(4, 2, 8, 12, "#e8ecff")
            s.rect(9, 3, 2, 10, "#c9d4ff")
    s.cell(112, 0)
    s.rect(4, 7, 8, 2, "#e8ecff")
    s.rect(6, 6, 4, 4, "#e8ecff")
    for i in range(2):
        s.cell(i * 16, 16)
        s.box(3, 3, 10, 10, "#8796c8")
        for y in range(4, 12, 2):
            for x in range(4 + (y + i) % 4, 12, 4):
                s.px(x, y, "#e8ecff")
    s.cell(32, 16)
    for y in range(16):
        for x in range(16):
            d = ((x - 7.5) ** 2 + (y - 7.5) ** 2) ** 0.5
            if d < 7.5:
                s.px(x, y, (255, 255, 255, int(200 * (1 - d / 7.5))))
    for i in range(2):
        s.cell(48 + i * 16, 16)
        s.box(0, 2 + i, 16, 11, "#e8ecff")
        for x, letter in zip((2, 6, 10), ("W", "O", "F")):
            s.rect(x, 5 + i, 3, 5, INK)
            s.rect(x + 1, 6 + i, 1, 3, "#e8ecff")
    s.cell(80, 16)
    s.rect(7, 2, 2, 12, "#ffffff")
    s.rect(2, 7, 12, 2, "#ffffff")
    s.rect(6, 6, 4, 4, "#ffffff")
    s.save("window-props")


# --- courier-tricks.png -----------------------------------------------------------
# 512x64: eight 64x64 poses, feet at y 58. Placeholders reuse courier.png
# frames: hanging 0-1, parachute 2-3, squat 4, launch 5, riding the cradle 6-7.

def tricks():
    src = Image.open(os.path.join(OUT, "courier.png")).convert("RGBA")
    s = Sheet(512, 64)
    for i, f in enumerate([6, 7, 6, 7, 8, 6, 0, 1]):
        s.img.paste(src.crop((f * 64, 0, f * 64 + 64, 64)), (i * 64, 0))
    s.save("courier-tricks")


# --- bat.png --------------------------------------------------------------------------
# 128x24: four 32x24 frames, claws at (16, 22). Hover 0-1, carrying 2-3.

BAT = [["V..........V", "VV........VV", "VVV.v..v.VVV", ".VVvvvvvvVV.", "..vvrvvrvv..", "...vvvvvv...", "....v..v....", "............"],
       ["............", "....v..v....", "...vvvvvv...", "..vvrvvrvv..", ".VVvvvvvvVV.", "VVV.vvvv.VVV", "VV........VV", "V..........V"]]
BAT_PAL = {"V": "#8a66b8", "v": "#4b3368", "r": "#ff4d5e"}


def bat():
    s = Sheet(128, 24)
    for f in range(4):
        s.cell(f * 32, 0)
        rows = BAT[f % 2]
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch in BAT_PAL:
                    c = BAT_PAL[ch] if f < 2 or ch != "r" else "#ffffff"
                    s.rect(4 + x * 2, 7 + y * 2 - (2 if f >= 2 else 0), 2, 2, c)
        s.rect(14, 20, 1, 3, INK)   # legs down to the claws
        s.rect(17, 20, 1, 3, INK)
    s.save("bat")


# --- steam.png -------------------------------------------------------------------------
# 160x32: pipe (bottom on row 31), then four puffs growing and fading.

def steam():
    s = Sheet(160, 32)
    s.cell(0, 0)
    s.box(11, 12, 10, 20, "#4b5788")
    s.box(8, 8, 16, 6, "#8796c8")
    s.box(3, 18, 8, 8, "#8796c8")   # valve wheel
    s.rect(6, 21, 2, 2, INK)
    for i in range(4):
        s.cell(32 + i * 32, 0)
        r = 4 + i * 3
        for y in range(32):
            for x in range(32):
                d = ((x - 15.5) ** 2 + (y - 15.5) ** 2) ** 0.5
                if d < r and (i < 2 or (x + y + i) % (i + 1) == 0):
                    s.px(x, y, "#e8ecff" if d < r - 3 else "#c9d4ff")
    s.save("steam")


# --- laundry.png ------------------------------------------------------------------------
# 144x48: a 96x48 line with two posts and four things pegged on, then a
# 48x48 sheet billowing like a parachute, corners at (18, 44) and (46, 44).

def laundry():
    s = Sheet(144, 48)
    s.rect(1, 0, 3, 48, "#4b5788")
    s.rect(92, 0, 3, 48, "#4b5788")
    for x in range(2, 94):
        s.px(x, 3 + int(4 * __import__("math").sin(3.14159 * (x - 2) / 92)), "#c9d4ff")
    for x0, w, h, c in ((8, 16, 20, "#ff8a3d"), (28, 10, 12, "#4a78ff"), (42, 14, 24, "#ffd27a"), (60, 28, 34, "#e8ecff")):
        top = 4 + int(4 * __import__("math").sin(3.14159 * (x0 + w / 2 - 2) / 92))
        s.box(x0, top, w, h, c)
        s.rect(x0 + 2, top - 1, 2, 3, "#b8733a")
        s.rect(x0 + w - 4, top - 1, 2, 3, "#b8733a")
    s.cell(96, 0)
    for y in range(8, 30):
        half = int(22 * (1 - ((y - 20) / 13) ** 2) ** 0.5) if abs(y - 20) < 13 else 0
        s.rect(24 - half, y, half * 2, 1, "#e8ecff")
    s.rect(4, 28, 40, 3, "#4a78ff")
    for k in range(13):
        s.px(18 - (k // 2) + 6, 31 + k, "#c9d4ff")
        s.px(46 - 6 + (k // 2), 31 + k, "#c9d4ff")
    s.save("laundry")


# --- skylight.png -----------------------------------------------------------------------
# 64x16: left end, middle (repeats), right end, broken. Glass top on row 2.

def skylight():
    s = Sheet(64, 16)
    for i in range(4):
        s.cell(i * 16, 0)
        s.rect(0, 2, 16, 14, "#2a3360")
        s.rect(0 if i else 3, 4, 16 if i in (1, 3) else 13, 10, "#7fd0ff")
        s.rect(0 if i else 3, 4, 16 if i in (1, 3) else 13, 2, "#c9f0ff")
        if i == 2:
            s.rect(13, 2, 3, 14, "#2a3360")
            s.rect(0, 4, 13, 10, "#7fd0ff")
            s.rect(0, 4, 13, 2, "#c9f0ff")
        s.rect(0, 2, 16, 1, INK)
        if i == 1:
            s.rect(7, 4, 2, 10, "#2a3360")
        if i == 3:
            s.clear(3, 4, 10, 10)
            for x, y in ((3, 4), (5, 4), (11, 4), (12, 5)):
                s.rect(x, y, 1, 3, "#c9f0ff")
    s.save("skylight")


# --- awning.png -------------------------------------------------------------------------
# 288x32: three 96x32 frames (rest, squashed, rebound); the bracket is at the
# right edge, the fabric top runs about row 6.

def awning():
    s = Sheet(288, 32)
    for f in range(3):
        s.cell(f * 96, 0)
        sag = [0, 6, -4][f]
        for x in range(4, 96):
            k = (x - 4) / 92
            y = 6 + int(sag * __import__("math").sin(3.14159 * k))
            stripe = "#ff8a3d" if (x // 8) % 2 else "#e8ecff"
            s.px(x, y - 1, INK)
            s.rect(x, y, 1, 6, stripe)
            s.px(x, y + 6, INK)
        for x in range(4, 92, 8):   # scalloped edge
            y = 6 + int(sag * __import__("math").sin(3.14159 * (x - 4) / 92))
            s.rect(x, y + 7, 4, 2, "#ff8a3d" if (x // 8) % 2 else "#e8ecff")
        s.rect(92, 2, 4, 20, "#4b5788")
        for i in range(8):
            s.px(92 - i * 4, 14 + i, "#4b5788")
        if f == 2:
            for x in (20, 46, 72):
                s.rect(x, 0, 1, 3, "#e8ecff")
    s.save("awning")


# --- zipline.png ------------------------------------------------------------------------
# 64x64: top pole, bottom pole (cable at (8, 4)), handle, handle sliding
# (wheels at (8, 4), grip at (8, 22)).

def zipline():
    s = Sheet(64, 64)
    for i in range(2):
        s.cell(i * 16, 0)
        s.box(6, 4, 4, 60, "#4b5788")
        s.box(4, 2, 8, 5, "#8796c8")
        s.rect(13 if i == 0 else 2, 6, 1, 1, INK)
    for i in range(2):
        s.cell(32 + i * 16, 0)
        s.box(4, 2, 8, 5, "#8796c8")
        s.rect(7, 7, 2, 13, "#4b5788")
        s.box(1, 20, 14, 4, "#ff8a3d")
        if i:
            s.rect(1, 3, 2, 2, "#ffd27a")
            s.rect(13, 1, 2, 2, "#ff8a3d")
    s.save("zipline")


# --- cradle.png ---------------------------------------------------------------------
# 192x32: cradle, cradle moving (floor on row 24, rope hooks at x 4 and 60),
# then the roof winch with its arm out to the left.

def cradle():
    s = Sheet(192, 32)
    for f in range(2):
        s.cell(f * 64, 0)
        s.box(0, 24, 64, 6, "#8796c8")
        s.box(0, 8, 64, 3, "#ffd27a")
        for x in (0, 30, 61):
            s.rect(x, 8, 3, 16, "#4b5788")
        s.box(44, 16, 8, 8, "#4b5788")   # bucket
        s.rect(28, 2, 6, 6, "#ff8a3d" if f else "#8f4731")
        s.rect(3, 0, 2, 8, INK)
        s.rect(59, 0, 2, 8, INK)
    s.cell(128, 0)
    s.box(36, 14, 24, 18, "#4b5788")
    s.box(4, 10, 40, 5, "#ffd27a")
    s.box(2, 14, 6, 6, "#8796c8")
    s.save("cradle")


# --- crane.png ---------------------------------------------------------------------
# 96x32: jib segment (repeats), jib end with trolley, hook (cable at (16, 0),
# grip at (16, 28)).

def crane():
    s = Sheet(96, 32)
    for f in range(2):
        s.cell(f * 32, 0)
        s.rect(0, 4, 32, 3, "#ffd27a")
        s.rect(0, 18, 32, 3, "#ffd27a")
        for x in range(0, 32, 8):
            for k in range(14):
                s.px(x + k // 2, 7 + k, "#d8a838")
        s.rect(0, 3, 32, 1, INK)
        s.rect(0, 21, 32, 1, INK)
        if f == 1:
            s.clear(24, 0, 8, 32)
            s.box(8, 22, 16, 6, "#4b5788")
    s.cell(64, 0)
    s.box(9, 2, 14, 10, "#ffd27a")
    s.rect(10, 6, 12, 2, "#ff4d5e")
    s.rect(15, 12, 3, 8, "#8796c8")
    s.rect(10, 26, 12, 3, "#8796c8")
    s.rect(10, 20, 3, 8, "#8796c8")
    s.rect(19, 18, 3, 4, "#8796c8")
    s.save("crane")


SHEETS = {"facade": facade, "window-rooms": rooms, "window-scenes": scenes, "window-props": props,
          "courier-tricks": tricks, "bat": bat, "steam": steam, "laundry": laundry,
          "skylight": skylight, "awning": awning, "zipline": zipline, "cradle": cradle, "crane": crane}

if __name__ == "__main__":
    names = sys.argv[1:] or [n for n in SHEETS if not os.path.exists(os.path.join(OUT, n + ".png"))]
    for n in names:
        SHEETS[n]()
