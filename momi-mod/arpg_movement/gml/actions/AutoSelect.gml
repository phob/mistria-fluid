// ARPG Movement: action target detection and item auto-selection

// True when the physical left button is bound to the repeating tool action.
// That is how the game's "continuous action" option works: it binds the
// button to UseToolRepeated, whose held state re-fires the swing in AriFsm's
// Default step. Only under that binding do held frames need re-selection.
function __arpg_movement_left_is_repeating_action() {
    var _bindings = BINDINGS.bindings[InputId.UseToolRepeated];
    for (var _j = 0; _j < array_length(_bindings); _j++) {
        var _binding = _bindings[_j];
        if (_binding != undefined
            && _binding.type == BindingType.Mouse
            && _binding.keycode == mb_left)
        {
            return true;
        }
    }
    return false;
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
    // This prediction is only read from PlayerState.Default, where steering
    // exists solely when it is enabled and not restricted to riding.
    if (_cfg.hold_to_steer
        && !_cfg.mouse_move_mounted_only
        && mouse_check_button(mb_right)
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

// Node categories the click handler acts on with a specific tool or weapon.
// Everything else (crops, grass, bushes, furniture) falls through to the
// terrain probes regardless of which node the picker returns.
function __arpg_movement_click_actionable(_node) {
    if (_node == undefined) return false;
    switch (object_id_to_object_category(_node.object_id)) {
        case ObjectCategory.Rock:
        case ObjectCategory.Tree:
        case ObjectCategory.Stump:
        case ObjectCategory.DigSite:
        case ObjectCategory.Breakable:
            return true;
    }
    return false;
}

// The grid footprint decides first: every footprint cell maps to its node
// (write_object_inst_node writes all write_size cells), so a click on a cell
// an actionable node occupies IS that node — the player aimed at the tile
// they see it standing on. Renderer bounding boxes must not override this:
// they are bbox-only (the engine has no precise masks), and a tree's box
// includes its whole transparent canopy while its lower base makes it sort
// "drawn on top" of anything standing behind it — ranking renderers by draw
// order alone made every click on such a rock arm the axe for the tree.
//
// Only when the clicked cell holds no actionable node — a genuine canopy or
// sprite-overhang click — do the renderers under the point decide. There the
// most specific sprite wins: smallest bounding box first (a rock's few
// pixels beat a canopy spanning dozens of cells), draw order breaks ties.
function __arpg_movement_clicked_node() {
    var _mx = mouse_x();
    var _my = mouse_y();

    var _cell_node = undefined;
    var _ni = GRID.try_node_index_for_room_position(_mx, _my);
    if (_ni != undefined) {
        _cell_node = GRID.node_parent[_ni];
    }
    if (__arpg_movement_click_actionable(_cell_node)) {
        return _cell_node;
    }

    // One persistent list, cleared per scan. The engine has ds_list_create
    // but NO ds_list_destroy (the game itself never destroys a list) — a
    // destroy call throws at runtime and kills the whole clock_tick handler.
    var _rt = __arpg_movement_runtime();
    if (_rt.click_scan_list == undefined) {
        _rt.click_scan_list = ds_list_create();
    }
    var _list = _rt.click_scan_list;
    ds_list_clear(_list);
    overlap_point_list(_mx, _my, obj_node_renderer, _list);

    var _best = undefined;
    var _best_area = infinity;
    var _best_depth = infinity;
    for (var _i = 0; _i < ds_list_size(_list); _i++) {
        var _renderer = _list[| _i];
        if (_renderer == undefined
            || !instance_exists(_renderer)
            || !__arpg_movement_click_actionable(_renderer.node))
        {
            continue;
        }
        var _area = (_renderer.bbox_right - _renderer.bbox_left)
            * (_renderer.bbox_bottom - _renderer.bbox_top);
        if (_area < _best_area
            || (_area == _best_area && _renderer.depth < _best_depth))
        {
            _best_area = _area;
            _best_depth = _renderer.depth;
            _best = _renderer.node;
        }
    }
    if (_best != undefined) {
        return _best;
    }

    // Nothing actionable anywhere near the click: hand back whatever occupies
    // the cell (possibly undefined) so the terrain probes see the same world
    // the old grid fallback did.
    return _cell_node;
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

// The game's net test (net_target_in_tile) counts more than bugs: a
// Rockclod's flying rocks and lit bombs are legal net targets too, because a
// deliberate swing may catch them. Auto-selection must not turn that trick
// into the default — a click at an incoming rock means "fight", not "catch" —
// so it only offers the net for an actual bug on the cell. A hand-picked net
// survives auto-selection through the held-item check, which still uses the
// game's full test, so catching rocks on purpose keeps working.
function __arpg_movement_bug_in_cell(_cell_x, _cell_y) {
    return collision_rectangle(
        _cell_x * 8,
        _cell_y * 8,
        _cell_x * 8 + 16,
        _cell_y * 8 + 16,
        obj_bug
    ) != undefined;
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
        var _usable;
        if (_tool_type == ToolType.Hoe) {
            _usable = __arpg_movement_hoe_tills_cells(_item, _selection);
        } else if (_tool_type == ToolType.Net) {
            var _bug = __arpg_movement_bug_in_cell(_selection.x, _selection.y);
            _usable = _bug && __arpg_movement_item_affects_cells(_item, _selection);
            if (!_bug
                && __arpg_movement_dev_logging()
                && __arpg_movement_item_affects_cells(_item, _selection))
            {
                __arpg_movement_log("net: suppressed, game test passes with no "
                    + "bug on cell (catchable projectile?) sel="
                    + string(_selection.x) + "," + string(_selection.y));
            }
        } else {
            _usable = __arpg_movement_item_affects_cells(_item, _selection);
        }
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
        if (_tool_type == ToolType.Net
            && !__arpg_movement_bug_in_cell(_cell_x, _cell_y))
        {
            continue;
        }
        if (GRID.item_effects_node_at_cell(_cell_x, _cell_y, _item.prototype)) {
            return _index;
        }
    }
    return undefined;
}

// Fishing rods do not participate in GRID.item_effects_node_at_cell(): vanilla
// validates their landing cell later, when the charged cast is released. Use
// that same landing predicate on the exact cell under the cursor so nearby
// waterable/tillable cells in Ari's limited tool selection cannot steal a
// deliberate click on open water.
function __arpg_movement_clicked_fishable_water() {
    var _ni = GRID.try_node_index_for_room_position(mouse_x(), mouse_y());
    return _ni != undefined
        && GRID.node_terrain_kind[_ni] == TerrainKind.Water
        && !GRID.node_collideable[_ni];
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
    var _pressed = mouse_check_button_pressed(mb_left);

    // Under the continuous-action binding, every repeat of a held swing passes
    // back through Default, so selection may run on held frames too: a held
    // sweep from a tree onto a stone then moves the axe to the pickaxe between
    // swings. Only clicked-node targets re-select during a hold — the terrain
    // probes and the mine weapon draw stay press-only below, so a sweep across
    // tillable dirt cannot till it and a monster wandering close cannot yank
    // the tool mid-swing.
    if (!_pressed
        && (!mouse_check_button(mb_left)
            || !__arpg_movement_left_is_repeating_action()))
    {
        return;
    }
    if (!__arpg_movement_left_is_action()
        || ARI.held_animal_id != undefined)
    {
        return;
    }

    if (__arpg_movement_point_over_actionable_ui()) {
        if (_pressed) {
            __arpg_movement_log("click: over actionable UI, skipped");
        }
        return;
    }

    var _held = ARI.held_item();
    if (_held != undefined
        && __arpg_movement_is_deliberate_placement(_held.prototype.use))
    {
        if (_pressed) {
            __arpg_movement_log("click: held placement item, skipped"
                + __arpg_movement_log_ctx());
        }
        return;
    }

    // In the mines, combat outranks tools: with a live monster close, the
    // weapon wins every world click, even one on a rock — a mid-fight click
    // must never trade the sword for a pickaxe, and a click that misses the
    // monster and lands on an unreachable stone must still draw it. That is
    // why this runs before the clicked-node branch. On held frames the same
    // closeness instead freezes the current item: force-drawing the weapon
    // there would steal a mid-mining pickaxe.
    if (is_dungeon_room(room())) {
        var _weapon_index = __arpg_movement_find_item(ItemUse.Attack);
        if (_weapon_index != undefined
            && __arpg_movement_monster_near(arpg_movement_config().sword_enemy_range_px))
        {
            if (_pressed) {
                __arpg_movement_select_item(_weapon_index);
                __arpg_movement_log("click: mines combat -> weapon slot "
                    + string(_weapon_index) + __arpg_movement_log_ctx());
            }
            return;
        }
    }

    // A held weapon in the mines is combat in progress even while no monster
    // is momentarily in range (it died, it leapt away, the pack scattered): a
    // held sweep never trades it for a tool, or the sword would turn into a
    // pickaxe the instant the last monster falls with the cursor over a
    // stone. A fresh click re-evaluates normally.
    if (!_pressed
        && is_dungeon_room(room())
        && _held != undefined
        && _held.prototype.use == ItemUse.Attack)
    {
        return;
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
                // Vanilla lets either tool excavate a dig site. Prefer the
                // shovel, but fall back to a pickaxe when none is carried.
                var _shovel_index = __arpg_movement_find_item(
                    ItemUse.UseTool, ToolType.Shovel
                );
                _tool_type = _shovel_index == undefined
                    ? ToolType.PickAxe : ToolType.Shovel;
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
                    if (_pressed) {
                        __arpg_movement_log(
                            "click: breakable, no weapon or out of swing range"
                            + __arpg_movement_log_ctx());
                    }
                    return;
                }
                var _prev_slot = ARI.held_item_index;
                __arpg_movement_select_item(_weapon_index);
                if (_pressed || ARI.held_item_index != _prev_slot) {
                    __arpg_movement_log((_pressed ? "click" : "sweep")
                        + ": breakable -> weapon slot " + string(_weapon_index)
                        + __arpg_movement_log_ctx());
                }
                return;
        }

        if (_tool_type != undefined) {
            var _tool_index = __arpg_movement_find_item(ItemUse.UseTool, _tool_type, _minimum_quality);
            if (_tool_index == undefined) {
                if (_pressed) {
                    __arpg_movement_log("click: node cat=" + string(_category)
                        + " needs tool type " + string(_tool_type)
                        + ", none usable in inventory" + __arpg_movement_log_ctx());
                }
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
                // Out of swing range. This is common even point-blank: a
                // tree's chop cells are only the 2x2 trunk at footprint
                // top_left + 2..3, so a click on the visible wood of a big
                // tree or log often selects cells the axe cannot act on. A
                // fresh click still voices intent — arm the tool and let the
                // swing whiff exactly as vanilla would, so the player steps
                // in and the next swing lands. A held sweep is aim, not
                // intent: it only switches when the target is truly in range.
                if (_pressed) {
                    __arpg_movement_select_item(_tool_index);
                    __arpg_movement_log("click: node cat=" + string(_category)
                        + " obj=" + string(_node.object_id)
                        + " tl=" + string(_node.top_left_x) + "," + string(_node.top_left_y)
                        + " out of reach, armed tool slot " + string(_tool_index)
                        + " anyway, sel=" + string(_selection.x) + "," + string(_selection.y)
                        + __arpg_movement_log_ctx());
                }
                return;
            }
            var _prev_slot = ARI.held_item_index;
            __arpg_movement_select_item(_tool_index);
            if (_pressed || ARI.held_item_index != _prev_slot) {
                __arpg_movement_log((_pressed ? "click" : "sweep")
                    + ": node cat=" + string(_category)
                    + " obj=" + string(_node.object_id)
                    + " tl=" + string(_node.top_left_x) + "," + string(_node.top_left_y)
                    + " -> tool slot " + string(_tool_index)
                    + __arpg_movement_log_ctx());
            }
            return;
        }
    }

    // Held sweeps end at node targets. The terrain probes below run on fresh
    // clicks only: re-running them per repeat would let a held sweep across
    // tillable dirt till it, or swing the net at a bug the cursor grazed.
    if (!_pressed) {
        return;
    }

    // A rod's eventual landing cell is based on facing and charge distance,
    // not update_cell_select(), so the generic terrain probes cannot discover
    // it. The exact clicked water cell is still clear player intent: arm the
    // rod now and let vanilla's normal charge/release logic choose and validate
    // the actual landing cell.
    if (__arpg_movement_clicked_fishable_water()) {
        var _rod_index = __arpg_movement_find_item(
            ItemUse.UseTool, ToolType.FishingRod
        );
        if (_rod_index != undefined) {
            __arpg_movement_select_item(_rod_index);
            __arpg_movement_log("click: fishable water -> fishing rod slot "
                + string(_rod_index) + __arpg_movement_log_ctx());
        } else {
            __arpg_movement_log("click: fishable water, no fishing rod in inventory"
                + __arpg_movement_log_ctx());
        }
        return;
    }

    // The clicked object had no explicit required tool. Preserve a hand-picked
    // item that the game says can act on the selected cells.
    if (_held != undefined && __arpg_movement_item_affects_cells(_held, _selection)) {
        __arpg_movement_log("click: held item already acts on selection, kept"
            + __arpg_movement_log_ctx());
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
        __arpg_movement_log("click: terrain tool -> slot " + string(_terrain_index)
            + " sel=" + string(_selection.x) + "," + string(_selection.y)
            + __arpg_movement_log_ctx());
        return;
    }

    // Every remaining click — no recognized target, no terrain tool, and no
    // monster in reach (handled up front) — keeps the current selection.
    __arpg_movement_log("click: no auto target, selection kept"
        + __arpg_movement_log_ctx());
}

