class_name MenuArt
extends RefCounted
## Art for the main menu, station map and level select (see art/menu/).
## A drawn piece in res://art/menu/<name>.png wins. Until it exists, the game
## uses the placeholder cut from the mockups (res://art/menu/placeholder/,
## made by art/menu/make_placeholders.py), or nothing for layers that the
## placeholder backgrounds already have baked in (logo, Kip, title plate).

const DIR := "res://art/menu/"
const FONT := preload("res://art/fonts/Fredoka.ttf")

static var _cache := {}
static var _font: Font


## True when the drawn piece exists (not just a placeholder).
static func drawn(name: String) -> bool:
	return ResourceLoader.exists(DIR + name + ".png")


## The drawn piece, else its placeholder, else null.
static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var t: Texture2D = null
	for p in [DIR + name + ".png", DIR + "placeholder/" + name + ".png"]:
		if ResourceLoader.exists(p):
			t = load(p)
			break
	_cache[name] = t
	return t


## Fredoka Bold, the rounded font of the mockups.
static func font() -> Font:
	if _font == null:
		var f := FontVariation.new()
		f.base_font = FONT
		var ts := TextServerManager.get_primary_interface()
		f.variation_opentype = {ts.name_to_tag("wght"): 700}
		_font = f
	return _font
