#macro DECOR global.__decor
global.__decor = undefined;

enum HomeUpgrade {
    Small,
    Large,
    LargeWest,
    LargeWestEast,
    LEN
}

function Decor() constructor {
    floorings = {};
    wallpapers = {};
    for (var i = 0; i < LocationId.LEN; i++) {
        if is_home_location(i) {
            floorings[$ location_id_to_string(i)] = {
                flooring: "default_v1",
                infusion: undefined
            }

            wallpapers[$ location_id_to_string(i)] = {
                wallpaper: "default_v1",
                door_mold_sprite: spr_carpenter_house_f2_doorway2_spring,
                infusion: undefined
            }
        }
    }

    size_upgrade = HomeUpgrade.Small;
    upper_floor = false;

    //
    transition_keys = fiddle_get("player_home/transition_keys");
    collision_grids = array_create_ext(HomeUpgrade.LEN, function(i) {
        var data = fiddle_get(format("player_home/collisions/{HomeUpgrade}", i));
        return {
            grid: parse_collision_strings(fiddle_deserialize_vec2(data.size), data.grid),
            offset: fiddle_deserialize_vec2(data.offset),
            size: fiddle_deserialize_vec2(data.size),
        }
    });

    collision_grid_removals = array_create_ext(HomeUpgrade.LEN, function(i) {
        var data = fiddle_get(format("player_home/collision_removals/{HomeUpgrade}", i));
        return {
            grid: parse_collision_strings(fiddle_deserialize_vec2(data.size), data.grid),
            offset: fiddle_deserialize_vec2(data.offset),
            size: fiddle_deserialize_vec2(data.size),
        }
    });


    //
    rule_grid_size = fiddle_deserialize_vec2(fiddle_get("player_home/upgraded_rules/size"));
    upgraded_rule_grid = parse_rule_strings(self.rule_grid_size, fiddle_get("player_home/upgraded_rules/grid"));
    upgraded_rules_grid_ex = parse_rule_strings(self.rule_grid_size, fiddle_get("player_home/upgraded_rules_ex/grid"));
    rule_offset = fiddle_deserialize_vec2(fiddle_get("player_home/upgraded_rules/offset"));

    basic_layers = fiddle_get("player_home/basic_layers");
    upgraded_layers = fiddle_get("player_home/upgraded_layers");
    side_room_layers = fiddle_get("player_home/side_room_layers");

    basic_shadow_layer_name = fiddle_get("player_home/basic_shadows");
    upgraded_shadow_layer_name = fiddle_get("player_home/upgraded_shadows");

    door_coordinates = Vec2(176, 88);

    sell_data = array_create_ext(HomeUpgrade.LEN, function(i) {
        if i == 0 {
            return undefined;
        }
        var data = {
            requirements: List(),
            gold_cost: fiddle_get(format("player_home/upgrades/{HomeUpgrade}_gold", i)),
        }

        var items_data = fiddle_get(format("player_home/upgrades/{HomeUpgrade}_items", i));

        for (var j = 0, c = array_length(items_data); j < c; j++) {
            var my_data = items_data[j];
            data.requirements.push({
                item_id: string_to_item_id(my_data.item_id),
                quantity: my_data.quantity
            })
        }

        return data;
    });

    var upper_data = fiddle_get("player_home/upper_floor_sell_data");
    var items_data = upper_data.items;
    var requirements = List();

    for (var i = 0, c = array_length(items_data); i < c; i++) {
        var my_data = items_data[i];
        requirements.push({
            item_id: string_to_item_id(my_data.item_id),
            quantity: my_data.quantity
        })
    }

    upper_floor_sell_data = {
        requirements,
        gold_cost: upper_data.gold
    }

    var upper_sprite_data = fiddle_get("player_home/upper_floor_base_sprites");
    var upper_sprite_names = struct_get_names(upper_sprite_data);
    self.upper_floor_base_sprites = {};
    for (var i = 0, c = array_length(upper_sprite_names); i < c; i++) {
        var name = upper_sprite_names[i];
        self.upper_floor_base_sprites[$ name] = string_to_asset(upper_sprite_data[$ name]);
    }



    function setup_room(grid) {
        var shadow_id;
        if CURRENT_LOCATION_ID == LocationId.PlayerHome {
            for (var i = 0, c = array_length(side_room_layers); i < c; i++) {
                strict_layer_set_visible(side_room_layers[i], false);
            }

            switch self.size_upgrade {
                case HomeUpgrade.LargeWest:
                    strict_layer_set_visible("Level_3_Ceiling", true);
                    break;

                case HomeUpgrade.LargeWestEast:
                    strict_layer_set_visible("Level_3_Ceiling", true);
                    strict_layer_set_visible("Level_4_Ceiling", true);
                break;
            }

            if self.size_upgrade > HomeUpgrade.Small {
                for (var i = 0; i < array_length(self.basic_layers); i++) {
                    strict_layer_set_visible(self.basic_layers[i], false);
                }

                for (var i = 0; i < array_length(self.upgraded_layers); i++) {
                    strict_layer_set_visible(self.upgraded_layers[i], true);
                }
                shadow_id = layer_get_id(self.upgraded_shadow_layer_name);
            } else {
                for (var i = 0; i < array_length(self.basic_layers); i++) {
                    strict_layer_set_visible(self.basic_layers[i], true);
                }

                for (var i = 0; i < array_length(self.upgraded_layers); i++) {
                    strict_layer_set_visible(self.upgraded_layers[i], false);
                }
                shadow_id = layer_get_id(self.basic_shadow_layer_name);
            }
        } else {
            shadow_id = layer_get_id(self.basic_shadow_layer_name);
        }

        var location_key = location_id_to_string(grid.location_id);
        self.apply_wallpaper(self.wallpapers[$ location_key].wallpaper, self.wallpapers[$ location_key].door_mold_sprite, false, self.wallpapers[$ location_key].infusion);
        self.apply_flooring(self.floorings[$ location_key].flooring, false, self.floorings[$ location_key].infusion);
        //
        instance_destroy(obj_shadow_level);

        //
        var shadow_map_id = strict_layer_tilemap_get_id(shadow_id);
        instance_create_depth(0, 0, layer_get_depth(shadow_id), obj_shadow_level, {
            target_shadow_grid: SHADOW_GRID,
            shadow_maps: [shadow_map_id],
            shadow_map_offsets: [
                Vec2(tilemap_get_x(shadow_map_id), tilemap_get_y(shadow_map_id)),
            ],
            render_outlines: true,
            write_z: true,
        });

        //
        instance_create_depth(0, 0, room_data_layer_depth(location_id_to_gm_room(grid.location_id), "Level_0_Walls") - 1, obj_shadow_level, {
            target_shadow_grid: new ShadowGrid(true),
            shadow_maps: undefined,
            render_outlines: false,
            shadow_area: [
                spr_pixel,
                0,
                0,
                0,
                room_width(),
                room_height() / 4,
            ],
            wall_shadow: true,
            write_z: true,
        });
    }

    function on_room_start() {
        if CURRENT_LOCATION_ID == LocationId.PlayerHome {
            for (var i = 0; i < instance_number(obj_roomtransition); i++) {
                var trans = instance_find(obj_roomtransition, i);
                if (trans.home_upgrade_key == HomeUpgrade.Small && self.size_upgrade > HomeUpgrade.Small) || trans.home_upgrade_key > self.size_upgrade {
                    instance_deactivate_object(trans);
                }
            }
        }
    }

    //
    function apply_wallpaper(tileset_wallpaper_name, door_mold_name, return_wallpaper=true, infusion) {
        var tset = try_string_to_asset(format("tile_furniture_{}", tileset_wallpaper_name));
        var location_key = location_id_to_string(CURRENT_LOCATION_ID);
        if tset == undefined {
            return false;
        }

        //
        if return_wallpaper {
            var old_item = undefined;
            var item_wp = undefined;
            for(var i = 0, j = array_length(ITEM_PROTOTYPES); i < j; i ++) {
                item_wp = ITEM_PROTOTYPES[i].wallpaper;
                if item_wp == self.wallpapers[$ location_key].wallpaper {
                    old_item = ITEM_PROTOTYPES[i];
                }
            }
            if old_item != undefined {
                var pt = fiddle_get("misc/wallpaper_spawn_point");
                var center_x = pt[0];
                var center_y = pt[1];

                var inst = instance_create_layer(center_x, center_y, "Instances", obj_item);
                inst.final_x = center_x;
                inst.final_y = center_y;
                inst.final_z = inst.z;

                inst.move_z = true;
                var li = new LiveItem(old_item.item_id);

                if self.wallpapers[$ location_key].infusion != undefined {
                    li.infusion = self.wallpapers[$ location_key].infusion;
                    self.wallpaper_infusion = undefined;
                }

                inst.setup(List(li));
            }
        }

        self.wallpapers[$ location_key] = {
            infusion,
            wallpaper: tileset_wallpaper_name,
            door_mold_sprite: door_mold_name
        }

        tilemap_tileset(strict_layer_tilemap_get_id("Level_0_Walls"), tset);
        tilemap_tileset(strict_layer_tilemap_get_id("Level_1_Ceiling"), tset);
        if CURRENT_LOCATION_ID == LocationId.PlayerHome {
            tilemap_tileset(strict_layer_tilemap_get_id("Level_2_Ceiling"), tset);
            tilemap_tileset(strict_layer_tilemap_get_id("Level_3_Ceiling"), tset);
            tilemap_tileset(strict_layer_tilemap_get_id("Level_4_Ceiling"), tset);
        }


        return true;
    }

    //
    function apply_flooring(tileset_flooring_name, return_flooring=true, infusion) {
        var location_key = location_id_to_string(CURRENT_LOCATION_ID);
        var tset = try_string_to_asset(format("tile_furniture_{}", tileset_flooring_name));
        if tset == undefined {
            return false;
        }

        //
        if return_flooring {
            var old_item = undefined;
            var item_floor;
            for(var i = 0, j = array_length(ITEM_PROTOTYPES); i < j; i ++) {
                item_floor = ITEM_PROTOTYPES[i].flooring;
                if item_floor == self.floorings[$ location_key].flooring {
                    old_item = ITEM_PROTOTYPES[i];
                }
            }
            if old_item != undefined {
                var pt = fiddle_get("misc/wallpaper_spawn_point");
                var center_x = pt[0];
                var center_y = pt[1];

                var inst = instance_create_layer(center_x, center_y, "Instances", obj_item);
                inst.final_x = center_x;
                inst.final_y = center_y;
                inst.final_z = inst.z;

                inst.move_z = true;
                var li = new LiveItem(old_item.item_id);

                if self.floorings[$ location_key].infusion != undefined {
                    li.infusion = self.floorings[$ location_key].infusion;
                    self.floorings[$ location_key].infusion = undefined;
                }

                inst.setup(List(li));
            }
        }

        self.floorings[$ location_key] = {
            flooring: tileset_flooring_name,
            infusion: infusion
        }

        tilemap_tileset(strict_layer_tilemap_get_id("Level_0_Floor"), tset);

        return true;
    }

    function serialize_wallpapers() {
        var arr = struct_get_names(wallpapers);
        var dump = {};
        for (var i = 0, c = array_length(arr); i < c; i++) {
            var wp = self.wallpapers[$ arr[i]];
            dump[$ arr[i]] = {
                wallpaper: wp.wallpaper,
                infusion: try_infusion_to_string(wp.infusion),
                door_mold_sprite: asset_to_string(wp.door_mold_sprite)
            }
        }
        return dump;
    }

    function serialize_floorings() {
        var arr = struct_get_names(floorings);
        var dump = {};
        for (var i = 0, c = array_length(arr); i < c; i++) {
            var fl = self.floorings[$ arr[i]];
            dump[$ arr[i]] = {
                flooring: fl.flooring,
                infusion: try_infusion_to_string(fl.infusion)
            }
        }
        return dump;
    }


    //
    //
    function apply_house_upgrade(g, size_upgrade) {

        if size_upgrade != HomeUpgrade.Small {
            //
            for (var i = 0; i < self.rule_grid_size.x; i++) {
                for (var j = 0; j < self.rule_grid_size.y; j++) {
                    var tile_flag = self.upgraded_rule_grid[# i, j];

                    if tile_flag == 0 {
                        continue;
                    }

                    g.node_flags[g.node_index_for_cell(self.rule_offset.x + i, self.rule_offset.y + j)] = tile_flag;
                }
            }
        } else {
            //
            for (var i = 0; i < self.rule_grid_size.x; i++) {
                for (var j = 0; j < self.rule_grid_size.y; j++) {
                    var tile_flag = self.upgraded_rule_grid[# i, j];

                    if tile_flag != 0 {
                        g.node_flags[g.node_index_for_cell(self.rule_offset.x + i, self.rule_offset.y + j)] = 0;
                    }
                }
            }
        }

        //
        for (var stage_size_upgrade = self.size_upgrade + 1; stage_size_upgrade <= size_upgrade; stage_size_upgrade++) {
            //
            var collision_grid_info = self.collision_grid_removals[stage_size_upgrade];
            for (var i = 0; i < collision_grid_info.size.x; i++) {
                for (var j = 0; j < collision_grid_info.size.y; j++) {
                    var col_flag = collision_grid_info.grid[# i, j];
                    if col_flag == 0 {
                        remove_collision_on_node(g, collision_grid_info.offset.x + i, collision_grid_info.offset.y + j, col_flag == 1);
                    }
                }
            }
            for (var i = 0; i < self.collision_grids[stage_size_upgrade].size.x; i++) {
                for (var j = 0; j < self.collision_grids[stage_size_upgrade].size.y; j++) {
                    var col_flag = self.collision_grids[stage_size_upgrade].grid[# i, j];
                    if col_flag != 0 {
                        set_collision_on_node(g, self.collision_grids[stage_size_upgrade].offset.x + i, self.collision_grids[stage_size_upgrade].offset.y + j, col_flag == 1);
                    }
                }
            }

        }

        self.size_upgrade = size_upgrade;
    }

    function player_home_room_transition() {
        if self.size_upgrade >= HomeUpgrade.Large {
            return self.transition_keys.upgraded;
        } else {
            return self.transition_keys.basic;
        }
    }
}

function deserialize_wallpapers(data) {
    var arr = struct_get_names(data);
    var return_data = {};
    for (var i = 0; i < array_length(arr); i++) {
        var my_data = data[$ arr[i]];
        return_data[$ arr[i]] = {
            wallpaper: my_data.wallpaper,
            infusion: try_string_to_infusion(my_data.infusion),
            door_mold_sprite: string_to_asset(my_data.door_mold_sprite)
        }
    }
    return return_data;
}

function deserialize_floorings(data) {
    var arr = struct_get_names(data);
    var return_data = {};
    for (var i = 0; i < array_length(arr); i++) {
        var my_data = data[$ arr[i]];
        return_data[$ arr[i]] = {
            flooring: my_data.flooring,
            infusion: try_string_to_infusion(my_data.infusion)
        }
    }
    return return_data;
}

//
function home_location_is_unlocked(lid) {
    switch lid {
        case LocationId.PlayerHome: return true;
        case LocationId.PlayerHomeWest: return DECOR.size_upgrade >= HomeUpgrade.LargeWest;
        case LocationId.PlayerHomeEast: return DECOR.size_upgrade >= HomeUpgrade.LargeWestEast;
        case LocationId.PlayerHomeUpperCentral:
        case LocationId.PlayerHomeUpperEast:
        case LocationId.PlayerHomeUpperWest: return DECOR.upper_floor;
        default: impossible("Unexpected LocationId: {LocationId}", lid);
    }
}
