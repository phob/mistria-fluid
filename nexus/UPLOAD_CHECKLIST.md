# Nexus 2.1.0 update checklist

1. The manifest is final: author `phobi666`, version `2.1.0`,
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
     watering, tilling, and bugs. WASD always stays in control. Requires MOMI
     0.14.0 beta 3 or newer from GitHub.
   - **Description:** paste `DESCRIPTION.bbcode` (Nexus descriptions use
     BBCode; use the "BBCode" editor mode).

4. Requirements section: add "Mods of Mistria Installer" (MOMI) as a
   requirement. In the requirement's notes field write: "0.14.0 beta 3 or
   newer — get it from the MOMI GitHub releases. The current 0.13.x Nexus
   version cannot install this mod."

5. Files tab: upload `dist/ARPGMovement-2.1.0.zip`, version `2.1.0`.

6. Changelog:
   - Added watering can, hoe, and net to Auto Tool Swapping: clicking a tile
     the game says one of them would act on now equips it.
   - Added protection for deliberate selections — a click the held item
     already acts on (seeds on tilled soil, a placement, the tool you just
     picked) never triggers a swap.
   - Added turning toward the cursor when you use a weapon or tool, and every
     repeat swing while the button is held re-aims at the cursor.
   - Fixed action clicks made while walking snapping to the direction of
     travel instead of staying on the cursor.
   - New settings: `face_cursor_on_action` and `cursor_targeting_on_action`
     (both on by default). Existing config files keep their values.

7. Keep `nexus/1936b44d-ed82-46e9-bd57-e28db83274d3-v2.png` as the main
   2.0 image. A short Auto Tool Swapping GIF would also make the feature
   immediately clear.

8. Mark the 2.0.1 file as archived only after confirming the 2.1.0 download
   extracts to `arpg_movement/manifest.json` and installs successfully.

9. Permissions: MOMI mods are plain-text GML, pick whatever permissions you
   want; the description already invites people to read/adapt the source.
