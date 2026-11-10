extends PaceSimRdPolicy
## A player who never lets the Assembler build a Scrounger: only the one Lumi built by hand
## carries parts, with what Lumi's own hands find. The crew must still grow, slowly.


func _init() -> void:
	scrounger_share = 0.0
