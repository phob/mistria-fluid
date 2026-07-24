#macro NPCS global.__npc_database
global.__npc_database = undefined;

#macro NPC_WHITELIST global.__npc_whitelist
global.__npc_whitelist = array_create(NpcId.LEN, true);

function npcs_on_step() {
    if DEBUG_TOOLS {
        var span = profile_span_start("npcs_on_step");
    }

    //
    var c_location_id = gm_room_to_location_id(room());

    for (var i = 0; i < NpcId.LEN; i++) {
        if DEBUG_TOOLS && !NPC_WHITELIST[i] {
            continue;
        }

        var npc = NPCS[i];

        //
        //
        var in_this_room = npc.location_position.location_id == c_location_id;
        if in_this_room && !instance_exists(npc_id_to_gm_obj_id(i)) {
            var new_inst = spawn_npc(i);
            new_inst.look_for_entry_transition();
        }

        npc.activity_handler.run();

        //
        if npc.brain_dead {
            //
            if npc.activity_handler.needs_brain() || T2R.schedule_will_execute(i, CLOCK.time) {
                npc.brain_dead = false;
                npc.brain.ticks_until_run = 0;
            } else {
                continue;
            }
        }

        if npc.brain.ticks_until_run <= 0 {
            run_brain(npc.brain);
            npc.brain.ticks_until_run = in_this_room
                ? IN_ROOM_BRAIN_FREQUENCY
                : OUT_OF_ROOM_BRAIN_FREQUENCY;
        } else {
            npc.brain.ticks_until_run -= 1;
        }
    }

    if DEBUG_TOOLS {
        profile_span_stop(span);
    }
}

function interrupt_npc(npc) {
    npc.brain.interrupt();
    npc.brain.blackboard.set("me", npc);
    npc.itinerary = undefined;
}

//
function npcs_time_jump(time, old_time, skip_pathfinding=false) {
    assert(time >= old_time, "internal time jump error -- we can't jump from {} to {}", time, old_time);

    //
    var npc_state_info = array_create(NpcId.LEN, undefined);

    for (var npc_id = 0; npc_id < NpcId.LEN; npc_id++) {
        if DEBUG_TOOLS && !NPC_WHITELIST[npc_id] {
            continue;
        }
        var npc = NPCS[npc_id];

        //
        npc.brain_dead = false;
        var npc_inst = instance_find(npc_id_to_gm_obj_id(npc_id), 0);
        var in_room = false;
        if npc_inst != undefined {
            instance_destroy(npc_inst);
            in_room = true;
        }
        interrupt_npc(npc);

        //
        //
        var current_schedule_data = T2R.schedule_current_action(npc_id);
        npc_state_info[npc_id] = {
            location_position: npc.location_position,
            going_to: trellis_point_location_position(current_schedule_data.point),
            time: current_schedule_data.time,
            in_room,
        };
    }

    while true {
        //
        var output = T2R.schedule_execute_any(time, CALENDAR.time);
        if output == undefined {
            break;
        }

        var state_info = npc_state_info[output.npc_id];
        if state_info == undefined {
            continue;
        }

        //
        for (var a = 0, c = array_length(output.on_arrival_actions); a < c; a++) {
            process_t2_action(output.on_arrival_actions[a], output.npc_id);
        }
        for (var a = 0, c = array_length(output.expiration_actions); a < c; a++) {
            process_t2_action(output.expiration_actions[a], output.npc_id);
        }
        for (var a = 0, c = array_length(output.on_departure_actions); a < c; a++) {
            process_t2_action(output.on_departure_actions[a], output.npc_id);
        }

        state_info.location_position = state_info.going_to;
        state_info.going_to = trellis_point_location_position(output.point);
        state_info.time = output.time;
        NPCS[output.npc_id].simulated_distance_traveled = 0;
    }

    for (var npc_id = 0; npc_id < NpcId.LEN; npc_id++) {
        var state_info = npc_state_info[npc_id];
        if state_info == undefined {
            continue;
        }
        var npc = NPCS[npc_id];

        //
        if npc.activity_handler.state != ActivityState.Inactive {
            continue;
        }

        //
        npc.location_position = state_info.location_position.clone();

        //
        //
        if T2R.schedule_current_action_has_arrived(npc_id) || skip_pathfinding {
            continue;
        }

        if time > state_info.time {
            var itinerary = PATHFINDING.calculate_map_path(npc.location_position, state_info.going_to);

            simulate_pathfind(npc_id, state_info.time, time, itinerary);
        }

        //
        if !MIST.running && npc.location_position.location_id == CURRENT_LOCATION_ID {
            spawn_npc(npc_id);
        }

        //
        run_brain(npc.brain);
    }

    if skip_pathfinding {
        return;
    }

    //
    for (var npc_id = 0; npc_id < NpcId.LEN; npc_id++) {
        if DEBUG_TOOLS && !NPC_WHITELIST[npc_id] {
            continue;
        }

        var npc = NPCS[npc_id];

        //
        //
        //
        var loop_breaker = 100;
        while true {
            var ender = false;

            switch npc.activity_handler.state {
                case ActivityState.Inactive:
                    ender = true;
                    break;
                case ActivityState.Traveling:
                    var itinerary = PATHFINDING.calculate_map_path(
                        npc.location_position,
                        npc.activity_handler.target_location,
                    );

                    var time_remaining = simulate_pathfind(
                        npc_id,
                        npc.activity_handler.start_time,
                        time,
                        itinerary,
                        false,
                    );

                    if itinerary.on_last_item() {
                        npc.activity_handler.run(time - time_remaining);
                    } else {
                        ender = true;
                    }
                    break;
                case ActivityState.Active:
                    if time >= npc.activity_handler.end_time {
                        npc.activity_handler.clear_activity();
                    } else {
                        ender = true;
                    }
                    break;
                default: impossible("unexpected activity_handler state");
            }

            loop_breaker -= 1;

            if ender || loop_breaker <= 0 {
                break;
            }
        }
    }
}

function npcs_on_room_start() {
    for (var i = 0; i < NpcId.LEN; i++) {
        if DEBUG_TOOLS && !NPC_WHITELIST[i] {
            continue;
        }
        var npc = NPCS[i];

        //
        if npc.location_position != undefined && npc.location_position.location_id == CURRENT_LOCATION_ID {
            spawn_npc(i);
        }
    }
}

function npcs_on_new_day() {
    for (var i = 0; i < NpcId.LEN; i++) {
        if DEBUG_TOOLS && !NPC_WHITELIST[i] {
            continue;
        }

        var npc = NPCS[i];

        //
        npc.times_spoken_today = 0;
        npc.gift_flag = true;
        npc.set_animation("idle");
        npc.activity_handler.reset();
        npc.simulated_distance_traveled = 0;

        npc.wardrobe.set_outfit(npc.prototype.get_suitable_outfit_key(npc.wardrobe, CALENDAR.time));
        interrupt_npc(npc);

        var schedule_end = T2R.schedule_end(i);
        for (var k = 0, c = array_length(schedule_end.on_arrival_actions); k < c; k++) {
            process_t2_action(schedule_end.on_arrival_actions[k], i);
        }
        for (var k = 0, c = array_length(schedule_end.on_departure_actions); k < c; k++) {
            process_t2_action(schedule_end.on_departure_actions[k], i);
        }

        //
        var new_schedule_name = T2R.request_schedule(i);
        var schedule_selected = T2R.schedule_start(i, new_schedule_name);

        //
        npc.location_position = trellis_point_location_position(schedule_selected.point);
        for (var k = 0, c = array_length(schedule_selected.actions); k < c; k++) {
            process_t2_action(schedule_selected.actions[k], i);
        }

        //
        T2R.write(format("is_{NpcId}_birthday", i), npc.is_birthday());
    }
}

function spawn_npc(npc_id) {
    var obj = npc_id_to_gm_obj_id(npc_id);
    with obj {
        instance_destroy();
    }
    var npc = NPCS[npc_id];
    var new_inst = instance_create_layer(
        npc.location_position.pos.x,
        npc.location_position.pos.y,
        "Instances",
        obj,
    );
    new_inst.initialize(npc);
    return new_inst;
}

function simulate_pathfind(npc_id, start_time, target_time, itinerary, execute_t2=true) {
    var npc = NPCS[npc_id];

    var simulated_time = start_time;
    while target_time > simulated_time {
        simulated_time += GAME_SECONDS_PER_FRAME;
        npc.simulated_distance_traveled += HUMAN_WALK_SPEED;
        var itinerary_item = itinerary.items.get(itinerary.cursor);

        if npc.simulated_distance_traveled >= itinerary_item.distance {
            npc.simulated_distance_traveled = 0;
            if itinerary.on_last_item() {
                npc.location_position = itinerary_item.target_location.clone();
                npc.brain.blackboard.remove("next_location");

                if execute_t2 {
                    var actions = T2R.schedule_arrived_at_destination(npc_id, CALENDAR.time + target_time);
                    if actions != undefined {
                        for (var a = 0, c = array_length(actions); a < c; a++) {
                            process_t2_action(actions[a], npc_id);
                        }
                    }
                }

                break;
            } else {
                npc.location_position = itinerary.advance_path(npc).clone();
            }
        }
    }

    return max(target_time - simulated_time, 0);
}
