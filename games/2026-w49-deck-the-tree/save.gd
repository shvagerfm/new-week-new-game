class_name Save
extends RefCounted
## Progress on disk: unlocked levels, stars, best times, boosters, settings.

const PATH := "user://deck_the_tree.cfg"
const BOOSTERS := ["slow", "shield", "aim", "magnet", "fire"]

var unlocked := 1  # levels open (1 = only the first)
var stars := {}  # level index -> 0..3
var best := {}  # level index -> seconds
var boosters := {}
var muted := false
var lang := ""


func _init() -> void:
	for b in BOOSTERS:
		boosters[b] = 1


func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	unlocked = cfg.get_value("progress", "unlocked", 1)
	stars = cfg.get_value("progress", "stars", {})
	best = cfg.get_value("progress", "best", {})
	var b: Dictionary = cfg.get_value("progress", "boosters", {})
	for k in BOOSTERS:
		boosters[k] = b.get(k, boosters[k])
	muted = cfg.get_value("settings", "muted", false)
	lang = cfg.get_value("settings", "lang", "")


func save_file() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "stars", stars)
	cfg.set_value("progress", "best", best)
	cfg.set_value("progress", "boosters", boosters)
	cfg.set_value("settings", "muted", muted)
	cfg.set_value("settings", "lang", lang)
	cfg.save(PATH)


func total_stars() -> int:
	var s := 0
	for k in stars:
		s += stars[k]
	return s
