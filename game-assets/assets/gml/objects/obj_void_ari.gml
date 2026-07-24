object_create(
    "obj_void_ari",
    object_reserve("par_interactable"),
    {
        sprite_index: spr_npc_mask,
        create: function() {
            event_inherit(ObjectEvent.Create);

            self.wait_timer = undefined;
            self.itinerary = undefined;
            self.move_spd = undefined;
            self.meddler = new PathfindingMeddler(PathfindingAgentKind.Npc, self);
            self.pathfinding_agent = new PathfindingAgent(self.meddler);
            self.move_accel = Vec2(HUMAN_WALK_SPEED, HUMAN_WALK_SPEED);

            function create_par() {
                self.par = new PlayerAnimationRuntime();
                self.par.cardinal = Cardinal.South;
                ARI.animation_assets().apply_to_par(self.par);
                self.par.set_animation(AnimationName.Idle);
                self.par.blend = {
                    src_mode: bm_zero,
                    dest_mode: bm_src_color,
                    color: make_color_rgb(75, 66, 81),
                    alpha: 1.0
                };
            }

            self.par_offset = undefined;
            self.default_par_offset = undefined;
            self.default_par_anim_spd = undefined;
            self.par_anim_spd = self.default_par_anim_spd;
            self.cardinal = Cardinal.South;
            self.bark_emitter = new BarkEmitter(self, 0, -38);
            self.star_offset = Vec2Zero();
            self.create_par();

            function start_pathfind(itinerary) {
                self.itinerary = itinerary;
                self.pathfinding_agent.set_path(self.itinerary, 0);
                self.wait_timer = 0;
                self.move_spd = Vec2Zero();
                self.par.set_animation(AnimationName.Walk);
            }

            function run_pathfind() {
                switch self.pathfinding_agent.move_along_path() {
                    case MoveAlongPathResponse.Ok:
                        self.wait_timer = 0;

                        var complete = pathfinding_util_move_along_path(
                            self,
                            self.move_accel,
                            self.move_spd,
                            self.pathfinding_agent,
                        );

                        self.x += self.move_spd.x;
                        self.y += self.move_spd.y;

                        if self.move_spd.is_zero() == false {
                            self.cardinal = self.move_spd.cardinality_heuristic();
                            //
                            self.par.set_cardinal(self.cardinal);
                            if self.par.new_frame && self.par.is_broadcasting(BroadcastMessage.EMIT_FOOTSTEP_SOUND) {
                                TANGO.play("SoundEffects/NPCs/VoidAriFootstep", self.x, self.y);
                            }
                        }

                        self.move_spd.set_zero();

                        if complete {
                            self.par.set_animation(AnimationName.Idle);
                            self.itinerary = undefined;
                        }

                        break;

                    case MoveAlongPathResponse.Err:
                        warn("void ari shouldn't have to wait...");
                        break;
                }
            }

            if instance_exists(obj_seal_tablet) {
                self.register_interaction(
                    InputId.Interact,
                    "misc_local/interact",
                    obj_seal_tablet.interact_callback,
                    obj_seal_tablet.quest_at_donation_stage,
                );
            }
        },
        step: function() {
            if self.itinerary != undefined {
                self.run_pathfind();
            }
            self.depth = get_instance_depth(self.y);
            self.par_offset = obj_ari.par_offset;
            self.default_par_offset = obj_ari.default_par_offset;
            self.default_par_anim_spd = obj_ari.default_par_anim_spd;
        },
        draw: function() {
            //
            self.par.render_offscreen();
        
            var ratio = DISPLAY.asset_resize();
            var draw_x = floor((x + obj_ari.par_offset.x) * ratio) / ratio;
            var draw_y = floor((y + obj_ari.par_offset.y) * ratio) / ratio;
            self.par.draw(draw_x, draw_y);

            self.star_offset.x += 0.06;
            self.star_offset.y += 0.10;

            shader_set("shd_star_punch_out");
            shader_set_texture("u_tex", spr_dense_stars);
            
            shader_set_uniform_f_array("u_offset", [(self.star_offset.x - self.x) / 128.0, (self.star_offset.y - self.y) / 128.0]);
            shader_set_uniform_f_array(
                "u_outline_offset",
                [
                    1.0 / surface_get_width(SurfaceId.PlayerAnimationRuntime),
                    1.0 / surface_get_height(SurfaceId.PlayerAnimationRuntime),
                ]
            );
            gpu_set_blendmode_ext(bm_src_alpha, bm_inv_src_color);
            var flipper = self.par.cardinal == Cardinal.West ? -1 : 1;

            var xoff = 0;
            if flipper == -1 {
                xoff = PAR_SURFACE_SIZE;
            }
            draw_surface_ext(SurfaceId.PlayerAnimationRuntime, draw_x + xoff - (SURFACE_OFFSET_X * self.par.scale), draw_y - (SURFACE_OFFSET_Y * self.par.scale), self.par.scale * flipper, self.par.scale, c_white, 1.0);

            shader_reset_to_default();
            gpu_set_blendmode_ext(bm_src_alpha, bm_inv_src_alpha);

            self.par.animate(self.par_anim_spd);
        },
        draw_end: function() {
            self.bark_emitter.on_draw();
        },
        cleanup: function() {
            self.meddler.release_reservations();
        },
    }
);
