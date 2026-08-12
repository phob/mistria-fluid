# ARPG Movement 2.3.0 (for Fields of Mistria 1.0)

ARPG Movement 2.3.0 is ready for Fields of Mistria 1.0 and requires MOMI
0.15.2 or newer. Older installers either lack Fields of Mistria 1.0 support or
the MMAPI hotkey function used by Auto Tool Swapping.

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
  before the action happens. Clicking fishable water equips the fishing rod;
  tiles the game says are waterable, tillable, or hold a bug select the
  watering can, hoe, or net. A click the held item already acts on is left
  alone, so deliberate selections survive. General action clicks in the mines
  select a weapon. Press **F6** to toggle this feature; the choice is
  remembered.
- **Click where the cursor points** — clicking with a weapon or tool turns the
  player toward the cursor first, and keeps aiming every swing of a repeating
  tool while the button is held. Action clicks stay aimed at the cursor while
  walking instead of snapping to the direction of travel. Movement keys and
  steering still set the facing themselves, as in vanilla.
- **Click outside menus to close them** — left- or right-click outside a
  normal menu to dismiss it. In the Skills screen, an outside click goes back
  one layer first, then closes from the category screen. Dialogue and
  confirmation prompts are protected from accidental closing.
- **WASD / jump / tool / E / Esc** — cancels any mouse-driven walk immediately.
  Keyboard control always wins, while gamepad play and cutscenes remain
  untouched.

Built as a [MOMI](https://github.com/Garethp/Mods-of-Mistria-Installer)
(0.15.2+) MMAPI mod. For Fields of Mistria 1.0, use MOMI 0.15.2 or newer. The
GML source is split by domain under `momi-mod/arpg_movement/gml/`;
`ArpgMovement.gml` is the single boot/registration file.

Gameplay options are available in **Journal → Settings → ARPG Movement**.
Changes are saved immediately to
`%LOCALAPPDATA%\FieldsOfMistria\mod_data\arpg_movement\arpg_movement.json`.
The default-off `dev_logging` diagnostic option is intentionally available
only by editing that file.

## Install / iterate

```sh
# game must be closed
cp -r momi-mod/arpg_movement "/d/SteamLibrary/steamapps/common/Fields of Mistria/mods/"
cd "/d/SteamLibrary/steamapps/common/Fields of Mistria" && \
  "C:/Users/pho/Source/mistria-fluid/tools/ModsOfMistriaInstaller-cli.exe"
```

`play.cmd` launches the game straight into the most recent save.

## Publishing

- `dist/ARPGMovement-2.3.0.zip` — Nexus-ready package.
- `nexus/DESCRIPTION.bbcode` — mod page description (BBCode).
- `nexus/UPLOAD_CHECKLIST.md` — upload steps.
