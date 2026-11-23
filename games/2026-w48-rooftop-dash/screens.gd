class_name Screens
extends Node2D
## The title and game-over screens, drawn over the city that keeps running
## behind them. main.gd owns the state; this draws it and says which button
## a tap landed on.

## Dima's logo goes here (transparent, about 800x300). Until it exists, the
## title is set in the pixel font instead.
const LOGO_PATH := "res://sprites/rooftop-dash-logo.png"
const LOGO_BOX := Vector2(800, 300)
const FONT: FontFile = preload("res://fonts/Jersey10.ttf")  # OFL, see fonts/OFL.txt

const INK := Color("0a0c1c")
const PANEL := Color("141a3e")
const PANEL_EDGE := Color("3d56a8")
const SOFT := Color("aab4e8")
const BTN := Color("ff8a3d")
const BTN_HI := Color("ffb478")
const BTN_LO := Color("c85a1c")
const BTN2 := Color("2a3570")
const BTN2_HI := Color("4a5ca8")
const BTN2_LO := Color("1a2250")

const WHY := {"fall": "Fell between the roofs", "wall": "Ran into a wall",
	"ac": "Tripped on an air conditioner", "antenna": "Hit an antenna",
	"wire": "Caught in a wire"}

var main: Node
var bold: FontVariation
var logo: Texture2D
var _buttons := {}   # name -> Rect2 on screen, refreshed every draw


func _ready() -> void:
	bold = FontVariation.new()
	bold.base_font = FONT
	bold.spacing_glyph = 2
	if ResourceLoader.exists(LOGO_PATH):
		logo = load(LOGO_PATH)
		# A big painted logo is scaled down, so smooth it; pixel art stays sharp.
		if logo.get_width() > LOGO_BOX.x * 0.6:
			texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


## The name of the button under pos ("play", "again", "menu"), or "".
func button_at(pos: Vector2) -> String:
	for k in _buttons:
		if (_buttons[k] as Rect2).grow(8).has_point(pos):
			return k
	return ""


func _process(_delta: float) -> void:
	# The results panel fades and slides in once taps can restart.
	var k := 1.0
	if main.state == main.State.OVER:
		k = clampf((main.over_t - main.RESTART_DELAY) / 0.25, 0.0, 1.0)
	modulate.a = 1.0 - pow(1.0 - k, 3.0)
	queue_redraw()


func _draw() -> void:
	_buttons.clear()
	if main._portrait():
		return
	var vp := get_viewport_rect().size
	match main.state:
		main.State.TITLE:
			_draw_title(vp)
		main.State.OVER:
			var k: float = clampf((main.over_t - main.RESTART_DELAY) / 0.25, 0.0, 1.0)
			if k > 0.0:
				_draw_over(vp, k)


# --- Title -----------------------------------------------------------------

func _draw_title(vp: Vector2) -> void:
	var cx := vp.x * 0.5
	var box := Rect2(cx - LOGO_BOX.x * 0.5, 30, LOGO_BOX.x, LOGO_BOX.y)
	if logo:
		var s := minf(box.size.x / logo.get_width(), box.size.y / logo.get_height())
		var size := Vector2(logo.get_width(), logo.get_height()) * s
		draw_texture_rect(logo, Rect2(box.get_center() - size * 0.5, size), false)
	else:
		_text(Vector2(cx, box.position.y + 140), "ROOFTOP", 128, Art.ORANGE, 20, 8)
		_text(Vector2(cx, box.position.y + 268), "DASH", 128, Art.GOLD, 20, 8)

	var bob := roundf(sin(main.time * 3.0) * 2.0) * 2.0
	_button("play", Rect2(cx - 170, 362 + bob, 340, 96), "PLAY", 56, true)

	var y := 530.0
	# A dark band behind the small print, so it reads over the lit facades.
	var lines := 2 if main.best_score <= 0 else 3
	_band(y - 46, 48.0 * lines + 30)
	if main.best_score > 0:
		_text(Vector2(cx, y), "BEST  %d   ·   %d m" % [main.best_score, int(main.best_m)], 40, Art.GOLD, 10)
		y += 56
	_text(Vector2(cx, y), "Tap, click or Space to jump. Hold it to jump higher.", 32, Art.TEXT, 8)
	_text(Vector2(cx, y + 40), "Land right on a roof's edge to grow the multiplier.", 32, SOFT, 8)


# --- Game over -------------------------------------------------------------

func _draw_over(vp: Vector2, k: float) -> void:
	var w: World = main.world
	var ease := 1.0 - pow(1.0 - k, 3.0)
	var size := Vector2(640, 500)
	var r := Rect2(vp * 0.5 - size * 0.5 + Vector2(0, (1.0 - ease) * 40.0 - 10.0), size)
	r.position = r.position.round()
	_panel(r)
	var cx := r.get_center().x
	var y := r.position.y

	_text(Vector2(cx, y + 64), WHY.get(w.death, "Run over").to_upper(), 40, Art.ORANGE, 8)
	_text(Vector2(cx, y + 172), str(main.final_score), 112, Art.TEXT, 14)
	if main.new_best:
		var on := fmod(main.time, 0.8) < 0.55
		_text(Vector2(cx, y + 226), "NEW BEST!", 40, Art.GOLD if on else Art.ORANGE, 10)
	else:
		_text(Vector2(cx, y + 226), "BEST  %d" % main.best_score, 36, SOFT, 8)

	draw_rect(Rect2(r.position.x + 40, y + 256, r.size.x - 80, 4), PANEL_EDGE)
	var stats := [["%d m" % int(main.final_m), "distance"], [str(w.parcels_taken), "parcels"],
		["x%d" % w.best_mult, "best combo"]]
	for i in stats.size():
		var sx := r.position.x + r.size.x * (i + 0.5) / stats.size()
		_text(Vector2(sx, y + 314), stats[i][0], 44, Art.TEXT, 10)
		_text(Vector2(sx, y + 348), stats[i][1], 28, SOFT, 6)

	_button("again", Rect2(r.position.x + 40, y + 384, 360, 84), "RUN AGAIN", 44, true)
	_button("menu", Rect2(r.position.x + 420, y + 384, 180, 84), "MENU", 40, false)
	_band(r.end.y + 20, 48)
	_text(Vector2(cx, r.end.y + 52), "Tap or Space to run again   ·   Esc for the menu", 30, SOFT, 6)


# --- Pieces ----------------------------------------------------------------

## Text centred on x with its baseline at y, with a dark outline and an
## optional drop shadow.
func _text(at: Vector2, s: String, size: int, col: Color, outline := 8, shadow := 0) -> void:
	var tw := bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := Vector2(roundf(at.x - tw * 0.5), roundf(at.y))
	if shadow > 0:
		draw_string_outline(bold, p + Vector2(shadow, shadow), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, INK)
		draw_string(bold, p + Vector2(shadow, shadow), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, INK)
	draw_string_outline(bold, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, INK)
	draw_string(bold, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _band(y: float, h: float) -> void:
	draw_rect(Rect2(0, y, get_viewport_rect().size.x, h), Color(INK, 0.6))


## A dark panel with a pixel border and an orange bar on top.
func _panel(r: Rect2) -> void:
	draw_rect(Rect2(r.position + Vector2(10, 10), r.size), Color(0, 0, 0, 0.35))
	draw_rect(r.grow(4), INK)
	draw_rect(r, Color(PANEL, 0.96))
	draw_rect(r, PANEL_EDGE, false, 4.0)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 10)), Art.ORANGE)
	draw_rect(Rect2(r.position + Vector2(0, 10), Vector2(r.size.x, 4)), BTN_LO)


## A chunky pixel button: outline, face, light top edge and dark lip below.
func _button(id: String, r: Rect2, label: String, size: int, primary: bool) -> void:
	_buttons[id] = r
	var face := BTN if primary else BTN2
	var hi := BTN_HI if primary else BTN2_HI
	var lo := BTN_LO if primary else BTN2_LO
	draw_rect(r.grow(4), INK)
	draw_rect(r, lo)
	draw_rect(Rect2(r.position, r.size - Vector2(0, 10)), face)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 6)), hi)
	draw_rect(Rect2(r.position, Vector2(6, r.size.y - 10)), hi)
	# Capitals are about 0.7 of the size tall, so this centres them on the face.
	_text(Vector2(r.get_center().x, r.position.y + (r.size.y - 10) * 0.5 + size * 0.35), label, size, Art.TEXT, 10)
