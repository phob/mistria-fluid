# Nexus upload checklist

Creating the page has to be done from your Nexus account; everything below is
prepared and ready.

1. The manifest is final: author `phobi666`, version `1.0.0`,
   `minInstallerVersion` `0.14.0` (this cannot go lower — 0.14.0 is the first
   MOMI with the GML layer this mod runs on). Don't change `author` or `name`
   after release: MOMI derives the mod's unique ID from them.

2. Go to https://www.nexusmods.com/fieldsofmistria → "Upload a mod".

3. Page details:
   - **Name:** ARPG Movement — Click or Hold to Move
   - **Category:** Gameplay (or Utilities if you prefer)
   - **Overview (short):** ARPG-style mouse movement: hold right-click to
     steer the player toward the cursor (walks near, runs far), tap to
     click-to-move with real pathfinding. WASD always stays in control.
     REQUIRES the MOMI 0.14.0 beta from GitHub — the 0.13.x Nexus MOMI
     cannot install this mod.
   - **Description:** paste `DESCRIPTION.bbcode` (Nexus descriptions use
     BBCode; use the "BBCode" editor mode).

4. Requirements section: add "Mods of Mistria Installer" (MOMI) as a
   requirement. In the requirement's notes field write: "0.14.0 beta or
   newer — get it from the MOMI GitHub releases; the 0.13.x version on
   Nexus cannot install this mod."

5. Files tab: upload `dist/ARPGMovement-1.0.0.zip`, version `1.0.0`.

6. Images: Nexus requires at least one image to publish. Good candidates:
   a short GIF/screenshot of hold-steering and one of a tap with the poof
   marker. (F12 in Steam, or any capture tool; the game window is 1280x720
   windowed which makes clean captures.)

7. Permissions: MOMI mods are plain-text GML, pick whatever permissions you
   want; the description already invites people to read/adapt the source.
