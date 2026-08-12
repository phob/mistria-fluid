// ARPG Movement: vanilla Settings menu integration

// Every rule describes the runtime path that actually consumes an option.
// Controls stay visible for discoverability, but are untappable and dimmed
// while their parent feature cannot use them.
function __arpg_movement_settings_rule_enabled(_rule) {
    var _cfg = arpg_movement_config();
    switch (_rule) {
        case "always":
            return true;
        case "enabled":
            return _cfg.enabled;
        case "steering":
            return _cfg.enabled && _cfg.hold_to_steer;
        case "mounted_mode":
            return _cfg.enabled && _cfg.hold_to_steer;
        case "on_foot_taps":
            return _cfg.enabled && !_cfg.mouse_move_mounted_only;
        case "tap_timing":
            return _cfg.enabled
                && !_cfg.mouse_move_mounted_only
                && (_cfg.tap_to_pathfind || _cfg.click_to_interact);
        case "tap_move":
            return _cfg.enabled
                && !_cfg.mouse_move_mounted_only
                && _cfg.tap_to_pathfind;
        case "path_feedback":
            return _cfg.enabled
                && !_cfg.mouse_move_mounted_only
                && (_cfg.tap_to_pathfind || _cfg.click_to_interact);
        case "auto_tool":
            return _cfg.enabled && _cfg.auto_select_action_item;
    }
    return false;
}

function __arpg_movement_settings_set_available(_node, _available) {
    _node.set_unlocked(_available);
    _node.set_alpha(_available ? 1 : 0.5);
}

function __arpg_movement_settings_toggle(_key, _rule) {
    if (!__arpg_movement_settings_rule_enabled(_rule)) return;

    var _cfg = arpg_movement_config();
    _cfg[$ _key] = !_cfg[$ _key];
    arpg_movement_config_save();
    __arpg_movement_log("settings: " + _key + "=" + string(_cfg[$ _key]));
}

function __arpg_movement_settings_refresh_checkbox(
    _element,
    _checkbox,
    _key,
    _rule
) {
    var _available = __arpg_movement_settings_rule_enabled(_rule);
    __arpg_movement_settings_set_available(_element, _available);

    var _cfg = arpg_movement_config();
    _checkbox.set_sprite(
        _cfg[$ _key]
            ? spr_ui_generic_checkbox_on
            : spr_ui_generic_checkbox_off
    );
}

function __arpg_movement_settings_add_checkbox(
    _menu,
    _key,
    _label,
    _rule
) {
    var _element = _menu.option_scroller.new_element(33)
        .set_tap_callback(
            __arpg_movement_settings_toggle,
            [_key, _rule]
        )
        .add_to_pilot(_menu.option_pilot, true)
        // Reuse vanilla's label wiring, then replace the localized text with
        // a mod-owned literal so selected/hover colors remain native.
        .add_text_label("misc_local/rumble");

    _element.text_label
        .set_text(_label)
        .set_align(Align.LeftIn, Align.Middle)
        .set_x(18)
        .set_max_width(141);

    var _checkbox = ANCHOR.sprite(_element)
        .set_x(4)
        .set_align(Align.LeftIn, Align.Middle);
    _element.arpg_setting_key = _key;
    _checkbox.set_think_callback(
        __arpg_movement_settings_refresh_checkbox,
        [_element, _checkbox, _key, _rule]
    );
    return _element;
}

function __arpg_movement_settings_add_section(_menu, _label) {
    var _element = _menu.option_scroller.new_element(22);
    ANCHOR.text(_element)
        .set_text(_label)
        .set_xy(7, 4)
        .set_align(Align.LeftIn, Align.TopIn)
        .set_lut(COMMON_LUT, CommonLutIndex.Header);
}

function __arpg_movement_settings_number_choices(_key) {
    static TAP_SECONDS = [
        0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1.0, 1.5, 2.0,
    ];
    static STEER_SECONDS = [
        0.0, 0.05, 0.1, 0.15, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1.0,
    ];
    static STOP_DISTANCES = [0, 4, 8, 12, 16, 24, 32];
    static WALK_DISTANCES = [
        0, 4, 8, 12, 16, 24, 32, 40, 48, 64, 96, 128, 160, 240, 320,
    ];
    static RUN_DISTANCES = [
        0, 8, 16, 24, 32, 40, 48, 64, 96, 128, 160, 240, 320, 480, 640,
    ];
    static INTERACT_DISTANCES = [0, 8, 16, 24, 32, 40, 48, 56, 64];
    static SWORD_DISTANCES = [
        0, 8, 16, 24, 32, 40, 48, 64, 80, 96, 128, 160, 240, 320, 480, 640,
    ];

    var _source = [];
    switch (_key) {
        case "tap_seconds":
            _source = TAP_SECONDS;
            break;
        case "steer_start_seconds":
            _source = STEER_SECONDS;
            break;
        case "stop_within_px":
            _source = STOP_DISTANCES;
            break;
        case "walk_within_px":
            _source = WALK_DISTANCES;
            break;
        case "run_beyond_px":
            _source = RUN_DISTANCES;
            break;
        case "interact_radius_px":
            _source = INTERACT_DISTANCES;
            break;
        case "sword_enemy_range_px":
            _source = SWORD_DISTANCES;
            break;
    }

    var _cfg = arpg_movement_config();
    var _choices = List();
    for (var _i = 0; _i < array_length(_source); _i++) {
        var _value = _source[_i];
        var _valid = true;
        switch (_key) {
            case "steer_start_seconds":
                _valid = _value <= _cfg.tap_seconds;
                break;
            case "stop_within_px":
                _valid = _value <= _cfg.walk_within_px;
                break;
            case "walk_within_px":
                _valid = _value >= _cfg.stop_within_px
                    && _value <= _cfg.run_beyond_px;
                break;
            case "run_beyond_px":
                _valid = _value >= _cfg.walk_within_px;
                break;
        }
        if (_valid) _choices.push(_value);
    }
    return _choices;
}

function __arpg_movement_settings_format_number(_value) {
    var _key = self.key;
    if (_key == "tap_seconds" || _key == "steer_start_seconds") {
        if (_value == 0) return "Immediate";
        return string_format(_value, 0, 2) + " s";
    }

    if (_value == 0) {
        if (_key == "sword_enemy_range_px") return "Cursor only";
        if (_key == "interact_radius_px") return "No dead zone";
        return "At cursor";
    }

    var _tiles = _value / 8;
    var _amount = floor(_tiles) == _tiles
        ? string(_tiles)
        : string_format(_tiles, 0, 1);
    return _amount + (_tiles == 1 ? " tile" : " tiles");
}

function __arpg_movement_settings_set_number(_value) {
    var _cfg = arpg_movement_config();
    _cfg[$ self.key] = _value;
    arpg_movement_config_save();
    __arpg_movement_log(
        "settings: " + self.key + "=" + string(_cfg[$ self.key])
    );
}

function __arpg_movement_settings_open_number_popup(_menu, _key, _title) {
    var _choices = __arpg_movement_settings_number_choices(_key);
    create_options_popup(
        ANCHOR.wrap_for_local("Choose " + _title),
        _choices,
        method({ key: _key }, __arpg_movement_settings_format_number),
        method({ key: _key }, __arpg_movement_settings_set_number),
        _menu.new_pilot(),
        2
    );
}

function __arpg_movement_settings_refresh_value(
    _element,
    _button,
    _key,
    _rule
) {
    var _available = __arpg_movement_settings_rule_enabled(_rule);
    __arpg_movement_settings_set_available(_button, _available);
    _element.set_alpha(_available ? 1 : 0.5);

    var _formatter = method(
        { key: _key },
        __arpg_movement_settings_format_number
    );
    _button.text_label.set_text(_formatter(arpg_movement_config()[$ _key]));
}

function __arpg_movement_settings_add_value(
    _menu,
    _key,
    _title,
    _rule
) {
    var _element = _menu.option_scroller.new_element(42);
    ANCHOR.text(_element)
        .set_text(_title)
        .set_xy(7, 2)
        .set_align(Align.LeftIn, Align.TopIn);

    var _button = ANCHOR.nine_slice(_element)
        .set_align(Align.LeftIn, Align.BottomIn)
        .set_xy(7, -5)
        .set_size(84, COMMON_BUTTON_HEIGHT)
        .set_sprites_from_key("spr_ui_button")
        .set_tap_callback(
            __arpg_movement_settings_open_number_popup,
            [_menu, _key, _title]
        )
        .add_to_pilot(_menu.option_pilot, true)
        .add_hover_outline()
        .add_text_label(
            "misc_local/rumble",
            COMMON_LUT,
            CommonLutIndex.Dark
        );
    _button.arpg_setting_key = _key;
    _button.set_think_callback(
        __arpg_movement_settings_refresh_value,
        [_element, _button, _key, _rule]
    );
}

function __arpg_movement_settings_set_hotkey(_name) {
    var _binding = mmapi_hotkey_binding_from_name(_name);
    if (_binding == undefined) return false;
    if (!__arpg_movement_register_hotkey_name(_name)) return false;

    var _cfg = arpg_movement_config();
    _cfg.auto_select_hotkey = _name;
    arpg_movement_config_save();
    __arpg_movement_log("settings: auto_select_hotkey=" + _name);
    return true;
}

function __arpg_movement_settings_hotkey_popup_message(_popup, _message) {
    _popup.body_text.set_text(_message);
    _popup.body_text.set_text_align(TextAlign.Center);
    _popup.body.set_height(max(
        _popup.body.get_height(),
        _popup.body_text.measure().y + 12
    ));
    _popup.refresh_backplate_height();
}

function __arpg_movement_settings_hotkey_popup_think(_popup) {
    if (_popup.close_requested) return;
    if (_popup.backplate.blackboard.try_take("frame_skip")) return;

    for (var _i = 0; _i < array_length(KEYBOARD_INPUTS); _i++) {
        var _keycode = KEYBOARD_INPUTS[_i];
        // Modifiers are useful as chord parts, but a modifier on its own is an
        // easy accidental binding and leaves no ordinary trigger key.
        if (_keycode == vk_shift || _keycode == vk_control) continue;
        if (!keyboard_check_pressed(_keycode)) continue;

        var _base_name = mmapi_hotkey_name_from_vk(_keycode);
        var _probe = mmapi_hotkey_vk_from_name(_base_name);
        if (_probe == undefined) {
            __arpg_movement_settings_hotkey_popup_message(
                _popup,
                "That key is not supported. Try F1-F12, a letter, digit, or navigation key."
            );
            return;
        }

        var _uses = BINDINGS.inputs_using_keycode(_keycode);
        if (_uses.count() > 0) {
            var _conflict = _uses.get(0);
            var _action = local_get(format(
                "misc_local/input_{InputId}",
                _conflict.input_id
            ));
            __arpg_movement_settings_hotkey_popup_message(
                _popup,
                "That key is already used for " + _action + ". Choose a free key."
            );
            return;
        }

        var _name = _base_name;
        if (keyboard_check(vk_shift)) _name = "SHIFT+" + _name;
        if (keyboard_check(vk_control)) _name = "CONTROL+" + _name;

        if (__arpg_movement_settings_set_hotkey(_name)) {
            _popup.close();
        }
        return;
    }
}

function __arpg_movement_settings_reset_hotkey(_popup) {
    if (__arpg_movement_settings_set_hotkey("F6")) {
        _popup.close();
    }
}

function __arpg_movement_settings_open_hotkey_popup() {
    var _popup = popup_creator(
        "misc_local/controls",
        "misc_local/press_any_input"
    );
    _popup.title.set_text("Auto tool change shortcut");
    __arpg_movement_settings_hotkey_popup_message(
        _popup,
        "Press a free key. Hold Shift or Ctrl for a shortcut."
    );
    _popup.manual_exit_listening = false;
    _popup.create_button("misc_local/cancel").remove_glyph();
    _popup.create_button(
        ANCHOR.wrap_for_local("Use F6"),
        __arpg_movement_settings_reset_hotkey,
        [_popup]
    ).remove_glyph();
    _popup.backplate
        .board_set("frame_skip", true)
        .set_think_callback(
            __arpg_movement_settings_hotkey_popup_think,
            [_popup]
        );
    _popup.spawn();
}

function __arpg_movement_settings_refresh_hotkey(
    _element,
    _button,
    _rule
) {
    var _available = __arpg_movement_settings_rule_enabled(_rule);
    __arpg_movement_settings_set_available(_button, _available);
    _element.set_alpha(_available ? 1 : 0.5);
    _button.text_label.set_text(arpg_movement_config().auto_select_hotkey);
}

function __arpg_movement_settings_add_hotkey(_menu) {
    var _element = _menu.option_scroller.new_element(42);
    ANCHOR.text(_element)
        .set_text("Auto tool change shortcut")
        .set_xy(7, 2)
        .set_align(Align.LeftIn, Align.TopIn);

    var _button = ANCHOR.nine_slice(_element)
        .set_align(Align.LeftIn, Align.BottomIn)
        .set_xy(7, -5)
        .set_size(84, COMMON_BUTTON_HEIGHT)
        .set_sprites_from_key("spr_ui_button")
        .set_tap_callback(__arpg_movement_settings_open_hotkey_popup)
        .add_to_pilot(_menu.option_pilot, true)
        .add_hover_outline()
        .add_text_label(
            "misc_local/rumble",
            COMMON_LUT,
            CommonLutIndex.Dark
        );
    _button.arpg_setting_key = "auto_select_hotkey";
    _button.set_think_callback(
        __arpg_movement_settings_refresh_hotkey,
        [_element, _button, "enabled"]
    );
}

// Debug-agent lookup used only by the registered automated UI drivers. The
// marker lives on the actual tappable node, so tests exercise the same tap
// callback, availability, and popup path as a player.
function __arpg_movement_settings_debug_node(_key) {
    for (var _i = 0; _i < ANCHOR.node_count; _i++) {
        var _node = ANCHOR.node_registrar[| _i];
        if (_node == undefined || _node.freed) continue;
        if (_node[$ "arpg_setting_key"] == _key) return _node;
    }
    return undefined;
}

// Bound to the live SettingsMenu instance before create_category stores it.
function arpg_movement_settings_open_page() {
    __arpg_movement_settings_add_checkbox(
        self,
        "enabled",
        "Enable ARPG Movement",
        "always"
    );

    __arpg_movement_settings_add_section(self, "Mouse movement");
    __arpg_movement_settings_add_checkbox(
        self,
        "hold_to_steer",
        "Hold right mouse to steer",
        "enabled"
    );
    __arpg_movement_settings_add_checkbox(
        self,
        "mouse_move_mounted_only",
        "Steer only while mounted",
        "mounted_mode"
    );
    __arpg_movement_settings_add_checkbox(
        self,
        "tap_to_pathfind",
        "Tap right mouse to move",
        "on_foot_taps"
    );
    __arpg_movement_settings_add_checkbox(
        self,
        "click_to_interact",
        "Approach clicked interactables",
        "on_foot_taps"
    );
    __arpg_movement_settings_add_value(
        self,
        "steer_start_seconds",
        "Steering delay",
        "steering"
    );
    __arpg_movement_settings_add_value(
        self,
        "tap_seconds",
        "Tap release window",
        "tap_timing"
    );
    __arpg_movement_settings_add_value(
        self,
        "stop_within_px",
        "Stop radius",
        "steering"
    );
    __arpg_movement_settings_add_value(
        self,
        "walk_within_px",
        "Walk radius",
        "steering"
    );
    __arpg_movement_settings_add_value(
        self,
        "run_beyond_px",
        "Run radius",
        "steering"
    );
    __arpg_movement_settings_add_value(
        self,
        "interact_radius_px",
        "Ground tap dead zone",
        "tap_move"
    );
    __arpg_movement_settings_add_checkbox(
        self,
        "click_marker",
        "Show destination marker",
        "path_feedback"
    );
    __arpg_movement_settings_add_checkbox(
        self,
        "invalid_click_marker",
        "Show failed-click marker",
        "path_feedback"
    );

    __arpg_movement_settings_add_section(self, "Actions and tools");
    __arpg_movement_settings_add_checkbox(
        self,
        "auto_select_action_item",
        "Automatically change tools",
        "enabled"
    );
    __arpg_movement_settings_add_hotkey(self);
    __arpg_movement_settings_add_value(
        self,
        "sword_enemy_range_px",
        "Mine combat range",
        "auto_tool"
    );
    __arpg_movement_settings_add_checkbox(
        self,
        "face_cursor_on_action",
        "Face actions toward cursor",
        "enabled"
    );
    __arpg_movement_settings_add_checkbox(
        self,
        "cursor_targeting_on_action",
        "Keep cursor aim while moving",
        "enabled"
    );

    __arpg_movement_settings_add_section(self, "Menus");
    __arpg_movement_settings_add_checkbox(
        self,
        "click_outside_closes_menus",
        "Click outside menus to close",
        "enabled"
    );

    __arpg_movement_settings_add_section(self, "Diagnostics");
    __arpg_movement_settings_add_checkbox(
        self,
        "dev_logging",
        "Diagnostic logging",
        "always"
    );
}

// The menu-opened hook runs after SettingsMenu has built its vanilla
// categories, so this safely appends one more category without replacing the
// engine constructor or claiming a new Menu enum value.
function arpg_movement_settings_menu_opened(_ctx) {
    if (_ctx.kind != Menu.Settings) return;

    var _menu = _ctx.menu;
    if (_menu.categories[$ "arpg_movement"] != undefined) return;

    var _open_page = method(_menu, arpg_movement_settings_open_page);
    var _icon = string_to_asset("spr_ui_journal_settings_icon_controls");
    var _category = _menu.create_category(
        "arpg_movement",
        _open_page,
        _icon
    );
    _category.text_label.set_text("ARPG Movement");
    _menu.categories[$ "arpg_movement"] = _category;
}
