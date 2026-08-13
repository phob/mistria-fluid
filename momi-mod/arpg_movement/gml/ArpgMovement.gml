// ARPG Movement
//
// Executable top-level boot code lives only in this file. Every other GML
// source in this mod contains definitions only; file initialization order is
// unspecified, but top-level functions are hoisted across the installed tree.

// A menu rebind cannot remove an MMAPI registry entry, so each installed
// binding carries the name it was created for. Old entries remain harmless:
// their callback only acts while that exact name is still current. Returning
// to a previously used name reuses its existing entry instead of registering
// a duplicate.
function __arpg_movement_hotkey_callback() {
    if (arpg_movement_config().auto_select_hotkey != self.hotkey_name) return;
    arpg_movement_toggle_auto_select();
}

function __arpg_movement_register_hotkey_name(_name) {
    var _rt = __arpg_movement_runtime();
    if (_rt.installed_hotkeys == undefined) {
        _rt.installed_hotkeys = {};
    }
    if (_rt.installed_hotkeys[$ _name] == true) return true;

    var _binding = mmapi_hotkey_binding_from_name(_name);
    if (_binding == undefined) return false;

    mmapi_hotkey_register_binding(
        _binding,
        method(
            { hotkey_name: _name },
            __arpg_movement_hotkey_callback
        ),
        { mod_name: "arpg_movement" }
    );
    _rt.installed_hotkeys[$ _name] = true;
    __arpg_movement_log("hotkey: registered " + _name);
    return true;
}

// The toggle hotkey comes from the config, and the config cannot be read at
// top-level boot (file IO is not ready). mmapi_register's first call is the
// first safe IO moment. mmapi_register invokes this repeatedly, so the outer
// latch also keeps the debug-agent registrations one-shot.
function __arpg_movement_install_hotkey() {
    var _rt = __arpg_movement_runtime();
    if (_rt.late_registration_installed) return;
    _rt.late_registration_installed = true;

    __arpg_movement_register_hotkey_name(
        arpg_movement_config().auto_select_hotkey
    );

    // Debug-agent drivers, following the MMAPI pattern: registered only while
    // the agent is enabled, so release users never see them and they claim
    // nothing. They power the automated UI test loop (open a store from the
    // debugger, inject an OS-level click, read this mod's log) that found the
    // gold_canvas outside-click bug — keep them for the next menu hunt.
    var _mmapi_cfg = mmapi_config_load("mmapi");
    if (mmapi_config_get(_mmapi_cfg, "debug_enabled", false) == true) {
        mmapi_debug_register_fn("arpg_movement.debug_open_settings", function() {
            var _journal = ANCHOR.get_menu(Menu.Journal);
            if (_journal == undefined) {
                _journal = ANCHOR.spawn_menu(Menu.Journal);
            }
            _journal.set_active_sub_menu(Menu.Settings);

            var _settings = _journal.sub_menu;
            var _category = _settings.categories[$ "arpg_movement"];
            if (_category == undefined) return "ARPG category missing";

            // Exercise the real tap callback so the option page is built by
            // the same path as a mouse or controller selection.
            ANCHOR.tap_node(_category);
            return "ARPG category opened with "
                + string(array_length(_settings.option_pilot.map))
                + " option nodes";
        }, {
            description: "Open and exercise the ARPG Movement settings page",
            args: [],
        });

        mmapi_debug_register_fn("arpg_movement.debug_setting_state", function(_key) {
            var _node = __arpg_movement_settings_debug_node(_key);
            if (_node == undefined) return "setting node missing: " + _key;
            var _value = arpg_movement_config()[$ _key];
            return _key
                + " value=" + string(_value)
                + " idx=" + string(_node.idx)
                + " unlocked=" + string(_node.is_unlocked())
                + " personal=" + string(_node.safe_unlocked)
                + " enabled=" + string(_node.safe_enabled)
                + " alpha=" + string(_node.cache_alpha);
        }, {
            description: "Read one live ARPG Movement setting node",
            args: [{ name: "key", type: "string" }],
        });

        mmapi_debug_register_fn("arpg_movement.debug_tap_setting", function(_key) {
            var _node = __arpg_movement_settings_debug_node(_key);
            if (_node == undefined) return "setting node missing: " + _key;
            // A scroller marks off-screen children disabled until they enter
            // the viewport. The debug driver may still tap such a personally
            // unlocked node; dependency-locked controls remain protected.
            if (!_node.safe_unlocked) return "setting node locked: " + _key;
            ANCHOR.tap_node(_node);
            return "tapped " + _key
                + " -> " + string(arpg_movement_config()[$ _key]);
        }, {
            description: "Tap one live ARPG Movement setting node",
            args: [{ name: "key", type: "string" }],
        });

        mmapi_debug_register_fn("arpg_movement.debug_close_popup", function() {
            var _popup = ANCHOR.get_menu(Menu.Popup);
            if (_popup == undefined) return "popup missing";
            _popup.close();
            return "popup closed";
        }, {
            description: "Close the active popup after an automated settings test",
            args: [],
        });

        mmapi_debug_register_fn("arpg_movement.debug_set_hotkey", function(_name) {
            var _ok = __arpg_movement_settings_set_hotkey(_name);
            return _ok
                ? "hotkey=" + arpg_movement_config().auto_select_hotkey
                : "invalid hotkey: " + string(_name);
        }, {
            description: "Exercise the in-menu hotkey setter",
            args: [{ name: "name", type: "string" }],
        });

        mmapi_debug_register_fn("arpg_movement.debug_hotkey_registry", function() {
            var _entries = global[$ "__mmapi_binding_hotkeys"];
            if (_entries == undefined) return "registry missing";
            var _report = "";
            for (var _i = 0; _i < array_length(_entries); _i++) {
                if (_entries[_i].mod_name != "arpg_movement") continue;
                if (_report != "") _report += ",";
                _report += mmapi_hotkey_name_from_binding(_entries[_i].binding);
            }
            return _report == "" ? "no ARPG hotkeys" : _report;
        }, {
            description: "List installed ARPG Movement hotkey registry entries",
            args: [],
        });

        mmapi_debug_register_fn("arpg_movement.debug_mounted_path_offset", function(_dx, _dy) {
            var _has_player = instance_exists(obj_ari);
            if (!_has_player) return "player missing";
            var _sid = obj_ari.fsm.current_state_id();
            if (_sid != PlayerState.MountDefault) return "player is not mounted";

            var _tx = obj_ari.x + _dx;
            var _ty = obj_ari.y + _dy;
            var _rt = __arpg_movement_runtime();
            _rt.running = true;
            var _ok = __arpg_movement_mounted_path_to(_rt, _tx, _ty);
            return _ok
                ? "mounted path started to " + string(_tx) + "," + string(_ty)
                : "mounted path refused to " + string(_tx) + "," + string(_ty);
        }, {
            description: "Start a mounted path to an offset for automated testing",
            args: [
                { name: "dx", type: "number" },
                { name: "dy", type: "number" },
            ],
        });

        mmapi_debug_register_fn("arpg_movement.debug_mounted_path_state", function() {
            var _has_player = instance_exists(obj_ari);
            if (!_has_player) return "player missing";
            var _rt = __arpg_movement_runtime();
            return "state=" + string(obj_ari.fsm.current_state_id())
                + " pos=" + string(obj_ari.x) + "," + string(obj_ari.y)
                + " active=" + string(_rt.mounted_path != undefined)
                + " waypoint=" + string(_rt.mounted_path_index)
                + " dest=" + string(_rt.mounted_path_dest_x) + ","
                    + string(_rt.mounted_path_dest_y)
                + " stall=" + string(_rt.mounted_path_stall_frames)
                + " replans=" + string(_rt.mounted_path_replans);
        }, {
            description: "Read mounted path follower state",
            args: [],
        });

        mmapi_debug_register_fn("arpg_movement.debug_open_store", function() {
            ANCHOR.spawn_menu(Menu.Store, Store.General);
        }, { description: "Open the general store menu", args: [] });

        mmapi_debug_register_fn("arpg_movement.debug_node_info", function(_idx) {
            var _target = undefined;
            for (var _i = 0; _i < ANCHOR.node_count; _i++) {
                var _n = ANCHOR.node_registrar[| _i];
                if (_n != undefined && _n.idx == _idx) {
                    _target = _n;
                    break;
                }
            }
            if (_target == undefined) return "node not found";

            var _report = "";
            var _walk = _target;
            while (_walk != undefined && _walk != ANCHOR.screen_canvas) {
                _report += "[idx=" + string(_walk.idx)
                    + " menu=" + (_walk.source_menu == undefined
                        ? "none" : string(_walk.source_menu.type))
                    + " alpha=" + string(_walk.cache_alpha)
                    + " hover=" + string(_walk.listens_for_hovers)
                    + " taps=" + string(_walk.listens_for_taps)
                    + "] <- ";
                _walk = _walk.parent;
            }

            var _root = __arpg_movement_screen_root(_target);
            for (var _m = 0; _m < ANCHOR.open_menus.count(); _m++) {
                var _menu = ANCHOR.open_menus.get(_m);
                var _fields = struct_get_names(_menu);
                for (var _f = 0; _f < array_length(_fields); _f++) {
                    if (_menu[$ _fields[_f]] == _root) {
                        _report += " ROOT=field '" + _fields[_f]
                            + "' of menu type " + string(_menu.type) + ";";
                    }
                }
            }
            __arpg_movement_log("debug: node " + string(_idx) + ": " + _report);
            return _report;
        }, {
            description: "Dump a UI node's parent chain and owning menu field",
            args: [{ name: "idx", type: "number" }],
        });

        mmapi_debug_register_fn("arpg_movement.debug_nodes_at", function(_x, _y) {
            var _report = "";
            for (var _i = 0; _i < ANCHOR.node_count; _i++) {
                var _node = ANCHOR.node_registrar[| _i];
                if (_node == undefined || _node.freed) continue;
                if (!ANCHOR.point_in_node(_node, _x, _y)) continue;
                var _owner = _node.source_menu;
                _report += "[idx=" + string(_node.idx)
                    + " type=" + string(_node.type)
                    + " menu=" + (_owner == undefined ? "none" : string(_owner.type))
                    + " en=" + string(_node.safe_enabled)
                    + " a=" + string(_node.cache_alpha)
                    + " bbox=" + string(_node.cache_bbox_left) + ","
                    + string(_node.cache_bbox_top) + ","
                    + string(_node.cache_bbox_right) + ","
                    + string(_node.cache_bbox_bottom) + "] ";
            }
            if (_report == "") _report = "no nodes contain point";
            __arpg_movement_log("debug: nodes at " + string(_x) + ","
                + string(_y) + ": " + _report);
            return _report;
        }, {
            description: "List every UI node whose bbox contains a GUI point",
            args: [
                { name: "x", type: "number" },
                { name: "y", type: "number" },
            ],
        });
    }
}

// The latched register function. Boot can re-run, this registers exactly once.
function arpg_movement_register_callbacks() {
    var _rt = __arpg_movement_runtime();
    if (_rt.registered_hooks != undefined) return;
    _rt.registered_hooks = true;

    mmapi_on("game.clock_tick", arpg_movement_clock_tick);
    mmapi_on("ui.menu_opened", arpg_movement_settings_menu_opened);
    mmapi_guard("items.use_guard", arpg_movement_items_use_guard);
    mmapi_register(__arpg_movement_install_hotkey);
}

// Boot wiring: memory-only top level.
mmapi_mod_declare("arpg_movement", "2.3.0");
arpg_movement_register_callbacks();
