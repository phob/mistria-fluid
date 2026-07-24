object_create(
    "obj_chicken_statue",
    object_reserve("par_interactable"),
    {
        sprite_index: spr_haydens_farm_chicken_statue_spring_off,
        create: function() {
            //
            event_inherit(ObjectEvent.Create);

            //
            SHADOW_WAIT_LIST.push({
                x,
                y,
                sprite: SHADOW_DICTIONARY.get(self.sprite_index),
            });

            self.mask_index = self.sprite_index;
            self.image_speed = 0;
            self.prize = undefined;
            self.high_price = fiddle_get("misc/chicken_statue/high_price");
            self.low_price = fiddle_get("misc/chicken_statue/low_price");
            self.on_sprite = CALENDAR.season() != Season.Winter ? spr_haydens_farm_chicken_statue_spring_on : spr_haydens_farm_chicken_statue_winter_on;
            self.off_sprite = CALENDAR.season() != Season.Winter ? spr_haydens_farm_chicken_statue_spring_off :spr_haydens_farm_chicken_statue_winter_off;

            sprite_index = self.off_sprite;
            self.register_interaction(
                InputId.Interact,
                "misc_local/inspect",
                function() {
                    var currency_amount = ARI.inventory.item_id_quantity(ItemId.AnimalCurrency);
                    var convo = currency_amount == 0 ? GpTriggeredConversation.ChickenStatueNoCurrency : GpTriggeredConversation.ChickenStatueHasCurrency;
                    var callback = undefined;
                    if convo == GpTriggeredConversation.ChickenStatueHasCurrency {
                        callback = function(driver) {
                            if matches(driver.prompt_index_selected, 0, 1) {
                                TANGO.play("SoundEffects/Objects/UseChickenStatue");

                                //
                                var yield = poll_statue_reward(CHICKEN_STATUE_REWARDS, driver.prompt_index_selected == 0);
                                ARI.inventory.remove(ItemId.AnimalCurrency, driver.prompt_index_selected == 0 ? self.low_price : self.high_price);
                                self.sprite_index = self.on_sprite;
                                self.image_speed = 1;
                                self.prize = consume_reward(yield);

                                array_push(GAME_STATS.chicken_statue_uses, {
                                    prize: self.prize.first().pretty_print(),
                                    currency: driver.prompt_index_selected == 0 ? self.low_price : self.high_price,
                                    day: total_days(),
                                });
                            }
                            STATUE_CTX = undefined;
                        }
                    };

                    STATUE_CTX = "chicken_statue";
                    var driver = play_conversation_from_path(NpcId.Caldarus, GAMEPLAY_CONVERSATIONS[convo], callback);

                    if currency_amount < self.low_price {
                        driver.textbox.prompt_one.blackboard.insert("stay_locked", true);
                    }
                    if currency_amount < self.high_price {
                        driver.textbox.prompt_two.blackboard.insert("stay_locked", true);
                    }
                }
            );

            depth = get_instance_depth(y);
        },
        animation_end: function() {
            self.sprite_index = self.off_sprite;
            self.image_speed = 0;
            drop_item_stack(self.x, self.y, self.prize);
        },
    }
);
