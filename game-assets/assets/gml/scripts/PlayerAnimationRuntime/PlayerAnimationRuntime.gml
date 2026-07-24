//
//
//
//
#macro SURFACE_OFFSET_X 24
#macro SURFACE_OFFSET_Y 24
#macro PAR_SURFACE_SIZE 128

function PlayerAnimationRuntime() constructor {
    self.cardinal = undefined;
    self.slots = array_create(AnimationSlot.LEN, undefined);
    self.priority = ds_priority_create();
    self.attachment = undefined;
    self.held_sprite = undefined;
    self.animation_complete = false;
    self.new_frame = false;
    self.scale = 1;
    self.alpha = 1;
    self.image_blend = c_white;
    self.blend = undefined;
    self.held_item_render_callback = undefined;
    self.tool_effect = ToolEffect.None;
    self.render_tool_effect = true;
    self.perform_outline = false;
    self.clip_region = [0, 0, 0, 0];
    self.render_hair = true;

    //
    for(var i = 0; i < AnimationSlot.LEN; i++) {
        self.slots[i] = {
            modifier: new PlayerAnimator(i, PlayerAnimationEndBehavior.Normal),
            modifier_uses_sprite_data: false,
            modifier_controls_depth: false,
            base: new PlayerAnimator(i, PlayerAnimationEndBehavior.Loop),
            lut_data: undefined,
            asset: undefined,
        }
    }

    //
    self.slots[AnimationSlot.Face].asset = PLAYER_ANIMATION_DATABASE.player_asset_parts.face_default[AnimationSlot.Face];
    self.slots[AnimationSlot.BaseArmLeft].asset = PLAYER_ANIMATION_DATABASE.player_asset_parts.base[AnimationSlot.BaseArmLeft];
    self.slots[AnimationSlot.BaseArmRight].asset = PLAYER_ANIMATION_DATABASE.player_asset_parts.base[AnimationSlot.BaseArmRight];
    self.slots[AnimationSlot.BaseChest].asset = PLAYER_ANIMATION_DATABASE.player_asset_parts.base[AnimationSlot.BaseChest];
    self.slots[AnimationSlot.BaseHead].asset = PLAYER_ANIMATION_DATABASE.player_asset_parts.base[AnimationSlot.BaseHead];
    self.slots[AnimationSlot.BaseLegs].asset = PLAYER_ANIMATION_DATABASE.player_asset_parts.base[AnimationSlot.BaseLegs];

    self.slots[AnimationSlot.Face].lut_data = new PlayerLutData(spr_player_base_lut);
    self.slots[AnimationSlot.BaseArmLeft].lut_data = new PlayerLutData(spr_player_base_lut);
    self.slots[AnimationSlot.BaseArmRight].lut_data = new PlayerLutData(spr_player_base_lut);
    self.slots[AnimationSlot.BaseChest].lut_data = new PlayerLutData(spr_player_base_lut);
    self.slots[AnimationSlot.BaseHead].lut_data = new PlayerLutData(spr_player_base_lut);
    self.slots[AnimationSlot.BaseLegs].lut_data = new PlayerLutData(spr_player_base_lut);

    self.slots[AnimationSlot.BaseEffect].asset = PLAYER_ANIMATION_DATABASE.player_asset_parts.water_effect[AnimationSlot.BaseEffect];

    //
    function base_animation() {
        return self.slots[AnimationSlot.BaseArmLeft].base.animation_name;
    }

    function has_modifier(anim_name) {
        for (var i = 0; i < AnimationSlot.LEN; i++) {
            var slot = self.slots[i];
            if slot.modifier.animation_name == anim_name {
                return true;
            }
        }

        return false;
    }

    //
    function base_current_frame_index() {
        return self.slots[AnimationSlot.BaseArmLeft].base.current_frame_index;
    }

    function is_broadcasting(broadcast_message) {
        var frame = self.slots[AnimationSlot.BaseArmLeft].base.current_frame;
        if frame == undefined {
            return false;
        }

        return has_flag(frame.broadcast_message, broadcast_message);
    }

    function is_modifier_broadcasting(broadcast_message) {
        var frame = self.slots[AnimationSlot.Eyes].modifier.current_frame;
        if frame == undefined {
            return false;
        }
        return has_flag(frame.broadcast_message, broadcast_message);
    }

    //
    function base_broadcast_message() {
        var frame = self.slots[AnimationSlot.BaseArmLeft].base.current_frame;
        if frame == undefined {
            return undefined;
        }

        return frame.broadcast_message;
    }

    function set_cardinal(cardinal) {
        self.cardinal = cardinal;

        //
        for (var i = 0; i < AnimationSlot.LEN; i++) {
            var slot = self.slots[i];
            //
            if slot.modifier.animation_name != undefined {
                self.set_animation_on_slot(slot.modifier.animation_name, slot.modifier, false);
            }

            if slot.base.animation_name != undefined {
                self.set_animation_on_slot(slot.base.animation_name, slot.base, false);
            }

        }
    }

    //
    function set_animation(animation_name) {
        var modifier_data = PLAYER_ANIMATION_DATABASE.modifiers[animation_name];

        if modifier_data == undefined {
            self.animation_complete = false;
            self.new_frame = true;

            //
            for (var i = 0; i < AnimationSlot.LEN; i++) {
                self.set_animation_on_slot(animation_name, self.slots[i].base);
            }
        } else {
            for (var i = 0, c = array_length(modifier_data.slots); i < c; i++) {
                var slot_data = modifier_data.slots[i];
                var slot = slot_data.slot;

                self.set_animation_on_slot(animation_name, self.slots[slot].modifier);
                self.slots[slot].modifier_controls_depth = slot_data.controls_depth;
                self.slots[slot].modifier_uses_sprite_data = slot_data.use_sprite_data;
                self.slots[slot].modifier.end_behavior = modifier_data.on_end;
            }
        }
    }

    //
    function set_animation_on_slot(animation_name, animator, reset_animation=true) {
        var animation = PLAYER_ANIMATION_DATABASE.animation(animator.slot, animation_name, self.cardinal);

        animator.set_animation(animation_name, animation, reset_animation);
    }

    //
    function set_base_hold_on_last_frame() {
        for (var i = 0; i < AnimationSlot.LEN; i++) {
            self.slots[i].base.end_behavior = PlayerAnimationEndBehavior.HoldLastFrame;
        }
    }

    //
    function set_base_loop() {
        for (var i = 0; i < AnimationSlot.LEN; i++) {
            self.slots[i].base.end_behavior = PlayerAnimationEndBehavior.Loop;
        }
    }

    //
    //
    function base_to_frame(animation_name, frame=undefined) {
        for (var i = 0; i < AnimationSlot.LEN; i++) {
            var slot = self.slots[i];
            if slot.base.animation_name == animation_name {
                var target_frame = frame;
                if target_frame == undefined {
                    target_frame = array_length(slot.base.animation) - 1;
                }

                slot.base.current_frame_time_remaining = 0;

                //
                if slot.base.animation != undefined {
                    target_frame = clamp(target_frame, 0, array_length(slot.base.animation) - 1);
                }

                slot.base.set_frame_index(target_frame);
            }
        }
    }

    //
    //
    function modifier_to_frame(animation_name, frame=undefined) {
        for (var i = 0; i < AnimationSlot.LEN; i++) {
            var slot = self.slots[i];
            if slot.modifier.animation_name == animation_name {
                var target_frame = frame;
                if target_frame == undefined {
                    target_frame = array_length(slot.modifier.animation) - 1;
                }
                slot.modifier.current_frame_time_remaining = 0;
                slot.modifier.set_frame_index(target_frame);
            }
        }
    }

    //
    //
    //
    //
    function unset_all_animations() {
        for (var i = 0; i < AnimationSlot.LEN; i++) {
            var slot = self.slots[i];
            if slot.modifier.has_animation() {
                slot.modifier.unset_animation();
            }

            if slot.base.has_animation() {
                slot.base.unset_animation();
            }
        }
    }

    function set_attachment(attachment_name) {
        self.attachment = {
            name: attachment_name,
            sprites: PLAYER_ANIMATION_DATABASE.player_attachments.get_unwrap(attachment_name),
        }
    }

    function remove_attachment() {
        self.attachment = undefined;
    }

    function set_held_sprite(sprite_index, image_index=0, x_offset=undefined, y_offset=undefined, flipped_x_offset=undefined, flips=false) {
        x_offset = x_offset ?? sprite_get_xoffset(sprite_index);

        self.held_sprite = {
            sprite_index: sprite_index,
            image_index: image_index,
            x_offset: x_offset,
            flipped_x_offset: flipped_x_offset ?? sprite_get_width(sprite_index) - x_offset,
            y_offset: y_offset ?? sprite_get_yoffset(sprite_index),
            flips,
        };
    }

    function remove_held_sprite() {
        self.held_sprite = undefined;
    }

    //
    //
    function remove_asset(asset_name) {
        var asset_manifest = PLAYER_ANIMATION_DATABASE.player_assets.get(asset_name);
        assert_neq(asset_manifest, undefined, "that asset_name does not exist");

        //
        for (var i = 0; i < AnimationSlot.LEN; i++) {
            if asset_manifest.slots[i] != undefined {
                self.slots[i].asset = undefined;
                self.slots[i].lut_data = undefined;
            }
        }
    }

    //
    //
    //
    function set_asset(asset_name, lut_index=1) {
        var asset_manifest = PLAYER_ANIMATION_DATABASE.player_assets.get(asset_name);
        assert_neq(asset_manifest, undefined, "asset_name {} does not exist", asset_name);

        //
        for (var i = 0; i < AnimationSlot.LEN; i++) {
            if asset_manifest.slots[i] != undefined {
                self.slots[i].asset = asset_manifest.slots[i];

                //
                if asset_manifest.lut_sprite != undefined {
                    self.slots[i].lut_data = new PlayerLutData(asset_manifest.lut_sprite);
                    self.slots[i].lut_data.lut_column_idx = lut_index;
                }
            }
        }

    }

    //
    //
    function unset_all_modifiers() {
        for (var i = 0; i < AnimationSlot.LEN; i++) {
            var slot = self.slots[i];
            if slot.modifier.has_animation() {
                slot.modifier.unset_animation();
            }
        }
    }

    //
    //
    function unset_modifier(animation_name) {
        for (var i = 0; i < AnimationSlot.LEN; i++) {
            var slot = self.slots[i];
            if slot.modifier.animation_name == animation_name {
                slot.modifier.unset_animation();
            }
        }
    }

    //
    function set_skin_tone(index) {
        self.slots[AnimationSlot.Face].lut_data.lut_column_idx = index;
        self.slots[AnimationSlot.BaseArmLeft].lut_data.lut_column_idx = index;
        self.slots[AnimationSlot.BaseArmRight].lut_data.lut_column_idx = index;
        self.slots[AnimationSlot.BaseChest].lut_data.lut_column_idx = index;
        self.slots[AnimationSlot.BaseHead].lut_data.lut_column_idx = index;
        self.slots[AnimationSlot.BaseLegs].lut_data.lut_column_idx = index;
    }

    function animate(spd=FRAME_TIME) {
        self.animation_complete = false;
        self.new_frame = false;

        for (var i = 0; i < AnimationSlot.LEN; i++) {
            var slot = self.slots[i];
            slot.modifier.animate(spd);

            var finished = slot.base.animate(spd);
            switch finished {
                case AnimatorOutput.FrameComplete:
                    self.new_frame = true;
                    break;
                case AnimatorOutput.AnimationComplete:
                    self.animation_complete = true;
                    self.new_frame = true;
                    break;
            }
        }
    }

    //
    function render_offscreen() {
        ds_priority_clear(self.priority);

        for (var i = 0; i < AnimationSlot.LEN; i++) {
            var slot = self.slots[i];
            var d = slot.base.get_depth();

            //
            if slot.modifier.has_animation() && slot.modifier_controls_depth {
                d = slot.modifier.get_depth();
            }

            if d != undefined {
                ds_priority_add(self.priority, i, d);
            }
        }

        var old_surface = surface_get_target();
        surface_set_target(SurfaceId.PlayerAnimationRuntime);

        var old_view_size = draw_camera_get_view_size();
        if old_view_size == undefined {
            old_view_size = [CAMERA.view_width, CAMERA.view_height];
        }
        var old_view_pos = draw_camera_get_view_pos();

        draw_camera_set_view_pos(0.0, 0.0);
        draw_camera_set_view_size(128, 128);
        draw_clear_color(c_white, 0.0);

        var queue_size = ds_priority_size(self.priority);
        gpu_set_blendmode_ext(bm_one, bm_inv_src_alpha);


        for (var i = 0; i < queue_size; i++) {
            var slot_id = ds_priority_delete_max(self.priority);
            slot = self.slots[slot_id];

            //
            var uses_lut = slot.lut_data != undefined;
            shader_set("shd_mistria_default");
            if uses_lut {
                shader_set_texture("u_LutTexture", slot.lut_data.lut_texture);
                gpu_set_extra(UberShaderKind.PaletteSwap, slot.lut_data.uvs[0], slot.lut_data.uvs[1], slot.lut_data.lut_column_idx);
            } else {
                gpu_reset_extra();
            }

            //
            if self.attachment != undefined {
                var anim_data = self.attachment.sprites[slot.base.animation_name];
                if anim_data != undefined {
                    var attachment_name = undefined;
                    var outline = undefined;

                    switch slot_id {
                        case AnimationSlot.Tool:
                            attachment_name = Attachment.Tool;
                            switch self.tool_effect {
                                case ToolEffect.None:
                                case ToolEffect.Critical:
                                    //
                                    break;
                                case ToolEffect.Ice:
                                    outline = Attachment.ToolEffectIceOutline;
                                    break;
                                case ToolEffect.Fire:
                                    outline = Attachment.ToolEffectFireOutline;
                                    break;
                                case ToolEffect.Venom:
                                    outline = Attachment.ToolEffectVenomOutline;
                                    break;
                                default: impossible("unexpected tool_effect: {}", self.tool_effect);
                            }

                            break;
                        case AnimationSlot.ToolEffect:
                            switch self.tool_effect {
                                case ToolEffect.None:
                                    attachment_name = Attachment.ToolEffect;
                                    break;
                                case ToolEffect.Critical:
                                    attachment_name = Attachment.ToolEffectCritical;
                                    break;
                                case ToolEffect.Ice:
                                    attachment_name = Attachment.ToolEffectIce;
                                    break;
                                case ToolEffect.Fire:
                                    attachment_name = Attachment.ToolEffectFire;
                                    break;
                                case ToolEffect.Venom:
                                    attachment_name = Attachment.ToolEffectVenom;
                                    break;
                                default: impossible("unexpected tool_effect: {}", self.tool_effect);
                            }

                            if self.render_tool_effect == false {
                                attachment_name = undefined;
                                outline = undefined;
                            }
                            break;
                    }

                    if attachment_name != undefined {
                        var slot_data = anim_data[attachment_name];
                        if slot_data != undefined && slot_data[self.cardinal] != undefined {
                            draw_sprite_ext(slot_data[self.cardinal], slot.base.current_frame_index, SURFACE_OFFSET_X, SURFACE_OFFSET_Y, 1, 1, 0, c_white, 1);

                            if slot_id == AnimationSlot.Tool && outline != undefined {
                                var outline_slot = anim_data[outline];
                                if outline_slot != undefined && outline_slot[self.cardinal] != undefined {
                                    draw_sprite_ext(outline_slot[self.cardinal], slot.base.current_frame_index, SURFACE_OFFSET_X, SURFACE_OFFSET_Y, 1, 1, 0, c_white, 1);
                                }
                            }

                            continue;
                        }
                    }
                }
            }

            //
            if slot_id == AnimationSlot.HeldItem && self.held_sprite != undefined {
                //
                if slot.modifier.animation_name != undefined && HELD_ITEM_ANIMATIONS[slot.modifier.animation_name] {
                    //
                    var left_arm_slot = self.slots[AnimationSlot.BaseArmLeft];
                    var base_offset = left_arm_slot.modifier.current_frame.offset;
                    var diff_offset = left_arm_slot.base.current_frame.offset;

                    var x_offset = slot.modifier.current_frame.offset.x + diff_offset.x - base_offset.x;
                    var y_offset = slot.modifier.current_frame.offset.y + diff_offset.y - base_offset.y;

                    //
                    var flipper = 1;
                    var held_sprite_x_offset = self.held_sprite.x_offset;

                    if self.cardinal == Cardinal.West {
                        //
                        if self.held_sprite.flips == false {
                            flipper = -1;
                        }
                        held_sprite_x_offset = self.held_sprite.flipped_x_offset;
                    }

                    if self.held_item_render_callback != undefined {
                        self.held_item_render_callback(
                            self.held_sprite.sprite_index,
                            self.held_sprite.image_index,
                            x_offset + held_sprite_x_offset + SURFACE_OFFSET_X,
                            y_offset + self.held_sprite.y_offset + SURFACE_OFFSET_Y,
                            flipper
                        );
                    } else {
                        draw_sprite_ext(
                            self.held_sprite.sprite_index,
                            self.held_sprite.image_index,
                            x_offset + held_sprite_x_offset + SURFACE_OFFSET_X,
                            y_offset + self.held_sprite.y_offset + SURFACE_OFFSET_Y,
                            flipper,
                            1,
                            0,
                            c_white,
                            1,
                        );
                    }

                    continue;
                } else if slot.base.animation_name != undefined && HELD_ITEM_ANIMATIONS[slot.base.animation_name] {
                    //
                    var flipper = 1;
                    var held_sprite_x_offset = self.held_sprite.x_offset;

                    if self.cardinal == Cardinal.West {
                        //
                        if self.held_sprite.flips == false {
                            flipper = -1;
                        }
                        held_sprite_x_offset = self.held_sprite.flipped_x_offset;
                    }

                    draw_sprite_ext(
                        self.held_sprite.sprite_index,
                        self.held_sprite.image_index,
                        slot.base.current_frame.offset.x + held_sprite_x_offset + SURFACE_OFFSET_X,
                        slot.base.current_frame.offset.y + self.held_sprite.y_offset + SURFACE_OFFSET_Y,
                        flipper,
                        1,
                        0,
                        c_white,
                        1
                    );
                    continue;
                }
            }

            //
            var target_frame = undefined;

            //
            if slot.modifier.has_animation() && slot.modifier_uses_sprite_data {
                target_frame = slot.modifier.current_frame.target_frame;
            }

            if
                slot.asset != undefined
                && (
                    self.render_hair
                    || !matches(slot_id, AnimationSlot.HairMid, AnimationSlot.HairBack)
                )
            {
                slot.base.draw(slot.asset, target_frame);
            }
        }
        shader_reset_to_default();

        //
        //
        if self.blend != undefined {
            gpu_set_blendmode_ext_sepalpha(self.blend.src_mode, self.blend.dest_mode, bm_zero, bm_one);

            draw_sprite_ext(spr_pixel, 0, 0, 0, PAR_SURFACE_SIZE, PAR_SURFACE_SIZE, 0, self.blend.color, self.blend.alpha);
        }

        gpu_set_blendmode_ext(bm_src_alpha, bm_inv_src_alpha);
        surface_set_target(old_surface);
        draw_camera_set_view_size(old_view_size[0], old_view_size[1]);
        draw_camera_set_view_pos(old_view_pos[0], old_view_pos[1]);
    }

    function draw(x, y) {
        //
        var flipper = self.cardinal == Cardinal.West ? -1 : 1;

        var xoff = 0;
        if flipper == -1 {
            xoff = PAR_SURFACE_SIZE;
        }

        gpu_set_extra(UberShaderKind.PlayerFinal, self.perform_outline, self.perform_outline, self.perform_outline);
        draw_surface_ext(SurfaceId.PlayerAnimationRuntime, x + xoff - (SURFACE_OFFSET_X * self.scale), y - (SURFACE_OFFSET_Y * self.scale), self.scale * flipper, self.scale, self.image_blend, self.alpha);
        gpu_reset_extra();
    }
}

function PlayerAnimator(slot, end_behavior) constructor {
    //
    function set_animation(animation_name, animation, reset_animation) {
        self.animation_name = animation_name;
        self.animation = animation;

        if reset_animation {
            self.current_frame_index = 0;
            if self.animation != undefined {
                self.current_frame_time_remaining = self.animation[0].duration;
            }
        }

        if self.animation != undefined {
            self.current_frame = self.animation[self.current_frame_index];
        }
    }

    //
    function unset_animation() {
        self.animation_name = undefined;
        self.animation = undefined;
        self.current_frame_index = 0;
        self.current_frame = undefined;
        self.current_frame_time_remaining = 0;
        self.end_behavior = default_end_behavior;
    }

    //
    function get_depth() {
        if self.animation == undefined {
            return undefined;
        }

        return self.current_frame.depth;
    }

    //
    function has_animation() {
        return self.animation != undefined;
    }

    //
    function animate(spd) {
        //
        if self.animation == undefined {
            return undefined;
        }

        //
        self.current_frame_time_remaining -= spd;

        //
        //
        var output = undefined;

        while (self.current_frame_time_remaining <= 0) {
            self.current_frame_index += 1;
            output = AnimatorOutput.FrameComplete;

            if self.current_frame_index >= array_length(self.animation) {
                output = AnimatorOutput.AnimationComplete;

                switch self.end_behavior {
                    case PlayerAnimationEndBehavior.Loop:

                        self.current_frame_index = 0;
                        break;
                    case PlayerAnimationEndBehavior.Normal:

                        self.animation = undefined;
                        self.animation_name = undefined;
                        return;
                    case PlayerAnimationEndBehavior.HoldLastFrame:
                        //
                        self.current_frame_index -= 1;
                        break;
                }
            }
            self.set_frame_index(self.current_frame_index);
        }

        return output;
    }

    function set_frame_index(idx) {
        self.current_frame_index = idx;
        if self.animation != undefined {
            self.current_frame = self.animation[self.current_frame_index];
            self.current_frame_time_remaining += self.current_frame.duration;
        }
    }

    //
    function draw(asset, target_frame) {
        target_frame = target_frame == undefined ? self.current_frame.target_frame : target_frame;

        draw_sprite_ext(asset, target_frame, self.current_frame.offset.x + SURFACE_OFFSET_X, self.current_frame.offset.y + SURFACE_OFFSET_Y, 1, 1, 0, c_white, 1);
    }

    self.slot = slot;
    cardinal = undefined;
    animation = undefined;
    animation_name = undefined;

    current_frame_index = 0;
    current_frame = undefined;
    current_frame_time_remaining = 0;

    self.end_behavior = end_behavior;
    self.default_end_behavior = self.end_behavior;
}

//
function PlayerLutData(spr) constructor {
    self.lut_texture = spr;
    var uvs_full = sprite_get_uvs(spr, 0);
    self.uvs = [uvs_full[0], uvs_full[1]];
    self.lut_column_idx = 0;
}
