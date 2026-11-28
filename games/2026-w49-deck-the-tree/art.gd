class_name Art
extends RefCounted
## Optional PNG art. The game draws placeholder shapes; when a file named in
## art/PROMPTS.md is dropped into art/ (e.g. art/elf.png), it is used instead.

static var _cache := {}


static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var path := "res://art/%s.png" % name
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[name] = t
	return t
