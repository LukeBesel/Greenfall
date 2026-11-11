class_name TownSite
extends Node3D
## A hub site that is a town on a street grid: what shared systems may read from any planet's
## town without knowing which planet built it. A planet's own site script extends this and fills
## the fields in; shared code (the garden's paving check, street power, the outpost street snap)
## asks `is TownSite` and never names the planet's class.
##
## Everything is in site-local metres (+Y up, y = 0 on the pad, x east, z south).

## The town's street grid, or null until it is laid out.
var layout: CityLayout
## How far the town reaches from the site centre on its pad (m).
var town_r: float = 0.0
## The regrowth stage (0-5) of the district this town stands in (systems/districts.gd), 0 on open
## ground. A planet's site script overrides set_district_stage to change the town with it.
var district_stage: int = 0
## The state of the town's pollution source: "broken" while it runs, "shut_down" once the
## player has stopped it. A planet's site script overrides set_source_state to change its landmark.
var source_state: String = "broken"


func set_district_stage(stage: int) -> void:
	district_stage = clampi(stage, 0, Districts.MAX_STAGE)


func set_source_state(state: String) -> void:
	source_state = state
