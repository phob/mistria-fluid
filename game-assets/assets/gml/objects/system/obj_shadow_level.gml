object_create(
    "obj_shadow_level",
    undefined,
    {
        sprite_index: undefined,
        create: function() {
            //
            //
            //
            //
            //

            //
            //
            //
            //
            //
            //
            //
            //
            //
            shadow_area = undefined;
        },
        draw: function() {
            if DEBUG_TOOLS {
                if self.shadow_maps == undefined {
                    gpu_push_group("shadows");
                } else if self.write_z {
                    gpu_push_group("shadows (tilemap)");
                }
            }
            if self.write_z {
                gpu_set_depth_test(cmpfunc_always, false);
            }
            gpu_set_stencil_operation(StencilOperation.Replace);

            if self.target_shadow_grid != undefined && self.shadow_area != undefined {
                gpu_set_stencil_test(cmpfunc_always, 0);
                draw_clear_stencil(255);

                //
                //
                gpu_set_colorwriteenable(false, false, false, false);
                draw_sprite_ext(
                    self.shadow_area[0],
                    self.shadow_area[1],
                    self.shadow_area[2],
                    self.shadow_area[3],
                    self.shadow_area[4],
                    self.shadow_area[5],
                    0,
                    c_white,
                    1.0,
                );
                gpu_set_colorwriteenable(true, true, true, true);
            } else {
                //
                draw_clear_stencil(0);
            }

            gpu_set_extra(UberShaderKind.Flat);
            var shadow_color = make_color_rgb(
                round(255 * POST_PROCESS.shadow_multiply_color[0] * POST_PROCESS.shadow_multiply_color[3] * self.image_alpha),
                round(255 * POST_PROCESS.shadow_multiply_color[1] * POST_PROCESS.shadow_multiply_color[3] * self.image_alpha),
                round(255 * POST_PROCESS.shadow_multiply_color[2] * POST_PROCESS.shadow_multiply_color[3] * self.image_alpha),
            );
            var shadow_alpha = POST_PROCESS.shadow_multiply_color[3] * self.image_alpha;

            gpu_set_blendmode_ext_sepalpha(
                bm_dest_color,
                bm_inv_src_alpha,
                bm_one,
                bm_one
            );
            gpu_set_stencil_test(cmpfunc_greater, 128);

            //
            if self.target_shadow_grid != undefined {
                //
                var collection = self.target_shadow_grid.grid_get_collection_view(CAMERA.get_cull_region());

                shadows_draw_shadow_collection(collection, shadow_color, shadow_alpha);

                //
                if instance_exists(obj_tile_cursor) && self.target_shadow_grid == SHADOW_GRID {
                    //
                    for (var i = 0; i < obj_tile_cursor.extra_casters_to_draw; i++) {
                        var shadow_caster = obj_tile_cursor.extra_shadow_casters.try_get(i);
                        //
                        if shadow_caster == undefined {
                            break;
                        }
                        draw_sprite_part(
                            shadow_caster[ShadowCasterField.SpriteIndex],
                            shadow_caster[ShadowCasterField.ImageIndex],
                            //
                            //
                            shadow_caster[ShadowCasterField.ImageXScale],
                            shadow_caster[ShadowCasterField.ImageYScale],
                            8,
                            8,
                            shadow_caster[ShadowCasterField.WorldX],
                            shadow_caster[ShadowCasterField.WorldY],
                            shadow_color,
                            shadow_alpha,
                        );
                    }

                    //
                    var old_b = obj_tile_cursor.image_blend;
                    obj_tile_cursor.image_blend = c_black;
                    obj_tile_cursor.shadow_draw(shadow_alpha);
                    obj_tile_cursor.image_blend = old_b;
                }
            }

            //
            if self.shadow_maps != undefined {
                for (var i = 0, c = array_length(self.shadow_maps); i < c; i++) {
                    var off = self.shadow_map_offsets[i];
                    draw_tilemap(self.shadow_maps[i], off.x, off.y, shadow_color, shadow_alpha);
                }
            }

            gpu_set_blendmode_ext(bm_src_alpha, bm_inv_src_alpha);
            gpu_disable_stencil();
            gpu_reset_extra();

            if self.write_z {
                gpu_set_depth_test(cmpfunc_always, true);
            }

            if self.render_outlines {
                shadows_draw_grass_backing();
            }

            if DEBUG_TOOLS && (self.shadow_maps == undefined || self.write_z) {
                gpu_pop_group();
            }
        }
    }
);
