// ARPG Movement: menu hit-testing and outside-click behavior

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
// tooltip floating above it. Canvas nodes never count: they are invisible
// layout containers, and several span the whole screen while the content
// they hold is a small child — a menu's root canvas, and prefab containers
// like player_gold_prefab's gold_canvas (a screen-sized canvas the store
// keeps in a field, whose visible gold pill is a 30x15 child; counting the
// container made every click read as inside the shop and broke outside-click
// closing). BackgroundMenu hangs from ANCHOR.screen_canvas and has no
// source_menu.
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
            || _node.type == NodeId.Canvas
            || !_node.safe_enabled
            || _node.cache_alpha <= 0)
        {
            continue;
        }

        if (ANCHOR.point_in_node(_node, MOUSE_GUI_X, MOUSE_GUI_Y)) {
            if (__arpg_movement_dev_logging()) {
                var _owner_desc = _owner == undefined
                    ? "root" : string(_owner.type);
                __arpg_movement_log("menu: inside via node idx=" + string(_node.idx)
                    + " owner=" + _owner_desc
                    + " bbox=" + string(_node.cache_bbox_left) + ","
                    + string(_node.cache_bbox_top) + ","
                    + string(_node.cache_bbox_right) + ","
                    + string(_node.cache_bbox_bottom)
                    + " mouse=" + string(MOUSE_GUI_X) + "," + string(MOUSE_GUI_Y));
            }
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
// Spawned popups with manual exit listening need the same treatment: their
// first button owns MenuBack and may run a Cancel callback before closing.
function __arpg_movement_menu_has_safe_custom_back(_menu) {
    if (_menu.type == Menu.Popup && _menu.manual_exit_listening) {
        return true;
    }

    var _type = _menu.type;
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
            && __arpg_movement_menu_has_safe_custom_back(_menu);
        var _allows_outside_close = _menu.listen_for_exit_flag
            || _custom_back;
        if (__arpg_movement_dev_logging()) {
            __arpg_movement_log("menu: outside-click probe type=" + string(_menu.type)
                + " close_req=" + string(_menu.close_requested)
                + " listen=" + string(_menu.listen_for_exit_flag)
                + " custom_back=" + string(_custom_back)
                + " canvas=" + string(_menu.canvas != undefined)
                + " unlocked=" + string(_menu.canvas != undefined
                    && _menu.canvas.is_unlocked()));
        }
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


