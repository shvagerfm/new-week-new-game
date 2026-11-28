class_name Loc
extends RefCounted
## Ukrainian and English strings. Loc.t("key") in the current language.

static var lang := "uk"

const S := {
	"title": ["Прикрась ялинку", "Deck the Tree"],
	"play": ["Грати", "Play"],
	"levels": ["Рівні", "Levels"],
	"level_n": ["Рівень %d", "Level %d"],
	"boss": ["БОС", "BOSS"],
	"tier": ["Ярус %d/%d", "Tier %d/%d"],
	"world_1": ["Лісова ялинка", "Forest Tree"],
	"world_2": ["Пряникове містечко", "Gingerbread Town"],
	"world_3": ["Крижане озеро", "Frozen Lake"],
	"world_4": ["Майстерня Санти", "Santa's Workshop"],
	"world_5": ["Новорічна площа", "New Year Square"],
	"boss_1": ["Сова-вартова", "The Watch Owl"],
	"boss_2": ["Пряниковий велетень", "The Gingerbread Giant"],
	"boss_3": ["Крижана зірка", "The Ice Star"],
	"boss_4": ["Заводна зірка", "The Clockwork Star"],
	"boss_5": ["Північна зірка", "The North Star"],
	"win": ["Ялинку прикрашено!", "Tree decorated!"],
	"fail": ["Ой! Прикраси зіткнулись", "Oops! Ornaments clashed"],
	"fail_ice": ["Ой! Прикраса розбилась об лід", "Oops! It shattered on the ice"],
	"fail_stars": ["Зібрано не всі зірки", "Not all stars collected"],
	"continue_ad": ["Продовжити ▶", "Continue ▶"],
	"retry": ["Ще раз", "Retry"],
	"next": ["Далі", "Next"],
	"menu": ["Меню", "Menu"],
	"resume": ["Продовжити", "Resume"],
	"paused": ["Пауза", "Paused"],
	"time": ["Час %.1f с", "Time %.1fs"],
	"best": ["Рекорд %.1f с", "Best %.1fs"],
	"reward": ["Нагорода:", "Reward:"],
	"double_ad": ["×2 ▶", "×2 ▶"],
	"no_ad": ["Реклама недоступна", "No ad available"],
	"perfect": ["Ідеально!", "Perfect!"],
	"tap_to_throw": ["Торкнись, щоб кинути", "Tap to throw"],
	"slow": ["Повільно", "Slow"],
	"shield": ["Щит", "Shield"],
	"aim": ["Приціл", "Aim"],
	"magnet": ["Магніт", "Magnet"],
	"fire": ["Вогонь", "Fire"],
	"tip_slow": ["Ярус крутиться повільніше 5 с", "Tier spins slower for 5 s"],
	"tip_shield": ["Одне зіткнення прощається", "One clash is forgiven"],
	"tip_aim": ["Показує, чи влучиш, 8 с", "Shows if a throw is safe, 8 s"],
	"tip_magnet": ["Знімає 3 прикраси знизу", "Removes 3 ornaments at the bottom"],
	"tip_fire": ["Наступна прикраса збиває все на шляху", "Next ornament knocks anything aside"],
	"intro_candies": ["Збери всі цукерки — друга зірочка", "Hit every candy for the second star"],
	"intro_ice": ["Не влучай у лід!", "Don't hit the ice!"],
	"intro_stars": ["Влуч у всі золоті зірки", "Hit every golden star"],
	"intro_move": ["Ярус гойдається", "The tier sways"],
	"intro_pulse": ["Ярус дихає", "The tier breathes"],
	"lang": ["EN", "УКР"],
	"sound_on": ["Звук ✓", "Sound ✓"],
	"sound_off": ["Звук ✗", "Sound ✗"],
	"candy": ["Цукерка!", "Candy!"],
	"phase": ["Нова фаза!", "New phase!"],
}


static func t(key: String) -> String:
	if not S.has(key):
		return key
	return S[key][0 if lang == "uk" else 1]
