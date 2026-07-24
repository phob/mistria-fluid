#macro CI (environment_get_variable("RUNNER_NAME") != undefined)
#macro FRAME_TIME 0.016666667
#macro USER_OS_NAME (os_type == os_windows ? environment_get_variable("USERNAME") : environment_get_variable("USER"))
#macro ON_WINDOWS (os_type == os_windows)
#macro ON_MAC (os_type == os_macosx)
#macro ON_LINUX (os_type == os_linux)
#macro ON_CONSOLE (ON_XBOX || ON_PLAYSTATION || ON_SWITCH || steam_on_deck())
#macro ON_XBOX (os_type == os_gdk || os_type == os_xboxseriesxs)
#macro ON_PLAYSTATION (os_type == os_ps4 || os_type == os_ps5)
#macro ON_SWITCH (os_type == os_switch)
#macro I32_MAX int64(0x7FFFFFFF)
#macro U32_MAX int64(0xFFFFFFFF)
#macro SQRT_2 1.4142
#macro GM_RUNTIME false

#macro ALL_UNLOCKS global.__all_unlocks
ALL_UNLOCKS = cli_all_unlocks();
#macro STORY_ENABLED global.__story_enabled
STORY_ENABLED = cli_story_mode();

#macro FPS room_speed
#macro OBJECT_CELL_SIZE 8

#macro MOUSE_GUI_X DISPLAY.mouse_gui_x()
#macro MOUSE_GUI_Y DISPLAY.mouse_gui_y()
#macro AUTOTILE_FULLGRASS_CELL 46

#macro unsafe if true

#macro ON_GAMEPAD (INPUT.active_input_type == InputType.Gamepad)
#macro ON_KBM (INPUT.active_input_type == InputType.Kbm)

TICK = -1;

#macro FROM_GAME global.__from_game
global.__from_game = false;

#macro DISPLAY_INVALID_SAVE_POPUP global.__display_invalid_save_popup
global.__display_invalid_save_popup = false;

#macro TEST_SUITE global.__test_suite
TEST_SUITE = cli_test_input() != undefined;

//
function surface_reset_target() {
    surface_set_target(SurfaceId.Staging);
}

function gpu_reset_scissor(scissor) {
    if scissor == undefined {
        gpu_disable_scissor();
    } else {
        gpu_set_scissor(
            scissor.x,
            scissor.y,
            scissor.w,
            scissor.h,
        );
    }
}

function gpu_enable_blending() {
    gpu_set_blendmode_ext(bm_src_alpha, bm_inv_src_alpha);
}
