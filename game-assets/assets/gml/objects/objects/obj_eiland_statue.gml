object_create(
    "obj_eiland_statue",
    undefined,
    {
        sprite_index: spr_museum_entryhall_armor_stand_spring_stage0,
        create: function() {
            SHADOW_WAIT_LIST.push({
                x,
                y,
                sprite: spr_museum_entryhall_armor_stand_shadow,
            });
        },
        step: function() {
            if requirements_pass(Requirement.HasDragonswornArmor) {
                sprite_index = spr_museum_entryhall_armor_stand_spring_stage0;
            } else if requirements_pass(Requirement.EilandArmorFour) {
                sprite_index = spr_museum_entryhall_armor_stand_spring_stage4;
            } else if requirements_pass(Requirement.EilandArmorThree) {
                sprite_index = spr_museum_entryhall_armor_stand_spring_stage3;
            } else if requirements_pass(Requirement.EilandArmorTwo) {
                sprite_index = spr_museum_entryhall_armor_stand_spring_stage2;
            } else if requirements_pass(Requirement.EilandArmorOne) {
                sprite_index = spr_museum_entryhall_armor_stand_spring_stage1;
            }
        },
        draw: function() {
            draw_self();
            depth = get_instance_depth(y);
        },
    }
);
