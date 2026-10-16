## Player's settings (screen «Настройки»). Kept in their own file, apart from the progress,
## so «Сбросить прогресс» does not touch them.
extends RefCounted

var show_names_in_battle := true  ## names under the fighters on the battlefield


## Unknown or missing keys keep their defaults (a settings file from an older version).
static func from_dict(values: Dictionary) -> RefCounted:
	var settings = new()
	if values.get("show_names_in_battle") is bool:
		settings.show_names_in_battle = values["show_names_in_battle"]
	return settings


func to_dict() -> Dictionary:
	return {"show_names_in_battle": show_names_in_battle}
