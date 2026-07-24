// ARPG Movement
//
// Mouse movement for the player:
// - Hold right mouse past a short threshold to begin steering toward the
//   cursor immediately. Walks when the cursor is within `walk_within_px`,
//   runs beyond `run_beyond_px`, and keeps its current pace in between
//   (hysteresis).
// - Releasing within `tap_seconds` commits the cursor position to pathfinding,
//   even if responsive steering has already begun. This intentional overlap
//   gives clicks a forgiving release window without making holds feel delayed.
//   Releases near the player re-inject the press instead, so tap-to-interact
//   with nearby objects still works.
// - The raw right-button press is muted the moment it lands, so Interact
//   (and anything else bound to right mouse) never fires during a hold.
// - WASD, jump, tool use, E, or Esc cancel a mouse-driven walk instantly.
// - Steering also works while swimming and mounted. Taps don't pathfind in
//   either case; mounted taps are handed back to vanilla Interact.
//
// Steering works by feeding the cursor direction into the input system as a
// virtual analog stick (`INPUT.gp_left_stick`), which the player's normal
// movement code reads through the default `left_stick_*` bindings. Movement,
// collision sliding, facing, and animation are all vanilla — the mod never
// touches the player's state machine while steering. Slow walking near the
// cursor, or while the player holds their bound Walk control, is done the same
// way: by holding the vanilla Walk binding down. Taps drive the game's own
// PlayerState.Pathfind, like scripted walks.

#macro ARPG_MOVEMENT_CONFIG_VERSION 1

// The lazy runtime struct. All mod state in one global, created on first use.
function __arpg_movement_runtime() {
    if (global[$ "__arpg_movement"] == undefined) {
        global.__arpg_movement = {
            registered_hooks: undefined,
            cfg: undefined,
            hold_frames: 0,
            running: true,
            pathfinding: false,
        };
    }
    return global.__arpg_movement;
}

// Lazy, versioned config. Call only after boot, when file IO is ready.
function arpg_movement_config() {
    var _rt = __arpg_movement_runtime();
    if (_rt.cfg != undefined) return _rt.cfg;
    var _source = mmapi_config_read_valid("arpg_movement", ARPG_MOVEMENT_CONFIG_VERSION);
    _rt.cfg = {
        enabled: mmapi_config_bool(_source, "enabled", true),
        tap_seconds: mmapi_config_number(_source, "tap_seconds", 0.6, 0.05, 2.0),
        steer_start_seconds: mmapi_config_number(_source, "steer_start_seconds", 0.1, 0.0, 1.0),
        walk_within_px: mmapi_config_number(_source, "walk_within_px", 16, 0, 320),
        run_beyond_px: mmapi_config_number(_source, "run_beyond_px", 32, 0, 640),
        interact_radius_px: mmapi_config_number(_source, "interact_radius_px", 24, 0, 64),
        stop_within_px: mmapi_config_number(_source, "stop_within_px", 8, 0, 32),
        click_marker: mmapi_config_bool(_source, "click_marker", true),
    };
    mmapi_config_write("arpg_movement", ARPG_MOVEMENT_CONFIG_VERSION, _rt.cfg);
    return _rt.cfg;
}

function __arpg_movement_reset(_rt) {
    _rt.hold_frames = 0;
}

// Ends a mouse-driven Pathfind walk and hands control back to the player.
function __arpg_movement_stop_walk(_rt) {
    obj_ari.set_animation(AnimationName.Idle);
    obj_ari.fsm.change_state(PlayerState.Default);
    _rt.pathfinding = false;
}

// Presses the vanilla Walk binding for this frame, so the engine itself
// picks the walk speed and walk animation.
function __arpg_movement_hold_walk_binding() {
    var _bindings = BINDINGS.bindings[InputId.Walk];
    for (var _i = 0; _i < array_length(_bindings); _i++) {
        var _b = _bindings[_i];
        if (_b == undefined) continue;
        if (_b.type == BindingType.Keyboard) {
            var _ki = array_index(KEYBOARD_INPUTS, _b.keycode);
            if (_ki >= 0) {
                INPUT.raw_keyboard[_ki] = set_flag(INPUT.raw_keyboard[_ki], DigitalStatus.On);
            }
        } else if (_b.type == BindingType.Mouse) {
            var _mi = array_index(MOUSE_BUTTONS, _b.keycode);
            if (_mi >= 0) {
                INPUT.raw_mouse[_mi] = set_flag(INPUT.raw_mouse[_mi], DigitalStatus.On);
            }
        }
    }
}

// Starts (or retargets) a Pathfind walk toward a position (used by taps).
// Returns false when no path exists.
function __arpg_movement_path_to(_x, _y) {
    var _rt = __arpg_movement_runtime();
    var _path_data = PATHFINDING.calculate_local_path(obj_ari.x, obj_ari.y, _x, _y, true);
    if (_path_data == undefined) return false;

    // Walk speed or full run speed with the engine's buffs applied.
    var _old_toggle = ARI.run_toggle;
    ARI.run_toggle = _rt.running;
    var _spd = ARI.get_move_speed();
    ARI.run_toggle = _old_toggle;

    obj_ari.fsm.blackboard.set("itinerary", new Itinerary(List(new ItineraryItem(
        new LocationPosition(CURRENT_LOCATION_ID, Vec2(obj_ari.x, obj_ari.y)),
        new LocationPosition(CURRENT_LOCATION_ID, Vec2(_x, _y)),
        0,
        _path_data.output_list
    ))));
    obj_ari.fsm.blackboard.set("move_accel", Vec2(_spd, _spd));
    obj_ari.fsm.blackboard.set("use_run_animation", _rt.running);
    obj_ari.fsm.blackboard.set("end_state", PlayerState.Default);
    obj_ari.fsm.change_state(PlayerState.Pathfind);
    _rt.pathfinding = true;
    return true;
}

// The per-frame heartbeat. game.clock_tick fires in the game's step_begin,
// after INPUT.begin_frame() and before any object steps — early enough that
// everything injected below (mute, virtual stick, Walk binding) is in place
// before the player state reads its input for the frame.
function arpg_movement_clock_tick(_ctx) {
    if (!instance_exists(obj_ari)) return;

    var _rt = __arpg_movement_runtime();
    var _cfg = arpg_movement_config();

    if (!_cfg.enabled || ON_GAMEPAD || game_paused()) {
        __arpg_movement_reset(_rt);
        return;
    }

    var _sid = obj_ari.fsm.current_state_id();
    if (_sid != PlayerState.Pathfind) {
        _rt.pathfinding = false;
    }
    var _in_default = _sid == PlayerState.Default;
    var _in_swim = _sid == PlayerState.Swim;
    var _in_mount = _sid == PlayerState.MountDefault;
    var _in_our_path = _sid == PlayerState.Pathfind && _rt.pathfinding;

    // Tools, cutscenes, other mods' pathfinds: stay out.
    if (!_in_default && !_in_swim && !_in_mount && !_in_our_path) {
        __arpg_movement_reset(_rt);
        return;
    }

    var _right_down = mouse_check_button(mb_right);

    // No mouse gesture or mod-owned path is active. Avoid resolving input
    // bindings every frame while the mod is idle.
    if (!_in_our_path && _rt.hold_frames == 0 && !_right_down) {
        return;
    }

    // WASD always wins over mouse movement.
    if (INPUT.check(InputId.Up)
        || INPUT.check(InputId.Down)
        || INPUT.check(InputId.Left)
        || INPUT.check(InputId.Right))
    {
        if (_in_our_path) {
            __arpg_movement_stop_walk(_rt);
        }
        __arpg_movement_reset(_rt);
        return;
    }

    // Jump, tool, E, or Esc cancel a mouse-driven walk.
    if (_in_our_path
        && (INPUT.pressed(InputId.Jump)
            || INPUT.pressed(InputId.UseToolCharged)
            || INPUT.pressed(InputId.Interact)
            || INPUT.pressed(InputId.MenuBack)))
    {
        __arpg_movement_stop_walk(_rt);
        __arpg_movement_reset(_rt);
        return;
    }

    if (_right_down) {
        _rt.hold_frames += 1;

        if (mouse_check_button_pressed(mb_right)) {
            // Mute the raw press so Interact and anything else bound to
            // right mouse stays silent until we decide what this click is.
            var _idx = array_index(MOUSE_BUTTONS, mb_right);
            INPUT.raw_mouse[_idx] = set_flag(INPUT.raw_mouse[_idx], DigitalStatus.Muted);

            // Initial pace from where the cursor starts.
            _rt.running = point_distance(obj_ari.x, obj_ari.y, mouse_x(), mouse_y())
                > (_cfg.walk_within_px + _cfg.run_beyond_px) * 0.5;
        }

        // Held past the threshold: steer toward the cursor.
        if (_rt.hold_frames > _cfg.steer_start_seconds * FPS) {
            var _mx = mouse_x();
            var _my = mouse_y();
            var _dist = point_distance(obj_ari.x, obj_ari.y, _mx, _my);

            // An explicit Walk input wins over automatic pacing. Otherwise,
            // hysteresis avoids a single distance boundary to flicker across.
            if (INPUT.check(InputId.Walk)) {
                _rt.running = false;
            } else {
                if (_dist <= _cfg.walk_within_px) {
                    _rt.running = false;
                } else if (_dist >= _cfg.run_beyond_px) {
                    _rt.running = true;
                }
            }

            // A tap-walk in progress hands over to steering.
            if (_in_our_path) {
                __arpg_movement_stop_walk(_rt);
            }

            // Swim and MountDefault read movement through the same binding
            // path and pick their own speed and animation.
            if ((_in_default || _in_swim || _in_mount) && _dist > _cfg.stop_within_px) {
                // The virtual stick: the player's movement code reads this
                // through the default left_stick bindings and does the rest
                // (collision sliding, facing, animation) exactly as vanilla.
                INPUT.gp_left_stick.x = (_mx - obj_ari.x) / _dist;
                INPUT.gp_left_stick.y = (_my - obj_ari.y) / _dist;
                INPUT.gp_left_mag = 1;

                if (!_rt.running) {
                    __arpg_movement_hold_walk_binding();
                }
            }
        }
    } else {
        if (mouse_check_button_released(mb_right) && _rt.hold_frames > 0) {
            if (_rt.hold_frames <= _cfg.tap_seconds * FPS) {
                // This is a click-release grace window, not a hard split
                // between tapping and steering: short holds may have already
                // steered responsively before committing to pathfinding.
                var _tx = mouse_x();
                var _ty = mouse_y();
                if (_in_mount) {
                    // Mounted taps never enter the on-foot Pathfind state.
                    // Return the muted press so mounted interaction remains
                    // exactly vanilla regardless of cursor distance.
                    var _mount_idx = array_index(MOUSE_BUTTONS, mb_right);
                    INPUT.raw_mouse[_mount_idx] = set_flag(INPUT.raw_mouse[_mount_idx], DigitalStatus.Pressed);
                    INPUT.raw_mouse[_mount_idx] = remove_flag(INPUT.raw_mouse[_mount_idx], DigitalStatus.Muted);
                } else if (point_distance(obj_ari.x, obj_ari.y, _tx, _ty) > _cfg.interact_radius_px) {
                    // Tap on open ground: pathfind there. Not while swimming —
                    // the grid doesn't path over water and the Pathfind state
                    // would walk on it.
                    _rt.running = !INPUT.check(InputId.Walk);
                    if (!_in_swim && __arpg_movement_path_to(_tx, _ty) && _cfg.click_marker) {
                        create_animation_effect(_tx, _ty, -100000, spr_fx_poof1_essence_once);
                    }
                } else {
                    // Tap next to the player: give the press back so the vanilla
                    // Interact fires this frame.
                    var _idx2 = array_index(MOUSE_BUTTONS, mb_right);
                    INPUT.raw_mouse[_idx2] = set_flag(INPUT.raw_mouse[_idx2], DigitalStatus.Pressed);
                    INPUT.raw_mouse[_idx2] = remove_flag(INPUT.raw_mouse[_idx2], DigitalStatus.Muted);
                }
            }
            // A steering hold that ends needs no cleanup: the moment the
            // stick stops being injected, the player stops.
        }
        __arpg_movement_reset(_rt);
    }
}

// The latched register function. Boot can re-run, this registers exactly once.
function arpg_movement_register_callbacks() {
    var _rt = __arpg_movement_runtime();
    if (_rt.registered_hooks != undefined) return;
    _rt.registered_hooks = true;

    mmapi_on("game.clock_tick", arpg_movement_clock_tick);
}

// Boot wiring: memory-only top level.
mmapi_mod_declare("arpg_movement", "1.0.1");
arpg_movement_register_callbacks();
