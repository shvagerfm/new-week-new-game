class_name Campaign
extends RefCounted
## Loads the zones in res://levels/. Each zone is a folder (played in name
## order) with a zone.cfg and one .txt map per level (also in name order).

const LEVEL_DIR := "res://levels"


## Returns [{id, name, story, booster, color, levels: [{id, path, rules}]}].
static func load_zones() -> Array[Dictionary]:
	var zones: Array[Dictionary] = []
	var dirs := Array(DirAccess.get_directories_at(LEVEL_DIR))
	dirs.sort()
	for dir: String in dirs:
		var path := LEVEL_DIR.path_join(dir)
		var cfg := ConfigFile.new()
		cfg.load(path.path_join("zone.cfg"))
		var zone := {
			"id": dir,
			"name": cfg.get_value("zone", "name", dir),
			"story": cfg.get_value("zone", "story", ""),
			"booster": cfg.get_value("zone", "booster", ""),
			"color": Color(cfg.get_value("zone", "color", "ffb347")),
			"levels": [],
		}
		var files := Array(DirAccess.get_files_at(path)).filter(
				func(f: String) -> bool: return f.get_extension() == "txt")
		files.sort()
		for f: String in files:
			var file_path := path.path_join(f)
			var text := FileAccess.get_file_as_string(file_path).replace("\r", "")
			var rules := Rules.parse(text.split("\n"), f.get_basename().substr(3).replace("-", " ").capitalize())
			if rules.error != "":
				push_warning("Skipping %s: %s" % [file_path, rules.error])
				continue
			zone.levels.append({"id": dir + "/" + f.get_basename(), "path": file_path, "rules": rules})
		if not zone.levels.is_empty():
			zones.append(zone)
	return zones
