# Progress

## Current state (end of session 1)
M0 done. M1 ("The Slice") is playable but not finished: the art direction changed mid-milestone (owner's realism override + many feature notes), so the slice was rebuilt around a city district.

### Built and verified
- Toolchain: Godot 4.7.2, GUT 9.7.1 (28 tests passing: BigNum, economy, saves/migration, field generation, compartment rules), Poly Haven CC0 asset pipeline (`tools/fetch_assets.py`), Blender 4.0 available in the container (`apt-get install blender`) for future modeling.
- World: city district (`planet/city_layout.gd`, `planet/city_view.gd`): 36 m blocks, roads with faded lane paint, curbs and sidewalks, modular-facade buildings near the play area, proxy buildings and towers beyond. Hub block: small swept yard with a lean-to shack + workbench and a scrap skip on a weigh scale.
- Hexes: 10 m radius (260 m²), 37 in the slice, junk hexes ~260-420 collectible real-model pieces each (landfill lots ×2.2, piled heaps), plus a dense layered litter carpet (~30/m²) that Patch's scoop sweeps through and that thins/vanishes as the hex is cleaned.
- Ground: PBR Texture2DArray shader; cleaning reveals cracked asphalt with lane paint, sidewalk concrete, or dry dirt.
- Patch: "Drum" design chosen from a 3-way design competition (turnarounds in `screenshots/turn_drum_*.png`): upright rusted drum on 2 drive wheels + caster, offset sensor head with 8-blade iris, clamshell arms, lid ram, rear bale hatch.
- Loop: scoop individual items → hopper fill gauge with Perfect band → hydraulic baling (ram, hatch, strapped bale ejects) → carry/stack bales → scale + skip cashes them. Upgrades only at the hub workbench. Part detector: beeps faster and blinks red near buried parts, rarity readout within 4 m, dig to recover parts into storage.
- UI: thin industrial HUD (cubes, district/planet %, hopper gauge, detector readout, message log); upgrade cards restyled by the shared theme.
- Lighting: physical sky, AgX, high sun, quality presets Low..Ultra (Low drops GI/volumetrics/SSR).

### Measured
- Autoplay (headless, `--autoplay --time-scale=4`): first bale 4.9 s, first cash-in 8.3 s, first upgrade 17 s; 67 bales in ~13 game-minutes; **0 hexes cleaned** in that time (hexes are now big and need 99%).
- Rendering in the cloud container uses software Vulkan: ~0.25 fps at 960×540 Low, 11 M primitives, ~2.7k draw calls. Real-GPU frame times not measured yet.

### Known issues / next steps (in priority order)
1. **Pacing**: first hex flip far too slow with 10 m hexes. Options: lower clean threshold to 95%, fewer collectible pieces in ring-1 hexes, faster early scoop. Retune with autoplay.
2. Litter colors read a bit pastel/confetti-like; add printed-paper/label textures and more cardboard/plastic film variety; more collectible variety (crumpled paper, cups, styrofoam as pickups).
3. Lens view (first-person) polish and diegetic HUD; touch overlay.
4. Tutorial (WREN intro, workbench lesson) replaces on-screen hints.
5. Performance: litter carpet + junk are heavy for software rendering; profile on a real GPU, add distance-based density for litter.
6. Then M2 (planet sphere, 40,962+ hexes, many cities, lakes) and M3 (robots: build from parts, fleet upgrade tracks, rusty → futuristic tiers, tractor-beam pickup).
