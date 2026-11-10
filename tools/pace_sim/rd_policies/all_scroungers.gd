extends PaceSimRdPolicy
## A player who tries to exploit the chain: the Assembler builds nothing but Scroungers. The loop
## must not run away (buried parts run out, trips take time, the crew cap holds).


func _init() -> void:
	scrounger_share = 1.0
