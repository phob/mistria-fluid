// ARPG Movement: pathfinding, steering, and the frame heartbeat

// Any discrete player command that needs direct control of Ari cancels the
// mod-owned Pathfind state before vanilla processes the same input. Walk is the
// sole exception: it is a speed modifier, not an action or destination change.
function __arpg_movement_path_cancel_requested() {
    var _inputs = [
        InputId.LeftMouse,
        InputId.Jump,
        InputId.Interact,
        InputId.SecondaryInteract,
        InputId.PickUpOne,
        InputId.OpenJournal,
        InputId.MenuBack,
        InputId.UseToolCharged,
        InputId.UseToolRepeated,
        InputId.CastPinnedSpell,
        InputId.Throw,
        InputId.Ride,
        InputId.OpenMapMenu,
        InputId.MenuTabRight,
        InputId.MenuTabLeft,
        InputId.NextPreset,
        InputId.LastPreset,
        InputId.ToolbarIncUp,
        InputId.ToolbarIncDown,
        InputId.RotateRight,
        InputId.RotateLeft,
        InputId.FurnitureUp,
        InputId.FurnitureDown,
        InputId.FurnitureLeft,
        InputId.FurnitureRight,
        InputId.NextToolbarTab,
        InputId.LastToolbarTab,
        InputId.SelectToolbarOne,
        InputId.SelectToolbarTwo,
        InputId.SelectToolbarThree,
        InputId.SelectToolbarFour,
        InputId.SelectToolbarFive,
        InputId.SelectToolbarSix,
        InputId.SelectToolbarSeven,
        InputId.SelectToolbarEight,
        InputId.SelectToolbarNine,
        InputId.SelectToolbarZero,
        InputId.ConfirmTextInput,
        InputId.ResetControls,
    ];

    for (var _i = 0; _i < array_length(_inputs); _i++) {
        if (INPUT.pressed(_inputs[_i])) return true;
    }
    return false;
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

// Pathfind consumes its waypoints with no collision testing, so a path
// segment crossing open water would carry Ari over the surface on foot — a
// move the player can never make. Vanilla treats a node as swimmable water
// when its terrain kind is Water (bridges keep their own terrain kind and
// stay walkable). The waypoint list holds the destination first and Ari's
// start last; sampling every segment at half-node steps visits each 8px node
// a segment can touch.
function __arpg_movement_path_crosses_water(_path_data) {
    var _list = _path_data.output_list;
    var _prev = undefined;
    for (var _i = 0; _i < _list.count(); _i++) {
        var _point = _list.get(_i);
        var _steps = 1;
        if (_prev != undefined) {
            _steps = max(1, ceil(
                point_distance(_prev.x, _prev.y, _point.x, _point.y) / 4
            ));
        }
        for (var _s = 1; _s <= _steps; _s++) {
            var _t = _s / _steps;
            var _ni = GRID.try_node_index_for_room_position(
                _prev == undefined ? _point.x : lerp(_prev.x, _point.x, _t),
                _prev == undefined ? _point.y : lerp(_prev.y, _point.y, _t)
            );
            if (_ni != undefined
                && GRID.node_terrain_kind[_ni] == TerrainKind.Water)
            {
                return true;
            }
        }
        _prev = _point;
    }
    return false;
}

// Starts (or retargets) a Pathfind walk toward a position (used by taps).
// A precomputed path lets smart interactions rank several approach points
// without calculating the winning path twice. Returns false when none exists.
function __arpg_movement_path_to(_x, _y, _path_data=undefined) {
    var _rt = __arpg_movement_runtime();

    // Pathfind moves Ari directly along its waypoint list without collision
    // checks. Hyperpath can still return a path for an out-of-room cursor
    // position, which lets Ari skip a door transition and eventually indexes
    // GRID outside its dimensions. Reject both endpoints before making an
    // itinerary; the caller will show the normal invalid-click marker.
    if (GRID.try_node_index_for_room_position(obj_ari.x, obj_ari.y) == undefined
        || GRID.try_node_index_for_room_position(_x, _y) == undefined)
    {
        return false;
    }

    if (_path_data == undefined) {
        _path_data = PATHFINDING.calculate_local_path(obj_ari.x, obj_ari.y, _x, _y, true);
    }
    if (_path_data == undefined) return false;

    // The grid only blocks collideable nodes, so open water is path-legal
    // even though the player cannot walk it. Refuse rather than surface-walk.
    if (__arpg_movement_path_crosses_water(_path_data)) return false;

    // Walk speed or full run speed with the engine's buffs applied.
    var _old_toggle = ARI.run_toggle;
    ARI.run_toggle = _rt.running;
    var _spd = ARI.get_move_speed();
    ARI.run_toggle = _old_toggle;

    var _itinerary = new Itinerary(List(new ItineraryItem(
        new LocationPosition(CURRENT_LOCATION_ID, Vec2(obj_ari.x, obj_ari.y)),
        new LocationPosition(CURRENT_LOCATION_ID, Vec2(_x, _y)),
        0,
        _path_data.output_list
    )));

    // Retarget an active tap-walk without restarting Pathfind. Its normal
    // start callback snaps to the path's final list item: Ari's current
    // position. The next step then spends one frame consuming that already
    // reached waypoint with zero movement, which becomes a visible stutter
    // when right click is tapped repeatedly.
    //
    // The path list is consumed from the end (destination first, start last).
    // Install the replacement directly and discard only that reached start
    // item, allowing this frame's Pathfind step to move toward the next point.
    if (obj_ari.fsm.current_state_id() == PlayerState.Pathfind
        && _rt.pathfinding
        && obj_ari.fsm.next_state == undefined)
    {
        var _state = obj_ari.fsm.current_state();
        _state.pathfinding_agent.set_path(_itinerary, 0);

        var _remaining = _state.pathfinding_agent.todo_list();
        if (_remaining.count() > 1) {
            _remaining.pop();
        }

        _state.move_accel = Vec2(_spd, _spd);
        _state.animation = _rt.running ? AnimationName.Run : AnimationName.Walk;
        return true;
    }

    obj_ari.fsm.blackboard.set("itinerary", _itinerary);
    obj_ari.fsm.blackboard.set("move_accel", Vec2(_spd, _spd));
    obj_ari.fsm.blackboard.set("use_run_animation", _rt.running);
    obj_ari.fsm.blackboard.set("end_state", PlayerState.Default);
    obj_ari.fsm.change_state(PlayerState.Pathfind);
    _rt.pathfinding = true;
    return true;
}

function __arpg_movement_remember_interact_plan(_rt, _target, _plan) {
    var _bounds = __arpg_movement_interact_bounds(_target);
    if (_bounds == undefined) return;

    _rt.interact_target = _target;
    _rt.interact_target_x = _bounds.center_x;
    _rt.interact_target_y = _bounds.center_y;
    _rt.interact_end_x = _plan.x;
    _rt.interact_end_y = _plan.y;
    _rt.interact_repath_frames = 0;
}

function __arpg_movement_fail_interact_walk(_rt, _cfg, _x, _y) {
    if (obj_ari.fsm.current_state_id() == PlayerState.Pathfind && _rt.pathfinding) {
        __arpg_movement_stop_walk(_rt);
    } else {
        _rt.pathfinding = false;
        __arpg_movement_clear_interact(_rt);
    }
    if (_cfg.invalid_click_marker && _x != undefined && _y != undefined) {
        __arpg_movement_show_marker(_x, _y, false);
    }
}

// Follow a moving interaction target without the rapid two-point retarget loop
// that made ordinary steering jitter. Replan at most five times per second and
// only after the target moved a grid cell or invalidated the chosen endpoint.
function __arpg_movement_update_interact_path(_rt, _cfg) {
    var _target = _rt.interact_target;
    if (_target == undefined) return false;

    if (!__arpg_movement_target_is_actionable(_target)) {
        __arpg_movement_fail_interact_walk(
            _rt,
            _cfg,
            _rt.interact_target_x,
            _rt.interact_target_y
        );
        return true;
    }

    var _bounds = __arpg_movement_interact_bounds(_target);
    if (_bounds == undefined) {
        __arpg_movement_fail_interact_walk(
            _rt,
            _cfg,
            _rt.interact_target_x,
            _rt.interact_target_y
        );
        return true;
    }

    _rt.interact_repath_frames += 1;
    var _moved = point_distance(
        _rt.interact_target_x,
        _rt.interact_target_y,
        _bounds.center_x,
        _bounds.center_y
    ) >= 8;
    var _endpoint_invalid = __arpg_movement_distance_to_interact(
        _target,
        _rt.interact_end_x,
        _rt.interact_end_y
    ) > obj_ari.interact_max_radius;

    if ((!_moved && !_endpoint_invalid)
        || _rt.interact_repath_frames < max(1, 0.2 * FPS))
    {
        return false;
    }

    var _plan = __arpg_movement_plan_interact(_target);
    if (_plan == undefined) {
        __arpg_movement_fail_interact_walk(
            _rt,
            _cfg,
            _bounds.center_x,
            _bounds.center_y
        );
        return true;
    }

    __arpg_movement_remember_interact_plan(_rt, _target, _plan);
    if (!__arpg_movement_path_to(_plan.x, _plan.y, _plan.path_data)) {
        __arpg_movement_fail_interact_walk(
            _rt,
            _cfg,
            _bounds.center_x,
            _bounds.center_y
        );
        return true;
    }
    return false;
}

// The toggle hotkey (config `auto_select_hotkey`, default F6) is registered
// through MMAPI so conflicts with other mods are diagnosed in one place
// instead of competing through independent raw-key polling.
function arpg_movement_toggle_auto_select() {
    if (!instance_exists(obj_ari) || game_paused()) return;

    var _cfg = arpg_movement_config();
    if (!_cfg.enabled) return;

    _cfg.auto_select_action_item = !_cfg.auto_select_action_item;
    arpg_movement_config_save();
    __arpg_movement_log("hotkey: auto-select toggled "
        + (_cfg.auto_select_action_item ? "ON" : "OFF"));
    create_notification(ANCHOR.wrap_for_local(
        _cfg.auto_select_action_item
            ? "ARPG auto-select: ON"
            : "ARPG auto-select: OFF"
    ));
}

// The per-frame heartbeat. game.clock_tick fires in the game's step_begin,
// after INPUT.begin_frame() and before any object steps — early enough that
// everything injected below (mute, virtual stick, Walk binding) is in place
// before the player state reads its input for the frame.
function arpg_movement_clock_tick(_ctx) {
    if (!instance_exists(obj_ari)) return;

    var _rt = __arpg_movement_runtime();
    var _cfg = arpg_movement_config();

    __arpg_movement_sync_context(_rt);

    // Before any early return: the displacement this reads has to be a single
    // frame's worth to predict the next one.
    __arpg_movement_track_step(_rt);

    if (!_cfg.enabled) {
        if (obj_ari.fsm.current_state_id() == PlayerState.Pathfind
            && _rt.pathfinding)
        {
            __arpg_movement_stop_walk(_rt);
        } else {
            _rt.pathfinding = false;
            __arpg_movement_clear_interact(_rt);
        }
        __arpg_movement_reset(_rt);
        return;
    }

    if (_cfg.click_outside_closes_menus
        && __arpg_movement_try_close_menu_from_outside())
    {
        __arpg_movement_reset(_rt);
        return;
    }

    if (game_paused()) {
        if (obj_ari.fsm.current_state_id() == PlayerState.Pathfind
            && _rt.pathfinding)
        {
            __arpg_movement_stop_walk(_rt);
        }
        __arpg_movement_reset(_rt);
        return;
    }

    if (ON_GAMEPAD) {
        if (obj_ari.fsm.current_state_id() == PlayerState.Pathfind
            && _rt.pathfinding)
        {
            __arpg_movement_stop_walk(_rt);
        }
        __arpg_movement_reset(_rt);
        return;
    }

    var _sid = obj_ari.fsm.current_state_id();

    // A swing armed by the use guard last frame reads its target cell on a
    // later animation frame; deliver the corrected aim before the strike
    // lands. One-frame lifetime: if the use was vetoed or the state is not
    // the tool swing, the plan is stale and dropped.
    if (_rt.tool_retarget != undefined) {
        if (_sid == PlayerState.Tool) {
            var _tool_state = obj_ari.fsm.current_state();
            if (_tool_state != undefined
                && _tool_state[$ "target_pos"] != undefined)
            {
                _tool_state.target_pos.x = _rt.tool_retarget.x;
                _tool_state.target_pos.y = _rt.tool_retarget.y;
            }
        }
        _rt.tool_retarget = undefined;
    }

    if (_sid == PlayerState.Sword && _cfg.face_cursor_on_action) {
        __arpg_movement_aim_sword_combo();
    }

    if (_sid != PlayerState.Pathfind && _rt.pathfinding) {
        _rt.pathfinding = false;

        // Pathfind returns to Default on natural completion. Finish a queued
        // smart interaction only when vanilla still selects the same target.
        // If a moving target left the selected endpoint, immediately calculate
        // the next approach instead of treating a successful walk as failure.
        if (_rt.interact_target != undefined) {
            var _finished_target = _rt.interact_target;
            if (_sid == PlayerState.Default
                && __arpg_movement_try_interact(_finished_target))
            {
                __arpg_movement_clear_interact(_rt);
            } else if (_sid == PlayerState.Default
                && __arpg_movement_target_is_actionable(_finished_target))
            {
                var _retry_bounds = __arpg_movement_interact_bounds(_finished_target);
                var _target_moved = _retry_bounds != undefined
                    && point_distance(
                        _rt.interact_target_x,
                        _rt.interact_target_y,
                        _retry_bounds.center_x,
                        _retry_bounds.center_y
                    ) >= 8;
                var _endpoint_invalid = _retry_bounds != undefined
                    && __arpg_movement_distance_to_interact(
                        _finished_target,
                        _rt.interact_end_x,
                        _rt.interact_end_y
                    ) > obj_ari.interact_max_radius;

                if (_target_moved || _endpoint_invalid) {
                    var _retry_plan = __arpg_movement_plan_interact(_finished_target);
                    if (_retry_plan != undefined) {
                        __arpg_movement_remember_interact_plan(
                            _rt,
                            _finished_target,
                            _retry_plan
                        );
                        if (__arpg_movement_path_to(
                            _retry_plan.x,
                            _retry_plan.y,
                            _retry_plan.path_data
                        )) {
                            return;
                        }
                    }
                }
                if (_retry_bounds != undefined) {
                    __arpg_movement_fail_interact_walk(
                        _rt,
                        _cfg,
                        _retry_bounds.center_x,
                        _retry_bounds.center_y
                    );
                }
            } else {
                __arpg_movement_fail_interact_walk(
                    _rt,
                    _cfg,
                    _rt.interact_target_x,
                    _rt.interact_target_y
                );
            }
        }
    }
    var _in_default = _sid == PlayerState.Default;
    var _in_swim = _sid == PlayerState.Swim;
    var _in_mount = _sid == PlayerState.MountDefault;
    var _in_our_path = _sid == PlayerState.Pathfind && _rt.pathfinding;

    if (_in_our_path
        && _rt.interact_target != undefined
        && __arpg_movement_update_interact_path(_rt, _cfg))
    {
        __arpg_movement_reset(_rt);
        return;
    }

    // Tools, cutscenes, other mods' pathfinds: stay out.
    if (!_in_default && !_in_swim && !_in_mount && !_in_our_path) {
        __arpg_movement_reset(_rt);
        return;
    }

    var _right_down = mouse_check_button(mb_right);
    var _right_pressed = mouse_check_button_pressed(mb_right);

    // Which right-mouse features may act from the current state. Steering is
    // its own toggle; taps matter on foot when either tap feature is on
    // (mounted taps only ever return the press to vanilla). With neither
    // allowed, the press is never muted and right mouse is exactly vanilla.
    var _steer_allowed = _cfg.hold_to_steer
        && (!_cfg.mouse_move_mounted_only || _in_mount);
    var _tap_allowed = !_in_mount
        && !_cfg.mouse_move_mounted_only
        && (_cfg.tap_to_pathfind || _cfg.click_to_interact);

    // Mute the physical press before checking cancellation bindings below.
    // Interact is bound to right mouse by default; if an active tap-walk saw
    // that press first, it stopped the old path and produced a pause before
    // the release could retarget it. Other Interact bindings (such as E)
    // remain unmuted and still cancel mouse movement normally.
    if (_right_pressed && (_steer_allowed || _tap_allowed)) {
        __arpg_movement_mute_mouse_press(mb_right);
    } else if (_right_pressed) {
        __arpg_movement_log("press: right stays vanilla (no gesture allowed here)"
            + __arpg_movement_log_ctx());
    }

    if (_in_default) {
        // Facing first: which tile the game hands the tool depends on the
        // player's cardinal, so the selection below has to see the new facing
        // for the same reason vanilla's update_cell_select() will.
        if (_cfg.face_cursor_on_action) {
            __arpg_movement_face_cursor_for_action();
        }
        // Then targeting, so the selection below and the one vanilla makes for
        // itself later in the frame are reading the same cursor.
        if (_cfg.cursor_targeting_on_action) {
            __arpg_movement_keep_mouse_targeting();
        }
        if (_cfg.auto_select_action_item) {
            __arpg_movement_auto_select_action_item(_rt);
        }
    }

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
            __arpg_movement_log("path: cancelled by movement keys");
        }
        __arpg_movement_reset(_rt);
        return;
    }

    // Every discrete action, menu command, and toolbar change hands control
    // back to vanilla in the same frame.
    if (_in_our_path && __arpg_movement_path_cancel_requested())
    {
        __arpg_movement_stop_walk(_rt);
        __arpg_movement_log("path: cancelled by player command");
        __arpg_movement_reset(_rt);
        return;
    }

    // No feature may claim the button here (all gestures configured off, or
    // restricted to riding while on foot). The press above stayed unmuted, so
    // vanilla already handles it; a leftover mod path still finishes or gets
    // cancelled through the checks above.
    if (!_steer_allowed && !_tap_allowed) {
        __arpg_movement_reset(_rt);
        return;
    }

    if (_right_down) {
        _rt.hold_frames += 1;

        if (_right_pressed) {
            // Initial pace from where the cursor starts.
            _rt.running = point_distance(obj_ari.x, obj_ari.y, mouse_x(), mouse_y())
                > (_cfg.walk_within_px + _cfg.run_beyond_px) * 0.5;
        }

        // Held past the threshold: steer toward the cursor.
        if (_steer_allowed && _rt.hold_frames > _cfg.steer_start_seconds * FPS) {
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
                    __arpg_movement_log("tap: mounted, press handed back"
                        + __arpg_movement_log_ctx());
                } else {
                    _rt.running = !INPUT.check(InputId.Walk);

                    // Resolve an explicitly clicked target before applying the
                    // near-ground radius. This keeps smart interaction useful
                    // even when interact_radius_px is configured generously.
                    var _target = undefined;
                    if (_cfg.click_to_interact && !_in_swim) {
                        _target = __arpg_movement_interactable_at(_tx, _ty);
                    }

                    if (_target != undefined) {
                        // A tall sprite can be clicked while its interaction
                        // point is already in range. Avoid a pointless path.
                        if (__arpg_movement_try_interact(_target)) {
                            __arpg_movement_log("tap: direct interact "
                                + object_get_name(_target.object_index)
                                + __arpg_movement_log_ctx());
                        } else {
                            var _plan = __arpg_movement_plan_interact(_target);
                            if (_plan != undefined) {
                                __arpg_movement_remember_interact_plan(
                                    _rt,
                                    _target,
                                    _plan
                                );
                                if (__arpg_movement_path_to(
                                    _plan.x,
                                    _plan.y,
                                    _plan.path_data
                                )) {
                                    __arpg_movement_log("tap: interact path to "
                                        + string(_plan.x) + "," + string(_plan.y)
                                        + " for " + object_get_name(_target.object_index)
                                        + __arpg_movement_log_ctx());
                                    if (_cfg.click_marker) {
                                        __arpg_movement_show_marker(_tx, _ty, true);
                                    }
                                } else {
                                    __arpg_movement_log("tap: interact path refused for "
                                        + object_get_name(_target.object_index)
                                        + __arpg_movement_log_ctx());
                                    __arpg_movement_clear_interact(_rt);
                                    if (_cfg.invalid_click_marker) {
                                        __arpg_movement_show_marker(_tx, _ty, false);
                                    }
                                }
                            } else {
                                __arpg_movement_log("tap: interact unreachable for "
                                    + object_get_name(_target.object_index)
                                    + __arpg_movement_log_ctx());
                                if (_cfg.invalid_click_marker) {
                                    __arpg_movement_show_marker(_tx, _ty, false);
                                }
                            }
                        }
                    } else if (_cfg.tap_to_pathfind
                        && point_distance(obj_ari.x, obj_ari.y, _tx, _ty)
                            > _cfg.interact_radius_px)
                    {
                        // Open ground uses the original tap path. Swimming has
                        // no valid local path and receives failure feedback.
                        __arpg_movement_clear_interact(_rt);
                        if (!_in_swim && __arpg_movement_path_to(_tx, _ty)) {
                            __arpg_movement_log("tap: path to " + string(_tx) + ","
                                + string(_ty) + " run=" + string(_rt.running)
                                + __arpg_movement_log_ctx());
                            if (_cfg.click_marker) {
                                __arpg_movement_show_marker(_tx, _ty, true);
                            }
                        } else {
                            __arpg_movement_log("tap: path refused (water, swim, "
                                + "or unreachable)" + __arpg_movement_log_ctx());
                            if (_cfg.invalid_click_marker) {
                                __arpg_movement_show_marker(_tx, _ty, false);
                            }
                        }
                    } else {
                        // A nearby ground tap is handed back so the game's
                        // ordinary facing-based Interact selection runs.
                        var _idx2 = array_index(MOUSE_BUTTONS, mb_right);
                        INPUT.raw_mouse[_idx2] = set_flag(INPUT.raw_mouse[_idx2], DigitalStatus.Pressed);
                        INPUT.raw_mouse[_idx2] = remove_flag(INPUT.raw_mouse[_idx2], DigitalStatus.Muted);
                        __arpg_movement_log("tap: press handed back to vanilla"
                            + __arpg_movement_log_ctx());
                    }
                }
            }
            // A steering hold that ends needs no cleanup: the moment the
            // stick stops being injected, the player stops.
        }
        __arpg_movement_reset(_rt);
    }
}
