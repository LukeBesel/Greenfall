# Snippet cut from SaveManager.migrate_v2 (autoload/SaveManager.gd) in task M3-13: the v1 -> v2
# step also rewrote the Requests board's state. Put it back in migrate_v2, before
# flags["money_migrated"] = true, when the board returns. Parked saves keep flags.contracts as it was.
	# Contracts are Requests now: the "Handle world events" contract is gone (events count directly).
	var cs: Variant = flags.get("contracts")
	if cs is Dictionary and (cs as Dictionary).get("slots") is Array:
		var slots: Array = cs["slots"]
		for i: int in slots.size():
			if slots[i] is Dictionary and str((slots[i] as Dictionary).get("tpl", "")) == "events":
				slots[i] = {"state": "wait", "wait": 30.0}
