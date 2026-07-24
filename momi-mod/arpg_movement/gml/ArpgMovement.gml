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
//   When `click_to_interact` is enabled, tapping a distant interactable paths
//   to its nearest reachable side and performs the vanilla interaction on
//   arrival. Releases near the player re-inject the press instead, so normal
//   tap-to-interact still works.
// - The raw right-button press is muted the moment it lands, so Interact
//   (and anything else bound to right mouse) never fires during a hold.
// - WASD, jump, tool use, E, or Esc cancel a mouse-driven walk instantly.
// - Steering also works while swimming and mounted. Taps don't pathfind in
//   either case; mounted taps are handed back to vanilla Interact.
// - F6 toggles action-item auto-selection. When enabled and left mouse is
//   bound to a vanilla tool-use action, a nearby clicked rock, tree/stump, or
//   dig site selects its usable inventory tool before vanilla consumes that
//   same click. Other world clicks select an inventory weapon only in mines.
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
            interact_target: undefined,
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
        click_to_interact: mmapi_config_bool(_source, "click_to_interact", true),
        click_marker: mmapi_config_bool(_source, "click_marker", true),
        invalid_click_marker: mmapi_config_bool(_source, "invalid_click_marker", true),
        auto_select_action_item: mmapi_config_bool(_source, "auto_select_action_item", true),
    };
    mmapi_config_write("arpg_movement", ARPG_MOVEMENT_CONFIG_VERSION, _rt.cfg);
    return _rt.cfg;
}

function __arpg_movement_reset(_rt) {
    _rt.hold_frames = 0;
}

function __arpg_movement_clear_interact(_rt) {
    _rt.interact_target = undefined;
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

// Returns the interaction geometry used by vanilla target selection.
function __arpg_movement_interact_bounds(_target) {
    switch (_target.interactable_mode) {
        case InteractableMode.Circle:
            var _cx = _target.x;
            var _cy = _target.y;
            if (_target.offset_with_cardinal) {
                switch (_target.animator.cardinality) {
                    case Cardinal.East:  _cx += _target.interact_nudge_distance; break;
                    case Cardinal.West:  _cx -= _target.interact_nudge_distance; break;
                    case Cardinal.South: _cy += _target.interact_nudge_distance; break;
                    case Cardinal.North: _cy -= _target.interact_nudge_distance; break;
                }
            }
            var _radius = max(_target.circle_size, 1);
            return {
                left: _cx - _radius,
                top: _cy - _radius,
                right: _cx + _radius,
                bottom: _cy + _radius,
                center_x: _cx,
                center_y: _cy,
            };

        case InteractableMode.Bbox:
            var _old_mask = undefined;
            if (_target.override_mask != undefined) {
                _old_mask = _target.mask_index;
                _target.mask_index = _target.override_mask;
            }
            var _bounds = {
                left: _target.bbox_left,
                top: _target.bbox_top,
                right: _target.bbox_right,
                bottom: _target.bbox_bottom,
                center_x: (_target.bbox_left + _target.bbox_right) * 0.5,
                center_y: (_target.bbox_top + _target.bbox_bottom) * 0.5,
            };
            if (_old_mask != undefined) {
                _target.mask_index = _old_mask;
            }
            return _bounds;

        case InteractableMode.Box:
            return {
                left: _target.interaction_center.x - _target.interaction_half_size.x,
                top: _target.interaction_center.y - _target.interaction_half_size.y,
                right: _target.interaction_center.x + _target.interaction_half_size.x,
                bottom: _target.interaction_center.y + _target.interaction_half_size.y,
                center_x: _target.interaction_center.x,
                center_y: _target.interaction_center.y,
            };
    }
    return undefined;
}

// Distance from a point to the target's vanilla interaction shape.
function __arpg_movement_distance_to_interact(_target, _x, _y) {
    var _bounds = __arpg_movement_interact_bounds(_target);
    if (_bounds == undefined) return infinity;

    if (_target.interactable_mode == InteractableMode.Circle) {
        return max(point_distance(_x, _y, _bounds.center_x, _bounds.center_y)
            - _target.circle_size, 0);
    }

    var _dx = max(abs(_x - _bounds.center_x) - (_bounds.right - _bounds.left) * 0.5, 0);
    var _dy = max(abs(_y - _bounds.center_y) - (_bounds.bottom - _bounds.top) * 0.5, 0);
    return sqrt(_dx * _dx + _dy * _dy);
}

// Finds the closest live interactable whose interaction shape or visible
// collision bounds contain the click.
function __arpg_movement_interactable_at(_x, _y) {
    var _best = undefined;
    var _best_distance = infinity;

    for (var _i = 0; _i < INTERACTABLES.count(); _i++) {
        var _candidate = INTERACTABLES.get(_i);
        if (_candidate == undefined
            || !instance_exists(_candidate)
            || !_candidate.has_potential_interactions())
        {
            continue;
        }

        var _bounds = __arpg_movement_interact_bounds(_candidate);
        if (_bounds == undefined) continue;

        var _hit = _x >= _bounds.left - 2
            && _x <= _bounds.right + 2
            && _y >= _bounds.top - 2
            && _y <= _bounds.bottom + 2;

        // Circle-mode objects include NPCs. Their interaction circle is at
        // their feet, so also accept clicks on their visible collision bounds.
        if (!_hit && _candidate.interactable_mode == InteractableMode.Circle) {
            _hit = _x >= _candidate.bbox_left - 2
                && _x <= _candidate.bbox_right + 2
                && _y >= _candidate.bbox_top - 2
                && _y <= _candidate.bbox_bottom + 2;
        }

        if (_hit) {
            var _distance = point_distance(_x, _y, _bounds.center_x, _bounds.center_y);
            if (_distance < _best_distance) {
                _best = _candidate;
                _best_distance = _distance;
            }
        }
    }

    return _best;
}

// Faces a target and interacts only if vanilla selects that exact target.
// This prevents a path from activating a neighboring object after the clicked
// target moved or disappeared.
function __arpg_movement_try_interact(_target) {
    if (_target == undefined || !instance_exists(_target)) return false;

    var _bounds = __arpg_movement_interact_bounds(_target);
    if (_bounds == undefined) return false;

    obj_ari.face_dir(point_direction(
        obj_ari.x,
        obj_ari.y,
        _bounds.center_x,
        _bounds.center_y
    ));

    var _selection = find_nearest_interactable(obj_ari.collision_list, obj_ari);
    if (_selection != _target) return false;

    var _callback = _target.attempt_interact(true);
    if (_callback == undefined) return false;
    _callback();
    return true;
}

// Calculates reachable grid-cell centers around the target and returns the
// shortest candidate from which vanilla considers the target in range.
function __arpg_movement_plan_interact(_target) {
    var _bounds = __arpg_movement_interact_bounds(_target);
    if (_bounds == undefined) return undefined;

    var _left_cell = floor(_bounds.left / 8) - 1;
    var _right_cell = floor(_bounds.right / 8) + 1;
    var _top_cell = floor(_bounds.top / 8) - 1;
    var _bottom_cell = floor(_bounds.bottom / 8) + 1;
    var _candidates = [];

    for (var _gy = _top_cell + 1; _gy < _bottom_cell; _gy++) {
        array_push(_candidates, [_left_cell * 8 + 4, _gy * 8 + 4]);
        array_push(_candidates, [_right_cell * 8 + 4, _gy * 8 + 4]);
    }
    for (var _gx = _left_cell + 1; _gx < _right_cell; _gx++) {
        array_push(_candidates, [_gx * 8 + 4, _top_cell * 8 + 4]);
        array_push(_candidates, [_gx * 8 + 4, _bottom_cell * 8 + 4]);
    }

    // Corners are useful when furniture is tight against a wall.
    array_push(_candidates, [_left_cell * 8 + 4, _top_cell * 8 + 4]);
    array_push(_candidates, [_right_cell * 8 + 4, _top_cell * 8 + 4]);
    array_push(_candidates, [_left_cell * 8 + 4, _bottom_cell * 8 + 4]);
    array_push(_candidates, [_right_cell * 8 + 4, _bottom_cell * 8 + 4]);

    var _best = undefined;
    var _best_distance = infinity;
    for (var _j = 0; _j < array_length(_candidates); _j++) {
        var _pos = _candidates[_j];
        var _px = _pos[0];
        var _py = _pos[1];
        var _dx = _bounds.center_x - _px;
        var _dy = _bounds.center_y - _py;
        var _probe_x = _px;
        var _probe_y = _py;

        if (abs(_dx) > abs(_dy)) {
            _probe_x += sign(_dx) * obj_ari.interact_nudge_distance;
        } else {
            _probe_y += sign(_dy) * obj_ari.interact_nudge_distance;
        }

        if (__arpg_movement_distance_to_interact(_target, _probe_x, _probe_y)
            > obj_ari.interact_max_radius)
        {
            continue;
        }

        var _path_data = PATHFINDING.calculate_local_path(
            obj_ari.x,
            obj_ari.y,
            _px,
            _py,
            true
        );
        if (_path_data != undefined && _path_data.distance < _best_distance) {
            _best = {
                x: _px,
                y: _py,
                path_data: _path_data,
            };
            _best_distance = _path_data.distance;
        }
    }

    return _best;
}

// True only when the physical left mouse button is one of the player's
// configured vanilla tool-use bindings. LeftMouse itself is also bound to the
// button for UI use and is intentionally not enough to enable this feature.
function __arpg_movement_left_is_action() {
    var _inputs = [InputId.UseToolCharged, InputId.UseToolRepeated];
    for (var _i = 0; _i < array_length(_inputs); _i++) {
        var _bindings = BINDINGS.bindings[_inputs[_i]];
        for (var _j = 0; _j < array_length(_bindings); _j++) {
            var _binding = _bindings[_j];
            if (_binding != undefined
                && _binding.type == BindingType.Mouse
                && _binding.keycode == mb_left)
            {
                return true;
            }
        }
    }
    return false;
}

// Mirrors the ordinary mouse-target branch of obj_ari.update_cell_select().
// Tool actions use the returned 2x2 cell, so validating against it guarantees
// that the same click which changes tools can actually affect the clicked node.
function __arpg_movement_consider_mouse_cell(_x_offset, _y_offset, _bundle) {
    var _candidate_x = _bundle.norm_x + _x_offset * 16;
    var _candidate_y = _bundle.norm_y + _y_offset * 16;
    var _dx = _candidate_x - _bundle.mouse_x;
    var _dy = _candidate_y - _bundle.mouse_y;
    var _score = _dx * _dx + _dy * _dy;
    if (_score < _bundle.best_score) {
        _bundle.best_score = _score;
        _bundle.best_x = _candidate_x;
        _bundle.best_y = _candidate_y;
    }
}

function __arpg_movement_mouse_cell_select() {
    var _base_x = obj_ari.x % 16;
    var _base_y = obj_ari.y % 16;
    var _bundle = {
        norm_x: 16 * (obj_ari.x div 16),
        norm_y: 16 * (obj_ari.y div 16),
        mouse_x: mouse_x() - 8,
        mouse_y: mouse_y() - 8,
        best_x: obj_ari.x,
        best_y: obj_ari.y,
        best_score: infinity,
    };

    for (var _xx = -1; _xx < 2; _xx++) {
        for (var _yy = -1; _yy < 2; _yy++) {
            __arpg_movement_consider_mouse_cell(_xx, _yy, _bundle);
        }
    }

    switch (obj_ari.cardinal) {
        case Cardinal.West:
            if (_base_x < 8) {
                __arpg_movement_consider_mouse_cell(-2, 0, _bundle);
                __arpg_movement_consider_mouse_cell(-2, _base_y < 8 ? -1 : 1, _bundle);
            }
            break;
        case Cardinal.East:
            if (_base_x >= 8) {
                __arpg_movement_consider_mouse_cell(2, 0, _bundle);
                __arpg_movement_consider_mouse_cell(2, _base_y < 8 ? -1 : 1, _bundle);
            }
            break;
        case Cardinal.North:
            if (_base_y < 8) {
                __arpg_movement_consider_mouse_cell(0, -2, _bundle);
                __arpg_movement_consider_mouse_cell(_base_x < 8 ? -1 : 1, -2, _bundle);
            }
            break;
        case Cardinal.South:
            if (_base_y >= 8) {
                __arpg_movement_consider_mouse_cell(0, 2, _bundle);
                __arpg_movement_consider_mouse_cell(_base_x < 8 ? -1 : 1, 2, _bundle);
            }
            break;
    }

    return {
        x: _bundle.best_x div 8,
        y: _bundle.best_y div 8,
    };
}

// Visible node sprites extend beyond their grid footprint (especially trees),
// so prefer the renderer under the cursor and fall back to the raw grid cell.
function __arpg_movement_clicked_node() {
    var _renderer = overlap_point(mouse_x(), mouse_y(), obj_node_renderer);
    if (_renderer != undefined
        && instance_exists(_renderer)
        && _renderer.node != undefined)
    {
        return _renderer.node;
    }

    var _ni = GRID.try_node_index_for_room_position(mouse_x(), mouse_y());
    if (_ni != undefined) {
        return GRID.node_parent[_ni];
    }
    return undefined;
}

function __arpg_movement_item_matches(_item, _use, _tool_type=undefined, _minimum_quality=undefined) {
    if (_item == undefined || _item.prototype.use != _use) return false;
    if (_tool_type != undefined && _item.prototype.tool_type != _tool_type) return false;
    if (_minimum_quality != undefined && _item.prototype.quality < _minimum_quality) return false;
    return true;
}

// Keeps a suitable current selection when possible, otherwise searches every
// inventory page in stable slot order.
function __arpg_movement_find_item(_use, _tool_type=undefined, _minimum_quality=undefined) {
    var _held = ARI.held_item();
    if (__arpg_movement_item_matches(_held, _use, _tool_type, _minimum_quality)) {
        return ARI.held_item_index;
    }

    for (var _i = 0; _i < ARI.inventory.size(); _i++) {
        var _item = ARI.inventory.slot(_i).item;
        if (__arpg_movement_item_matches(_item, _use, _tool_type, _minimum_quality)) {
            return _i;
        }
    }
    return undefined;
}

// ARI changes the selected slot and cursor. It deliberately leaves toolbar
// page ownership to callers, so an automatic cross-page selection must update
// the visible page too.
function __arpg_movement_select_item(_index) {
    if (_index == undefined) return false;
    if (ARI.held_item_index == _index) return true;
    if (!ARI.set_held_item_index(_index)) return false;

    var _toolbar = ANCHOR.get_menu(Menu.Toolbar);
    if (_toolbar != undefined) {
        var _page = _index div 10;
        if (_toolbar.page != _page) {
            _toolbar.page = _page;
            _toolbar.update();
        }
    }
    return true;
}

function __arpg_movement_tool_reaches_node(_node, _item) {
    var _selection = __arpg_movement_mouse_cell_select();
    for (var _xx = 0; _xx < 2; _xx++) {
        for (var _yy = 0; _yy < 2; _yy++) {
            var _cell_x = _selection.x + _xx;
            var _cell_y = _selection.y + _yy;
            var _ni = GRID.try_node_index_for_cell(_cell_x, _cell_y);
            if (_ni != undefined
                && GRID.node_parent[_ni] == _node
                && GRID.item_effects_node_at_cell(_cell_x, _cell_y, _item.prototype))
            {
                return true;
            }
        }
    }
    return false;
}

// Selects the item before AriFsm's Default step reads this frame's unchanged
// left-button press. Recognized tool targets never fall back to a weapon when
// the required tool is absent, inadequate, or out of range.
function __arpg_movement_auto_select_action_item() {
    if (!mouse_check_button_pressed(mb_left)
        || !__arpg_movement_left_is_action()
        || ARI.held_animal_id != undefined)
    {
        return;
    }

    // Anchor consumes HUD clicks later in the frame. Its hover remains live
    // here, early enough to avoid selecting an item behind the toolbar.
    if (ANCHOR.current_hovered_node != undefined) return;

    var _node = __arpg_movement_clicked_node();
    if (_node != undefined) {
        var _category = object_id_to_object_category(_node.object_id);
        var _tool_type = undefined;
        var _minimum_quality = undefined;

        switch (_category) {
            case ObjectCategory.Rock:
                _tool_type = ToolType.PickAxe;
                _minimum_quality = _node.prototype.minimum_quality;
                break;
            case ObjectCategory.Tree:
            case ObjectCategory.Stump:
                _tool_type = ToolType.Axe;
                _minimum_quality = _node.prototype.minimum_quality;
                break;
            case ObjectCategory.DigSite:
                _tool_type = ToolType.Shovel;
                break;
        }

        if (_tool_type != undefined) {
            var _tool_index = __arpg_movement_find_item(ItemUse.UseTool, _tool_type, _minimum_quality);
            if (_tool_index == undefined) return;

            var _tool = ARI.inventory.slot(_tool_index).item;
            if (!__arpg_movement_tool_reaches_node(_node, _tool)) return;
            __arpg_movement_select_item(_tool_index);
            return;
        }
    }

    // Outside the mines, ambiguous clicks preserve the user's farming,
    // placement, or other current selection.
    if (is_dungeon_room(room())) {
        __arpg_movement_select_item(__arpg_movement_find_item(ItemUse.Attack));
    }
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

// F6 is registered through MMAPI so conflicts with other mods are diagnosed
// in one place instead of competing through independent raw-key polling.
function arpg_movement_toggle_auto_select() {
    if (!instance_exists(obj_ari) || game_paused()) return;

    var _cfg = arpg_movement_config();
    if (!_cfg.enabled) return;

    _cfg.auto_select_action_item = !_cfg.auto_select_action_item;
    mmapi_config_write("arpg_movement", ARPG_MOVEMENT_CONFIG_VERSION, _cfg);
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

    if (!_cfg.enabled || game_paused()) {
        __arpg_movement_reset(_rt);
        return;
    }

    if (ON_GAMEPAD) {
        __arpg_movement_reset(_rt);
        return;
    }

    var _sid = obj_ari.fsm.current_state_id();
    if (_sid != PlayerState.Pathfind && _rt.pathfinding) {
        _rt.pathfinding = false;

        // Pathfind returns to Default on natural completion. Finish a queued
        // smart interaction only when vanilla still selects the same target.
        if (_rt.interact_target != undefined) {
            var _finished_target = _rt.interact_target;
            __arpg_movement_clear_interact(_rt);
            if (_sid == PlayerState.Default
                && !__arpg_movement_try_interact(_finished_target)
                && _cfg.invalid_click_marker
                && instance_exists(_finished_target))
            {
                var _failed_bounds = __arpg_movement_interact_bounds(_finished_target);
                if (_failed_bounds != undefined) {
                    __arpg_movement_show_marker(
                        _failed_bounds.center_x,
                        _failed_bounds.center_y,
                        false
                    );
                }
            }
        }
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

    if (_in_default && _cfg.auto_select_action_item) {
        __arpg_movement_auto_select_action_item();
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
                        if (!__arpg_movement_try_interact(_target)) {
                            var _plan = __arpg_movement_plan_interact(_target);
                            if (_plan != undefined) {
                                _rt.interact_target = _target;
                                if (__arpg_movement_path_to(
                                    _plan.x,
                                    _plan.y,
                                    _plan.path_data
                                )) {
                                    if (_cfg.click_marker) {
                                        __arpg_movement_show_marker(_tx, _ty, true);
                                    }
                                } else {
                                    __arpg_movement_clear_interact(_rt);
                                    if (_cfg.invalid_click_marker) {
                                        __arpg_movement_show_marker(_tx, _ty, false);
                                    }
                                }
                            } else if (_cfg.invalid_click_marker) {
                                __arpg_movement_show_marker(_tx, _ty, false);
                            }
                        }
                    } else if (point_distance(obj_ari.x, obj_ari.y, _tx, _ty)
                        > _cfg.interact_radius_px)
                    {
                        // Open ground uses the original tap path. Swimming has
                        // no valid local path and receives failure feedback.
                        __arpg_movement_clear_interact(_rt);
                        if (!_in_swim && __arpg_movement_path_to(_tx, _ty)) {
                            if (_cfg.click_marker) {
                                __arpg_movement_show_marker(_tx, _ty, true);
                            }
                        } else if (_cfg.invalid_click_marker) {
                            __arpg_movement_show_marker(_tx, _ty, false);
                        }
                    } else {
                        // A nearby ground tap is handed back so the game's
                        // ordinary facing-based Interact selection runs.
                        var _idx2 = array_index(MOUSE_BUTTONS, mb_right);
                        INPUT.raw_mouse[_idx2] = set_flag(INPUT.raw_mouse[_idx2], DigitalStatus.Pressed);
                        INPUT.raw_mouse[_idx2] = remove_flag(INPUT.raw_mouse[_idx2], DigitalStatus.Muted);
                    }
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

    var _f6 = mmapi_hotkey_vk_from_name("F6");
    if (_f6 != undefined) {
        mmapi_hotkey_register(_f6, arpg_movement_toggle_auto_select);
    }
}

// Boot wiring: memory-only top level.
mmapi_mod_declare("arpg_movement", "2.0.0");
arpg_movement_register_callbacks();
