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
//   same click. Failing that, the watering can, hoe, or net is selected when
//   the game itself says that tool would act on the clicked tile, which covers
//   watering, tilling, and bug catching. A click the held item already acts on
//   is always left alone, so deliberate selections survive. Other world clicks
//   select an inventory weapon only in mines.
// - Action clicks keep aiming at the cursor while the player walks. Vanilla
//   gives up on mouse aiming as soon as a moving player stops nudging the
//   mouse, and silently falls back to the tile the player faces; the mod holds
//   mouse aiming until the player actually walks away from the cursor.
// - Clicking with a weapon or a tool turns the player toward the cursor first,
//   so swings, casts, and tool reach follow the mouse instead of whichever
//   direction the player last walked in. Facing keeps following the cursor for
//   as long as the action button is held, which aims every swing of a
//   repeating tool. Walking still wins: a movement key or a steering hold sets
//   the facing itself, exactly as in vanilla.
// - Left- or right-clicking outside the topmost normal closable menu closes
//   it. Dialogue, modal prompts, and menus with custom Back behavior stay out.
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

// Half a tile. Running is a fraction of this, so anything larger is a warp,
// a room transition, or a dismount rather than a step the player took.
#macro ARPG_MOVEMENT_MAX_STEP_PX 8

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
            last_x: undefined,
            last_y: undefined,
            step_x: 0,
            step_y: 0,
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
        face_cursor_on_action: mmapi_config_bool(_source, "face_cursor_on_action", true),
        cursor_targeting_on_action: mmapi_config_bool(_source, "cursor_targeting_on_action", true),
        click_outside_closes_menus: mmapi_config_bool(_source, "click_outside_closes_menus", true),
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

// True when the pointer is over any visible part owned by this menu. The
// menu's root canvas covers the whole UI area, so only its descendants count.
// BackgroundMenu hangs from ANCHOR.screen_canvas and has no source_menu.
function __arpg_movement_point_inside_menu(_menu) {
    for (var _i = 0; _i < ANCHOR.node_count; _i++) {
        var _node = ANCHOR.node_registrar[| _i];
        if (_node == undefined
            || _node == _menu.canvas
            || _node.freed
            || !_node.safe_enabled
            || _node.source_menu != _menu
            || _node.cache_alpha <= 0)
        {
            continue;
        }

        if (ANCHOR.point_in_node(_node, MOUSE_GUI_X, MOUSE_GUI_Y)) {
            return true;
        }
    }
    return false;
}

// Closes only the topmost modal menu that uses AnchorMenu's ordinary Back
// behavior. The Skills screen handles Back itself because its tier view has
// an internal back step, so an outside click mirrors that layered behavior.
// A non-closable modal above another menu blocks the search, so an outside
// click can never dismiss the obscured menu underneath it.
function __arpg_movement_try_close_menu_from_outside() {
    var _left_pressed = mouse_check_button_pressed(mb_left);
    var _right_pressed = mouse_check_button_pressed(mb_right);
    if ((!_left_pressed && !_right_pressed)
        || FOCUS.out_of_focus())
    {
        return false;
    }

    for (var _i = ANCHOR.open_menus.count() - 1; _i >= 0; _i--) {
        var _menu = ANCHOR.open_menus.get(_i);
        if (_menu.data.pause == PauseStatus.EMPTY) {
            continue;
        }

        // This is the topmost modal. Custom-exit menus (dialogue, prompts,
        // cutscene UI) deliberately stop here. DragonShrine is the Skills
        // screen and is the one safe custom-exit exception.
        var _allows_outside_close = _menu.listen_for_exit_flag
            || _menu.type == Menu.DragonShrine;
        if (_menu.close_requested
            || !_allows_outside_close
            || _menu.canvas == undefined
            || !_menu.canvas.is_unlocked()
            || __arpg_movement_point_inside_menu(_menu))
        {
            return false;
        }

        if (_menu.type == Menu.DragonShrine
            && _menu.state == DragonShrineState.TierScreen)
        {
            // Match the Skills screen's own Back action: return from a
            // category's tiers to the category list. Passing the menu
            // explicitly keeps the delayed transition callback independent
            // of whatever `self` is active when the chain reaches it.
            var _category = _menu.scroller.canvas.board_get("cat_key");
            _menu.transition(
                DragonShrineState.CategoryScreen,
                function(_skills_menu, _category_key) {
                    _skills_menu.create_category_nodes(_category_key);
                    _skills_menu.scroller.free();
                },
                [_menu, _category],
            );
        } else {
            // Category screen (and the Horse Shrine's single layer) mirrors
            // its own Back action by closing.
            _menu.close();
        }

        // Do not let the dismissing click reach UI or gameplay underneath.
        if (_left_pressed) {
            var _left_idx = array_index(MOUSE_BUTTONS, mb_left);
            INPUT.raw_mouse[_left_idx] = set_flag(
                INPUT.raw_mouse[_left_idx],
                DigitalStatus.Muted
            );
        }
        if (_right_pressed) {
            var _right_idx = array_index(MOUSE_BUTTONS, mb_right);
            INPUT.raw_mouse[_right_idx] = set_flag(
                INPUT.raw_mouse[_right_idx],
                DigitalStatus.Muted
            );
        }
        return true;
    }

    return false;
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

// Vanilla decides which tile a click acts on from inside the player's step: it
// moves the player first (AriFsm's move_ari) and selects the cell afterwards.
// This mod runs a step earlier, in game.clock_tick, where obj_ari still holds
// the pose the frame began with. Standing still the two agree exactly; walking,
// they differ by one frame of movement — enough to shift the 16px tile the
// candidate cells are anchored to, or to flip the 8px halves that decide how
// far the selection reaches. Either flip is a whole tile of disagreement, and
// the reason an action click could refuse to change tools while moving and
// never while still.
//
// The step just taken predicts the step about to be taken: the game applies
// speed instantly, so a heading only changes when the player changes it. Going
// through the actual displacement also covers collision sliding, sticky
// patches, and pathfinding for free.
function __arpg_movement_track_step(_rt) {
    if (_rt.last_x == undefined) {
        _rt.step_x = 0;
        _rt.step_y = 0;
    } else {
        _rt.step_x = obj_ari.x - _rt.last_x;
        _rt.step_y = obj_ari.y - _rt.last_y;

        if (point_distance(0, 0, _rt.step_x, _rt.step_y) > ARPG_MOVEMENT_MAX_STEP_PX) {
            _rt.step_x = 0;
            _rt.step_y = 0;
        }
    }

    _rt.last_x = obj_ari.x;
    _rt.last_y = obj_ari.y;
}

// Mirrors obj_ari.face_dir(): eight-way facing collapsed onto four cardinals,
// with both diagonals resolving to east or west.
function __arpg_movement_cardinal_for_dir(_dir) {
    switch ((round(_dir / 45) * 45) mod 360) {
        case 90: return Cardinal.North;
        case 135:
        case 180:
        case 225: return Cardinal.West;
        case 270: return Cardinal.South;
    }
    return Cardinal.East;
}

// The pose vanilla will select the clicked cell from: this frame's movement
// applied, and the facing that movement implies. While walking, AriFsm's own
// face_dir(heading) runs before the selection and overwrites whatever
// __arpg_movement_face_cursor_for_action() set, so a moving player's selection
// has to assume the heading rather than the cursor.
function __arpg_movement_predicted_pose(_rt) {
    var _cardinal = obj_ari.cardinal;
    if (_rt.step_x != 0 || _rt.step_y != 0) {
        _cardinal = __arpg_movement_cardinal_for_dir(
            point_direction(0, 0, _rt.step_x, _rt.step_y)
        );
    }

    return {
        x: obj_ari.x + _rt.step_x,
        y: obj_ari.y + _rt.step_y,
        cardinal: _cardinal,
    };
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

function __arpg_movement_mouse_cell_select(_pose) {
    var _base_x = _pose.x % 16;
    var _base_y = _pose.y % 16;
    var _bundle = {
        norm_x: 16 * (_pose.x div 16),
        norm_y: 16 * (_pose.y div 16),
        mouse_x: mouse_x() - 8,
        mouse_y: mouse_y() - 8,
        best_x: _pose.x,
        best_y: _pose.y,
        best_score: infinity,
    };

    for (var _xx = -1; _xx < 2; _xx++) {
        for (var _yy = -1; _yy < 2; _yy++) {
            __arpg_movement_consider_mouse_cell(_xx, _yy, _bundle);
        }
    }

    switch (_pose.cardinal) {
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

function __arpg_movement_tool_reaches_node(_node, _item, _selection) {
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

// Asks the game whether an item would act on the selected tiles at all. This
// mirrors the validity test at the end of obj_ari.update_cell_select(): the net
// acts only on the selected cell, every other item on any cell of its 2x2.
// The tool_type read stays behind the use check because only tools carry one.
function __arpg_movement_item_affects_cells(_item, _selection) {
    var _prototype = _item.prototype;

    if (_prototype.use == ItemUse.UseTool && _prototype.tool_type == ToolType.Net) {
        return GRID.item_effects_node_at_cell(_selection.x, _selection.y, _prototype);
    }

    for (var _xx = 0; _xx < 2; _xx++) {
        for (var _yy = 0; _yy < 2; _yy++) {
            if (GRID.item_effects_node_at_cell(
                _selection.x + _xx,
                _selection.y + _yy,
                _prototype
            )) {
                return true;
            }
        }
    }
    return false;
}

// The hoe toggles dirt into soil and soil back into dirt, so can_hoe_node() is
// equally true on a plot that is already tilled. Offer it only where there is
// untilled dirt to break, never where the same click would undo a finished bed.
function __arpg_movement_hoe_tills_cells(_item, _selection) {
    for (var _xx = 0; _xx < 2; _xx++) {
        for (var _yy = 0; _yy < 2; _yy++) {
            var _cell_x = _selection.x + _xx;
            var _cell_y = _selection.y + _yy;
            var _ni = GRID.try_node_index_for_cell(_cell_x, _cell_y);
            if (_ni != undefined
                && GRID.node_terrain_ground_kind[_ni] == GroundKind.Dirt
                && GRID.item_effects_node_at_cell(_cell_x, _cell_y, _item.prototype))
            {
                return true;
            }
        }
    }
    return false;
}

// Terrain work has no clicked node to identify it — dry soil and bare dirt are
// ground, not objects — so the game's own item/cell predicate decides instead.
// Ordered by how much a wrong guess would cost: watering changes nothing that
// the next day would not, tilling reshapes a plot, the net is last because its
// single-cell test is the easiest to satisfy by accident.
function __arpg_movement_find_terrain_tool(_selection) {
    var _probe_tools = [ToolType.WateringCan, ToolType.Hoe, ToolType.Net];

    for (var _i = 0; _i < array_length(_probe_tools); _i++) {
        var _tool_type = _probe_tools[_i];
        var _index = __arpg_movement_find_item(ItemUse.UseTool, _tool_type);
        if (_index == undefined) continue;

        var _item = ARI.inventory.slot(_index).item;
        var _usable = _tool_type == ToolType.Hoe
            ? __arpg_movement_hoe_tills_cells(_item, _selection)
            : __arpg_movement_item_affects_cells(_item, _selection);
        if (_usable) return _index;
    }
    return undefined;
}

// Selects the item before AriFsm's Default step reads this frame's unchanged
// left-button press. Recognized tool targets never fall back to a weapon when
// the required tool is absent, inadequate, or out of range.
function __arpg_movement_auto_select_action_item(_rt) {
    if (!mouse_check_button_pressed(mb_left)
        || !__arpg_movement_left_is_action()
        || ARI.held_animal_id != undefined)
    {
        return;
    }

    // Anchor consumes HUD clicks later in the frame. Its hover remains live
    // here, early enough to avoid selecting an item behind the toolbar.
    if (ANCHOR.current_hovered_node != undefined) return;

    var _selection = __arpg_movement_mouse_cell_select(
        __arpg_movement_predicted_pose(_rt)
    );

    // The held item already does something where the player clicked: seeds on
    // tilled soil, a hoe aimed at their own plot, the tool they just chose by
    // hand. A deliberate selection outranks every guess made below.
    var _held = ARI.held_item();
    if (_held != undefined && __arpg_movement_item_affects_cells(_held, _selection)) {
        return;
    }

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
            if (!__arpg_movement_tool_reaches_node(_node, _tool, _selection)) return;
            __arpg_movement_select_item(_tool_index);
            return;
        }
    }

    // No node, or one no tool works on (crops, grass, bushes): the tile itself
    // may still be waterable, tillable, or hold a bug.
    var _terrain_index = __arpg_movement_find_terrain_tool(_selection);
    if (_terrain_index != undefined) {
        __arpg_movement_select_item(_terrain_index);
        return;
    }

    // Outside the mines, ambiguous clicks preserve the user's farming,
    // placement, or other current selection.
    if (is_dungeon_room(room())) {
        __arpg_movement_select_item(__arpg_movement_find_item(ItemUse.Attack));
    }
}

// Vanilla aims a click at the cursor only while obj_ari.using_mouse is true,
// and that flag is fragile the moment the player moves. AriFsm's Default step
// re-arms it only on frames the mouse physically moved, and otherwise drops it
// as soon as the movement heading differs at all from the one it saved last
// frame — an exact float compare. Steering rewrites that heading every frame as
// the player closes on a parked cursor, so the flag falls within a frame or two
// of setting off and the game quietly switches to its facing-based tile queue:
// a different tile than the one this mod validated the click against, and the
// reason a click that should have swapped tools sometimes did nothing.
//
// Re-arming the flag alone would not survive — the same step clears it again
// before update_cell_select() runs. Clearing saved_heading as well sends that
// step down its other branch, which keeps mouse aiming until the player walks
// away from the cursor by 135 degrees or more. That is vanilla's own rule for
// deciding the mouse is no longer what the player aims with, so the fallback
// to facing-based targeting still happens, just for the right reason.
function __arpg_movement_keep_mouse_targeting() {
    // Held, not just pressed, for the same reason as facing: a repeating tool
    // re-selects its cell on every repeat.
    if (!mouse_check_button(mb_left)
        || !__arpg_movement_left_is_action()
        || ARI.held_animal_id != undefined)
    {
        return;
    }

    if (ANCHOR.current_hovered_node != undefined) return;

    // Furniture, tiles, saplings, and blueprints each aim through their own
    // branch of update_cell_select(), where this flag picks between cursor
    // placement and keyboard nudging. Leave the player's nudging alone.
    var _held = ARI.held_item();
    if (_held == undefined) return;
    switch (_held.prototype.use) {
        case ItemUse.PlaceObject:
        case ItemUse.PlaceTile:
        case ItemUse.PlantSapling:
        case ItemUse.Blueprint:
            return;
    }

    obj_ari.using_mouse = true;

    var _state = obj_ari.fsm.current_state();
    if (_state != undefined) {
        _state.saved_heading = undefined;
    }
}

// Turns the player toward the cursor on the frame an action click lands. The
// attack and tool states cache the player's cardinal when they start, so
// facing settled here decides where the swing goes. It also widens the tile
// the game hands the tool: update_cell_select() reaches an extra cell in the
// direction the player faces.
//
// Standing still, vanilla never revisits facing, which is what makes clicks go
// out the player's back. While moving, the Default step's own face_dir() runs
// later in the same frame and overwrites this with the heading — already the
// cursor direction whenever the mod is steering.
function __arpg_movement_face_cursor_for_action() {
    // Held, not just pressed. AriFsm's Default step re-fires a repeating tool
    // on INPUT.check(UseToolRepeated), so each repeat passes back through
    // Default and picks up the facing set here — sweeping the cursor while the
    // button is down aims every swing in the burst, not only the first.
    if (!mouse_check_button(mb_left)
        || !__arpg_movement_left_is_action()
        || ARI.held_animal_id != undefined)
    {
        return;
    }

    // Same reason as auto-selection: Anchor consumes HUD clicks later.
    if (ANCHOR.current_hovered_node != undefined) return;

    // Furniture, blueprints, and tiles preview through the cardinal, so
    // turning the player would rotate whatever they are about to place.
    var _held = ARI.held_item();
    if (_held == undefined) return;
    if (_held.prototype.use != ItemUse.Attack
        && _held.prototype.use != ItemUse.UseTool)
    {
        return;
    }

    var _mx = mouse_x();
    var _my = mouse_y();
    if (point_distance(obj_ari.x, obj_ari.y, _mx, _my) < 1) return;

    obj_ari.face_dir(point_direction(obj_ari.x, obj_ari.y, _mx, _my));
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

    // Before any early return: the displacement this reads has to be a single
    // frame's worth to predict the next one.
    __arpg_movement_track_step(_rt);

    if (!_cfg.enabled) {
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
    var _right_pressed = mouse_check_button_pressed(mb_right);

    // Mute the physical press before checking cancellation bindings below.
    // Interact is bound to right mouse by default; if an active tap-walk saw
    // that press first, it stopped the old path and produced a pause before
    // the release could retarget it. Other Interact bindings (such as E)
    // remain unmuted and still cancel mouse movement normally.
    if (_right_pressed) {
        var _idx = array_index(MOUSE_BUTTONS, mb_right);
        INPUT.raw_mouse[_idx] = set_flag(INPUT.raw_mouse[_idx], DigitalStatus.Muted);
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

        if (_right_pressed) {
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
mmapi_mod_declare("arpg_movement", "2.1.0");
arpg_movement_register_callbacks();
