enum NodeDrawFlag {
    EMPTY = 0,
    PERFORMING_TRANSPARENCY = 1 << 0,
    PERFORMING_PREPASS = 1 << 1,
}

function draw_instance_pixel_perfect(object, rot) {
    draw_sprite_ext_pixel_perfect(
        object.sprite_index,
        object.image_index,
        object.x,
        object.y,
        object.image_xscale,
        object.image_yscale,
        rot,
        object.image_blend,
        object.image_alpha,
    );
}

function draw_sprite_ext_pixel_perfect(
    _sprite_index,
    _image_index,
    _x,
    _y,
    _image_xscale,
    _image_yscale,
    _rot,
    _image_blend,
    _image_alpha,
) {
    //
    //
    //
    if _rot % 90 == 0 && abs(_image_xscale) == 1 && abs(_image_yscale == 1) {
        draw_sprite_ext(
            _sprite_index,
            _image_index,
            _x,
            _y,
            _image_xscale,
            _image_yscale,
            _rot,
            _image_blend,
            _image_alpha,
        );
        return;
    }

    surface_set_target(SurfaceId.Rotation);
    var old_view_size = draw_camera_get_view_size();
    if old_view_size == undefined {
        old_view_size = [CAMERA.view_width, CAMERA.view_height];
    }
    var old_view_pos = camera_get_view_pos();
    draw_camera_set_view_pos(0.0, 0.0);
    draw_camera_set_view_size(1000, 1000);

    draw_clear_color(c_white, 0.0);

    //
    draw_sprite_ext(
        _sprite_index,
        _image_index,
        500,
        500,
        _image_xscale,
        _image_yscale,
        _rot,
        _image_blend,
        1.0,
    );
    surface_reset_target();
    draw_camera_set_view_size(old_view_size[0], old_view_size[1]);
    draw_camera_set_view_pos(old_view_pos[0], old_view_pos[1]);

    //
    draw_surface_ext(SurfaceId.Rotation, _x - 500, _y - 500, 1, 1, c_white, _image_alpha);
}

//
//
//
function blend_rgb32(lhs, rhs, amount) {
    var output = [0, 0, 0];

    for (var i = 0; i < 3; i++) {
        output[i] = lerp(lhs[i], rhs[i], amount);
    }

    return output;
}

//
//
//
function blend_rgba32(lhs, rhs, amount) {
    var output = [0, 0, 0, 0];

    for (var i = 0; i < 4; i++) {
        output[i] = lerp(lhs[i], rhs[i], amount);
    }

    return output;
}

function shader_reset_to_default() {
    gml_pragma("forceinline");

    shader_set("shd_mistria_default");
}
