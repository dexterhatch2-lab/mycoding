# ArenaFPS

A round-based team FPS for Roblox, inspired by duel shooters like Rivals.
About 5,600 lines of Luau. No uploaded assets are needed: weapons are built
from parts and every animation is procedural (driven by code).

## Setup

**Option A: open the place (easiest)**
1. Download `build/ArenaFPS.rbxlx`.
2. In Roblox Studio: **File → Open from File…** and pick it.
3. Press **Play**. The map, dummies and HUD are built when the game starts, so
   the place looks empty in edit mode. That's expected.
4. To test a real match: **Test** tab → **Clients and Servers** → set 2
   players → **Start**.

**Option B: insert into your own place**
1. Right-click **ReplicatedStorage** → **Insert from File…** → `build/ArenaFPS_Shared.rbxmx`
2. Right-click **ServerScriptService** → **Insert from File…** → `build/ArenaFPS_Server.rbxmx`
3. Right-click **StarterPlayer → StarterPlayerScripts** → **Insert from File…** → `build/ArenaFPS_Client.rbxmx`
4. In **Players** properties, untick `CharacterAutoLoads`. (The script also
   sets it, but setting it here avoids a race.)
5. In **StarterPlayer** properties, untick `EnableMouseLockOption` so Shift is
   free for sprinting.

**Option C: Rojo**: `rojo serve` from this folder (`default.project.json`).

## Controls

| Key | Action |
| --- | --- |
| Mouse 1 | Fire / swing / throw |
| Mouse 2 | Aim down sights |
| 1 2 3 4 / wheel | Primary, secondary, melee, utility |
| R | Reload |
| G | Quick-throw grenade |
| Shift | Sprint |
| Ctrl or C | Crouch; press while sprinting to slide |
| M | Loadout menu |

## How it plays

- **Lobby:** you spawn here with your loadout. Shoot the training dummies
  (two of them strafe). Press M to change weapons. In the lobby the change
  applies straight away.
- **Match:** once 2+ players are in, a 10 s countdown starts. Players are
  split into Red and Blue. Each round everyone spawns frozen for 3 s, then
  the last team alive wins. If time runs out (90 s), the team with more total
  health wins. First to 5 rounds takes the match.
- **Dead players** spectate a living teammate until the round ends.
- Players who join mid-match wait in the lobby for the next one.

## Weapons

| Slot | Weapon | Notes |
| --- | --- | --- |
| Primary | Assault Rifle | Auto, 30 mag, all-rounder |
| Primary | SMG | Auto, very fast, falls off at range |
| Primary | Shotgun | Pump, 9 pellets, animated pump |
| Primary | Sniper | Bolt, scope overlay, 2x headshots (kills in one) |
| Secondary | Handgun | Semi-auto, slide blowback |
| Secondary | Revolver | Heavy semi-auto |
| Melee | Knife | Fast, double damage from behind |
| Melee | Katana | Slower, longer reach |
| Utility | Frag / Flashbang / Smoke | Physics grenades |

All stats are in `src/ReplicatedStorage/Shared/Config.lua`. Weapon looks are
in `WeaponModels.lua`: each part is one line (size, position, colour,
material).

## Architecture

```
src/
  ReplicatedStorage/Shared/       shared by server + client
    Config.lua                    every tunable number
    Net.lua                       RemoteEvents
    WeaponModels.lua              part-built weapons
    Spring.lua, Util.lua
  ServerScriptService/Server/
    init.server.lua               entry, spawning, loadouts
    CombatServer.lua              ammo, fire rate, hit validation, damage, grenades
    MatchManager.lua              lobby → rounds → victory
    MapBuilder.lua                lobby + arena built from parts
    Dummies.lua                   training targets
  StarterPlayer/StarterPlayerScripts/Client/
    init.client.lua               entry, spectating, frame loop
    WeaponController.lua          input, firing, reload, ADS, melee, throws
    Viewmodel.lua                 first-person arms + procedural animation
    CameraFX.lua                  recoil, bob, slide tilt, FOV
    Movement.lua                  sprint, crouch, slide
    Effects.lua                   tracers, muzzle flash, impacts, explosions, sound
    HUD.lua                       all UI
    ThirdPerson.lua               other players' arms aim with their camera
```

**Anti-cheat:** the server owns ammo, fire rate, reload timing and damage.
Each client hit is checked for range, line of sight through the map, shooter
position and hit position before it counts. Movement speed is *not* checked
on the server, so add that if you publish publicly.

## Known limits / what to add next

- **Sounds** use Roblox's built-in placeholder sounds. Put real gun sounds from
  the Creator Store into `Config.Sounds` (`"rbxassetid://..."`).
- **Real meshes/animations** must be uploaded to your own account. Swap a
  weapon's parts for a MeshPart in `WeaponModels.lua` if you want.
- **No data saving** (stats reset when you leave). Add a DataStore if you want
  persistent stats or unlocks.
- **PC only:** there are no mobile touch controls.
- I couldn't run this in Roblox Studio while building it. The code passes a
  structural checker (`tools/lualint.py`), not a real Luau run. If something
  errors, check the Output window and send me the message.

## Rebuilding after edits

```
python3 tools/lualint.py src    # sanity check
python3 tools/build.py          # regenerates build/*.rbxlx / *.rbxmx
```
