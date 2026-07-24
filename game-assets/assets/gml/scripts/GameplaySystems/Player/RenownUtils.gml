#macro RENOWN global.__renown
RENOWN = undefined;

#macro RENOWN_REWARD_INVENTORY global.__renown_reward_inventory
RENOWN_REWARD_INVENTORY = undefined;

#macro MAX_RENOWN_LEVEL 95

function load_renown() {
    var data = clone_value(fiddle_get("renown"));
    for (var i = 0; i < array_length(data.ranks); i++) {
        var rank = data.ranks[i];

        rank.sprite = string_to_asset(rank.sprite);
        rank.small_sprite = string_to_asset(rank.small_sprite);
    }

    data.rewards = ListFromArray(data.rewards).map(parse_reward);
    data.ranks = ListFromArray(data.ranks);

    return data;
}

//
function renown_level_total_cost(level) {
    var total = 0;
    for (var i = 0; i <= level; i++) {
        total += renown_level_individual_cost(i);
    }
    return total;
}

//
//
//
//
function renown_level_individual_cost(level) {
    static MULTIP = 2;
    static POWER = 1.1;
    return level == 0 ? 0 : round(20 + power((level - 1) * MULTIP, POWER));
}

//
function renown_to_level(renown) {
    var level = 0;
    while true {
        var next_cost = renown_level_individual_cost(level + 1);
        if renown >= next_cost {
            renown -= next_cost;
            level += 1;
        } else {
            return level;
        }
    }
}

//
function renown_level_to_rank(level) {
    var rank = min(
        level div RENOWN.levels_per_rank,
        RENOWN.ranks.count() - 1,
    );
    return RENOWN.ranks.get(rank);
}

enum RenownEntryType {
    Gold,
    MuseumDonation,
    Quest,
    LEN
}

function renown_entry_value(entry) {
    switch entry.type {
        case RenownEntryType.Gold:
            return ceil(entry.gold * 0.01);
        case RenownEntryType.MuseumDonation:
            //
            return ITEM_PROTOTYPES[entry.item_id].value.renown ?? 5;
        case RenownEntryType.Quest:
            var quest = QUESTS.get(entry.quest_key);
            var reward = quest.reward_list.find_value(function(reward) {
                return reward.type == QuestRewardType.Renown;
            });
            assert_neq(
                reward,
                undefined,
                "Quest was registered for renown with no suitable reward: {}",
                entry.quest_key,
            );
            return reward.value;
        default: impossible("Unexpected RenownEntryType: {}", entry.type);
    }
}

function RenownEntryFactory() constructor {
    static Gold = function(gold) {
        return {
            type: RenownEntryType.Gold,
            gold: gold,
        };
    }

    static MuseumDonation = function(item_id) {
        return {
            type: RenownEntryType.MuseumDonation,
            item_id: item_id,
        };
    }

    static Quest = function(quest_key) {
        return {
            type: RenownEntryType.Quest,
            quest_key: quest_key
        };
    }
}

function serialize_renown_entry(entry) {
    var output = clone_value(entry);
    switch output.type {
        case RenownEntryType.Gold: break;
        case RenownEntryType.MuseumDonation:
            output.item = item_id_to_string(output.item_id);
            break;
        case RenownEntryType.Quest: break;
        default: impossible("Unexpected RenownEntryType: {}", output.type);
    }

    output.type = renown_entry_type_to_string(output.type);

    return output;
}

function deserialize_renown_entry(entry) {
    entry.type = string_to_renown_entry_type(entry.type);
    switch entry.type {
        case RenownEntryType.Gold: return RenownEntry.Gold(entry.gold);
        case RenownEntryType.MuseumDonation: return RenownEntry.MuseumDonation(string_to_item_id(entry.item));
        case RenownEntryType.Quest: return RenownEntry.Quest(entry.quest_key);
        default: impossible("Unexpected RenownEntryType: {}", output.type);
    }
}

#macro RenownEntry global.__renown_entry_factory
global.__renown_entry_factory = new RenownEntryFactory();
