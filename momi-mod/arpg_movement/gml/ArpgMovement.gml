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
//   tap-to-interact still works. A path that would cross open water is
//   refused (invalid marker) — Pathfind ignores collision, and walking on
//   water is not a move the player can make; interact paths pick a dry
//   approach (bridge, far bank) when one exists.
// - The raw right-button press is muted the moment it lands, so Interact
//   (and anything else bound to right mouse) never fires during a hold.
// - Any keyboard movement or discrete player command (actions, menus, toolbar,
//   placement controls) cancels a mouse-driven walk before vanilla reads that
//   same frame. Walk remains a speed modifier; the muted right-click gesture
//   retains ownership so it can retarget or hand over to steering.
// - Steering also works while swimming and mounted. Taps don't pathfind in
//   either case; mounted taps are handed back to vanilla Interact.
// - F6 toggles action-item auto-selection. When enabled and left mouse is
//   bound to a vanilla tool-use action, a nearby clicked rock, tree/stump, or
//   dig site selects its usable inventory tool before vanilla consumes that
//   same click, and a clicked breakable (mine barrels, crates, and debris,
//   farm branches and leaf piles) arms an inventory weapon the same way. Failing that, the watering can, hoe, or net is selected when
//   the game itself says that tool would act on the clicked tile, which covers
//   watering, tilling, and bug catching. A click the held item already acts on
//   is always left alone, so deliberate selections survive. In the mines,
//   combat outranks tools: while a live monster is close to the player
//   (`sword_enemy_range_px`) or under the cursor, any world click arms an
//   inventory weapon — even a click on a rock. With no monster near, mine
//   clicks keep the current selection, so a hand-picked fishing rod casts.
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
// - Left- or right-clicking outside the topmost normal pause menu requests its
//   own Back behavior, preserving nested screens and items held by menu cursors.
//   Dialogue, cutscene UI, and modal prompts stay out.
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
            interact_target_x: undefined,
            interact_target_y: undefined,
            interact_end_x: undefined,
            interact_end_y: undefined,
            interact_repath_frames: 0,
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
        // One field is 8px. Ambiguous mine clicks arm the weapon only when a
        // live monster is inside this radius around the player (0 disables the
        // player-radius check; clicks at a monster still arm it).
        sword_enemy_range_px: mmapi_config_number(_source, "sword_enemy_range_px", 40, 0, 640),
    };
    // Keep the three distance bands coherent even if a user hand-edits the
    // JSON. The nearest band stops, the middle band walks, and only the
    // farthest band runs.
    _rt.cfg.walk_within_px = max(_rt.cfg.walk_within_px, _rt.cfg.stop_within_px);
    _rt.cfg.run_beyond_px = max(_rt.cfg.run_beyond_px, _rt.cfg.walk_within_px);
    mmapi_config_write("arpg_movement", ARPG_MOVEMENT_CONFIG_VERSION, _rt.cfg);
    return _rt.cfg;
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

// Item tooltips are Popup menus that hover over the menu that owns them.
// They sit on top of it in ANCHOR.open_menus and never take Back input, so
// they must not count as a blocking modal, and their panel counts as part of
// the menu underneath. Stores spawn one the moment they open, which is why
// tooltip-bearing menus have to be handled here at all.
function __arpg_movement_is_tooltip_menu(_menu) {
    return _menu != undefined
        && _menu.type == Menu.Popup
        && _menu[$ "is_tooltip"] == true;
}

// Finds the top-level screen node a detached menu component belongs to.
function __arpg_movement_screen_root(_node) {
    var _root = _node;
    while (_root != undefined
        && _root.parent != undefined
        && _root.parent != ANCHOR.screen_canvas)
    {
        _root = _root.parent;
    }
    return _root;
}

// A few menus keep panels directly under screen_canvas instead of under their
// main canvas. Those panels have no source_menu, but the menu stores the root
// node in one of its fields.
function __arpg_movement_menu_owns_root(_menu, _root) {
    if (_root == undefined || _root == ANCHOR.screen_canvas) return false;

    var _fields = struct_get_names(_menu);
    for (var _i = 0; _i < array_length(_fields); _i++) {
        if (_menu[$ _fields[_i]] == _root) return true;
    }
    return false;
}

// Anchor updates current_hovered_node after this hook. Probe the current mouse
// position against the live node registry so a fast click cannot leak through
// a HUD control whose hover still describes the previous frame.
function __arpg_movement_point_over_actionable_ui() {
    for (var _i = ANCHOR.node_count - 1; _i >= 0; _i--) {
        var _node = ANCHOR.node_registrar[| _i];
        if (_node == undefined
            || _node.freed
            || _node.marked_for_death
            || !_node.run_logic
            || !_node.safe_enabled
            || !_node.safe_unlocked
            || _node.cache_alpha <= 0
            || (!_node.listens_for_hovers && !_node.listens_for_taps))
        {
            continue;
        }

        if (ANCHOR.point_in_node(_node, MOUSE_GUI_X, MOUSE_GUI_Y)
            && (!_node.canvas.render_partial_info.enabled
                || ANCHOR.point_in_node(_node.canvas, MOUSE_GUI_X, MOUSE_GUI_Y)))
        {
            return true;
        }
    }
    return false;
}

// True when the pointer is over any visible part owned by this menu or by a
// tooltip floating above it. A menu's root canvas covers the whole UI area,
// so only its descendants count. BackgroundMenu hangs from
// ANCHOR.screen_canvas and has no source_menu.
function __arpg_movement_point_inside_menu(_menu) {
    for (var _i = 0; _i < ANCHOR.node_count; _i++) {
        var _node = ANCHOR.node_registrar[| _i];
        if (_node == undefined || _node.freed) {
            continue;
        }

        var _owner = _node.source_menu;
        var _owned = _owner == _menu
            || __arpg_movement_is_tooltip_menu(_owner)
            || __arpg_movement_menu_owns_root(
                _menu,
                __arpg_movement_screen_root(_node)
            );
        if (!_owned
            || (_owner != undefined && _node == _owner.canvas)
            || !_node.safe_enabled
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

function __arpg_movement_mute_mouse_press(_button) {
    var _idx = array_index(MOUSE_BUTTONS, _button);
    if (_idx >= 0) {
        INPUT.raw_mouse[_idx] = set_flag(
            INPUT.raw_mouse[_idx],
            DigitalStatus.Muted
        );
    }
}

// Injects a logical press through every configured binary binding. This lets a
// custom menu execute its own layered Back behavior in Anchor's normal step.
function __arpg_movement_inject_input_press(_input_id) {
    var _bindings = BINDINGS.bindings[_input_id];
    var _injected = false;
    for (var _i = 0; _i < array_length(_bindings); _i++) {
        var _binding = _bindings[_i];
        if (_binding == undefined) continue;

        var _index = -1;
        switch (_binding.type) {
            case BindingType.Keyboard:
                _index = array_index(KEYBOARD_INPUTS, _binding.keycode);
                if (_index >= 0) {
                    INPUT.raw_keyboard[_index] = set_flag(
                        INPUT.raw_keyboard[_index],
                        DigitalStatus.Pressed
                    );
                    INPUT.raw_keyboard[_index] = remove_flag(
                        INPUT.raw_keyboard[_index],
                        DigitalStatus.Muted
                    );
                    _injected = true;
                }
                break;
            case BindingType.Mouse:
                _index = array_index(MOUSE_BUTTONS, _binding.keycode);
                if (_index >= 0) {
                    INPUT.raw_mouse[_index] = set_flag(
                        INPUT.raw_mouse[_index],
                        DigitalStatus.Pressed
                    );
                    INPUT.raw_mouse[_index] = remove_flag(
                        INPUT.raw_mouse[_index],
                        DigitalStatus.Muted
                    );
                    _injected = true;
                }
                break;
            case BindingType.GamepadButton:
                _index = array_index(GAMEPAD_BUTTONS, _binding.keycode);
                if (_index >= 0) {
                    INPUT.raw_gp_buttons[_index] = set_flag(
                        INPUT.raw_gp_buttons[_index],
                        DigitalStatus.Pressed
                    );
                    INPUT.raw_gp_buttons[_index] = remove_flag(
                        INPUT.raw_gp_buttons[_index],
                        DigitalStatus.Muted
                    );
                    _injected = true;
                }
                break;
        }
    }
    return _injected;
}

// Menus in this list deliberately consume Back themselves instead of enabling
// AnchorMenu's generic close listener. They are ordinary pause menus with
// internal pages, so an outside click should request Back, not bypass them.
function __arpg_movement_menu_has_safe_custom_back(_type) {
    switch (_type) {
        case Menu.Almanac:
        case Menu.Adoption:
        case Menu.FarmBuildingSelection:
        case Menu.Customization:
        case Menu.Crafting:
        case Menu.Inbox:
        case Menu.Museum:
        case Menu.QuestLog:
        case Menu.Spellcasting:
        case Menu.Settings:
        case Menu.DragonShrine:
            return true;
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
        if (_menu.data.pause == PauseStatus.EMPTY
            || __arpg_movement_is_tooltip_menu(_menu))
        {
            continue;
        }

        // This is the topmost modal. Cutscene UI and custom prompt menus stop
        // here. Ordinary pause menus with a custom Back handler receive a
        // synthetic Back press so their own internal navigation remains intact.
        var _custom_back = _menu.data.pause == PauseStatus.MENU
            && __arpg_movement_menu_has_safe_custom_back(_menu.type);
        var _allows_outside_close = _menu.listen_for_exit_flag
            || _custom_back;
        if (_menu.close_requested
            || !_allows_outside_close
            || _menu.canvas == undefined
            || !_menu.canvas.is_unlocked()
            || __arpg_movement_point_inside_menu(_menu))
        {
            return false;
        }

        if (_custom_back) {
            if (!__arpg_movement_inject_input_press(InputId.MenuBack)) {
                return false;
            }
        } else {
            _menu.close();
        }

        // Do not let the dismissing click reach UI or gameplay underneath.
        if (_left_pressed) {
            __arpg_movement_mute_mouse_press(mb_left);
        }
        if (_right_pressed) {
            __arpg_movement_mute_mouse_press(mb_right);
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

// Vanilla's has_potential_interactions() accidentally tests whether each
// callback exists instead of calling it. Smart targeting must use the real
// eligibility result or it can chase disabled doors, sleeping NPCs, and stale
// contextual actions.
function __arpg_movement_target_is_actionable(_target) {
    if (_target == undefined || !instance_exists(_target)) return false;

    for (var _i = 0; _i < _target.interactions.count(); _i++) {
        var _interaction = _target.interactions.get(_i);
        if (_interaction != undefined
            && _interaction.can_interact_callback() != false)
        {
            return true;
        }
    }
    return false;
}

// Finds the closest live interactable whose interaction shape or visible
// collision bounds contain the click.
function __arpg_movement_interactable_at(_x, _y) {
    var _best = undefined;
    var _best_kind = infinity;
    var _best_distance = infinity;

    for (var _i = 0; _i < INTERACTABLES.count(); _i++) {
        var _candidate = INTERACTABLES.get(_i);
        if (!__arpg_movement_target_is_actionable(_candidate)) continue;

        var _bounds = __arpg_movement_interact_bounds(_candidate);
        if (_bounds == undefined) continue;

        var _hit = _x >= _bounds.left - 2
            && _x <= _bounds.right + 2
            && _y >= _bounds.top - 2
            && _y <= _bounds.bottom + 2;

        var _hit_kind = _hit ? 0 : 1;

        // Interaction geometry may live at an object's feet or be much smaller
        // than its visible sprite. Accept its collision bounds as a fallback
        // for every mode, while ranking a true interaction-shape hit first.
        if (!_hit) {
            _hit = _x >= _candidate.bbox_left - 2
                && _x <= _candidate.bbox_right + 2
                && _y >= _candidate.bbox_top - 2
                && _y <= _candidate.bbox_bottom + 2;
        }

        if (_hit) {
            var _distance = point_distance(_x, _y, _bounds.center_x, _bounds.center_y);
            if (_hit_kind < _best_kind
                || (_hit_kind == _best_kind && _distance < _best_distance))
            {
                _best = _candidate;
                _best_kind = _hit_kind;
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
    if (!__arpg_movement_target_is_actionable(_target)) return false;

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

    var _reach_cells = ceil(
        (obj_ari.interact_max_radius + obj_ari.interact_nudge_distance) / 8
    ) + 1;
    var _left_cell = floor(_bounds.left / 8) - _reach_cells;
    var _right_cell = floor(_bounds.right / 8) + _reach_cells;
    var _top_cell = floor(_bounds.top / 8) - _reach_cells;
    var _bottom_cell = floor(_bounds.bottom / 8) + _reach_cells;
    var _candidates = [];

    for (var _gx = _left_cell; _gx <= _right_cell; _gx++) {
        for (var _gy = _top_cell; _gy <= _bottom_cell; _gy++) {
            var _px = _gx * 8 + 4;
            var _py = _gy * 8 + 4;
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
                <= obj_ari.interact_max_radius
                && GRID.try_node_index_for_room_position(_px, _py) != undefined)
            {
                array_push(_candidates, {
                    x: _px,
                    y: _py,
                    straight: point_distance(obj_ari.x, obj_ari.y, _px, _py),
                });
            }
        }
    }

    // Evaluate promising cells first. Once straight-line distance cannot beat
    // the best path, no later candidate can either.
    array_sort(_candidates, function(_a, _b) {
        return _a.straight - _b.straight;
    });

    var _best = undefined;
    var _best_distance = infinity;
    for (var _j = 0; _j < array_length(_candidates); _j++) {
        var _pos = _candidates[_j];
        if (_pos.straight >= _best_distance) break;

        var _path_data = PATHFINDING.calculate_local_path(
            obj_ari.x,
            obj_ari.y,
            _pos.x,
            _pos.y,
            true
        );
        if (_path_data != undefined
            && _path_data.distance < _best_distance
            && !__arpg_movement_path_crosses_water(_path_data))
        {
            _best = {
                x: _pos.x,
                y: _pos.y,
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
function __arpg_movement_predicted_pose(_rt, _cfg) {
    var _intent_x = INPUT.check_value(InputId.Right) - INPUT.check_value(InputId.Left);
    var _intent_y = INPUT.check_value(InputId.Down) - INPUT.check_value(InputId.Up);

    // Once a right hold has crossed the steering threshold, the injected stick
    // later in this heartbeat is the movement intent vanilla will actually use.
    if (mouse_check_button(mb_right)
        && _rt.hold_frames + 1 > _cfg.steer_start_seconds * FPS)
    {
        var _mouse_dist = point_distance(obj_ari.x, obj_ari.y, mouse_x(), mouse_y());
        if (_mouse_dist > _cfg.stop_within_px) {
            _intent_x = (mouse_x() - obj_ari.x) / _mouse_dist;
            _intent_y = (mouse_y() - obj_ari.y) / _mouse_dist;
        } else {
            _intent_x = 0;
            _intent_y = 0;
        }
    }

    var _step_x = _rt.step_x;
    var _step_y = _rt.step_y;
    var _cardinal = obj_ari.cardinal;
    if (_intent_x == 0 && _intent_y == 0) {
        // A released key stops Ari immediately; repeating the last displacement
        // here would predict a movement the upcoming Default step will not make.
        _step_x = 0;
        _step_y = 0;
    } else {
        var _intent_dir = point_direction(0, 0, _intent_x, _intent_y);
        _cardinal = __arpg_movement_cardinal_for_dir(_intent_dir);

        if ((_step_x == 0 && _step_y == 0)
            || abs(angle_difference(
                point_direction(0, 0, _step_x, _step_y),
                _intent_dir
            )) > 22.5)
        {
            // A changed heading or a blocked previous frame is not enough
            // evidence to predict collision sliding in the new direction.
            _step_x = 0;
            _step_y = 0;
        }
    }

    return {
        x: obj_ari.x + _step_x,
        y: obj_ari.y + _step_y,
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

// Every 16px tile vanilla's update_cell_select() could legally choose from
// this pose: the 3x3 around the player's tile plus the conditional two-tile
// reach in the facing direction. Returned as cell (8px) top-left coords.
function __arpg_movement_selection_candidates(_x, _y, _cardinal) {
    var _tiles = [];
    for (var _xx = -1; _xx < 2; _xx++) {
        for (var _yy = -1; _yy < 2; _yy++) {
            array_push(_tiles, [_xx, _yy]);
        }
    }

    var _base_x = _x % 16;
    var _base_y = _y % 16;
    switch (_cardinal) {
        case Cardinal.West:
            if (_base_x < 8) {
                array_push(_tiles, [-2, 0]);
                array_push(_tiles, [-2, _base_y < 8 ? -1 : 1]);
            }
            break;
        case Cardinal.East:
            if (_base_x >= 8) {
                array_push(_tiles, [2, 0]);
                array_push(_tiles, [2, _base_y < 8 ? -1 : 1]);
            }
            break;
        case Cardinal.North:
            if (_base_y < 8) {
                array_push(_tiles, [0, -2]);
                array_push(_tiles, [_base_x < 8 ? -1 : 1, -2]);
            }
            break;
        case Cardinal.South:
            if (_base_y >= 8) {
                array_push(_tiles, [0, 2]);
                array_push(_tiles, [_base_x < 8 ? -1 : 1, 2]);
            }
            break;
    }

    var _norm_x = 16 * (_x div 16);
    var _norm_y = 16 * (_y div 16);
    var _out = array_create(array_length(_tiles));
    for (var _i = 0; _i < array_length(_tiles); _i++) {
        _out[_i] = {
            x: (_norm_x + _tiles[_i][0] * 16) div 8,
            y: (_norm_y + _tiles[_i][1] * 16) div 8,
        };
    }
    return _out;
}

// Breakables (mine barrels, crates, debris piles, coral, farm branches) are
// smashed by the sword's slash, not by any cell-selected tool, and the game's
// item_effects_node_at_cell() has no ItemUse.Attack case to ask. Swing range
// is approximated the way the tools do it: the node counts as reachable when
// any vanilla-legal selection's 2x2 covers one of its cells. The mod already
// turns the player toward the cursor on an action click, so a node inside
// that range sits in the swing arc.
function __arpg_movement_node_in_swing_range(_x, _y, _cardinal, _node) {
    var _candidates = __arpg_movement_selection_candidates(_x, _y, _cardinal);
    for (var _i = 0; _i < array_length(_candidates); _i++) {
        var _cand = _candidates[_i];
        for (var _xx = 0; _xx < 2; _xx++) {
            for (var _yy = 0; _yy < 2; _yy++) {
                var _ni = GRID.try_node_index_for_cell(_cand.x + _xx, _cand.y + _yy);
                if (_ni != undefined && GRID.node_parent[_ni] == _node) {
                    return true;
                }
            }
        }
    }
    return false;
}

// Node sprites overhang their grid footprint, so a click on the visible top
// of a rock parks the cursor a tile outside the cells the rock occupies and
// vanilla's cursor-nearest selection whiffs. This finds the vanilla-legal
// selection nearest the cursor whose 2x2 still contains a cell of _node the
// item acts on — proof the node is in genuine swing range even though the
// cursor's own tile is not part of it. Scoring mirrors update_cell_select()
// (squared distance to the cursor minus the half-tile offset) so the choice
// is the one vanilla itself would have made from inside the footprint.
function __arpg_movement_selection_reaching_node(_x, _y, _cardinal, _node, _prototype) {
    var _candidates = __arpg_movement_selection_candidates(_x, _y, _cardinal);
    var _mx = mouse_x() - 8;
    var _my = mouse_y() - 8;
    var _best = undefined;
    var _best_score = infinity;

    for (var _i = 0; _i < array_length(_candidates); _i++) {
        var _cand = _candidates[_i];
        var _hits = false;
        for (var _xx = 0; _xx < 2 && !_hits; _xx++) {
            for (var _yy = 0; _yy < 2; _yy++) {
                var _cell_x = _cand.x + _xx;
                var _cell_y = _cand.y + _yy;
                var _ni = GRID.try_node_index_for_cell(_cell_x, _cell_y);
                if (_ni != undefined
                    && GRID.node_parent[_ni] == _node
                    && GRID.item_effects_node_at_cell(_cell_x, _cell_y, _prototype))
                {
                    _hits = true;
                    break;
                }
            }
        }
        if (!_hits) continue;

        var _dx = _cand.x * 8 - _mx;
        var _dy = _cand.y * 8 - _my;
        var _score = _dx * _dx + _dy * _dy;
        if (_score < _best_score) {
            _best_score = _score;
            _best = _cand;
        }
    }
    return _best;
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

// Exact clicked-cell probe used before the broader vanilla 2x2 selection.
// This prevents a neighboring dry/tillable cell from outranking the terrain
// directly under the pointer in a mixed selection.
function __arpg_movement_find_exact_terrain_tool(_cell_x, _cell_y, _selection) {
    if (_cell_x < _selection.x
        || _cell_x > _selection.x + 1
        || _cell_y < _selection.y
        || _cell_y > _selection.y + 1)
    {
        return undefined;
    }

    var _probe_tools = [ToolType.WateringCan, ToolType.Hoe, ToolType.Net];
    var _ni = GRID.try_node_index_for_cell(_cell_x, _cell_y);
    if (_ni == undefined) return undefined;

    for (var _i = 0; _i < array_length(_probe_tools); _i++) {
        var _tool_type = _probe_tools[_i];
        var _index = __arpg_movement_find_item(ItemUse.UseTool, _tool_type);
        if (_index == undefined) continue;

        var _item = ARI.inventory.slot(_index).item;
        if (_tool_type == ToolType.Hoe
            && GRID.node_terrain_ground_kind[_ni] != GroundKind.Dirt)
        {
            continue;
        }
        if (GRID.item_effects_node_at_cell(_cell_x, _cell_y, _item.prototype)) {
            return _index;
        }
    }
    return undefined;
}

function __arpg_movement_is_deliberate_placement(_use) {
    switch (_use) {
        case ItemUse.PlaceObject:
        case ItemUse.PlaceTile:
        case ItemUse.PlantSeed:
        case ItemUse.PlantSapling:
        case ItemUse.PlantGrass:
        case ItemUse.Blueprint:
        case ItemUse.Bait:
            return true;
    }
    return false;
}

// True when a live monster stands within _player_range_px of the player, or
// within three fields of the cursor — clicking at a monster is combat intent
// no matter how far away it stands. par_monster covers every real monster;
// projectiles and effect objects are separate object trees and never match.
function __arpg_movement_monster_near(_player_range_px) {
    var _mx = mouse_x();
    var _my = mouse_y();
    var _count = instance_number(par_monster);
    for (var _i = 0; _i < _count; _i++) {
        var _monster = instance_find(par_monster, _i);
        // A monster playing its death animation is no reason to draw steel.
        if (_monster.hit_points <= 0) continue;
        if (point_distance(obj_ari.x, obj_ari.y, _monster.x, _monster.y) <= _player_range_px
            || point_distance(_mx, _my, _monster.x, _monster.y) <= 24)
        {
            return true;
        }
    }
    return false;
}

// Selects the item before AriFsm's Default step reads this frame's unchanged
// left-button press. In mine combat the weapon is chosen up front; outside it,
// recognized tool targets never fall back to a weapon when the required tool
// is absent, inadequate, or out of range.
function __arpg_movement_auto_select_action_item(_rt) {
    if (!mouse_check_button_pressed(mb_left)
        || !__arpg_movement_left_is_action()
        || ARI.held_animal_id != undefined)
    {
        return;
    }

    if (__arpg_movement_point_over_actionable_ui()) {
        return;
    }

    var _held = ARI.held_item();
    if (_held != undefined
        && __arpg_movement_is_deliberate_placement(_held.prototype.use))
    {
        return;
    }

    // In the mines, combat outranks tools: with a live monster close, the
    // weapon wins every world click, even one on a rock — a mid-fight click
    // must never trade the sword for a pickaxe, and a click that misses the
    // monster and lands on an unreachable stone must still draw it. That is
    // why this runs before the clicked-node branch.
    if (is_dungeon_room(room())) {
        var _weapon_index = __arpg_movement_find_item(ItemUse.Attack);
        if (_weapon_index != undefined
            && __arpg_movement_monster_near(arpg_movement_config().sword_enemy_range_px))
        {
            __arpg_movement_select_item(_weapon_index);
            return;
        }
    }

    var _pose = __arpg_movement_predicted_pose(_rt, arpg_movement_config());
    var _selection = __arpg_movement_mouse_cell_select(_pose);

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
            case ObjectCategory.Breakable:
                // Mine barrels, crates, and debris (and farm branches/leaf
                // piles) break with the sword's slash, so a click on one arms
                // an inventory weapon exactly like a rock arms the pickaxe.
                var _weapon_index = __arpg_movement_find_item(ItemUse.Attack);
                if (_weapon_index == undefined
                    || !__arpg_movement_node_in_swing_range(
                        _pose.x, _pose.y, _pose.cardinal, _node
                    ))
                {
                    return;
                }
                __arpg_movement_select_item(_weapon_index);
                return;
        }

        if (_tool_type != undefined) {
            var _tool_index = __arpg_movement_find_item(ItemUse.UseTool, _tool_type, _minimum_quality);
            if (_tool_index == undefined) {
                return;
            }

            var _tool = ARI.inventory.slot(_tool_index).item;
            // The cursor-anchored selection misses when the player clicked the
            // node's sprite overhang; any other legal selection covering the
            // node proves it is still within vanilla's swing range.
            if (!__arpg_movement_tool_reaches_node(_node, _tool, _selection)
                && __arpg_movement_selection_reaching_node(
                    _pose.x, _pose.y, _pose.cardinal, _node, _tool.prototype
                ) == undefined)
            {
                return;
            }
            __arpg_movement_select_item(_tool_index);
            return;
        }
    }

    // The clicked object had no explicit required tool. Preserve a hand-picked
    // item that the game says can act on the selected cells.
    if (_held != undefined && __arpg_movement_item_affects_cells(_held, _selection)) {
        return;
    }

    // No node, or one no tool works on (crops, grass, bushes): the tile itself
    // may still be waterable, tillable, or hold a bug.
    var _terrain_index = __arpg_movement_find_exact_terrain_tool(
        mouse_x() div 8,
        mouse_y() div 8,
        _selection
    );
    if (_terrain_index == undefined) {
        _terrain_index = __arpg_movement_find_terrain_tool(_selection);
    }
    if (_terrain_index != undefined) {
        __arpg_movement_select_item(_terrain_index);
        return;
    }

    // Every remaining click — no recognized target, no terrain tool, and no
    // monster in reach (handled up front) — keeps the current selection.
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

    if (__arpg_movement_point_over_actionable_ui()) return;

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
    if (__arpg_movement_point_over_actionable_ui()) return;

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

// Clicking the visible top of a rock parks the cursor a tile outside the
// rock's footprint, so the selection vanilla finalized for this swing points
// at empty ground and the strike whiffs. The guard fires with movement,
// facing, and cell_select all final; when that selection misses the node
// under the cursor but another vanilla-legal one hits it, remember the better
// selection. The tool state reads its target on a later animation frame, so
// the next clock_tick delivers the correction before the strike lands.
function __arpg_movement_plan_tool_retarget(_item) {
    var _rt = __arpg_movement_runtime();
    _rt.tool_retarget = undefined;

    // Cursor-driven swings only: a keyboard-triggered tool aims by facing.
    if (!mouse_check_button(mb_left)
        || !__arpg_movement_left_is_action()
        || ARI.held_animal_id != undefined)
    {
        return;
    }
    if (__arpg_movement_point_over_actionable_ui()) return;

    // Only tools whose target is the clicked node itself. Hoe, watering can,
    // and net act on the tile under the cursor, where vanilla's aim is right.
    if (_item.prototype.use != ItemUse.UseTool) return;
    switch (_item.prototype.tool_type) {
        case ToolType.PickAxe:
        case ToolType.Axe:
        case ToolType.Shovel:
            break;
        default:
            return;
    }

    var _node = __arpg_movement_clicked_node();
    if (_node == undefined) return;

    // Vanilla's own selection already reaches the node: leave it alone.
    if (__arpg_movement_tool_reaches_node(_node, _item, obj_ari.cell_select)) {
        return;
    }

    var _best = __arpg_movement_selection_reaching_node(
        obj_ari.x, obj_ari.y, obj_ari.cardinal, _node, _item.prototype
    );
    if (_best == undefined) return;

    _rt.tool_retarget = _best;
}

// The item-use guard runs after Default has moved and re-faced Ari but before
// use_item() creates the action state. Reapply cursor facing at that exact
// seam so the first weapon/tool action caches the cursor direction even while
// the player is moving with the keyboard, then plan the aim correction for
// sprite-overhang clicks from the same settled pose. The guard fires once per
// swing, so held repeats stay corrected too.
function arpg_movement_items_use_guard(_item) {
    if (!instance_exists(obj_ari) || game_paused() || ON_GAMEPAD) {
        return undefined;
    }

    var _cfg = arpg_movement_config();
    if (!_cfg.enabled
        || obj_ari.fsm.current_state_id() != PlayerState.Default
        || _item == undefined
        || (_item.prototype.use != ItemUse.Attack
            && _item.prototype.use != ItemUse.UseTool))
    {
        return undefined;
    }

    if (_cfg.face_cursor_on_action) {
        __arpg_movement_face_cursor_for_action();
    }
    if (_cfg.cursor_targeting_on_action) {
        __arpg_movement_plan_tool_retarget(_item);
    }
    return undefined;
}

// Sword combos stay in one state, so later swings do not pass through the item
// guard. Keep the state's cached cardinal, hitbox direction, and forward push
// aligned with the cursor while the action button remains held.
function __arpg_movement_aim_sword_combo() {
    if (!mouse_check_button(mb_left)
        || !__arpg_movement_left_is_action()
        || __arpg_movement_point_over_actionable_ui())
    {
        return;
    }

    var _mx = mouse_x();
    var _my = mouse_y();
    if (point_distance(obj_ari.x, obj_ari.y, _mx, _my) < 1) return;

    var _dir = point_direction(obj_ari.x, obj_ari.y, _mx, _my);
    var _state = obj_ari.fsm.current_state();
    if (_state == undefined) return;

    obj_ari.face_dir(_dir);
    _state.cached_cardinal = obj_ari.cardinal;
    _state.dir = cardinal_to_angle(_state.cached_cardinal);
    _state.push_spd.set_zero();
    switch (_state.cached_cardinal) {
        case Cardinal.East:  _state.push_spd.x = _state.max_push_spd; break;
        case Cardinal.North: _state.push_spd.y = -_state.max_push_spd; break;
        case Cardinal.West:  _state.push_spd.x = -_state.max_push_spd; break;
        case Cardinal.South: _state.push_spd.y = _state.max_push_spd; break;
    }
}

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

    // Mute the physical press before checking cancellation bindings below.
    // Interact is bound to right mouse by default; if an active tap-walk saw
    // that press first, it stopped the old path and produced a pause before
    // the release could retarget it. Other Interact bindings (such as E)
    // remain unmuted and still cancel mouse movement normally.
    if (_right_pressed) {
        __arpg_movement_mute_mouse_press(mb_right);
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

    // Every discrete action, menu command, and toolbar change hands control
    // back to vanilla in the same frame.
    if (_in_our_path && __arpg_movement_path_cancel_requested())
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
    mmapi_guard("items.use_guard", arpg_movement_items_use_guard);

    var _f6 = mmapi_hotkey_vk_from_name("F6");
    if (_f6 != undefined) {
        mmapi_hotkey_register(_f6, arpg_movement_toggle_auto_select);
    }
}

// Boot wiring: memory-only top level.
mmapi_mod_declare("arpg_movement", "2.2.0");
arpg_movement_register_callbacks();
