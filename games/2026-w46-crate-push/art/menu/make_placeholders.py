"""Cuts placeholder menu art out of the three mockups in art/source/ui/.

The mockups have their labels, numbers, locks and progress baked in, so this
paints those out (OpenCV inpainting) and keeps the rest. The game draws the
labels itself on top. Drawn art in art/menu/<name>.png replaces each file.

    python3 art/menu/make_placeholders.py   (needs numpy, opencv-python, pillow)

All coordinates are in mockup pixels (1080 x 1920).
"""
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
UI = HERE.parent / "source" / "ui"
OUT = HERE / "placeholder"


def load(name):
    return cv2.imread(str(UI / name), cv2.IMREAD_COLOR)


def paint_out(img, rects=(), circles=(), polys=(), rings=(), radius=9):
    """Inpaints rects (x0, y0, x1, y1), circles (x, y, r), polygons and
    rect outlines (x0, y0, x1, y1, width)."""
    mask = np.zeros(img.shape[:2], np.uint8)
    for x0, y0, x1, y1 in rects:
        cv2.rectangle(mask, (x0, y0), (x1, y1), 255, -1)
    for x, y, r in circles:
        cv2.circle(mask, (x, y), r, 255, -1)
    for p in polys:
        cv2.fillPoly(mask, [np.array(p, np.int32)], 255)
    for x0, y0, x1, y1, w in rings:
        cv2.rectangle(mask, (x0, y0), (x1, y1), 255, w)
    return cv2.inpaint(img, mask, radius, cv2.INPAINT_TELEA)


def cut(img, x0, y0, x1, y1, corner=0, circle=False, poly=None):
    """Crops a piece and gives it an alpha mask: a rounded rect, a circle or a polygon."""
    piece = img[y0:y1, x0:x1].copy()
    h, w = piece.shape[:2]
    alpha = np.zeros((h, w), np.uint8)
    if circle:
        cv2.circle(alpha, (w // 2, h // 2), min(w, h) // 2 - 1, 255, -1, cv2.LINE_AA)
    elif poly is not None:
        cv2.fillPoly(alpha, [np.array(poly, np.int32) - (x0, y0)], 255, cv2.LINE_AA)
    else:
        r = corner
        cv2.rectangle(alpha, (r, 0), (w - 1 - r, h - 1), 255, -1)
        cv2.rectangle(alpha, (0, r), (w - 1, h - 1 - r), 255, -1)
        for cx, cy in ((r, r), (w - 1 - r, r), (r, h - 1 - r), (w - 1 - r, h - 1 - r)):
            cv2.circle(alpha, (cx, cy), r, 255, -1, cv2.LINE_AA)
    return np.dstack([piece, alpha])


def save(name, img):
    cv2.imwrite(str(OUT / name), img)
    print("wrote", name, img.shape[1], "x", img.shape[0])


def main_menu():
    m = load("01-main-menu.png")
    save("button-play.png", cut(paint_out(m, rects=[(280, 1215, 810, 1370)]), 92, 1185, 986, 1402, corner=58))
    save("button-continue.png", cut(paint_out(m, rects=[(280, 1470, 805, 1580)]), 95, 1433, 982, 1617, corner=62))
    save("button-settings.png", cut(paint_out(m, rects=[(240, 1675, 860, 1805)]), 95, 1648, 982, 1832, corner=58))
    # The floor under the buttons.
    save("menu-bg.png", paint_out(m, rects=[(80, 1175, 1000, 1845)], radius=15))


def station_map():
    m = load("02-zone-map.png")
    save("back-button.png", cut(m, 19, 24, 167, 147, corner=30))
    save("map-node-lock.png", cut(m, 795, 325, 895, 425, circle=True))
    save("map-node-check.png", cut(m, 793, 1580, 897, 1684, circle=True))
    pin = [(783, 1395), (790, 1360), (812, 1337), (845, 1328), (878, 1337), (900, 1360), (907, 1395),
           (898, 1430), (875, 1455), (848, 1500), (818, 1455), (792, 1430)]
    save("kip-pin.png", cut(m, 780, 1325, 910, 1505, poly=pin))
    names = [(135, 315, 345, 412), (135, 535, 305, 627), (135, 708, 552, 842), (135, 928, 442, 1022),
             (135, 1123, 537, 1217), (135, 1333, 417, 1472), (135, 1578, 512, 1672)]
    nodes = [(845, y, 54) for y in (375, 583, 783, 977, 1172)] + [(845, 1632, 68)]
    bg = paint_out(m,
        rects=names + [(270, 40, 815, 120), (10, 15, 178, 158), (830, 260, 860, 1720),
               (92, 1282, 150, 1340), (930, 1282, 988, 1340), (92, 1455, 150, 1513), (930, 1455, 988, 1513)],
        circles=nodes + [(845, 1395, 72)],
        polys=[[(790, 1420), (900, 1420), (848, 1510)]],
        rings=[(96, 1286, 984, 1509, 30)])
    save("map-bg.png", bg)


def level_select():
    m = load("03-level-select.png")
    tiles = []
    for x0 in (127, 563):
        for y0 in (438, 712, 985, 1260, 1535):
            tiles.append((x0 - 14, y0 - 16, x0 + 404, y0 + 262))
    bg = paint_out(m,
        rects=tiles + [(30, 35, 192, 182), (240, 55, 890, 145), (70, 205, 1015, 290), (90, 295, 995, 395)],
        radius=20)
    save("levels-bg.png", bg)
    # Tile 1 and tile 7 with their number, stars and padlock painted out.
    t = paint_out(m, rects=[(275, 462, 370, 578), (195, 578, 452, 657)], radius=6)
    save("level-tile.png", cut(t, 127, 438, 518, 682, corner=34))
    t = paint_out(m, rects=[(275, 1285, 375, 1392), (280, 1392, 372, 1480)], radius=6)
    save("level-tile-locked.png", cut(t, 127, 1260, 518, 1508, corner=34))


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    main_menu()
    station_map()
    level_select()
