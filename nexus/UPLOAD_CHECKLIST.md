# Nexus 2.3.1 update checklist

1. The manifest is final: author `phobi666`, version `2.3.1`,
   `minInstallerVersion` `0.15.2`. Don't change `author` or `name` after
   release: MOMI derives the mod's unique ID from them.

2. Open the existing ARPG Movement Nexus page and choose to add a new file.

3. Page details:
   - **Name:** ARPG Movement — Click, Hold, and Auto-Swap Tools
   - **Category:** Gameplay (or Utilities if you prefer)
   - **Overview (short):** Move on foot or horseback with click-to-move or
     hold-to-steer, click characters and objects to approach and interact, aim
     tools and weapons at your cursor, and automatically equip the right tool
     for rocks, trees, stumps, dig spots, watering, tilling, bugs, breakables,
     and fishable water. Configure gameplay options in game. WASD always stays
     in control. Ready for Fields of Mistria 1.0; requires MOMI 0.15.2 or
     newer.
   - **Description:** paste `DESCRIPTION.bbcode` (Nexus descriptions use
     BBCode; use the "BBCode" editor mode).

4. Requirements section: add "Mods of Mistria Installer" (MOMI) as a
   requirement. In the requirement's notes field write: "Requires MOMI 0.15.2
   or newer."

5. Files tab: upload `dist/ARPGMovement-2.3.1.zip`, version `2.3.1`.

6. Changelog (paste as plain text, one entry per line):

   ```text
   Added mounted click-to-move pathfinding
   Mounted routes preserve normal riding behavior
   Blocked mounted routes replan twice before stopping
   ```

7. Keep `nexus/1936b44d-ed82-46e9-bd57-e28db83274d3-v2.png` as the main
   2.0 image. A short Auto Tool Swapping GIF would also make the feature
   immediately clear.

8. Mark the 2.3.0 file as archived only after confirming the 2.3.1 download
   extracts to `arpg_movement/manifest.json` and installs successfully.

9. Permissions: MOMI mods are plain-text GML, pick whatever permissions you
   want; the description already invites people to read/adapt the source.
