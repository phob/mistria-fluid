object_create(
    "obj_dungeon_ladder_down",
    object_reserve("par_ladder"),
    {
        sprite_index: spr_main_dungeon_prototype_instance_door_ladder_down,
        state: LadderState.Spawned,
        create: function() {
            event_inherit(ObjectEvent.Create);
            self.ladder_choice_index = 0;

            self.xstart = self.x;
            self.ystart = self.y;
        },
        step: function() {
            //
            if self.want_to_spawn_collision {
                var ox = self.xstart div 8;
                var oy = self.ystart div 8;

                if collision_rectangle(ox * 8, oy * 8, ox * 8 + 16, oy * 8 + 16, obj_ari) == undefined {
                    var jumpable = self.object_index != obj_dungeon_ladder_up;
                    set_collision_on_node_region(GRID, ox, oy, ox + 1, oy + 1, jumpable);

                    self.want_to_spawn_collision = false;
                }
            }
        },
        draw: function() {
            event_inherit(ObjectEvent.Draw);

            //
            if
                is_dungeon_room(room())
                && DUNGEON_IMPL == DungeonImpl.LadderChoice
                && !TAXI.is_traveling()
            {
                draw_sprite(spr_ui_bark_bubble_think_open, 0, self.x, self.y - 16);
                draw_sprite(
                    spr_mines_level_types,
                    DUNGEON_RUNNER.ladder_choice_options[self.ladder_choice_index],
                    self.x,
                    self.y - 16,
                );
            }
        },
    }
);
