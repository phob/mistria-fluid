#macro DISPLAY global.__display
global.__display = undefined;

#macro NORMAL_MINSPEC_HEIGHT (240)
#macro NORMAL_MINSPEC_WIDTH ((16 * NORMAL_MINSPEC_HEIGHT) / 9) //

enum PostPostProcessing {
    None,
    Sepia,
}

//
//
function create_display() {
    var display = new Display();
    display.calculate_view_size();

    return display;
}

//
//
//
function Display() constructor {
    self.texel_resize = 1
    self.expansion = 0;
    self.force_resize = undefined;
    self.post_post_processing = PostPostProcessing.None;

    function create_camera() {
        var output_size = window_get_output_dimensions();
        var texel_resize = resize_amount(
            output_size[0],
            output_size[1],
            self.expansion,
            self.force_resize
        );

        return new Camera(output_size[0] / texel_resize, output_size[1] / texel_resize);
    }

    function on_draw_gui() {
        draw_camera_set_view_pos(0, 0);
        var output_size = window_get_output_dimensions();
        draw_camera_set_view_size(output_size[0], output_size[1]);
        surface_set_target(undefined);
        draw_clear_color(c_black, 0.0);

        //
        POST_PROCESS.draw(SurfaceId.Staging, 1.0);

        if WEATHER != undefined {
            WEATHER.on_draw_gui();
            draw_clear_depth(1.0);
        }

        if DATE_PHOTO_REQUEST != undefined {
            //
            if DATE_PHOTO_STATUS == undefined {
                render_date_photo();
                //
                draw_clear_color(c_black, 1.0);
                DATE_PHOTO_STATUS = 1;
            } else {
                save_date_photo(DATE_PHOTO_REQUEST[0], DATE_PHOTO_REQUEST[1]);
                DATE_PHOTO_REQUEST = undefined;
                DATE_PHOTO_STATUS = undefined;
            }
        }

        //
        //
        if DEBUG_TOOLS == false || BUGGER.hide_ui == false {
            ANCHOR.on_draw_gui(self.asset_resize());
        }

        //
        if CURSOR.render_strategy == CursorRender.OnGpu {
            CURSOR.render_cursor_manually(
                device_mouse_x_to_gui(),
                device_mouse_y_to_gui(),
                self.asset_resize(),
            );
        }

        surface_reset_target();

        //
        //
        if self.post_post_processing == PostPostProcessing.Sepia {
            gpu_disable_blending();

            //
            surface_blit(undefined, SurfaceId.Staging);

            surface_set_target(undefined);
            shader_set("shd_post_post_sepia");
            draw_surface_ext(
                SurfaceId.Staging,
                0,
                0,
                1.0,
                1.0,
                make_color_rgb(159, 142, 126),
                1.0
            );
            surface_reset_target();
            gpu_enable_blending();
        }
    }

    function inverse_asset_resize() {
        return 1.0 / self.asset_resize();
    }

    //
    //
    //
    function asset_resize() {
        return self.texel_resize;
    }

    //
    //
    function window_sizes() {
        static CORE_LIST = [
            Vec2(640, 360),
            Vec2(1280, 720),
            Vec2(1280, 1024),
            Vec2(1366, 768),
            Vec2(1400, 900),
            Vec2(1920, 1080),
            Vec2(2560, 1080),
            Vec2(2560, 1440),
            Vec2(3440, 1440),
            Vec2(3840, 2160),
        ];

        var output = List();

        var output_size = window_get_output_dimensions();
        var monitor_width = display_get_width();
        var monitor_height = display_get_height();

        var current_output_found = false;

        for (var i = 0, c = array_length(CORE_LIST); i < c; i++) {
            var size = CORE_LIST[i].clone();

            if size.x == output_size[0] && size.y == output_size[1]  {
                current_output_found = true;
            }

            var can_use = size.x <= monitor_width && size.y <= (monitor_height - 25);

            output.push({ size: size, can_use });
        }

        if current_output_found == false {
            output.push({ size: Vec2(output_size[0], output_size[1]), can_use: true});
        }

        return output;
    }

    //
    //
    function max_expansion_amount() {
        return max(0, (window_get_output_height() div NORMAL_MINSPEC_HEIGHT) - 1);
    }

    //
    //
    function max_expansion_looks_decent() {
        return max(0, (window_get_output_height() div 360) - 1);
    }

    function set_fullscreen(expansion, borderless) {
        self.expansion = expansion;

        window_set_fullscreen(borderless);
        window_sync();
        self.calculate_view_size();
    }

    function set_windowed(width, height, expansion) {
        self.expansion = expansion;

        window_set_windowed(width, height);
        window_center();
        window_sync();
        self.calculate_view_size();
    }

    //
    function set_expansion(expansion) {
        if expansion > self.max_expansion_amount() {
            error("display is too expanded!");
            return false;
        }
        self.expansion = expansion;
        self.calculate_view_size();

        return true;
    }

    //
    function calculate_view_size() {
        var output_size = window_get_output_dimensions();

        self.texel_resize = resize_amount(
            output_size[0],
            output_size[1],
            self.expansion,
            self.force_resize
        );

        var view_width = output_size[0] / self.texel_resize;
        var view_height = output_size[1] / self.texel_resize;

        if CAMERA != undefined {
            CAMERA.ratio = self.texel_resize;
            CAMERA.set_view_size(view_width, view_height);
        }
        if ANCHOR != undefined {
            ANCHOR.set_gui_size(view_width, view_height);
        }
        if WEATHER != undefined && WEATHER.atmosphere != undefined {
            WEATHER.set_atmosphere(WEATHER.atmosphere.id);
        }
    }

    //
    function mouse_gui_x() {
        return floor(device_mouse_x_to_gui(0) * (1.0 / self.texel_resize));
    }

    //
    function mouse_gui_y() {
        return floor(device_mouse_y_to_gui(0) * (1.0 / self.texel_resize));
    }

    function readout() {
        var output_size = window_get_output_dimensions();
        var texel_resize = resize_amount(
            output_size[0],
            output_size[1],
            self.expansion,
            self.force_resize
        );
        var horiz_trans = output_size[0] / texel_resize - NORMAL_MINSPEC_WIDTH;
        var vert_trans = output_size[1] / texel_resize - NORMAL_MINSPEC_HEIGHT;

        return fmt(
            "Display Information:\nOutputting to {}x{} ({})\n{}x Texel Size{} with Expansion Level {}\n({}, {}) Translation{}\nHiRes Gui: {}x{}\nCamera Dims: {}x{}",
            output_size[0],
            output_size[1],
            window_is_fullscreen() ? "fullscreen" : "windowed",
            texel_resize,
            self.force_resize == undefined ? "" : " (FORCED)",
            self.expansion,
            horiz_trans,
            vert_trans,
            (horiz_trans == 0 && vert_trans == 0) ? " (PERFECT CLAIRE)" : "",
            surface_get_width(SurfaceId.Staging),
            surface_get_height(SurfaceId.Staging),
            CAMERA.view_width,
            CAMERA.view_height,
        );
    }
}

function resize_amount(width, height, expansion, force_resize) {
    var texel_resize = force_resize;
    if force_resize == undefined {
        //
        texel_resize = min(
            width div floor(NORMAL_MINSPEC_WIDTH),
            height div NORMAL_MINSPEC_HEIGHT
        ) - expansion;
    }

    return clamp(texel_resize, 1, I32_MAX);
}
