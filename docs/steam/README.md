# Greenfall on Steam: owner checklist

Everything that can be done without your Steam account is already in the repo. This page lists
what is left for you, in order, and where each piece lives.

## What is already done

| Piece | Where |
|---|---|
| Steam wrapper that runs fine without Steam (no extension, Steam closed, headless, CI) | `steam/steam_service.gd` (autoload `SteamService`) |
| Achievements mirrored to Steam (set + store), 14 lifetime stats | `data/achievements.json`, `data/steam.json` |
| Steamworks lists to type in | `docs/steam/achievements.csv`, `docs/steam/stats.csv` (regenerate: `python3 tools/steam/export_steam_csv.py`) |
| Achievement icons, 256x256, unlocked and locked | `/home/user/Greenfall/screenshots/steam/achievement_icons/` (regenerate: `tools/steam/capsules.tscn -- --icons`) |
| Steam Cloud through Remote Storage, newest save wins | `steam/steam_cloud.gd`, hooks in `autoload/SaveManager.gd` |
| Demo build (first district, base level 2 cap, no rockets, end screen with Wishlist) | `steam/demo.gd`, `steam/demo_end_screen.gd`, export presets `* Demo` |
| CI builds of the full game and the demo for Windows, Linux, macOS | `.github/workflows/build.yml` |
| Store capsules, library art, screenshots | `/home/user/Greenfall/screenshots/steam/` (not in git); recipes in `docs/steam/TRAILER.md` |

## 1. Steamworks account and app ids

1. Sign up at https://partner.steamgames.com, accept the distribution agreement, fill in the tax and bank
   forms, and pay the **Steam Direct fee (US$100 per app)**. It is paid back once the game has made US$1,000.
2. Create the app. Steam gives you an **App ID** (for example 2345670). A **demo** is a separate app attached
   to the main one: in Steamworks open the main app, then *All Associated Packages, DLC, Demos and Tools* >
   *Request a demo app*. It gets its own App ID (no extra fee).
3. Put both ids in `project.godot`. Until then they are 480, Valve's "Spacewar" test app:

   ```ini
   [greenfall]
   steam/app_id=2345670        ; full game: Steam init, and the demo's "Wishlist" store page
   steam/demo_app_id=2345680   ; the demo build initialises with this one
   steam/cloud_mode="remote_storage"
   ```

4. Replace the `480` in `steam_appid.txt` with the full game's App ID. That file is only for running from the
   editor or a local build outside Steam; it is not exported, and Steam supplies the id when it starts the game.

## 2. GodotSteam (the Steam plugin)

The project uses the **GodotSteam GDExtension** (Community Edition, Godot 4.x, Windows/Linux/macOS). It could
not be downloaded from the build sandbox (the project moved from GitHub to Codeberg, and the sandbox cannot
reach Codeberg or the Godot Asset Library), so `addons/godotsteam/` is not in the repo yet. The game runs
without it and logs `[steam] GodotSteam extension not installed`.

Install (about 5 minutes):

1. Download the latest **GDExtension** release for Godot 4.4 or newer from
   https://codeberg.org/godotsteam/godotsteam/releases (the GDExtension zip, not the pre-compiled editor), or from the
   Godot Asset Library ("GodotSteam GDExtension 4.4+"). GDExtensions built for Godot 4.4 or newer load in 4.7.
2. Unzip so that `addons/godotsteam/godotsteam.gdextension` exists, with the `win64`, `linux64` and `osx`
   folders beside it. Those already contain Valve's `steam_api64.dll`, `libsteam_api.so` and `libsteam_api.dylib`.
3. Open the project in the editor once (or run `godot --headless --path . --import`), then commit `addons/godotsteam`.
4. Start the game with Steam open. The log should say `[steam] Steam active (app 480)` and the Steam overlay
   opens with Shift+Tab. Scoop one piece of junk: the FIRST_SCOOP achievement pops in the overlay
   (with app 480 it is Spacewar's list, so only after step 1 does it show Greenfall's).

Exports pick the extension up by themselves (the `.gdextension` file lists the libraries per platform).
No code changes: `SteamService` looks for the `Steam` engine singleton at start-up.

Run flags: `-- --no-steam` starts without Steam; `-- --demo` behaves as the demo build.

## 3. Achievements and stats in Steamworks

App Admin > *Stats & Achievements*:

1. **Stats** first: one per line of `docs/steam/stats.csv` (API name, type INT/FLOAT, *Set By: Client*,
   *Increment only*: yes).
2. **Achievements**: one per line of `docs/steam/achievements.csv` (71). The API name must match exactly
   (`FIRST_SCOOP`, ...). Where `progress_stat` is filled, set *Progress Stat* to that stat with the given
   min and max so Steam shows a progress bar. Rows with `hidden=yes` are easter eggs.
3. Icons: `achievement_icons/<API_NAME>.png` (unlocked) and `<API_NAME>_locked.png`, 256x256.
4. Click **Publish**: stats and achievements are live only after the app config is published.

## 4. Steam Cloud

Pick one option in `project.godot` (`greenfall/steam/cloud_mode`).

**A. `remote_storage` (default; the code is in place).** Every save is also written to Steam Cloud through
the Steam API. On start, each slot is compared with its cloud copy and the save with the newest internal
save time wins; on a tie the local one stays. A local save replaced by a newer cloud copy is kept as
`slot_N.save.local_bak`. Steamworks: App Admin > *Steam Cloud* > *Byte quota per user* **50 MB**,
*Number of files per user* **20**, then Publish.

**B. `auto_cloud` (no code; Steam syncs the folder).** Set `cloud_mode="auto_cloud"`, then in *Steam Cloud* >
*Root paths* add (pattern `*.save`, not recursive):

| OS | Root | Subdirectory |
|---|---|---|
| Windows | `WinAppDataRoaming` | `Godot/app_userdata/Greenfall/saves` |
| macOS | `MacAppSupport` | `Godot/app_userdata/Greenfall/saves` |
| Linux / Steam Deck | `LinuxXdgDataHome` | `godot/app_userdata/Greenfall/saves` |

For the demo app use the same roots with `saves_demo` in place of `saves`. Auto-Cloud resolves conflicts
with Steam's own "which copy do you want" dialog.

Either way the save files are Cloud friendly already: one compressed, platform-neutral file per slot, so
Windows to Steam Deck works. Do not turn on both A and B for the same app.

The demo keeps its saves in `user://saves_demo`. On the first start of the full game, a demo save is copied
into `user://saves` (only when that slot is empty), so demo progress carries over.

## 5. Builds and depots

Steamworks > *SteamPipe* > *Depots*: three depots for the full game, three for the demo app:

| Depot | OS | Content (CI artifact) |
|---|---|---|
| App ID + 1 | Windows 64-bit | `Greenfall-Windows` (Greenfall.exe + Greenfall.pck) |
| App ID + 2 | macOS | `Greenfall-macOS` (Greenfall.zip, unzipped: Greenfall.app) |
| App ID + 3 | Linux + SteamOS | `Greenfall-Linux` (Greenfall.x86_64 + Greenfall.pck) |

The demo uses the same layout with the `GreenfallDemo-*` artifacts. In *Installation* > *General* add a launch
option per OS: `Greenfall.exe`, `Greenfall.app`, `Greenfall.x86_64` (demo: `GreenfallDemo.exe`,
`GreenfallDemo.app`, `GreenfallDemo.x86_64`). Publish.

Steam Deck: the Linux depot runs natively; request the Steam Deck compatibility review from the app's admin page.

## 6. macOS signing and notarization (Apple Developer Program, US$99 a year)

macOS builds must be signed with a **Developer ID Application** certificate and notarized, or Gatekeeper
blocks them. In the `macOS` and `macOS Demo` presets (Project > Export):

- *Codesign*: `rcodesign` (works on Linux CI) or `Xcode codesign` (on a Mac); the certificate as a .p12 file
  with its password; *Hardened Runtime* on. The GodotSteam `.dylib` is signed along with the app.
- *Notarization*: `rcodesign` with an App Store Connect API key (issuer id, key id, .p8 key file).

On CI, keep these out of the repo: store `APPLE_CERT_P12_BASE64`, `APPLE_CERT_PASSWORD`,
`APPLE_API_KEY_P8_BASE64`, `APPLE_API_ISSUER` and `APPLE_API_KEY_ID` as GitHub secrets, decode the files in a
step, and pass them to Godot through its `GODOT_MACOS_*` export environment variables (or a generated
`.godot/export_credentials.cfg`). The macOS export steps stay `continue-on-error` until this is set up.

## 7. Uploading with SteamPipe (CI step, ready to fill)

Make a separate Steam account for builds (no purchases; Steam Guard by e-mail) and give it the *Edit App
Metadata* and *Publish App Changes To Steam* permissions. Log in once with steamcmd on any machine to approve
Steam Guard, then base64-encode `config/config.vdf` from the steamcmd folder.

GitHub > Settings > Secrets and variables > Actions:

- secret `STEAM_USERNAME`: the build account
- secret `STEAM_CONFIG_VDF`: base64 of `config.vdf` (avoids the Steam Guard prompt on CI)
- variables `STEAM_APP_ID` and `STEAM_DEMO_APP_ID`

Add this job to `.github/workflows/build.yml`, after the `export` job. It uploads to the `beta` branch only
when the workflow is started by hand, so ordinary pushes never touch Steam:

```yaml
  steam-upload:
    needs: export
    if: github.event_name == 'workflow_dispatch' && vars.STEAM_APP_ID != ''
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          path: dist
      - name: Unzip the macOS apps
        run: |
          for d in Greenfall-macOS GreenfallDemo-macOS; do
            z=$(ls dist/$d/*.zip 2>/dev/null | head -1)
            [ -n "$z" ] && (cd dist/$d && unzip -q "$(basename "$z")" && rm "$(basename "$z")") || true
          done
      - name: Upload full game
        uses: game-ci/steam-deploy@v3
        with:
          username: ${{ secrets.STEAM_USERNAME }}
          configVdf: ${{ secrets.STEAM_CONFIG_VDF }}
          appId: ${{ vars.STEAM_APP_ID }}
          buildDescription: ${{ github.sha }}
          rootPath: dist
          depot1Path: Greenfall-Windows
          depot2Path: Greenfall-macOS
          depot3Path: Greenfall-Linux
          releaseBranch: beta
      - name: Upload demo
        if: vars.STEAM_DEMO_APP_ID != ''
        uses: game-ci/steam-deploy@v3
        with:
          username: ${{ secrets.STEAM_USERNAME }}
          configVdf: ${{ secrets.STEAM_CONFIG_VDF }}
          appId: ${{ vars.STEAM_DEMO_APP_ID }}
          buildDescription: demo ${{ github.sha }}
          rootPath: dist
          depot1Path: GreenfallDemo-Windows
          depot2Path: GreenfallDemo-macOS
          depot3Path: GreenfallDemo-Linux
          releaseBranch: beta
```

`game-ci/steam-deploy` numbers the depots App ID + 1, + 2, + 3, which matches the table above. Set the `beta`
build live on `default` in Steamworks > *SteamPipe* > *Builds* once it has been tested.

By hand instead: install steamcmd, write an `app_build_<appid>.vdf` listing the three depots
(https://partner.steamgames.com/doc/sdk/uploading), then
`steamcmd +login <user> +run_app_build /abs/path/app_build_<appid>.vdf +quit`.

## 8. Store page

- Capsules, all rendered in-game: header 920x430, small 462x174, main 1232x706, vertical 748x896, library
  capsule 600x900, library hero 3840x1240 (no text, as Steam asks), library logo 1280x720 (transparent PNG),
  page background 1438x810. Files: `/home/user/Greenfall/screenshots/steam/`.
- Screenshots: 1920x1080 `store_*.png` in the same folder (Steam asks for at least 5).
- Trailer: shot list with exact commands in `docs/steam/TRAILER.md`.
- Short description, tags (Casual, Incremental, Automation, Base Building, Cozy, Robots, Sci-fi, Relaxing),
  the content survey, price, and a release date. Put the **Coming Soon** page live early so wishlists count;
  it must be live at least two weeks before launch.
- Valve reviews the store page and a build before release (allow 3 to 5 working days for each).

## 9. Before launch

- [ ] Steam Direct fee paid; App ID and demo App ID in `project.godot` and `steam_appid.txt`
- [ ] `addons/godotsteam` installed and committed; the overlay and one achievement work in a local build
- [ ] Stats, achievements (with icons) and the Steam Cloud quota entered and **published**
- [ ] Depots, launch options, OS support (Windows, macOS, Linux + Steam Deck)
- [ ] Apple Developer ID signing and notarization for both macOS presets
- [ ] GitHub secrets and variables set; a hand-started workflow run uploads to `beta`; test installs from Steam on each OS
- [ ] Store page assets, description, tags, trailer; Coming Soon page live
- [ ] Demo app: depots, the "Download demo" button on the main store page
- [ ] Optional: `restartAppIfNecessary` (relaunch through Steam when started from the folder) once the real id
      is in. It is off for now because it would quit every test run outside Steam.
