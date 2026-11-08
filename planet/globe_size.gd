class_name GlobeSize
extends RefCounted
## [orbE] How big each planet's walkable globe is, for maps and the sky (owner, Nov 8: planets
## differ in size). A thin view over orbB's GlobeSpec (data/planets.json `<id>.globe`): the grid
## frequency is the truth (10 m hexes, 10·f²+2 cells, radius linear in f; Verdance f = 128,
## R 1,840 m). Nothing here assumes Verdance's size.

const VERDANCE_R: float = 1840.0
## Every campaign planet (maps size each globe by its scale).
const IDS: Array[String] = ["verdance", "ochre", "tidewell", "rime", "anvil"]


## Radius relative to Verdance's globe.
static func scale_of(id: String) -> float:
	return float(GlobeSpec.of(id.to_lower())["frequency"]) / float(GlobeSpec.VERDANCE_FREQ)


static func radius_m(id: String) -> float:
	return VERDANCE_R * scale_of(id)


static func cells_of(id: String) -> int:
	return GlobeSpec.cells_for(int(GlobeSpec.of(id.to_lower())["frequency"]))
