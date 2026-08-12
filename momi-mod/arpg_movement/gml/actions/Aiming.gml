// ARPG Movement: cursor targeting, facing, and action guards

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


