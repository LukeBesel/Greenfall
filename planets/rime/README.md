# Rime (`rime`)

An ice moon, core-mined until it froze.

Not shipped (`shipped = false` in `planet.tres`): the game never offers this planet. It stays
registered so tests and the dev flag `--orbit-planet=rime` can load it by id.

- `planet.tres`: the PlanetDefinition (campaign order 3, globe frequency 205, 16 hubs).
- `data/look.json`: sky, fog, sun, ambient, palette, junk tint, map globe and orbit (was this
  planet's entry in the old `data/planets.json`, `ui/planet_globe.gd` and `data/solar_system.json`).
- `data/sites.json`: its hub and landmark sites, built by `rime_site.gd` (the definition's `sites_script`).
- `env.gd`: the environment script (the definition's `env_script`).
- The other files are this planet's own props, shaders and data, used only by the scripts above.

**Inherits Planet 1's tables until its own are written.** The required tables (`pollution`,
`upgrades`, `regrowth`, `tutorial`, `goals`) point at the files in `planets/verdance/data/` so the
definition validates and loads. Before this planet ships it needs its own copies: see
`docs/PLANET_PLAYBOOK.md`.
