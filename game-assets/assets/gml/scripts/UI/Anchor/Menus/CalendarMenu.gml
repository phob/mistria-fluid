function CalendarMenu(ari) : AnchorMenu(Menu.Calendar) constructor {
    self.filter = function(time) {
        var year = years(get_years(self.time));
        return time >= year && time < year + years(1);
    };
    self.show_events_flag = true;
    self.pilot = undefined;
    self.pilot_cache = undefined;
    self.time = 0;
    self.ari = ARI;
    self.select_callback = undefined;
    self.show_year_flag = true;
    self.today = undefined;

    function on_close() {
        if self.pilot_cache != undefined {
            ANCHOR.set_active_pilot(self.pilot_cache);
        }
    }

    //
    function with_time(time) {
        self.time = time;
        return self;
    }

    //
    function with_today(today) {
        self.today = today;
        return self;
    }

    //
    function with_ari(ari) {
        self.ari = ari;
        return self;
    }

    //
    //
    //
    function with_filter(filter) {
        self.filter = filter;
        return self;
    }

    //
    function show_events(show_events_flag=true) {
        self.show_events_flag = show_events_flag;
        return self;
    }

    //
    //
    function enable_selection(select_callback) {
        self.select_callback = select_callback;
        return self;
    }

    //
    function show_year(show_year_flag=true) {
        self.show_year_flag = show_year_flag;
        return self;
    }

    function with_banner(banner) {
        //
        todo();
    }

    //
    function build() {
        var season = get_seasons(self.time);
        var day = get_days(self.time);

        self.backplate = ANCHOR.sprite(self.canvas)
            .set_align(Align.Center, Align.Middle)
            .set_sprite(string_to_asset(format("spr_ui_calendar_backplate_{Season}", season)))

        self.title = ANCHOR.text(self.backplate)
            .set_align(Align.Center, Align.TopIn)
            .set_xy(5, 13)
            .set_lut(COMMON_LUT)

        self.arrow_left_button = ANCHOR.nine_slice(self.backplate)
            .set_sprites_from_key(format("spr_ui_calendar_button_{Season}", season))
            .set_size(16)
            .add_glyph(InputId.MenuTabLeft, undefined, true)
            .set_tap_sound("SoundEffects/UI/UIJournalTabSwitch")
            .set_xy(8, 12)
            .set_tap_callback(function() {
                self.time -= seasons(1);
                self.refresh();
            })

        self.arrow_left_icon = ANCHOR.sprite(self.arrow_left_button)
            .set_align(Align.Center, Align.Middle)
            .set_sprites_from_key(format("spr_ui_calendar_left_arrow_{Season}", season))
            .set_key_sprite_target(self.arrow_left_button)

        self.arrow_right_button = ANCHOR.nine_slice(self.backplate)
            .set_sprites_from_key(format("spr_ui_calendar_button_{Season}", season))
            .set_size(16)
            .add_glyph(InputId.MenuTabRight)
            .set_tap_sound("SoundEffects/UI/UIJournalTabSwitch")
            .set_xy(-8, 12)
            .set_align(Align.RightIn, Align.TopIn)
            .set_tap_callback(function() {
                self.time += seasons(1);
                self.refresh();
            })

        self.arrow_right_icon = ANCHOR.sprite(self.arrow_right_button)
            .set_align(Align.Center, Align.Middle)
            .set_sprites_from_key(format("spr_ui_calendar_right_arrow_{Season}", season))
            .set_key_sprite_target(self.arrow_right_button)

        self.season_icon = ANCHOR.sprite(self.title)
            .set_align(Align.LeftOut, Align.Middle)
            .set_x(-2)

        self.grid_area = ANCHOR.positional(self.backplate)
            .set_xy(18, 52)
            .set_size(274, 157)

        self.refresh();

        return self;
    }

    //
    function refresh() {
        var season = get_seasons(self.time);
        var day = get_days(self.time);
        var year = get_years(self.time);

        if self.pilot_cache == undefined {
            self.pilot_cache = ANCHOR.get_active_pilot();
        }
        self.pilot = self.new_pilot()
            .allow_horizontal_wrapping()
            .allow_vertical_wrapping()

        self.backplate.set_sprite(string_to_asset(format("spr_ui_calendar_backplate_{Season}", season)))

        var lut_index = season + 1;
        var season_display = local_get(format("misc_local/{Season}", season));
        var year_insert = self.show_year_flag ? format(" - {Local} {}", "misc_local/year", year + 1) : "";
        self.title.set_text(season_display + year_insert);
        self.title.set_lut_index(lut_index + 8);
        self.season_icon.set_sprite(string_to_asset(format(
            "spr_ui_calendar_icon_{}",
            season == Season.Fall ? "autumn" : season_to_string(season)
        )));

        self.arrow_left_button.set_sprites_from_key(format("spr_ui_calendar_button_{Season}", season));
        self.arrow_left_icon.set_sprites_from_key(format("spr_ui_calendar_left_arrow_{Season}", season));
        self.arrow_right_button.set_sprites_from_key(format("spr_ui_calendar_button_{Season}", season));
        self.arrow_right_icon.set_sprites_from_key(format("spr_ui_calendar_right_arrow_{Season}", season));

        var previous_season_valid = true;
        var next_season_valid = true;
        var start_of_season = self.time - days(get_days(self.time));
        for (var i = 0; i < 28; i++) {
            var previous = start_of_season - seasons(1) + days(i);
            var next = start_of_season + seasons(1) + days(i);
            if previous < 0 || !self.filter(previous) {
                previous_season_valid = false;
            }
            if !self.filter(next) {
                next_season_valid = false;
            }
        }

        self.arrow_left_button.set_unlocked(previous_season_valid);
        self.arrow_right_button.set_unlocked(next_season_valid);

        ANCHOR.free_children(self.grid_area);
        var assets = ListFromArray(array_create_ext(28, identity));
        var layout = new GridLayout(assets, self.pilot, 7, 40);
        while layout.has_next() {
            var output = layout.next(self.grid_area);
            var this_time = start_of_season + days(output.iter);
            var passes_filter = self.filter(this_time);
            var alpha = 1;
            if !passes_filter || (self.today != undefined && this_time < self.today) {
                alpha = 0.4;
            }

            var tile = output.square;
            tile
                .listen_for_hovers()
                .set_sprites_from_key("spr_nothing_nineslice")
                .set_hovered_untappable_sprite(spr_ui_generic_box_hovered_untappable)
                .set_hovered_sprite(spr_ui_generic_box_hovered_untappable)

            if self.time == this_time && ANCHOR.in_directional_control() {
                self.pilot.force_select(tile);
            }

            if self.select_callback != undefined {
                tile.set_tap_callback(function(this_time) {
                    self.time = this_time;
                    self.select_callback(self);
                }, [this_time]);
                tile.set_soft_locked(!passes_filter);
            }

            var num = ANCHOR.text(tile)
                .set_xy(3, 3)
                .set_sprite_font("calendar_font_number")
                .set_lut(spr_ui_calendar_font_number_lut)
                .set_text(get_days(this_time) + 1)
                .set_alpha(alpha)
                .set_z(tile.get_z() - 50);


            static MAKE_BUBBLE = function(tile, name) {
                var width = string_width_font(name) + 24;
                var bubble = ANCHOR.nine_slice(tile);
                bubble
                    .set_sprite(spr_ui_calendar_popup_box)
                    .set_size(width, 18)
                    .set_alpha(0)
                    .set_align(Align.Center, Align.TopOut)
                    .set_z(tile.get_z() - 200)
                    .set_think_callback(function(tile, bubble) {
                        bubble.set_alpha(tile.is_hovered())
                    }, [tile, bubble])

                var text = ANCHOR.text(bubble)
                    .set_text(name)
                    .set_align(Align.Center, Align.Middle)
                    .set_lut(COMMON_LUT)

                return {
                    bubble: bubble,
                    text: text,
                }
            }

            var bubble = undefined;
            var sprite = undefined;
            var name = undefined;
            var pos = undefined;
            if self.show_events_flag {
                for (var i = 0; i < NpcId.LEN; i++) {
                    var npc = NPCS[i];
                    if npc.has_met()
                        && npc_is_unlocked(i)
                        && npc.prototype.birthday.season == season
                        && npc.prototype.birthday.day - 1 == get_days(this_time)
                    {
                        sprite = get_npc_icon(i);
                        name = format(local_get("misc_local/birthday_template"), local_get(npc.prototype.name));
                        pos = Vec2(0, 0);
                    }
                }
                for (var i = 0; i < FestivalId.LEN; i++) {
                    var festival = FESTIVALS[i];
                    if !festival.prototype.implemented {
                        continue;
                    }
                    if festival.prototype.date.season == season && festival.prototype.date.day - 1 == get_days(this_time) {
                        sprite = festival.prototype.icon;
                        name = local_get(festival.prototype.name);
                        pos = Vec2(-3, -3);
                    }
                }

                if sprite != undefined {
                    ANCHOR.sprite(tile)
                        .set_xy(pos)
                        .set_align(Align.RightIn, Align.BottomIn)
                        .set_sprite(sprite)
                        .set_alpha(alpha)
                        .set_z(tile.get_z() - 50)

                    bubble = MAKE_BUBBLE(tile, name);
                }

                if this_time == self.today {
                    num.set_lut(spr_ui_calendar_weekdays_lut, lut_index);
                }
            }

            //
            //
            if ARI.wedding_date != undefined
                && season == get_seasons(ARI.wedding_date)
                && get_days(this_time) == get_days(ARI.wedding_date)
            {
                sprite = spr_illegal_16;
                if get_years(ARI.wedding_date) == get_years(this_time) {
                    name = local_get("misc_local/your_wedding");
                } else {
                    name = local_get("misc_local/your_anniversary");
                }
                pos = Vec2(-3, -3);
            }

            if season == get_seasons(self.ari.birthday) && get_days(this_time) == get_days(self.ari.birthday) {
                var icon = ANCHOR.sprite(tile)
                    .set_sprite(spr_ui_generic_birthday_icon)
                    .set_alpha(alpha)
                    .set_z(tile.get_z() - 50)
                    .set_y(-2)

                if sprite == undefined {
                    icon.set_align(Align.RightIn, Align.BottomIn);
                    icon.set_x(-2);
                } else {
                    icon.set_align(Align.LeftIn, Align.BottomIn);
                    icon.set_x(2);
                }

                if is_world_room(room()) {
                    var text = format(local_get("misc_local/birthday_template"), self.ari.name);
                    if bubble == undefined {
                        MAKE_BUBBLE(tile, text);
                    } else {
                        bubble.bubble.add_height(18);
                        bubble.text.set_text(bubble.text.get_text() + "\n" + text);
                    }
                }
            }

            if output.iter mod 4 == 0 {
                var n = output.iter div 4;
                ANCHOR.sprite(self.grid_area)
                    .set_xy((39 * n) + 12, -8)
                    .set_sprite(spr_ui_hud_font_calendar_weekdays_english)
                    .set_index(n)
                    .set_lut(spr_ui_calendar_weekdays_lut, lut_index)
            }
        }

        ANCHOR.set_active_pilot(self.pilot);
    }

}

function spawn_calendar_ui(time) {
    return ANCHOR.spawn_menu(Menu.Calendar).with_time(time);
}
