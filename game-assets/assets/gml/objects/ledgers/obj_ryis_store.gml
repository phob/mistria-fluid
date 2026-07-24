object_create(
    "obj_ryis_store",
    object_reserve("par_ledger"),
    {
        sprite_index: spr_generalstore_store_ledger_spring,
        create: function() {
            event_inherit(ObjectEvent.Create);

            self.darkness_sprite = spr_generalstore_store_ledger_darkness;
            self.name = "ryis_store";

            function spawn_menu() {
                self.mcp = new MultipleChoicePopup("stores/carpenter/name", spr_ui_generic_icon_npc_ryis);
                self.mcp.option("misc_local/shop", function() {
                    var shop = ANCHOR.spawn_menu(Menu.Store, Store.Carpenter);
                    shop.background.in_now();
                    self.mcp.popup.background.out_now();

                    shop.on_free = function() {
                        var menu = ANCHOR.get_menu(Menu.Store);
                        if menu.tooltip != undefined {
                            menu.tooltip.close();
                        }
                        self.spawn_menu();
                    }
                });

                var all_home_upgrades = DECOR.size_upgrade == HomeUpgrade.LargeWestEast;
                var can_buy_floor_two = QUEST_LOG.completed.contains("upgrade_the_carpenters_shop")
                    && DECOR.upper_floor == false && DECOR.size_upgrade == HomeUpgrade.LargeWestEast;

                self.mcp.option("misc_local/home_upgrade", function(can_buy_floor_two) {
                    var popup_text = undefined;
                    if can_buy_floor_two {
                        popup_text = "misc_local/home_upgrade_four";
                    } else {
                        var next_upgrade = DECOR.size_upgrade + 1;
                        switch next_upgrade {
                            case HomeUpgrade.Large:
                                popup_text = "misc_local/home_upgrade_one";
                                break;
                            case HomeUpgrade.LargeWest:
                                popup_text = "misc_local/home_upgrade_two";
                                break;
                            case HomeUpgrade.LargeWestEast:
                                popup_text = "misc_local/home_upgrade_three";
                                break;
                            default: impossible("Not set up for {HomeUpgrade}", next_upgrade);
                        }
                    }

                    var next_upgrade = DECOR.size_upgrade + 1;

                    var popup = popup_creator(popup_text, "misc_local/ok");

                    popup.body_text.disable(); //
                    popup.body.set_align(Align.Center, Align.BottomIn)
                        .set_y(-32)

                    var sprite = string_to_asset(format("spr_ui_player_house_{}_preview", DECOR.size_upgrade + 2));
                    ANCHOR.sprite(popup.header)
                        .set_sprite(sprite)
                        .set_align(Align.Center, Align.BottomOut)
                        .set_y(4)

                    var upgrade_data = can_buy_floor_two ? DECOR.upper_floor_sell_data : DECOR.sell_data[next_upgrade];
                    var listings = List(Listing.Gold(upgrade_data.gold_cost));

                    for (var i = 0, c = upgrade_data.requirements.count(); i < c; i++) {
                        var data = upgrade_data.requirements.get(i);
                        var listing = Listing.Item(data.item_id, ARI.inventory, data.quantity);

                        listings.push(listing);
                    }

                    var yy = 0;
                    for (var i = 0; i < listings.count(); i++) {
                        var listing = listings.get(i);
                        var label = listing_label(listing);
                        var root_height = ANCHOR.text_height(label, 113) + 8;
                        var root = ANCHOR.positional(popup.body)
                            .set_size(161, root_height)
                            .set_y(yy)

                        render_quest_requirement(listing, root);
                        yy += root_height;
                    }

                    popup.body.set_height(yy);
                    popup.refresh_backplate_height();
                    popup.backplate.add_height(can_buy_floor_two ? 108 : 96);


                    var can_fulfill = true;
                    for (var i = 0; i < listings.count(); i++) {
                        var listing = listings.get(i);
                        if !can_fulfill_listing(listing) {
                            can_fulfill = false;
                        }
                    }

                    popup.create_button("misc_local/cancel", function() {
                        await_popup(function() {
                            self.spawn_menu();
                        })
                    });

                    var button = popup.create_button("misc_local/buy", function(can_buy_floor_two) {
                        var next_upgrade = DECOR.size_upgrade + 1;
                        var upgrade_data = can_buy_floor_two
                            ? DECOR.upper_floor_sell_data
                            : DECOR.sell_data[next_upgrade];

                        if !can_buy_floor_two {
                            DECOR.apply_house_upgrade(GRIDS[LocationId.PlayerHome], next_upgrade);
                        } else {
                            DECOR.upper_floor = true;
                        }

                        for (var i = 0, c = upgrade_data.requirements.count(); i < c; i++) {
                            var data = upgrade_data.requirements.get(i);
                            ARI.inventory.remove(data.item_id, data.quantity);
                        }

                        ARI.modify_gold(-upgrade_data.gold_cost);

                        array_push(GAME_STATS.home_upgrades, {
                            upgrade: can_buy_floor_two ? "upper_floor" : home_upgrade_to_string(next_upgrade),
                            day: total_days(),
                        });

                        await_popup(function() {
                            var pop = popup_creator("misc_local/house_upgraded", "misc_local/house_upgraded_description");
                            pop.create_button("misc_local/close");
                            pop.spawn();

                            await_popup(function() {
                                self.spawn_menu();
                            })

                        })

                    }, [can_buy_floor_two]);

                    button.set_unlocked(can_fulfill);

                    popup.spawn();
                }, [can_buy_floor_two]);
                self.mcp.buttons.last().set_unlocked(!all_home_upgrades || can_buy_floor_two);
                self.mcp.option("misc_local/farm_expansion", function() {
                    var popup = popup_creator("misc_local/farm_expansion", "misc_local/ok");
                    popup.body_text.disable();
                    popup.body.set_align(Align.Center, Align.BottomIn)
                        .set_y(-32)

                    ANCHOR.sprite(popup.header)
                        .set_sprite(EXPANSION_COST.preview)
                        .set_align(Align.Center, Align.BottomOut)
                        .set_y(4)

                    var yy = 0;

                    var listings = List(Listing.Gold(EXPANSION_COST.gold));

                    for (var i = 0, ic = EXPANSION_COST.items.count(); i < ic; i++) {
                        var item = EXPANSION_COST.items.get(i);
                        listings.push(Listing.Item(item.item_id, ARI.inventory, item.count))
                    }

                    for (var i = 0, ic = listings.count(); i < ic; i++) {
                        var listing = listings.get(i);
                        var root_height = ANCHOR.text_height(listing_label(listing), 113) + 8;
                        var root = ANCHOR.positional(popup.body)
                            .set_size(161, root_height)
                            .set_y(yy)

                        render_quest_requirement(listing, root);
                        yy += root_height;
                    }

                    popup.body.set_height(yy);
                    popup.refresh_backplate_height();
                    popup.backplate.add_height(96);

                    var can_fulfill = true;
                    for (var i = 0, ic = listings.count(); i < ic; i++) {
                        var listing = listings.get(i);
                        if !can_fulfill_listing(listing) {
                            can_fulfill = false;
                        }
                    }

                    popup.create_button("misc_local/cancel", function() {
                        await_popup(function() {
                            self.spawn_menu();
                        })
                    });

                    var button = popup.create_button("misc_local/buy", function() {
                        expand_farm();

                        for (var i = 0, c = EXPANSION_COST.items.count(); i < c; i++) {
                            var data = EXPANSION_COST.items.get(i);
                            ARI.inventory.remove(data.item_id, data.count);
                        }

                        ARI.modify_gold(-EXPANSION_COST.gold);

                        await_popup(function() {
                            var pop = popup_creator("misc_local/farm_expanded", "misc_local/farm_expanded_description");
                            pop.create_button("misc_local/close");
                            pop.spawn();

                            await_popup(function() {
                                self.spawn_menu();
                            });

                        })
                    });

                    button.set_unlocked(can_fulfill);

                    popup.spawn();
                });

                self.mcp.buttons.last().set_unlocked(!FARM_EXPANDED);

                self.mcp.popup.close_callback = function() {
                    if FARM_EXPANDED && !ari_has_recipe_anywhere(ItemId.FarmBridge) {
                        item_from_critical_poof(self.x + 4, self.y, new LiveItem(ItemId.CraftingScroll, ItemId.FarmBridge), 135, 225);
                        item_from_critical_poof(self.x + 4, self.y, new LiveItem(ItemId.FarmBridge), 135, 225);
                    }

                    if DECOR.upper_floor && !ari_has_recipe_anywhere(ItemId.Stairs) {
                        item_from_critical_poof(self.x + 4, self.y, new LiveItem(ItemId.CraftingScroll, ItemId.Stairs), 135, 225);
                        item_from_critical_poof(self.x + 4, self.y, new LiveItem(ItemId.Stairs), 135, 225);
                    }
                }
            }

            self.register_interaction(
                InputId.Interact,
                "misc_local/shop",
                function() {
                    self.spawn_menu();
                },
            );

            depth = get_instance_depth(y);
        },
    }
);
