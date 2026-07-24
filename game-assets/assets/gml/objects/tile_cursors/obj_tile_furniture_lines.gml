object_create(
    "obj_tile_furniture_lines",
    undefined,
    {
        sprite_index: undefined,
        create: function() {
            valid = false;
            cursor_data = undefined;
            splotch_data = undefined;
            line_alpha = 1.0
        },
        step_begin: function() {
            self.splotch_data = undefined;
            self.cursor_data = undefined;
        },
        draw: function() {
            if self.splotch_data != undefined {
                draw_test_placement_furniture_splotches(
                    self.valid,
                    self.splotch_data,
                    x,
                    y,
                );
            }

            if self.cursor_data != undefined {
                draw_test_placement_furniture_lines(
                    self.valid,
                    self.cursor_data,
                    x,
                    y,
                    self.line_alpha,
                );
            }
        },
    }
);
