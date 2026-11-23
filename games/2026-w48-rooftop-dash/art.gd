class_name Art
extends RefCounted
## The palette and the pixel sprites, drawn as 4 px squares straight from the
## strings below. One character is one pixel; "." is see-through.

const P := 4.0

const PAL := {
	"k": Color("0a0c1c"),  # outline
	"c": Color("ff8a3d"),  # cap
	"s": Color("f4c49c"),  # skin
	"j": Color("4a78ff"),  # jacket
	"J": Color("2f52c8"),  # jacket shade
	"p": Color("232a55"),  # trousers
	"w": Color("e8ecff"),  # shoes
	"b": Color("b8733a"),  # parcel on the back
	"o": Color("ffd27a"),  # tape and strap
	"r": Color("ff4d5e"),
	"v": Color("4b3368"),  # bat body
	"V": Color("8a66b8"),  # bat wing
}

const SKY := [Color("0a0d22"), Color("0f1534"), Color("151d47"), Color("1d2459"),
	Color("2a2a66"), Color("40306c"), Color("5c3768")]
const FAR := Color("2c2b66")
const MID := Color("232460")
const NEAR := Color("1b1d52")
const BODY := [Color("080b1f"), Color("0a0d24"), Color("070a1b")]
const FACE := Color("17204d")
const LIP := Color("3d56a8")
const LIP_HI := Color("8aa6ff")
const WINDOW_ON := [Color("ffb347"), Color("ff8a3d"), Color("ffd27a")]
const WINDOW_OFF := Color("161c3e")
const ORANGE := Color("ff8a3d")
const GOLD := Color("ffd27a")
const STEEL := Color("8796c8")
const STEEL_DARK := Color("4b5788")
const WIRE := Color("c9d4ff")
const BRICK := Color("6e4a5a")
const TEXT := Color("eef0ff")

## Rows 0-9: head and body. Two variants: arm swinging forward, arm down.
const TOP_ARM := [
	"....kkkkk...",
	"...kccccck..",
	"...kcccccckk",
	"...kkssssk..",
	".bbkssskssk.",
	"bbbksssssk..",
	"bobkkjjjkk..",
	"bbbkjjjJjk..",
	"bbbkjjjjjsk.",
	".bbkjjjJk...",
]
const TOP := [
	"....kkkkk...",
	"...kccccck..",
	"...kcccccckk",
	"...kkssssk..",
	".bbkssskssk.",
	"bbbksssssk..",
	"bobkkjjjkk..",
	"bbbkjjsjjk..",
	"bbbkjjsjjk..",
	".bbkjjjJk...",
]
## Rows 10-15: legs.
const LEGS := {
	"run_a": [
		"..kpppppk...",
		".kppkkppk...",
		"kppk..kppk..",
		"kpk....kppk.",
		"kwk.....kwwk",
		"kk.......kkk",
	],
	"run_b": [
		"..kpppppk...",
		"..kppppk....",
		"...kppk.....",
		"...kpppk....",
		"...kwwwk....",
		"...kkkkk....",
	],
	"run_c": [
		"..kpppppk...",
		"..kppkppk...",
		"..kpk.kppk..",
		".kppk..kpk..",
		".kwwk..kwk..",
		".kkk...kkk..",
	],
	"run_d": [
		"..kpppppk...",
		"..kpppppkk..",
		"..kppkkppk..",
		"..kpk..kk...",
		"..kwk.......",
		"..kkk.......",
	],
	"jump": [
		"..kpppppk...",
		".kppppppk...",
		"kppkkkppk...",
		"kwk..kppk...",
		"kk...kwwk...",
		".....kkk....",
	],
	"fall": [
		"..kpppppk...",
		"..kppkppk...",
		".kppk.kppk..",
		".kpk...kpk..",
		".kwk...kwk..",
		".kkk...kkk..",
	],
}

## Placeholder bat, two wing frames, 12x8 pixels.
const BAT := [
	[
		"V..........V",
		"VV........VV",
		"VVV.v..v.VVV",
		".VVvvvvvvVV.",
		"..vvrvvrvv..",
		"...vvvvvv...",
		"....v..v....",
		"............",
	],
	[
		"............",
		"....v..v....",
		"...vvvvvv...",
		"..vvrvvrvv..",
		".VVvvvvvvVV.",
		"VVV.vvvv.VVV",
		"VV........VV",
		"V..........V",
	],
]

const PARCEL := [
	"kkkkkk",
	"kbobbk",
	"kooook",
	"kbobbk",
	"kkkkkk",
]


## The courier's frame: legs name plus whether the arm swings forward.
## Run frames bob up a pixel on the passing steps.
static func courier(legs: String, arm := false) -> Array:
	var rows: Array = (TOP_ARM if arm else TOP).duplicate()
	rows.append_array(LEGS[legs])
	return rows


## Draws rows of pixel characters with the top-left corner at pos.
static func sprite(ci: CanvasItem, rows: Array, pos: Vector2, scale := P, tint := Color.WHITE) -> void:
	for ry in rows.size():
		var row: String = rows[ry]
		for rx in row.length():
			var ch := row[rx]
			if ch == "." or not PAL.has(ch):
				continue
			ci.draw_rect(Rect2(pos.x + rx * scale, pos.y + ry * scale, scale, scale), PAL[ch] * tint)


## A whole number from a few ints, the same every time (for buildings,
## windows and stars that must not flicker).
static func hash3(a: int, b := 0, c := 0) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))
