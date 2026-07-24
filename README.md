# ARPG Movement (for Fields of Mistria)

Mouse movement for the player, action-RPG style:

- **Hold right mouse** — steer toward the cursor. Walks when the cursor is
  within 1 tile, runs beyond 2 tiles (hysteresis in between, so no
  flickering). Stops instantly on release.
- **Tap right mouse** (< 0.6s) — pathfind to the clicked spot with the game's
  own pathfinding; an essence poof marks the destination.
- **Tap next to an object/NPC** — vanilla Interact.
- **WASD / jump / tool / E / Esc** — cancels any mouse walk; keyboard always
  wins. Gamepad play and cutscenes are untouched.

Built as a [MOMI](https://github.com/Garethp/Mods-of-Mistria-Installer)
(0.14.0+) MMAPI mod. The entire mod is one GML file:
`momi-mod/arpg_movement/gml/ArpgMovement.gml`.

All tunables live in
`%LOCALAPPDATA%\FieldsOfMistria\mod_data\arpg_movement\arpg_movement.json`
after first launch.

## Install / iterate

```sh
# game must be closed
cp -r momi-mod/arpg_movement "/d/SteamLibrary/steamapps/common/Fields of Mistria/mods/"
cd "/d/SteamLibrary/steamapps/common/Fields of Mistria" && \
  "C:/Users/pho/Source/mistria-fluid/tools/ModsOfMistriaInstaller-cli.exe"
```

`play.cmd` launches the game straight into the most recent save.

## Publishing

- `dist/ARPGMovement-1.0.0.zip` — Nexus-ready package.
- `nexus/DESCRIPTION.bbcode` — mod page description (BBCode).
- `nexus/UPLOAD_CHECKLIST.md` — upload steps.

See `CLAUDE.md` for development context and engine internals.
