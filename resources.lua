-- GAG Hub Resource Config
-- Auto-generated from decompiled SeedData + GearShopData
-- Load via: loadstring(game:HttpGet(URL))()
-- Returns: table with SeedPrices, GearPrices, SeedMeta, GearMeta

local Resources = {}

-------------------------------------------------
-- SEED PRICES (from SharedModules.SeedData)
-------------------------------------------------
Resources.SeedPrices = {
    ["Carrot"]           = 1,
    ["Strawberry"]       = 10,
    ["Blueberry"]        = 25,
    ["Tulip"]            = 40,
    ["Tomato"]           = 200,
    ["Apple"]            = 400,
    ["Bamboo"]           = 700,
    ["Corn"]             = 2500,
    ["Cactus"]           = 5000,
    ["Pineapple"]        = 10000,
    ["Mushroom"]         = 15000,
    ["Green Bean"]       = 20000,
    ["Banana"]           = 30000,
    ["Grape"]            = 50000,
    ["Coconut"]          = 70000,
    ["Mango"]            = 85000,
    ["Dragon Fruit"]     = 120000,
    ["Acorn"]            = 200000,
    ["Cherry"]           = 250000,
    ["Sunflower"]        = 300000,
    ["Venus Fly Trap"]   = 400000,
    ["Poison Apple"]     = 400000,
    ["Pomegranate"]      = 2000000,
    ["Ghost Pepper"]     = 2800000,
    ["Poison Ivy"]       = 2800000,
    ["Moon Bloom"]       = 7000000,
    ["Dragon's Breath"]  = 9000000,
    -- Event/special seeds (not in shop)
    ["Baby Cactus"]      = 1,
    ["Glow Mushroom"]    = 1,
    ["Romanesco"]        = 1,
    ["Horned Melon"]     = 1,
}

-------------------------------------------------
-- SEED META (name, rarity, restock chance, single harvest)
-------------------------------------------------
Resources.SeedMeta = {
    ["Carrot"]           = { rarity = "Common",    restockChance = 100,    singleHarvest = true  },
    ["Strawberry"]       = { rarity = "Common",    restockChance = 100,    singleHarvest = false },
    ["Blueberry"]        = { rarity = "Common",    restockChance = 100,    singleHarvest = false },
    ["Tulip"]            = { rarity = "Uncommon",  restockChance = 100,    singleHarvest = true  },
    ["Tomato"]           = { rarity = "Uncommon",  restockChance = 90,     singleHarvest = false },
    ["Apple"]            = { rarity = "Uncommon",  restockChance = 52.63,  singleHarvest = false },
    ["Bamboo"]           = { rarity = "Rare",      restockChance = 80,     singleHarvest = true  },
    ["Corn"]             = { rarity = "Rare",      restockChance = 35,     singleHarvest = false },
    ["Cactus"]           = { rarity = "Rare",      restockChance = 16.668, singleHarvest = false },
    ["Pineapple"]        = { rarity = "Rare",      restockChance = 12.501, singleHarvest = false },
    ["Mushroom"]         = { rarity = "Epic",      restockChance = 9.092,  singleHarvest = true  },
    ["Green Bean"]       = { rarity = "Epic",      restockChance = 15,     singleHarvest = true  },
    ["Banana"]           = { rarity = "Epic",      restockChance = 9,      singleHarvest = false },
    ["Grape"]            = { rarity = "Epic",      restockChance = 6.668,  singleHarvest = false },
    ["Coconut"]          = { rarity = "Epic",      restockChance = 5.001,  singleHarvest = false },
    ["Mango"]            = { rarity = "Epic",      restockChance = 5.001,  singleHarvest = false },
    ["Dragon Fruit"]     = { rarity = "Legendary", restockChance = 4,      singleHarvest = false },
    ["Acorn"]            = { rarity = "Legendary", restockChance = 2.942,  singleHarvest = false },
    ["Cherry"]           = { rarity = "Legendary", restockChance = 2.274,  singleHarvest = false },
    ["Sunflower"]        = { rarity = "Legendary", restockChance = 1.787,  singleHarvest = false },
    ["Venus Fly Trap"]   = { rarity = "Mythic",    restockChance = 1.43,   singleHarvest = false },
    ["Poison Apple"]     = { rarity = "Mythic",    restockChance = 0.533,  singleHarvest = false },
    ["Pomegranate"]      = { rarity = "Mythic",    restockChance = 0.927,  singleHarvest = false },
    ["Ghost Pepper"]     = { rarity = "Mythic",    restockChance = 0.533,  singleHarvest = false },
    ["Poison Ivy"]       = { rarity = "Legendary", restockChance = 0.533,  singleHarvest = false },
    ["Moon Bloom"]       = { rarity = "Super",     restockChance = 0.35,   singleHarvest = false },
    ["Dragon's Breath"]  = { rarity = "Super",     restockChance = 0.275,  singleHarvest = false },
}

-------------------------------------------------
-- GEAR PRICES (from SharedModules.GearShopData)
-------------------------------------------------
Resources.GearPrices = {
    ["Trowel"]               = 1000,
    ["Common Watering Can"]  = 2000,
    ["Speed Mushroom"]       = 1500,
    ["Jump Mushroom"]        = 1800,
    ["Common Sprinkler"]     = 3000,
    ["Sign"]                 = 4000,
    ["Shrink Mushroom"]      = 4500,
    ["Supersize Mushroom"]   = 4500,
    ["Uncommon Sprinkler"]   = 10000,
    ["Flashbang"]            = 8000,
    ["Lantern"]              = 12000,
    ["Teleporter"]           = 18000,
    ["Invisibility Mushroom"]= 18000,
    ["Rare Sprinkler"]       = 50000,
    ["Gnome"]                = 50000,
    ["Basic Pot"]            = 60000,
    ["Legendary Sprinkler"]  = 100000,
    ["Super Sprinkler"]      = 300000,
    ["Super Watering Can"]   = 250000,
    ["Wheelbarrow"]          = 500000,
}

-------------------------------------------------
-- GEAR META (name, rarity, restock chance)
-------------------------------------------------
Resources.GearMeta = {
    ["Trowel"]               = { rarity = "Rare",      restockChance = 28   },
    ["Common Watering Can"]  = { rarity = "Common",    restockChance = 90   },
    ["Speed Mushroom"]       = { rarity = "Rare",      restockChance = 22   },
    ["Jump Mushroom"]        = { rarity = "Rare",      restockChance = 24   },
    ["Common Sprinkler"]     = { rarity = "Common",    restockChance = 50   },
    ["Sign"]                 = { rarity = "Common",    restockChance = nil  },
    ["Shrink Mushroom"]      = { rarity = "Epic",      restockChance = 10   },
    ["Supersize Mushroom"]   = { rarity = "Epic",      restockChance = 10   },
    ["Uncommon Sprinkler"]   = { rarity = "Uncommon",  restockChance = 35   },
    ["Flashbang"]            = { rarity = "Epic",      restockChance = 7    },
    ["Lantern"]              = { rarity = "Rare",      restockChance = nil  },
    ["Teleporter"]           = { rarity = "Legendary", restockChance = 3    },
    ["Invisibility Mushroom"]= { rarity = "Legendary", restockChance = 4    },
    ["Rare Sprinkler"]       = { rarity = "Rare",      restockChance = 25   },
    ["Gnome"]                = { rarity = "Epic",      restockChance = 8    },
    ["Basic Pot"]            = { rarity = "Epic",      restockChance = 7    },
    ["Legendary Sprinkler"]  = { rarity = "Legendary", restockChance = 4    },
    ["Super Sprinkler"]      = { rarity = "Super",     restockChance = 1.2  },
    ["Super Watering Can"]   = { rarity = "Super",     restockChance = 2    },
    ["Wheelbarrow"]          = { rarity = "Legendary", restockChance = nil  },
}

-------------------------------------------------
-- ALL SEED NAMES (sorted by price)
-------------------------------------------------
Resources.AllSeeds = {}
for name, _ in pairs(Resources.SeedPrices) do
    table.insert(Resources.AllSeeds, name)
end
table.sort(Resources.AllSeeds, function(a, b)
    return Resources.SeedPrices[a] < Resources.SeedPrices[b]
end)

-------------------------------------------------
-- ALL GEAR NAMES (sorted by price)
-------------------------------------------------
Resources.AllGears = {}
for name, _ in pairs(Resources.GearPrices) do
    table.insert(Resources.AllGears, name)
end
table.sort(Resources.AllGears, function(a, b)
    return Resources.GearPrices[a] < Resources.GearPrices[b]
end)

return Resources
