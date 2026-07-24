//
//
function find_npc_at_or_approaching(location_position, npc_to_ignore) {
    for (var i = 0; i < NpcId.LEN; i++) {
        if DEBUG_TOOLS && !NPC_WHITELIST[i] {
            continue;
        }

        if npc_to_ignore == i {
            continue;
        }
        var npc = NPCS[i];
        var currently_present = npc.location_position.eq(location_position);
        var approaching =
            npc.itinerary != undefined
            && npc.itinerary.items.last().target_location.eq(location_position);
        var brain_order =
            npc.brain.blackboard.get("next_location") != undefined
            && npc.brain.blackboard.get("next_location").eq(location_position);
        if currently_present || approaching || brain_order {
            return i;
        }
    }
    return undefined;
}

//
//
function npcs_enter_pause_animations(conversation) {
    //
    with par_NPC {
        //
        self.restore_animation = undefined;
        self.restore_cardinality = undefined;

        if conversation != undefined && T2R.npc_is_speaker_in_conversation(conversation, self.npc_id) {
            //
            if self.animator.sprite_pack_collection.on_pause_speaking != undefined {
                self.restore_animation = self.me.animation;
                self.me.set_animation(self.animator.sprite_pack_collection.on_pause_speaking);
            }

            //
            if self.animator.sprite_pack_collection.on_pause_speaking_turn
                && T2R.conversation_is_group(conversation) == false
            {
                //
                self.restore_cardinality = self.animator.cardinality;
                self.me.set_cardinality(angle_to_cardinal(point_direction(self.x, self.y, obj_ari.x, obj_ari.y)));
            }
        } else if self.animator.sprite_pack_collection.on_pause_background != undefined {
            self.restore_animation = self.me.animation;
            self.me.set_animation(self.animator.sprite_pack_collection.on_pause_background);
        }

        self.animate();
    }
}

function npcs_exit_pause_animations() {
    with par_NPC {
        if self.restore_animation != undefined {
            self.me.set_animation(self.restore_animation);
        }

        if self.restore_cardinality != undefined {
            self.me.set_cardinality(self.restore_cardinality);
        }

        self.restore_cardinality = undefined;
        self.restore_animation = undefined;

        self.animate();
    }
}

function get_small_npc_icon(npc_id) {
    if npc_id == NpcId.Seridia {
        return npc_is_unlocked(npc_id)
            ? spr_ui_generic_icon_npc_small_seridia
            : spr_ui_generic_icon_npc_small_priestess;
    } else {
        return NPC_PROTOTYPES[npc_id].small_icon_sprite;
    }
}

function get_small_outlined_npc_icon(npc_id) {
    if npc_id == NpcId.Seridia {
        return npc_is_unlocked(npc_id)
            ? spr_ui_generic_icon_npc_small_outline_seridia
            : spr_ui_generic_icon_npc_small_outline_priestess;
    } else {
        return NPC_PROTOTYPES[npc_id].small_outlined_icon_sprite;
    }
}

function get_npc_icon(npc_id) {
    if npc_id == NpcId.Seridia {
        return npc_is_unlocked(npc_id)
            ? spr_ui_generic_icon_npc_seridia
            : spr_ui_generic_icon_npc_priestess;
    } else {
        return NPC_PROTOTYPES[npc_id].icon_sprite;
    }
}

function most_special_human() {
    return ListFromArray([
            NpcId.Adeline,
            NpcId.Celine,
            NpcId.Balor,
            NpcId.Eiland,
            NpcId.Hayden,
            NpcId.March,
            NpcId.Juniper,
            NpcId.Reina,
            NpcId.Ryis,
            NpcId.Valen,
        ])
        .sort_with(function(a, b) {
            var ap = NPCS[a];
            var bp = NPCS[b];

            if ap.is_spouse() != bp.is_spouse() {
                return ap.is_spouse() ? -1 : 1;
            }

            if ap.is_fiance() != bp.is_fiance() {
                return ap.is_fiance() ? -1 : 1;
            }

            if ap.is_dating() != bp.is_dating() {
                return ap.is_dating() ? -1 : 1;
            }

            if ap.is_best_friend() != bp.is_best_friend() {
                return ap.is_best_friend() ? -1 : 1;
            }

            if ap.heart_points == bp.heart_points {
                return 0;
            } else {
                return ap.heart_points > bp.heart_points ? -1 : 1;
            }

        })
        .first();
}

//
//
function spouse_wake_position() {
    var p_bed = player_bed();

    if p_bed != undefined {
        var spouse_bed = undefined;
        var p_node = GRIDS[p_bed.location_id].node_parent[p_bed.ni];
        if p_node.prototype.bed_kind == BedKind.Double {
            spouse_bed = p_bed;
        } else {
            spouse_bed = all_player_beds().find(function(a, b) {
                return a.location_id != b.location_id || a.ni != b.ni;
            }, p_bed);
        }

        if spouse_bed != undefined {
            var node = GRIDS[spouse_bed.location_id].node_parent[spouse_bed.ni];
            var offset = bed_sleep_offset(node.object_id, true);
            return new LocationPosition(
                spouse_bed.location_id,
                Vec2(node.top_left_x * 8 + offset.x, node.top_left_y * 8 + offset.y),
            );
        }
    }

    warn("Couldn't find any bed for spouse! Using a safe position...");
    return new LocationPosition(
        LocationId.PlayerHome,
        player_home_safe_position(LocationId.PlayerHome),
    );
}

//
function test_most_special_human() {
    var original = array_create_ext(NpcId.LEN, function(i) {
        return [NPCS[i].heart_points, T2R.read(format("{NpcId}_status", i))];
    });

    static RESET = function() {
        for (var i = 0; i < NpcId.LEN; i++) {
            T2R.write(format("{NpcId}_status", i), undefined);
            NPCS[i].heart_points = 0;
        }
    }

    static SET = function(npc, hearts, status) {
        NPCS[npc].heart_points = hearts;
        T2R.write(format("{NpcId}_status", npc), status ?? "undefined");
    }

    RESET();
    SET(NpcId.Adeline, 10);
    SET(NpcId.Eiland, 0, "best_friend");
    assert_eq(most_special_human(), NpcId.Eiland);

    RESET();
    SET(NpcId.Adeline, 10, "best_friend");
    SET(NpcId.Eiland, 0, "best_friend");
    assert_eq(most_special_human(), NpcId.Adeline);

    RESET();
    SET(NpcId.Adeline, 0, "best_friend");
    SET(NpcId.Eiland, 0, "dating");
    assert_eq(most_special_human(), NpcId.Eiland);

    RESET();
    SET(NpcId.Adeline, 5, "dating");
    SET(NpcId.Eiland, 8, "best_friend");
    SET(NpcId.Valen, 10);
    SET(NpcId.Juniper, 6, "dating");
    assert_eq(most_special_human(), NpcId.Juniper);

    RESET();
    SET(NpcId.Caldarus, 10, "dating");
    SET(NpcId.Adeline, 1);
    assert_eq(most_special_human(), NpcId.Adeline);

    RESET();
    SET(NpcId.Adeline, 5, "dating");
    SET(NpcId.Eiland, 1, "spouse");
    assert_eq(most_special_human(), NpcId.Eiland);

    for (var i = 0; i < NpcId.LEN; i++) {
        T2R.write(format("{NpcId}_status", i), original[i][1]);
        NPCS[i].heart_points = original[i][0];
    }
}

function fade_value(obj, value, start, target, len) {
    obj[$ value] = start;
    new_chain().append(LinkId.Ease, new Ease(EaseId.Linear, start, target, len), function(_, a, inst, value) {
        var early_exit = is_struct(inst) ? false : !instance_exists(inst);
        if early_exit {
            return;
        }
        inst[$ value] = a;
    }, [obj, value])
}
