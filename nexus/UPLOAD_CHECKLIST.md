# Nexus 2.0.1 update checklist

1. The manifest is final: author `phobi666`, version `2.0.1`,
   `minInstallerVersion` `0.14.0` (this cannot go lower — 0.14.0 is the first
   MOMI with the GML layer this mod runs on). Don't change `author` or `name`
   after release: MOMI derives the mod's unique ID from them.

2. Open the existing ARPG Movement Nexus page and choose to add a new file.

3. Page details:
   - **Name:** ARPG Movement — Click, Hold, and Auto-Swap Tools
   - **Category:** Gameplay (or Utilities if you prefer)
   - **Overview (short):** Move with the mouse, click characters and objects
     to approach and interact, and automatically equip the right tool when
     you click rocks, trees, stumps, or dig spots. WASD always stays in
     control. Requires MOMI 0.14.0 beta 3 or newer from GitHub.
   - **Description:** paste `DESCRIPTION.bbcode` (Nexus descriptions use
     BBCode; use the "BBCode" editor mode).

4. Requirements section: add "Mods of Mistria Installer" (MOMI) as a
   requirement. In the requirement's notes field write: "0.14.0 beta 3 or
   newer — get it from the MOMI GitHub releases. The current 0.13.x Nexus
   version cannot install this mod."

5. Files tab: upload `dist/ARPGMovement-2.0.1.zip`, version `2.0.1`.

6. Changelog:
   - Added left- and right-click outside normal menus to close them; in the
     Skills screen it goes back one layer first, then closes.
   - Kept dialogue, confirmation prompts, and menus with special Back
     behavior protected from accidental outside-click closing.
   - Fixed the brief movement pause when rapidly right-clicking new
     destinations.

7. Keep `nexus/1936b44d-ed82-46e9-bd57-e28db83274d3-v2.png` as the main
   2.0 image. A short Auto Tool Swapping GIF would also make the feature
   immediately clear.

8. Mark the 2.0.0 file as archived only after confirming the 2.0.1 download
   extracts to `arpg_movement/manifest.json` and installs successfully.

9. Permissions: MOMI mods are plain-text GML, pick whatever permissions you
   want; the description already invites people to read/adapt the source.
