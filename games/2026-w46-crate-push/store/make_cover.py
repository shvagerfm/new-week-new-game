# Builds store/cover-630x500.png (the itch.io cover) from the game art.
# Run from the game folder: python3 store/make_cover.py . store/cover-630x500.png
import json, sys, random
from PIL import Image, ImageDraw, ImageFilter, ImageChops
G = sys.argv[1]; OUT = sys.argv[2]
W, H = 630, 500
random.seed(7)

def lerp(a, b, t): return tuple(int(a[i] + (b[i]-a[i])*t) for i in range(3))

# panel floor: diagonal gradient like the icon (lighter top-left)
bg = Image.new("RGB", (W, H))
px = bg.load()
c0, c1 = (40, 74, 110), (22, 40, 66)
for y in range(H):
    for x in range(W):
        t = min(1, max(0, (x*0.55 + y*0.8) / (W*0.55 + H*0.8)))
        n = random.randint(-2, 2)
        c = lerp(c0, c1, t)
        px[x, y] = (c[0]+n, c[1]+n, c[2]+n)

# seams (polylines with chamfered corners, like the icon's plates)
seams = [
    [(-10, 150), (170, 150), (200, 120), (380, 120), (410, 150), (640, 150)],
    [(-10, 410), (120, 410), (150, 440), (470, 440), (500, 410), (640, 410)],
    [(200, 120), (200, -10)], [(410, 150), (410, -10)],
    [(110, 150), (110, 410)], [(530, 150), (530, 410)],
    [(320, 440), (320, 510)],
]
groove = Image.new("L", (W, H), 0); gd = ImageDraw.Draw(groove)
line = Image.new("L", (W, H), 0); ld = ImageDraw.Draw(line)
for s in seams:
    gd.line(s, fill=255, width=7, joint="curve")
    ld.line(s, fill=255, width=2, joint="curve")
bg.paste((4, 14, 26), (0, 0), groove)
cyan = Image.new("RGB", (W, H), (40, 215, 235))
glow = line.filter(ImageFilter.GaussianBlur(7)).point(lambda v: min(255, v*3))
bg = ImageChops.add(bg, ImageChops.multiply(cyan, Image.merge("RGB", [glow]*3)).point(lambda v: v*0.6))
bg.paste((70, 225, 245), (0, 0), line)
# rivets near plate corners
d = ImageDraw.Draw(bg)
for (x, y) in [(22, 22), (178, 135), (395, 105), (612, 135), (125, 168), (515, 168), (125, 392), (515, 392), (22, 480), (612, 480), (220, 20), (390, 20)]:
    d.ellipse((x-3, y-3, x+3, y+3), fill=(15, 28, 45)); d.point((x-1, y-1), fill=(70, 100, 130))

# vignette
vig = Image.new("L", (W, H), 0); vd = ImageDraw.Draw(vig)
vd.ellipse((-140, -120, W+140, H+120), fill=255)
vig = vig.filter(ImageFilter.GaussianBlur(60))
bg = Image.composite(bg, Image.new("RGB", (W, H), (6, 12, 24)), vig)
canvas = bg.convert("RGBA")

def sprite(sheet, name, atlas):
    a = json.load(open(atlas))
    for sh in a["sheets"]:
        if sh["file"] == sheet:
            for s in sh["sprites"]:
                if s["name"] == name:
                    im = Image.open(f"{G}/art/source/{sheet}").convert("RGBA")
                    return im.crop((s["x"], s["y"], s["x"]+s["width"], s["y"]+s["height"]))
    raise KeyError(name)

atlas = f"{G}/art/source/atlas.json"
def put(im, x, y, size, shadow=True, glowc=None):
    im = im.crop(im.split()[3].point(lambda v: 255 if v > 30 else 0).getbbox())
    k = size / max(im.size)
    im = im.resize((round(im.width*k), round(im.height*k)), Image.LANCZOS)
    x -= im.width//2; y -= im.height//2
    size = max(im.size)
    if glowc:
        a = im.split()[3].filter(ImageFilter.GaussianBlur(14))
        g = Image.new("RGBA", im.size, glowc); g.putalpha(a.point(lambda v: int(v*0.9)))
        pad = Image.new("RGBA", (size+60, size+60)); pad.paste(g, (30, 30))
        canvas.alpha_composite(pad.filter(ImageFilter.GaussianBlur(10)), (x-30, y-30))
    if shadow:
        sh = Image.new("RGBA", im.size, (0, 0, 0, 0)); sh.putalpha(im.split()[3].point(lambda v: int(v*0.55)))
        pad = Image.new("RGBA", (size+40, size+40)); pad.paste(sh, (20, 20))
        canvas.alpha_composite(pad.filter(ImageFilter.GaussianBlur(6)), (x-20+6, y-20+10))
    canvas.alpha_composite(im, (x, y))

S = 140; Y = 300; yc = 380
target = sprite("sheet-1-core.png", "target", atlas)
put(target, 530, yc, 132, shadow=False, glowc=(40, 220, 240, 255))
# motion streaks behind Kip
md = ImageDraw.Draw(canvas)
for i, (yy, ln) in enumerate([(yc-34, 40), (yc, 56), (yc+34, 34)]):
    md.rounded_rectangle((14, yy-3, 14+ln, yy+3), 3, fill=(120, 220, 240, 150))
put(sprite("sheet-1-core.png", "robot-right", atlas), 145, yc, 158)
put(sprite("sheet-1-core.png", "crate", atlas), 296, yc, 140)
# chevrons pointing at the target
for i in range(2):
    x0 = 398 + i*24
    md.line([(x0, yc-14), (x0+12, yc), (x0, yc+14)], fill=(110, 235, 250, 230), width=6, joint="curve")

# logo from the UI sheet
ua = json.load(open(f"{G}/art/source/ui/atlas.json"))
L = next(a for a in ua["assets"] if a["name"] == "logo")
logo = Image.open(f"{G}/art/source/ui/crate-push-ui-assets.png").convert("RGBA").crop((L["x"], L["y"], L["x"]+L["width"], L["y"]+L["height"]))
al = logo.split()[3].point(lambda v: 0 if v < 60 else min(255, int((v-60)*255/120)))
logo.putalpha(al)
lw = 310; lh = int(L["height"]*lw/L["width"])
logo = logo.resize((lw, lh), Image.LANCZOS)
# dark halo so the logo pops on the floor
halo = Image.new("RGBA", (lw+80, lh+80)); h = Image.new("RGBA", logo.size, (2, 8, 18, 255)); h.putalpha(logo.split()[3])
halo.paste(h, (40, 40)); halo = halo.filter(ImageFilter.GaussianBlur(16))
lx = (W-lw)//2; ly = 6
canvas.alpha_composite(halo, (lx-40, ly-40+6))
canvas.alpha_composite(logo, (lx, ly))
canvas.convert("RGB").save(OUT, optimize=True)
print(OUT, lw, lh)
