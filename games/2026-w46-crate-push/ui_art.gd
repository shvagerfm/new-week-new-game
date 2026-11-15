class_name UiArt
extends RefCounted
## Regions of the UI sheet (art/source/ui/crate-push-ui-assets.png).
## Some pieces cross the 256 px grid, so these are the measured bounds of
## each piece, not grid cells. Mirrors art/source/ui/atlas.json.

const SHEET := preload("res://art/source/ui/crate-push-ui-assets.png")

## name -> Rect2(x, y, w, h)
const MAP := {
	"logo": Rect2(23, 47, 246, 213),
	"primary-normal": Rect2(293, 105, 237, 117),
	"primary-pressed": Rect2(552, 105, 227, 117),
	"secondary": Rect2(802, 107, 229, 114),
	"round-button": Rect2(1055, 62, 192, 198),
	"level-unlocked": Rect2(1304, 59, 201, 195),
	"level-locked": Rect2(49, 315, 207, 199),
	"level-current": Rect2(311, 313, 210, 201),
	"star-filled": Rect2(572, 334, 170, 160),
	"star-empty": Rect2(794, 332, 175, 165),
	"padlock": Rect2(1029, 322, 150, 177),
	"panel-frame": Rect2(1228, 313, 285, 197),
	"zone-warehouse": Rect2(34, 571, 237, 172),
	"zone-cold-storage": Rect2(328, 555, 178, 197),
	"zone-boiler-room": Rect2(566, 555, 170, 201),
	"zone-security": Rect2(785, 590, 211, 142),
	"zone-maintenance": Rect2(1040, 552, 196, 199),
	"zone-lab": Rect2(1302, 560, 179, 191),
	"zone-core": Rect2(64, 784, 180, 216),
	"back": Rect2(305, 820, 184, 153),
	"settings": Rect2(535, 793, 207, 201),
	"sound-on": Rect2(785, 815, 203, 168),
	"sound-off": Rect2(1042, 805, 183, 181),
}

## Zone folder name (without the number) -> icon.
const ZONE_ICONS := {
	"warehouse": "zone-warehouse", "cold-storage": "zone-cold-storage",
	"boiler-room": "zone-boiler-room", "security": "zone-security",
	"maintenance": "zone-maintenance", "lab": "zone-lab", "core": "zone-core",
}


static func tex(name: String) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = SHEET
	t.region = MAP[name]
	return t


## A stretchable box from one piece. margin keeps the corners from stretching.
static func box(name: String, margin: Vector4, content := Vector4.ZERO, mod := Color.WHITE) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex(name)
	s.texture_margin_left = margin.x
	s.texture_margin_top = margin.y
	s.texture_margin_right = margin.z
	s.texture_margin_bottom = margin.w
	s.content_margin_left = content.x
	s.content_margin_top = content.y
	s.content_margin_right = content.z
	s.content_margin_bottom = content.w
	s.modulate_color = mod
	return s


## Icon for a zone id such as "3-boiler-room".
static func zone_icon(zone_id: String) -> String:
	var key := zone_id.substr(zone_id.find("-") + 1)
	return ZONE_ICONS.get(key, "zone-warehouse")
