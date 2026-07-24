object_create(
    "obj_cutscene_trigger",
    undefined,
    {
        sprite_index: spr_pixel,
        visible: false,
        step: function() {
            if ARI.end_of_day_status != undefined {
                return;
            }
            if overlap_instance_any(self.x, self.y, obj_ari) {
                obj_ari.set_idle_simple();
                MIST.request_scene(self.cutscene);
                instance_destroy();
            }
        },
    }
);
