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
