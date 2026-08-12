// ARPG Movement: runtime, configuration, and shared state

#macro ARPG_MOVEMENT_CONFIG_VERSION 1

// Half a tile. Running is a fraction of this, so anything larger is a warp,
// a room transition, or a dismount rather than a step the player took.
#macro ARPG_MOVEMENT_MAX_STEP_PX 8

// The lazy runtime struct. All mod state in one global, created on first use.
function __arpg_movement_runtime() {
    if (global[$ "__arpg_movement"] == undefined) {
        global.__arpg_movement = {
            registered_hooks: undefined,
            late_registration_installed: false,
            installed_hotkeys: undefined,
            cfg: undefined,
            hold_frames: 0,
            running: true,
            pathfinding: false,
            interact_target: undefined,
            interact_target_x: undefined,
            interact_target_y: undefined,
            interact_end_x: undefined,
            interact_end_y: undefined,
            interact_repath_frames: 0,
            click_scan_list: undefined,
            player_id: undefined,
            location_id: undefined,
            last_x: undefined,
            last_y: undefined,
            step_x: 0,
            step_y: 0,
            tool_retarget: undefined,
        };
    }
    return global.__arpg_movement;
}

// A hotkey name (single key or a "+"-chord), validated through MMAPI's
// binding parser so a typo falls back to the default instead of silently
// leaving the toggle unbound.
function __arpg_movement_config_hotkey(_source, _key, _default) {
    var _name = mmapi_config_get(_source, _key, _default);
    // The binding probe stays in its own local. With the call inlined into the
    // short-circuited `if` condition, this engine's VM returned undefined from
    // this function even on the `return _name` path (observed live: the config
    // materialized null instead of "F6"). Also note a JSON null on disk reads
    // back as a non-string value that is not == undefined, so is_string is the
    // check that actually catches it.
    var _binding = mmapi_hotkey_binding_from_name(_name);
    if (!is_string(_name) || _binding == undefined) {
        return _default;
    }
    return _name;
}

// Keep the three distance bands coherent after either a disk load or a future
// in-game settings edit. The nearest band stops, the middle band walks, and
// only the farthest band runs.
function __arpg_movement_normalize_config(_cfg) {
    // Steering may begin inside the tap-release grace window, but never after
    // it. A later steering threshold would create a dead period in which a
    // right-mouse hold can neither become a tap nor steer the player.
    _cfg.steer_start_seconds = min(_cfg.steer_start_seconds, _cfg.tap_seconds);

    _cfg.walk_within_px = max(_cfg.walk_within_px, _cfg.stop_within_px);
    _cfg.run_beyond_px = max(_cfg.run_beyond_px, _cfg.walk_within_px);

    // Mounted-only taps intentionally fall through to vanilla interaction;
    // steering is the only mouse-movement feature that can run while mounted.
    // Without steering this flag would merely and invisibly disable both
    // on-foot tap features, so collapse that nonsensical combination.
    if (!_cfg.hold_to_steer) {
        _cfg.mouse_move_mounted_only = false;
    }
}

// One persistence path for hotkeys and the in-game settings UI. Call only
// after boot, when config IO is safe.
function arpg_movement_config_save() {
    var _cfg = arpg_movement_config();
    __arpg_movement_normalize_config(_cfg);
    mmapi_config_write("arpg_movement", ARPG_MOVEMENT_CONFIG_VERSION, _cfg);
}

// Lazy, versioned config. Call only after boot, when file IO is ready.
function arpg_movement_config() {
    var _rt = __arpg_movement_runtime();
    if (_rt.cfg != undefined) return _rt.cfg;
    var _source = mmapi_config_read_valid("arpg_movement", ARPG_MOVEMENT_CONFIG_VERSION);
    _rt.cfg = {
        enabled: mmapi_config_bool(_source, "enabled", true),
        // The two right-mouse gestures, individually. `mouse_move_mounted_only`
        // restricts both to riding; on foot the button is then never muted and
        // Interact stays exactly vanilla.
        hold_to_steer: mmapi_config_bool(_source, "hold_to_steer", true),
        tap_to_pathfind: mmapi_config_bool(_source, "tap_to_pathfind", true),
        mouse_move_mounted_only: mmapi_config_bool(_source, "mouse_move_mounted_only", false),
        tap_seconds: mmapi_config_number(_source, "tap_seconds", 0.6, 0.05, 2.0),
        steer_start_seconds: mmapi_config_number(_source, "steer_start_seconds", 0.1, 0.0, 1.0),
        walk_within_px: mmapi_config_number(_source, "walk_within_px", 16, 0, 320),
        run_beyond_px: mmapi_config_number(_source, "run_beyond_px", 32, 0, 640),
        interact_radius_px: mmapi_config_number(_source, "interact_radius_px", 24, 0, 64),
        stop_within_px: mmapi_config_number(_source, "stop_within_px", 8, 0, 32),
        click_to_interact: mmapi_config_bool(_source, "click_to_interact", true),
        click_marker: mmapi_config_bool(_source, "click_marker", true),
        invalid_click_marker: mmapi_config_bool(_source, "invalid_click_marker", true),
        auto_select_action_item: mmapi_config_bool(_source, "auto_select_action_item", true),
        auto_select_hotkey: __arpg_movement_config_hotkey(_source, "auto_select_hotkey", "F6"),
        dev_logging: mmapi_config_bool(_source, "dev_logging", false),
        face_cursor_on_action: mmapi_config_bool(_source, "face_cursor_on_action", true),
        cursor_targeting_on_action: mmapi_config_bool(_source, "cursor_targeting_on_action", true),
        click_outside_closes_menus: mmapi_config_bool(_source, "click_outside_closes_menus", true),
        // One field is 8px. Ambiguous mine clicks arm the weapon only when a
        // live monster is inside this radius around the player (0 disables the
        // player-radius check; clicks at a monster still arm it).
        sword_enemy_range_px: mmapi_config_number(_source, "sword_enemy_range_px", 40, 0, 640),
    };
    arpg_movement_config_save();
    return _rt.cfg;
}

// Dev-only decision tracing, opt-in via `dev_logging` in the config. Lines
// land in %LOCALAPPDATA%\FieldsOfMistria\mod_data\arpg_movement\logs\
// arpg_movement.log. The flag ships default-off, so release builds carry the
// call sites but stay silent — nothing to strip before a release, and a user
// chasing a bug can flip the flag and send the log in. Every line is flushed
// immediately so tailing the file during a play session stays live.
//
// Call sites on discrete events (clicks, taps, toggles) may build their
// message unconditionally; anything on a per-frame path must check
// __arpg_movement_dev_logging() before assembling strings.
function __arpg_movement_dev_logging() {
    var _rt = __arpg_movement_runtime();
    return _rt.cfg != undefined && _rt.cfg.dev_logging;
}

function __arpg_movement_log(_msg) {
    if (!__arpg_movement_dev_logging()) return;
    mmapi_log_info("arpg_movement", _msg);
    mmapi_log_flush("arpg_movement");
}

// The shared context suffix: where Ari and the cursor are and what is held.
function __arpg_movement_log_ctx() {
    return " | ari=" + string(obj_ari.x) + "," + string(obj_ari.y)
        + " mouse=" + string(mouse_x()) + "," + string(mouse_y())
        + " slot=" + string(ARI.held_item_index);
}

function __arpg_movement_reset(_rt) {
    _rt.hold_frames = 0;
}

function __arpg_movement_clear_interact(_rt) {
    _rt.interact_target = undefined;
    _rt.interact_target_x = undefined;
    _rt.interact_target_y = undefined;
    _rt.interact_end_x = undefined;
    _rt.interact_end_y = undefined;
    _rt.interact_repath_frames = 0;
}

// Room changes, reloads, and save swaps can all replace Ari without destroying
// this global. Never carry a path, a gesture, or a displacement sample across
// that boundary.
function __arpg_movement_sync_context(_rt) {
    if (_rt.player_id == obj_ari.id && _rt.location_id == CURRENT_LOCATION_ID) {
        return;
    }

    _rt.player_id = obj_ari.id;
    _rt.location_id = CURRENT_LOCATION_ID;
    _rt.pathfinding = false;
    _rt.running = true;
    _rt.last_x = undefined;
    _rt.last_y = undefined;
    _rt.step_x = 0;
    _rt.step_y = 0;
    __arpg_movement_reset(_rt);
    __arpg_movement_clear_interact(_rt);
}

// Ends a mouse-driven Pathfind walk and hands control back to the player.
function __arpg_movement_stop_walk(_rt) {
    obj_ari.set_animation(AnimationName.Idle);
    obj_ari.fsm.change_state(PlayerState.Default);
    _rt.pathfinding = false;
    __arpg_movement_clear_interact(_rt);
}

// The normal destination poof doubles as failure feedback when tinted red.
function __arpg_movement_show_marker(_x, _y, _valid) {
    var _effect = create_animation_effect(_x, _y, -100000, spr_fx_poof1_essence_once);
    if (!_valid) {
        _effect.image_blend = make_color_rgb(255, 72, 72);
    }
}
