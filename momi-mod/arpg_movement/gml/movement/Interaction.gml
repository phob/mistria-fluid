// ARPG Movement: interactable targeting and approach planning

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


