# Nexus 2.2.0 update checklist

1. The manifest is final: author `phobi666`, version `2.2.0`,
   `minInstallerVersion` `0.14.0` (this cannot go lower — 0.14.0 is the first
   MOMI with the GML layer this mod runs on). Don't change `author` or `name`
   after release: MOMI derives the mod's unique ID from them.

2. Open the existing ARPG Movement Nexus page and choose to add a new file.

3. Page details:
   - **Name:** ARPG Movement — Click, Hold, and Auto-Swap Tools
   - **Category:** Gameplay (or Utilities if you prefer)
   - **Overview (short):** Move with the mouse, click characters and objects
     to approach and interact, aim tools and weapons at your cursor, and
     automatically equip the right tool for rocks, trees, stumps, dig spots,
     watering, tilling, bugs, and breakables. WASD always stays in control.
     Ready for Fields of Mistria 1.0; requires an official MOMI release that
     explicitly supports game version 1.0.
   - **Description:** paste `DESCRIPTION.bbcode` (Nexus descriptions use
     BBCode; use the "BBCode" editor mode).

4. Requirements section: add "Mods of Mistria Installer" (MOMI) as a
   requirement. In the requirement's notes field write: "Use the first
   official MOMI release that explicitly supports Fields of Mistria 1.0, or a
   newer release. Pre-1.0 installer builds cannot install the mod on game
   version 1.0."

5. Files tab: upload `dist/ARPGMovement-2.2.0.zip`, version `2.2.0`.

6. Changelog:
   - Clicking a breakable (mine barrels, crates, debris; farm branches and
     leaf piles) draws your weapon, just like rocks equip the pickaxe.
   - Mines: the weapon is drawn only when a monster is near you or your
     cursor; other clicks keep your selection (new sword_enemy_range_px
     setting).
   - Clicking the overhanging top of a rock or tree no longer whiffs; the
     strike re-aims at the object you clicked.
   - Click-to-move and interactions no longer path across open water;
     impossible routes show the red poof.

7. Keep `nexus/1936b44d-ed82-46e9-bd57-e28db83274d3-v2.png` as the main
   2.0 image. A short Auto Tool Swapping GIF would also make the feature
   immediately clear.

8. Mark the 2.1.1 file as archived only after confirming the 2.2.0 download
   extracts to `arpg_movement/manifest.json` and installs successfully.

9. Permissions: MOMI mods are plain-text GML, pick whatever permissions you
   want; the description already invites people to read/adapt the source.
