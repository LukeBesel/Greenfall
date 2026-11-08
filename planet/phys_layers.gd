class_name PhysLayers
extends RefCounted
## [world2] Physics layer bits used across the game (one place to read them).
##   WORLD  ground, sidewalks, buildings, base stations (the camera spring arm hits these)
##   PATCH  Lumi
##   CUBE   bales
##   ROBOT  robots
##   PROP   street furniture, yard kit, fences, landmarks, decor: solid for Lumi, robots and bales,
##          but not for the camera arm (thin poles would yank the camera in)
##   MOUND  junk-pile mounds: only bales rest on them (Lumi hovers through, as before)

const WORLD: int = 1
const PATCH: int = 2
const CUBE: int = 4
const ROBOT: int = 8
const PROP: int = 32
const MOUND: int = 64

## What Lumi, robots and bales bump into besides the ground.
const SOLID: int = WORLD | PROP
