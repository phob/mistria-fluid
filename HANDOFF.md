# Session handoff — 2026-08-12

## 2.3.0 release

ARPG Movement 2.3.0 packages the current domain-split source and adds the
in-game settings category, fishable-water fishing-rod Auto-Swap, dig-site
pickaxe fallback, and corrected layered-popup outside-click behavior. The
release archive is `dist/ARPGMovement-2.3.0.zip` with `arpg_movement` at its
root. Manifest and `mmapi_mod_declare` both carry version 2.3.0. Diagnostic
logging remains config-file-only and defaults to false.

Working state for the next Claude session. Read alongside AGENTS.md (auto-loaded).
The functions discussed below now live in domain files under
`momi-mod/arpg_movement/gml/`; see AGENTS.md for the current source map. The
2.2.1 state was installed to the game (compile gate OK) and **released as 2.2.1**
(`dist/ARPGMovement-2.2.1.zip`, 2026-08-11) after the change-8 picker fix
resolved the user's rock/axe mis-selection.

## Changes made this session (chronological)

1. **Net fix** (Nexus report: clicking a Living Stone's rock swung the net).
   The game's `net_target_in_tile` (BugManager.gml:25) counts `obj_bug`,
   `obj_monster_clod_bomb`, AND `obj_monster_clod_projectile` — vanilla lets a
   deliberate net swing catch the projectiles. Auto-select now requires a real
   `obj_bug` on the cell (`__arpg_movement_bug_in_cell`) in both terrain
   probes. A hand-picked net still catches rocks (held-item check unchanged).

2. **Configurable toggle hotkey**: config `auto_select_hotkey` (default "F6",
   chords like "SHIFT+F6" work), validated via `mmapi_hotkey_binding_from_name`,
   registered on first frame via `mmapi_register` latch
   (`__arpg_movement_install_hotkey`). Verified end-to-end with F5 + the MMAPI
   debug agent (registry: `global.__mmapi_binding_hotkeys`).

3. **New movement toggles** (all in config, defaults keep old behavior):
   `hold_to_steer` (true), `tap_to_pathfind` (true),
   `mouse_move_mounted_only` (false). When no right-mouse feature can claim
   the press in the current state, the button is never muted → fully vanilla.
   Gating lives in `arpg_movement_clock_tick` (`_steer_allowed`/`_tap_allowed`).

4. **Continuous-action held re-selection**: the game's continuous-action
   option binds LMB to `UseToolRepeated`; repeats pass through Default each
   swing. Auto-select now also runs on held frames
   (`__arpg_movement_left_is_repeating_action`), so a held sweep tree→stone
   swaps axe→pickaxe between swings. Guardrails: held sweeps only re-select
   node targets (never terrain tools), mines weapon-draw is press-only, and a
   held weapon in a dungeon is never traded away mid-hold.

5. **Dev logging**: `__arpg_movement_log()` + `dev_logging` config flag
   (default false; **currently TRUE in the user's local config**). See the
   "Dev logging" section in AGENTS.md. Log:
   `%LOCALAPPDATA%\FieldsOfMistria\mod_data\arpg_movement\logs\arpg_movement.log`
   — flushes per line, live-tail with `Get-Content <log> -Wait -Tail 20`.
   Do NOT strip log calls for release; the flag ships default-off.

6. **Out-of-reach node clicks arm the tool anyway** (user report: clicking a
   log kept the pickaxe). A tree's choppable cells are only its 2x2 trunk at
   `top_left + 2..3` (Chop.gml), so recognized-but-out-of-range fresh clicks
   now still select the right tool and whiff like vanilla. Held sweeps stay
   reach-gated.

7. **Clicked-node picker rewritten** (user report: rock at a tree's foot kept
   resolving to the tree). `overlap_point` returns an arbitrary overlapping
   renderer; now `__arpg_movement_clicked_node` collects all renderers via
   `overlap_point_list` and picks the lowest depth (= drawn on top, depth is
   -y — what the player visually clicked). Grid cell stays the fallback.
   ⚠ First version crashed every clock_tick: **`ds_list_destroy` does not
   exist in this engine** (runtime throw, not caught by compile gate). Fixed
   with a persistent `_rt.click_scan_list` + `ds_list_clear`. Engine lesson
   recorded in AGENTS.md.

8. **Clicked-node picker rewritten again — grid footprint first** (user
   report: standing at a rock with the axe, every click on the rock kept the
   axe). Log showed clicks at the rock's cell resolving to a tree at
   tl=138,30: renderer overlap is **bbox-only** (engine has no precise
   masks), so the tree's box includes its transparent canopy, and depth=-y
   makes a tree whose base is lower always sort "on top" of a rock behind
   it — then change 6 armed the axe "out of reach anyway" on every click.
   Now `__arpg_movement_clicked_node` returns the clicked cell's grid
   occupant outright when it is an actionable category
   (`__arpg_movement_click_actionable`: Rock/Tree/Stump/DigSite/Breakable —
   every footprint cell maps to its node via `write_object_inst_node`).
   Renderers only decide for empty/non-actionable cells (true canopy or
   overhang clicks), ranked smallest-bbox-area first (most specific sprite
   wins), draw order as tiebreak, actionable nodes only. Non-actionable cell
   occupant is the final fallback for the terrain probes.

9. **Shop outside-click closing fixed** (user report: shop menus stopped
   closing on outside clicks; regression from the game's 1.0 update). Cause:
   1.0's `player_gold_prefab` (StoreMenu.gml:148) stores a **screen-sized
   invisible canvas** (`gold_canvas`, holding the 30x15 gold pill) in a menu
   field. `__arpg_movement_menu_owns_root` matched that field, so
   `__arpg_movement_point_inside_menu` counted the whole screen as inside
   the shop. Fix: canvas-type nodes (`NodeId.Canvas`) never count as visible
   menu content — generalizes the old "skip the menu's own canvas" rule;
   visible children still count. Verified live both ways (inside click keeps
   the shop open, outside click closes it) via the automated UI loop below.
   Kept: dev-gated probe logging in the closer, and three debug-agent
   drivers (`arpg_movement.debug_open_store` / `debug_node_info` /
   `debug_nodes_at`), registered only when MMAPI's debug agent is enabled.

## Verified-by-automation UI test loop (new this session)

No human input needed: enable `debug_enabled` in `mod_data/mmapi/mmapi.json`
→ launch `FieldsOfMistria.exe --auto-start continue` → drive
`control.json`/`state.json` (`{"rev":N,"commands":[{"op":"call","fn":...}]}`,
rev must exceed `state.json.applied_rev`; wait ~25s after launch or the call
fires before the save loads) → inject real clicks with user32
SetCursorPos/mouse_event via PowerShell Add-Type (re-Add-Type every call,
shell state resets; GUI space is 960x540, so physical = GUI x window/960) →
read the mod log. Note: the game's "minspec" content canvas is smaller than
GUI space and centered — the shop window spans roughly x 287-620, y 160-380.

## Immediate next step

Changes 6–8 are installed (compile gate OK), **unverified in game**. Retest:
stand at a rock near a tree with the axe held, click the rock — log should
show `click: node cat=7 obj=... -> tool slot 3` (cat 7=Rock, 8=Stump,
9=Tree, 0=Breakable). Then re-verify canopy/log clicks still arm the axe
(renderer fallback path), and the original rock-at-tree's-foot case.

## Open items

- Playtest: net-vs-Living-Stone in mines, held-sweep tool swapping, new
  config toggles, mounted-only mode.
- Decide: should a below-minimum-quality tool still be armed on click (for
  vanilla "too weak" feedback)? Currently it is not (log says "none usable").
- ~~Release~~ Done: shipped as **2.2.1** (not 2.3.0) — manifest +
  `mmapi_mod_declare` bumped, `dist/ARPGMovement-2.2.1.zip` built (folder at
  zip root), same build reinstalled to the game. `minInstallerVersion`
  raised 0.14.0 → **0.15.2**: `mmapi_hotkey_binding_from_name` first shipped
  in MOMI 0.15.2 (AGENTS.md rule updated). `nexus/DESCRIPTION.bbcode`
  refreshed for 2.2.1: MOMI 0.15.2 requirement, all new config keys
  (hold_to_steer, tap_to_pathfind, mouse_move_mounted_only,
  auto_select_hotkey, interact_radius_px, stop_within_px, dev_logging), and
  a link to the MMAPI hotkey key-name list (verified live). Nexus upload
  still manual (see `nexus/` checklist).
- User's local config extras: `dev_logging: true`, `interact_radius_px: 64`.
- MMAPI debug agent is currently DISABLED again (mmapi.json). Re-enable +
  restart if live watches are needed (see AGENTS.md lessons).

## Diagnostic workflow that worked well

User plays → hits oddity → paste/tail the mod log → the `click:`/`sweep:`/
`tap:` lines carry position, slot, node obj/tl, and the decision taken →
cross-reference game GML in `game-assets/` → fix → `Copy-Item` mod →
installer CLI → user retests. Boot smoke test: launch with
`--auto-start continue`, check log/config, `Stop-Process` FieldsOfMistria.
