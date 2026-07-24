function DefaultNpcBrain() {
    var brain = NewTreeBuilder();
    return brain.build(
        Selector(
            //
            Run(function(bb) {
                var me = bb.get("me");

                if me.is_roommate() {
                    //
                    var instance = bb.get("instance");
                    if instance != undefined && instance.kissing {
                        return Status.Err;
                    }

                    //
                    var state = bb.get("roommate_state");
                    var target_state = undefined;
                    if CLOCK.time < ROOMMATE_TIMES.wake_up {
                        target_state = RoommateState.Sleep;
                    } else if CLOCK.time < ROOMMATE_TIMES.go_out {
                        target_state = RoommateState.Routine;
                    } else if CLOCK.time < ROOMMATE_TIMES.come_home {
                        //
                        target_state = me.location_position.location_id != CURRENT_LOCATION_ID
                            ? RoommateState.Schedule
                            : state;
                    } else if CLOCK.time < ROOMMATE_TIMES.sleep {
                        //
                        target_state = me.location_position.location_id != CURRENT_LOCATION_ID
                            ? RoommateState.Routine
                            : state;
                    } else {
                        target_state = RoommateState.Sleep;
                    }

                    //
                    if target_state != state {
                        bb.insert("roommate_state", target_state);
                        switch target_state {
                            case RoommateState.Sleep:
                                //
                                //
                                //
                                break;
                            case RoommateState.Routine:
                                me.activity_handler.set_routine(me.prototype.roommate_routine);
                                break;
                            case RoommateState.Schedule:
                                var tp = T2R.schedule_current_destination(me.id);
                                me.location_position = trellis_point_location_position(tp);

                                //
                                var start_time = hours(6);
                                while true {
                                    var output = T2R.schedule_execute(me.id, CALENDAR.unified_time());
                                    if output == undefined {
                                        break;
                                    }
                                    start_time = output.time;
                                }

                                //
                                var tp = T2R.schedule_current_destination(me.id);
                                var target = trellis_point_location_position(tp);
                                var itinerary = PATHFINDING.calculate_map_path(me.location_position, target);
                                simulate_pathfind(me.id, start_time, CLOCK.time, itinerary);
                                start_schedule_pathfind(bb, target);

                                //
                                //
                                bb.insert("roommate_state", target_state);


                                //
                                //
                                //
                                me.activity_handler.reset();

                                return Status.Err;
                            default: impossible("Unexpected RoommateState: {RoommateState}", target_state)
                        }
                    }

                    if target_state != RoommateState.Schedule {
                        return Status.Err;
                    }
                }

                var output = T2R.schedule_execute(me.id, CALENDAR.unified_time());
                if output == undefined {
                    if T2R.schedule_current_action_has_arrived(me.id) {
                        return Status.Err;
                    }

                    //
                    //
                    var new_destination = T2R.schedule_current_destination(me.id);
                    output = {
                        type: undefined,
                        point: new_destination,
                    };
                }

                if output.type == T2OutputId.ScheduleState {
                    for (var k = 0, c = array_length(output.actions); k < c; k++) {
                        process_t2_action(output.actions[k], me.id);
                    }
                }

                start_schedule_pathfind(bb, trellis_point_location_position(output.point));
                return Status.Err;
            }),

            //
            ServeBarSubTree(),
            ServeTableSubTree(),
            OrderSubTree(Activity.OrderFood),
            OrderSubTree(Activity.OrderDrink),

            //
            Invert(PathfindingSubTree()),

            //
            //
            //
        ),
    );
}

function MistNpcBrain() {
    var brain = NewTreeBuilder();
    return brain.build(
        Selector(
            //
            ServeBarSubTree(),
            ServeTableSubTree(),
            OrderSubTree(Activity.OrderFood),
            OrderSubTree(Activity.OrderDrink),

            //
            Invert(PathfindingSubTree()),
        ),
    );
}

function CameoBrain() {
    var brain = NewTreeBuilder();
    return brain.build(
        Selector(
            Invert(PathfindingSubTree()),
        ),
    );
}


function start_schedule_pathfind(bb, next_location) {
    var me = bb.get("me");
    var instance = bb.get("instance");
    bb.clear();
    bb.insert("me", me);
    bb.insert("instance", instance);

    bb.set("next_location", next_location);
    bb.set("on_arrived_at_next_location", function(bb) {
        var me = bb.get("me");
        var actions = T2R.schedule_arrived_at_destination(me.id, CALENDAR.unified_time());
        if actions != undefined {
            for (var i = 0, c = array_length(actions); i < c; i++) {
                process_t2_action(actions[i], me.id);
            }
        }
        me.brain_dead = true;
    });
}

//
enum RoommateState {
    Sleep,
    Routine,
    Schedule
}
