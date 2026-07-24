# ARPG Movement 2.0.1 (for Fields of Mistria)

Mouse movement and automatic tool swapping for action-RPG-style play:

- **Hold right mouse** — steer toward the cursor. Walks when the cursor is
  close and runs when it is farther away. Holding the normal Walk control
  keeps the player walking.
- **Tap right mouse** — click-to-move around obstacles. A normal essence poof
  marks the destination; a red poof means the click cannot be reached.
- **Tap an object or NPC** — walk to it and interact automatically. Nearby
  taps still behave like the normal Interact control.
- **Ride or swim with the mouse** — hold-to-steer also works while mounted or
  swimming without replacing their normal actions.
- **Auto Tool Swapping** — left-click a nearby rock, tree, stump, or dig spot
  and the correct usable tool is selected from anywhere in the inventory
  before the action happens. General action clicks in the mines select a
  weapon. Press **F6** to toggle this feature; the choice is remembered.
- **Click outside menus to close them** — left- or right-click outside a
  normal menu to dismiss it. In the Skills screen, an outside click goes back
  one layer first, then closes from the category screen. Dialogue and
  confirmation prompts are protected from accidental closing.
- **WASD / jump / tool / E / Esc** — cancels any mouse-driven walk immediately.
  Keyboard control always wins, while gamepad play and cutscenes remain
  untouched.

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

- `dist/ARPGMovement-2.0.1.zip` — Nexus-ready package.
- `nexus/DESCRIPTION.bbcode` — mod page description (BBCode).
- `nexus/UPLOAD_CHECKLIST.md` — upload steps.
