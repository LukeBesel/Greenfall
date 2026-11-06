# How to play-test Greenfall

There are two ways to play. Option A is quickest if you just want to play. Option B lets you see the latest changes right away.

## Option A: download a ready-made build (no install)

Every push to this branch builds the game automatically on GitHub.

1. Open the repository on GitHub, then the **Actions** tab, then the latest **Build game** run.
2. Scroll to **Artifacts** and download the one for your computer:
   - **Greenfall-Windows**: unzip it, then double-click `Greenfall.exe`. If Windows SmartScreen appears, click "More info", then "Run anyway". The build isn't code-signed.
   - **Greenfall-macOS**: unzip it to get `Greenfall.app`. The first time, right-click it and choose **Open**, then **Open** again. It isn't notarized, so macOS asks once.
   - **Greenfall-Linux**: unzip it, then run `chmod +x Greenfall.x86_64 && ./Greenfall.x86_64`.
3. Keep the `.pck` file next to the program. The game data lives in it.

## Option B: run the project in the Godot editor

1. Install **Godot 4.7.2** (standard build, not .NET) from https://godotengine.org/download/archive/4.7.2-stable/ . It's a single program; unzip it and run it.
2. Get the code:
   ```bash
   git clone https://github.com/LukeBesel/Greenfall.git
   ```
   ```bash
   cd Greenfall && git checkout claude/kind-wright-rhxixd
   ```
3. Open Godot, click **Import**, pick `Greenfall/project.godot`. The first import takes a few minutes because all the textures get processed.
4. Press **F5** (or the ▶ button, top right) to play.

## Controls

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move | WASD | Left stick |
| Look | Mouse | Right stick |
| Scoop junk (tractor beam) | Hold Left mouse / Space | Right trigger |
| Press a bale | Right mouse / C | X |
| Pick up / interact | E | A |
| Drop | Q | B |
| Tools: scoop / plant / water | 1 / 2 / 3 | D-pad |
| Upgrades (at the workbench) | Tab or U | Y |
| Command robots | B | D-pad down |
| Survey hologram (planet map) | M | Back / Select |
| Lens view | V | Right stick click |
| Pause / settings | Esc | Start |

## Good things to try in a first session

- Watch the intro (Space skips it). Clean your first hex, press a bale, and sell it on the scale.
- Buy an upgrade at the workbench in the shack.
- Build a Scoopie and a Haul Bug (Bots tab), then press **B**. Pick the cleaners and drag over hexes to send them there.
- Press **M** to see the planet hologram in Aurora's hand.
- Follow the greenhouse signal to plant the first seed.
- Settings (Esc, then Settings) covers volume, quality, fullscreen, mouse sensitivity and more.

## Saves

The game autosaves every minute and when you quit. On the title screen, **Continue** loads it and **New Game** starts over (it asks first).
Saves live in Godot's user folder:
- Windows: `%APPDATA%\Godot\app_userdata\Greenfall`
- macOS: `~/Library/Application Support/Godot/app_userdata/Greenfall`
- Linux: `~/.local/share/godot/app_userdata/Greenfall`

## Reporting issues

Note what you were doing and take a screenshot. Then tell Claude, or add it to `docs/ROADMAP.md`.
