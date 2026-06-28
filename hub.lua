--[[
    GAG Hub — Clean Edition
    All features from the big 4500-line hub, rewritten in the simple style:
    direct require(Networking), plain toggles, no Modules/startModule abstraction.
    Paste & play: loadstring(game:HttpGet("..."))()
]]

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

---------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TeleportService   = game:GetService("TeleportService")
local VirtualUser        = game:GetService("VirtualUser")

local player   = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Networking = require(ReplicatedStorage:WaitForChild("SharedModules"):FindFirstChild("Networking"))
local Notify      = ReplicatedStorage:WaitForChild("Notify")

---------------------------------------------------------------
-- CONFIG (adjustable values, all in one place)
---------------------------------------------------------------
local Config = {
    HarvestInterval   = 0.5,
    WaterInterval     = 3,
    PlantInterval     = 5,
    RestockInterval   = 1,
    GearInterval      = 2,
    MutationInterval  = 3,
    WeatherInterval   = 5,
    StealInterval     = 1.5,
    InventoryInterval = 10,
    PetHatchInterval  = 2,
    SeedPackInterval  = 2,
    PetCatchInterval  = 3,

    WaterAll          = false,
    WaterFullyGrown   = false,
    RequiredCan       = "",

    PreferSeed        = nil,
    GridSpacing       = 3,
    PlantOrder        = "Top",       -- Top | Bottom | Random
    SkipMutatedSeeds  = true,

    RestockTargets    = {},
    RestockBlacklist  = {},
    GearTargets       = {},

    FavoriteThreshold = 500,
    AutoFavorite      = true,
    AutoPromote       = true,
    DropThreshold     = 5,

    PetMinRarity      = "Rare",
    PetAutoSellUnwanted = false,

    MutationAlerts    = { "Rainbow", "Starstruck", "Gold", "Frozen", "Electric", "Bloodlit", "Chained" },
    MutationMultipliers = {
        Gold = 20, Rainbow = 50, Electric = 12, Frozen = 10,
        Bloodlit = 5, Chained = 8, Starstruck = 100,
    },

    StealMinValue     = 10000,
    StealMaxPerNight  = 20,

    PetCatchMinRarity = "Common",
    PetCatchAutoReturn = true,

    TargetJobId       = "",
    AutoRejoin        = true,
    RejoinDelay       = 5,
}

-- Approximate base sell values (used for steal value filter / inventory drop logic)
local BaseValues = {
    Carrot=5, Strawberry=3, Blueberry=5, Tomato=9, Apple=12, Cactus=40,
    Pineapple=30, Banana=35, Corn=34, Grape=45, Mango=90, Coconut=60,
    Cherry=350, Pomegranate=900, ["Dragon Fruit"]=150, Mushroom=13000,
    Sunflower=1750, ["Venus Fly Trap"]=3000, ["Moon Bloom"]=9000,
    ["Dragon's Breath"]=3400, ["Ghost Pepper"]=2500, Lotus=6500,
    Romanesco=1500, ["Poison Apple"]=900, ["Poison Ivy"]=1700,
    ["Glow Mushroom"]=700, ["Horned Melon"]=200, ["Baby Cactus"]=70,
    Tulip=60, Bamboo=800, Pumpkin=350, Pinetree=100, ["Green Bean"]=10,
    Beanstalk=2000, ["Thorn Rose"]=140, Acorn=200,
}

local AllSeeds = {
    "Strawberry","Carrot","Blueberry","Tomato","Green Bean",
    "Apple","Pineapple","Corn","Banana","Cactus","Grape",
    "Coconut","Tulip","Baby Cactus","Mango","Pinetree",
    "Thorn Rose","Dragon Fruit","Acorn","Horned Melon",
    "Pumpkin","Cherry","Glow Mushroom","Bamboo",
    "Pomegranate","Poison Apple","Romanesco","Poison Ivy",
    "Sunflower","Beanstalk","Ghost Pepper","Venus Fly Trap",
    "Dragon's Breath","Lotus","Moon Bloom","Mushroom",
}

local AllGears = {
    "Trowel","Speed Mushroom","Jump Mushroom","Common Watering Can",
    "Common Sprinkler","Sign","Shrink Mushroom","Supersize Mushroom",
    "Flashbang","Uncommon Sprinkler","Lantern","Teleporter",
    "Rare Sprinkler","Gnome","Basic Pot","Legendary Sprinkler",
    "Super Watering Can","Super Sprinkler","Wheelbarrow",
}

---------------------------------------------------------------
-- SMALL HELPERS
---------------------------------------------------------------
local function getMyGarden()
    local plotId = player:GetAttribute("PlotId")
    if not plotId then return nil end
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return nil end
    return gardens:FindFirstChild("Plot" .. tostring(plotId))
end

local function getHRP()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function isAlive()
    local char = player.Character
    local hum = char and char:FindFirstChildWhichIsA("Humanoid")
    return hum and hum.Health > 0
end

local function getSheckles()
    local ls = player:FindFirstChild("leaderstats")
    local s = ls and ls:FindFirstChild("Sheckles")
    return s and s.Value or 0
end

local function isNight()
    local night = ReplicatedStorage:FindFirstChild("Night")
    if night then return night.Value == true end
    local clock = game:GetService("Lighting").ClockTime
    return clock >= 18 or clock < 6
end

local function formatNumber(n)
    if n >= 1e12 then return string.format("%.1fT", n / 1e12) end
    if n >= 1e9  then return string.format("%.1fB", n / 1e9) end
    if n >= 1e6  then return string.format("%.1fM", n / 1e6) end
    if n >= 1e3  then return string.format("%.1fK", n / 1e3) end
    return tostring(n)
end

local function getPlantsInGarden(garden)
    local out = {}
    if not garden then return out end
    for _, child in ipairs(garden:GetDescendants()) do
        if child:IsA("Model") and child:GetAttribute("SeedName") then
            table.insert(out, child)
        end
    end
    return out
end

local function getPlantInfo(plant)
    return {
        Name     = plant:GetAttribute("SeedName") or plant.Name,
        Growth   = plant:GetAttribute("Growth") or 0,
        Mutation = plant:GetAttribute("Mutation"),
    }
end

---------------------------------------------------------------
-- AUTO HARVEST
---------------------------------------------------------------
local harvestRunning = false
local function isHarvestable(fruitModel)
    if not fruitModel or not fruitModel.Parent then return false end
    local hp = fruitModel:FindFirstChild("HarvestPart")
    local prompt = hp and hp:FindFirstChild("HarvestPrompt")
    return prompt ~= nil and prompt.Enabled
end

local function startAutoHarvest()
    if harvestRunning then return end
    harvestRunning = true
    Notify:Fire("Auto Harvest enabled")
    task.spawn(function()
        while harvestRunning do
            pcall(function()
                if not isAlive() then return end
                local plot = getMyGarden()
                if not plot then return end
                local plantsFolder = plot:FindFirstChild("Plants")
                if not plantsFolder then return end

                for _, plantModel in ipairs(plantsFolder:GetChildren()) do
                    if not harvestRunning then break end
                    local plantId = plantModel:GetAttribute("PlantId")
                    if not plantId then continue end

                    local fruitsFolder = plantModel:FindFirstChild("Fruits")
                    if fruitsFolder then
                        for _, fruitModel in ipairs(fruitsFolder:GetChildren()) do
                            if not harvestRunning then break end
                            if isHarvestable(fruitModel) then
                                local fruitId = fruitModel:GetAttribute("FruitId")
                                pcall(function()
                                    Networking.Garden.CollectFruit:Fire(plantId, fruitId or "")
                                end)
                                task.wait(0.1)
                            end
                        end
                    end

                    if isHarvestable(plantModel) then
                        pcall(function()
                            Networking.Garden.CollectFruit:Fire(plantId, "")
                        end)
                        task.wait(0.1)
                    end
                end
            end)
            task.wait(Config.HarvestInterval)
        end
    end)
end

local function stopAutoHarvest()
    harvestRunning = false
    Notify:Fire("Auto Harvest disabled")
end

---------------------------------------------------------------
-- AUTO WATER
---------------------------------------------------------------
local waterRunning = false

local function findWateringCan(requiredCan)
    local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
    local reqNorm = trim(requiredCan)

    local function scan(container)
        if not container then return nil end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute("WateringCan") ~= nil then
                if reqNorm == "" or trim(tool.Name) == reqNorm then
                    return tool, tool.Name
                end
            end
        end
        return nil
    end

    local tool, name = scan(player.Character)
    if tool then return tool, name end
    return scan(player:FindFirstChild("Backpack"))
end

local function equipTool(tool)
    local char = player.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    if tool.Parent == char then return true end
    pcall(function() humanoid:EquipTool(tool) end)
    task.wait(0.2)
    return tool.Parent == char
end

local function startAutoWater()
    if waterRunning then return end
    waterRunning = true
    Notify:Fire("Auto Water enabled")
    task.spawn(function()
        while waterRunning do
            pcall(function()
                local garden = getMyGarden()
                if not garden then return end

                local canTool, canName = findWateringCan(Config.RequiredCan)
                if not canTool then return end
                if not equipTool(canTool) then return end

                for _, plant in ipairs(getPlantsInGarden(garden)) do
                    if not waterRunning then break end
                    local info = getPlantInfo(plant)
                    local growth = info.Growth or 0
                    local fullyGrown = growth >= 1
                    if fullyGrown and not Config.WaterFullyGrown then continue end
                    if not (growth < 1 or Config.WaterAll or Config.WaterFullyGrown) then continue end

                    local rootPart = plant:FindFirstChildWhichIsA("BasePart")
                    if not rootPart then continue end

                    local pos = rootPart.Position - Vector3.new(0, 0.3, 0)
                    pcall(function()
                        Networking.WateringCan.UseWateringCan:Fire(pos, canName, canTool)
                    end)
                    task.wait(0.5)
                end
            end)
            task.wait(Config.WaterInterval)
        end
    end)
end

local function stopAutoWater()
    waterRunning = false
    Notify:Fire("Auto Water disabled")
end

---------------------------------------------------------------
-- AUTO PLANT
---------------------------------------------------------------
local plantRunning = false

local function isMutatedSeed(seedToolValue)
    if not seedToolValue then return false end
    if seedToolValue == "Gold" or seedToolValue == "Rainbow" then return true end
    return seedToolValue:match("^Gold ") ~= nil or seedToolValue:match("^Rainbow ") ~= nil
end

local function getEquippedSeed()
    local char = player.Character
    local tool = char and char:FindFirstChildWhichIsA("Tool")
    if not tool then return nil, nil end
    if tool:GetAttribute("MainCategory") ~= "Seed" then return nil, nil end
    local seedName = tool:GetAttribute("SeedTool")
    if not seedName then return nil, nil end
    return seedName, tool
end

local function findSeedsInBackpack(preferSeed, skipMutated)
    local bp = player:FindFirstChild("Backpack")
    if not bp then return {} end
    local seeds = {}
    for _, tool in ipairs(bp:GetChildren()) do
        if tool:IsA("Tool") then
            local cat, sn = tool:GetAttribute("MainCategory"), tool:GetAttribute("SeedTool")
            if sn and cat == "Seed" then
                if not (skipMutated and isMutatedSeed(sn)) then
                    table.insert(seeds, { tool = tool, seedName = sn })
                end
            end
        end
    end
    table.sort(seeds, function(a, b)
        if preferSeed then
            local am, bm = a.seedName == preferSeed, b.seedName == preferSeed
            if am ~= bm then return am end
        end
        return a.seedName < b.seedName
    end)
    return seeds
end

local function equipSeed(preferSeed, skipMutated)
    local char = player.Character
    local humanoid = char and char:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return nil, nil end

    local sn, tool = getEquippedSeed()
    if sn and not (skipMutated and isMutatedSeed(sn)) then return sn, tool end

    local seeds = findSeedsInBackpack(preferSeed, skipMutated)
    if #seeds == 0 then return nil, nil end

    local target = seeds[1]
    pcall(function() humanoid:EquipTool(target.tool) end)

    local waited = 0
    while waited < 2 do
        task.wait(0.1); waited += 0.1
        local equipped = char:FindFirstChild(target.tool.Name)
        if equipped and equipped:IsA("Tool") and equipped:GetAttribute("SeedTool") then
            return target.seedName, target.tool
        end
    end
    return nil, nil
end

local function unequipTool()
    local char = player.Character
    local tool = char and char:FindFirstChildWhichIsA("Tool")
    if tool then pcall(function() tool.Parent = player:FindFirstChild("Backpack") end) end
end

local function generateGridFromPart(part, spacing)
    spacing = spacing or 3
    local positions = {}
    local size, cf = part.Size, part.CFrame
    local stepsX = math.max(1, math.floor(size.X / spacing))
    local stepsZ = math.max(1, math.floor(size.Z / spacing))
    for ix = 0, stepsX do
        for iz = 0, stepsZ do
            local localX = -size.X/2 + (ix/stepsX) * size.X
            local localZ = -size.Z/2 + (iz/stepsZ) * size.Z
            table.insert(positions, cf * Vector3.new(localX, size.Y/2, localZ))
        end
    end
    return positions
end

local function isPosEmpty(pos, myPlot, minDist)
    minDist = minDist or 2.5
    local plantsFolder = myPlot:FindFirstChild("Plants")
    if not plantsFolder then return true end
    for _, plantModel in ipairs(plantsFolder:GetChildren()) do
        if plantModel:GetAttribute("PlantId") then
            local root = plantModel.PrimaryPart or plantModel:FindFirstChildWhichIsA("BasePart")
            if root then
                local dist = (Vector2.new(root.Position.X, root.Position.Z) - Vector2.new(pos.X, pos.Z)).Magnitude
                if dist < minDist then return false end
            end
        end
    end
    return true
end

local function findEmptySpots(myPlot, spacing, sortMode)
    local plantAreaParts = {}
    for _, part in ipairs(CollectionService:GetTagged("PlantArea")) do
        if part:IsA("BasePart") and part:IsDescendantOf(myPlot) then
            table.insert(plantAreaParts, part)
        end
    end
    if #plantAreaParts == 0 then
        for _, part in ipairs(CollectionService:GetTagged("GardenTotalArea")) do
            if part:IsA("BasePart") and part:IsDescendantOf(myPlot) then
                table.insert(plantAreaParts, part)
            end
        end
    end

    local allPositions = {}
    for _, part in ipairs(plantAreaParts) do
        for _, pos in ipairs(generateGridFromPart(part, spacing)) do
            table.insert(allPositions, pos)
        end
    end

    local emptySpots = {}
    for _, pos in ipairs(allPositions) do
        if isPosEmpty(pos, myPlot) then table.insert(emptySpots, pos) end
    end

    if sortMode == "Top" then
        table.sort(emptySpots, function(a, b) return a.Y > b.Y end)
    elseif sortMode == "Bottom" then
        table.sort(emptySpots, function(a, b) return a.Y < b.Y end)
    else
        for i = #emptySpots, 2, -1 do
            local j = math.random(1, i)
            emptySpots[i], emptySpots[j] = emptySpots[j], emptySpots[i]
        end
    end
    return emptySpots
end

local function startAutoPlant()
    if plantRunning then return end
    plantRunning = true
    Notify:Fire("Auto Plant enabled")
    task.spawn(function()
        while plantRunning do
            pcall(function()
                local seedName, toolInstance = equipSeed(Config.PreferSeed, Config.SkipMutatedSeeds)
                if not seedName then return end

                local myPlot = getMyGarden()
                if not myPlot then unequipTool() return end

                local spots = findEmptySpots(myPlot, Config.GridSpacing, Config.PlantOrder)
                if #spots == 0 then unequipTool() return end

                for _, pos in ipairs(spots) do
                    if not plantRunning then break end
                    local curSn = getEquippedSeed()
                    if not curSn then
                        seedName, toolInstance = equipSeed(Config.PreferSeed, Config.SkipMutatedSeeds)
                        if not seedName then break end
                    end
                    pcall(function()
                        Networking.Plant.PlantSeed:Fire(pos, seedName, toolInstance)
                    end)
                    task.wait(0.3)
                end

                unequipTool()
            end)
            task.wait(Config.PlantInterval)
        end
    end)
end

local function stopAutoPlant()
    plantRunning = false
    Notify:Fire("Auto Plant disabled")
end

---------------------------------------------------------------
-- AUTO SELL (sell all fruits in backpack to nearest sell point)
---------------------------------------------------------------
local sellRunning = false

local function startAutoSell()
    if sellRunning then return end
    sellRunning = true
    Notify:Fire("Auto Sell enabled")
    task.spawn(function()
        while sellRunning do
            pcall(function()
                local bp = player:FindFirstChild("Backpack")
                if not bp then return end
                for _, tool in ipairs(bp:GetChildren()) do
                    if not sellRunning then break end
                    if tool:IsA("Tool") and (tool:GetAttribute("FruitName") or tool:GetAttribute("ItemType") == "HarvestedFruit") then
                        pcall(function()
                            Networking.NPCS.SellItem:Fire(tool.Name)
                        end)
                        task.wait(0.1)
                    end
                end
            end)
            task.wait(Config.HarvestInterval > 0 and 5 or 5) -- sell sweep interval
        end
    end)
end

local function stopAutoSell()
    sellRunning = false
    Notify:Fire("Auto Sell disabled")
end

---------------------------------------------------------------
-- RESTOCK SNIPER (buy seeds the instant they're in stock)
---------------------------------------------------------------
local restockRunning = false

local function getStock(category, itemName)
    local ok, val = pcall(function()
        return ReplicatedStorage:WaitForChild("StockValues", 5)
            :WaitForChild(category, 5):WaitForChild("Items", 5)
            :FindFirstChild(itemName)
    end)
    if not ok or not val then return 0 end
    return val.Value or 0
end

local function startRestockSniper()
    if restockRunning then return end
    restockRunning = true
    Notify:Fire("Restock Sniper enabled")
    task.spawn(function()
        while restockRunning do
            pcall(function()
                local blacklist = {}
                for _, n in ipairs(Config.RestockBlacklist) do blacklist[n] = true end

                for _, seedName in ipairs(Config.RestockTargets) do
                    if not restockRunning then break end
                    if blacklist[seedName] then continue end

                    local stock = getStock("SeedShop", seedName)
                    if stock <= 0 then continue end

                    for i = 1, stock do
                        if not restockRunning then break end
                        local prevStock = getStock("SeedShop", seedName)
                        pcall(function() Networking.SeedShop.PurchaseSeed:Fire(seedName) end)
                        task.wait(0.15)
                        if getStock("SeedShop", seedName) >= prevStock then break end
                    end
                end
            end)
            task.wait(Config.RestockInterval)
        end
    end)
end

local function stopRestockSniper()
    restockRunning = false
    Notify:Fire("Restock Sniper disabled")
end

---------------------------------------------------------------
-- GEAR BUYER
---------------------------------------------------------------
local gearRunning = false

local function startGearBuyer()
    if gearRunning then return end
    gearRunning = true
    Notify:Fire("Gear Buyer enabled")
    task.spawn(function()
        while gearRunning do
            pcall(function()
                for _, gearName in ipairs(Config.GearTargets) do
                    if not gearRunning then break end
                    local stock = getStock("GearShop", gearName)
                    if stock <= 0 then continue end

                    for i = 1, stock do
                        if not gearRunning then break end
                        local prevStock = getStock("GearShop", gearName)
                        pcall(function() Networking.GearShop.PurchaseGear:Fire(gearName) end)
                        task.wait(0.15)
                        if getStock("GearShop", gearName) >= prevStock then break end
                    end
                end
            end)
            task.wait(Config.GearInterval)
        end
    end)
end

local function stopGearBuyer()
    gearRunning = false
    Notify:Fire("Gear Buyer disabled")
end

---------------------------------------------------------------
-- MUTATION TRACKER (alerts on rare mutations)
---------------------------------------------------------------
local mutationRunning = false
local mutationConns = {}

local function onMutation(source, plantId, mutation)
    if not mutation or mutation == "" then return end
    local isAlert = false
    for _, name in ipairs(Config.MutationAlerts) do
        if name == mutation then isAlert = true break end
    end
    if isAlert then
        local mult = Config.MutationMultipliers[mutation] or 1
        local msg = string.format("[%s] mutation: %s (x%d value)", source, mutation, mult)
        print("[Hub] 🧬 " .. msg)
        Config.Notify and nil
        Notify:Fire("🧬 Mutation: " .. mutation .. " (x" .. mult .. ")")
    end
end

local function startMutationTracker()
    if mutationRunning then return end
    mutationRunning = true
    Notify:Fire("Mutation Tracker enabled")

    local function connect(remote, fn)
        local ok, conn = pcall(function() return remote.OnClientEvent:Connect(fn) end)
        if ok and conn then table.insert(mutationConns, conn) end
    end

    pcall(function()
        connect(Networking.Garden.PlantMutationUpdated, function(plantId, mutation)
            onMutation("plant", plantId, mutation)
        end)
    end)
    pcall(function()
        connect(Networking.Garden.FruitMutationUpdated, function(plantId, fruitId, mutation)
            onMutation("fruit", plantId, mutation)
        end)
    end)
end

local function stopMutationTracker()
    mutationRunning = false
    for _, c in ipairs(mutationConns) do pcall(function() c:Disconnect() end) end
    mutationConns = {}
    Notify:Fire("Mutation Tracker disabled")
end

---------------------------------------------------------------
-- WEATHER BOT (notifies on rare weather events)
---------------------------------------------------------------
local weatherRunning = false
local weatherConns = {}

local function startWeatherBot()
    if weatherRunning then return end
    weatherRunning = true
    Notify:Fire("Weather Bot enabled")

    local events = {
        "BloodmoonBeam","RainbowStart","RainbowEnd","GoldMoonStrike",
        "RainbowMoonStrike","BlizzardStart","BlizzardEnd","ShootingStar","ChainPull",
    }
    for _, name in ipairs(events) do
        pcall(function()
            local remote = Networking.WeatherEffects[name]
            local conn = remote.OnClientEvent:Connect(function(...)
                print("[Hub] 🌧 Weather event:", name)
                Notify:Fire("🌧 Weather: " .. name)
            end)
            table.insert(weatherConns, conn)
        end)
    end
end

local function stopWeatherBot()
    weatherRunning = false
    for _, c in ipairs(weatherConns) do pcall(function() c:Disconnect() end) end
    weatherConns = {}
    Notify:Fire("Weather Bot disabled")
end

---------------------------------------------------------------
-- SEED PACK CLAIMER
---------------------------------------------------------------
local seedPackRunning = false
local seedPackClaimed = {}

local function claimSeedPack(part)
    if not part or not part.Parent or seedPackClaimed[part] then return end
    local root = getHRP()
    if not root then return end

    local origCFrame = root.CFrame
    pcall(function() root.CFrame = part.CFrame * CFrame.new(0, 3, 0) end)
    task.wait(0.3)

    local prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
    local claimed = false
    if prompt then
        pcall(function()
            prompt.HoldDuration = 0
            prompt:InputHoldBegin()
            task.wait(0.1)
            prompt:InputHoldEnd()
            claimed = true
        end)
    end
    if not claimed then
        pcall(function() Networking.SeedPack.ClickPack:Fire(part) claimed = true end)
    end

    seedPackClaimed[part] = true
    if part:GetAttribute("RainbowSeed") then
        Notify:Fire("🌈 Rainbow Seed Pack claimed!")
    elseif part:GetAttribute("GoldSeed") then
        Notify:Fire("🥇 Gold Seed Pack claimed!")
    end

    task.wait(0.1)
    pcall(function() root.CFrame = origCFrame end)

    task.spawn(function()
        while part and part.Parent do task.wait(1) end
        seedPackClaimed[part] = nil
    end)
end

local function startSeedPackClaimer()
    if seedPackRunning then return end
    seedPackRunning = true
    Notify:Fire("Seed Pack Claimer enabled")
    task.spawn(function()
        while seedPackRunning do
            pcall(function()
                local folder = workspace:FindFirstChild("Map")
                    and workspace.Map:FindFirstChild("SeedPackSpawnServerLocations")
                if not folder then return end

                local spawns = {}
                for _, part in ipairs(folder:GetChildren()) do
                    if part:IsA("BasePart") and not seedPackClaimed[part] then
                        local priority = part:GetAttribute("RainbowSeed") and 3
                            or (part:GetAttribute("GoldSeed") and 2 or 1)
                        table.insert(spawns, { part = part, priority = priority })
                    end
                end
                table.sort(spawns, function(a, b) return a.priority > b.priority end)
                for _, s in ipairs(spawns) do
                    if not seedPackRunning then break end
                    claimSeedPack(s.part)
                end
            end)
            task.wait(Config.SeedPackInterval)
        end
    end)
end

local function stopSeedPackClaimer()
    seedPackRunning = false
    Notify:Fire("Seed Pack Claimer disabled")
end

---------------------------------------------------------------
-- WILD PET CATCH
---------------------------------------------------------------
local petCatchRunning = false
local petCatchTamed = {}
local RARITY_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Legendary = 4, Mythic = 5, Super = 6 }

local function getRefPart(uuid)
    local refFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("WildPetRef")
    return refFolder and refFolder:FindFirstChild("WildPet_" .. uuid)
end

local function catchWildPet(model, uuid, petName)
    if not model or not model.Parent or petCatchTamed[model] then return end
    local refPart = uuid and getRefPart(uuid)
    if refPart then
        local rarity = refPart:GetAttribute("Rarity") or "Common"
        local owned = refPart:GetAttribute("OwnerUserId") or 0
        if owned ~= 0 then return end
        if (RARITY_ORDER[rarity] or 0) < (RARITY_ORDER[Config.PetCatchMinRarity] or 0) then return end
    end

    local root = getHRP()
    local petPart = model:FindFirstChild("RootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not root or not petPart then return end

    local orig = root.CFrame
    pcall(function() root.CFrame = petPart.CFrame * CFrame.new(0, 5, 0) end)
    task.wait(0.8)

    local nearestPrompt, nearestDist = nil, math.huge
    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled and desc.Parent:IsA("BasePart") then
            local dist = (desc.Parent.Position - root.Position).Magnitude
            if dist < nearestDist and dist <= desc.MaxActivationDistance then
                nearestDist, nearestPrompt = dist, desc
            end
        end
    end

    local caught = false
    if nearestPrompt then
        pcall(function()
            nearestPrompt.HoldDuration = 0
            nearestPrompt:InputHoldBegin()
            task.wait(0.2)
            nearestPrompt:InputHoldEnd()
            caught = true
        end)
    end
    if not caught then
        pcall(function() Networking.Pets.WildPetTame:Fire(model) caught = true end)
    end

    task.wait(1)
    if Config.PetCatchAutoReturn then
        pcall(function() root.CFrame = orig end)
    end

    petCatchTamed[model] = true
    Notify:Fire("🐾 Pet caught: " .. (petName or "Unknown"))

    task.spawn(function()
        while model and model.Parent do task.wait(1) end
        petCatchTamed[model] = nil
    end)
end

local function startAutoPetCatch()
    if petCatchRunning then return end
    petCatchRunning = true
    Notify:Fire("Wild Pet Catch enabled")
    task.spawn(function()
        while petCatchRunning do
            pcall(function()
                local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("WildPetSpawns")
                if not folder then return end
                for _, model in ipairs(folder:GetChildren()) do
                    if not petCatchRunning then break end
                    if model:IsA("Model") and not petCatchTamed[model] then
                        local petName = model:GetAttribute("PetName") or model.Name
                        local uuid = model.Name:match("WildPet_%w+_WildPet_(.+)")
                        catchWildPet(model, uuid, petName)
                        task.wait(0.5)
                    end
                end
            end)
            task.wait(Config.PetCatchInterval)
        end
    end)
end

local function stopAutoPetCatch()
    petCatchRunning = false
    Notify:Fire("Wild Pet Catch disabled")
end

---------------------------------------------------------------
-- STEAL BOT (collects unlocked crops on other plots — a real
-- in-game night mechanic, mirrors what a player can do manually)
---------------------------------------------------------------
local stealRunning = false
local stealAttemptsTonight = 0

local function isGardenUnlocked(garden)
    local ownerUserId = tonumber(garden:GetAttribute("OwnerUserId") or garden:GetAttribute("Owner"))
    if not ownerUserId then return true end
    local owner = Players:GetPlayerByUserId(ownerUserId)
    local ownerHRP = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
    if not ownerHRP then return true end
    for _, part in ipairs(garden:GetDescendants()) do
        if part:IsA("BasePart") then
            local rel = part.CFrame:PointToObjectSpace(ownerHRP.Position)
            local half = part.Size / 2
            if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y + 10 and math.abs(rel.Z) <= half.Z then
                return false
            end
        end
    end
    return true
end

local function findStealablePrompts(myPlotId)
    local results = {}
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return results end
    for _, garden in ipairs(gardens:GetChildren()) do
        local plotNum = tonumber(garden.Name:match("Plot(%d+)"))
        if plotNum and plotNum ~= myPlotId and isGardenUnlocked(garden) then
            local plantsFolder = garden:FindFirstChild("Plants")
            if plantsFolder then
                for _, plantModel in ipairs(plantsFolder:GetChildren()) do
                    local fruitsFolder = plantModel:FindFirstChild("Fruits")
                    if fruitsFolder then
                        for _, fruitModel in ipairs(fruitsFolder:GetChildren()) do
                            local prompt = fruitModel:FindFirstChild("StealPrompt", true)
                            if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled
                                and not prompt:GetAttribute("Collected") and prompt.HoldDuration == 0 then
                                local plantId = fruitModel:GetAttribute("PlantId")
                                if plantId then
                                    table.insert(results, { prompt = prompt, plantId = plantId, gardenName = garden.Name })
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return results
end

local function attemptSteal(entry)
    local prompt = entry.prompt
    if not prompt or not prompt.Parent or not prompt.Enabled then return false end

    local hrp = getHRP()
    if not hrp then return false end
    local saved = hrp.CFrame

    local fruitPart = prompt.Parent
    if not fruitPart:IsA("BasePart") then
        fruitPart = prompt.Parent:FindFirstChildWhichIsA("BasePart")
    end
    if not fruitPart then return false end

    pcall(function() hrp.CFrame = fruitPart.CFrame + Vector3.new(0, 3, 0) end)
    task.wait(0.8)

    local triggered = false
    pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(0.09, prompt.HoldDuration + 0.1))
        if prompt.Parent then prompt:InputHoldEnd() end
        triggered = true
    end)
    if not triggered then pcall(function() hrp.CFrame = saved end) return false end

    task.wait(0.5)
    local carrying = player:GetAttribute("CarryingStolenFruit")

    local garden = getMyGarden()
    local spawnPoint = garden and (garden:FindFirstChild("SpawnPoint") or garden:FindFirstChildWhichIsA("BasePart"))
    if spawnPoint then
        pcall(function() hrp.CFrame = spawnPoint.CFrame + Vector3.new(0, 3, 0) end)
    else
        pcall(function() hrp.CFrame = saved end)
    end

    return carrying and true or false
end

local function startStealBot()
    if stealRunning then return end
    stealRunning = true
    Notify:Fire("Steal Bot enabled (waits for night)")
    task.spawn(function()
        local wasNight = false
        while stealRunning do
            local night = isNight()
            if night and not wasNight then stealAttemptsTonight = 0 end
            wasNight = night

            if night then
                pcall(function()
                    if player:GetAttribute("CarryingStolenFruit") then
                        local garden = getMyGarden()
                        local hrp = getHRP()
                        local spawnPoint = garden and (garden:FindFirstChild("SpawnPoint") or garden:FindFirstChildWhichIsA("BasePart"))
                        if hrp and spawnPoint then hrp.CFrame = spawnPoint.CFrame + Vector3.new(0, 3, 0) end
                        return
                    end
                    if stealAttemptsTonight >= Config.StealMaxPerNight then return end

                    local myPlotId = player:GetAttribute("PlotId")
                    if not myPlotId then return end

                    local entries = findStealablePrompts(myPlotId)
                    table.sort(entries, function(a, b)
                        return (BaseValues[a.plantId] or 0) > (BaseValues[b.plantId] or 0)
                    end)

                    for _, entry in ipairs(entries) do
                        if stealAttemptsTonight >= Config.StealMaxPerNight then break end
                        local val = BaseValues[entry.plantId] or 0
                        if Config.StealMinValue > 0 and val < Config.StealMinValue then continue end
                        stealAttemptsTonight += 1
                        if attemptSteal(entry) then break end
                        task.wait(0.5)
                    end
                end)
            end
            task.wait(Config.StealInterval)
        end
    end)
end

local function stopStealBot()
    stealRunning = false
    Notify:Fire("Steal Bot disabled")
end

---------------------------------------------------------------
-- AUTO BUY PET (hatch eggs, keep/sell by rarity)
---------------------------------------------------------------
local petRunning = false
local PetData = nil
pcall(function()
    PetData = require(ReplicatedStorage:WaitForChild("SharedData"):WaitForChild("PetData"))
end)

local function getSpeciesRarity(petName)
    return (PetData and PetData[petName] and PetData[petName].Rarity) or "Common"
end

local function findEggTools()
    local bp = player:FindFirstChild("Backpack")
    if not bp then return {} end
    local eggs = {}
    for _, tool in ipairs(bp:GetChildren()) do
        if tool:IsA("Tool") then
            local eggName = tool:GetAttribute("Egg")
            if eggName and eggName ~= "" then table.insert(eggs, { tool = tool, eggName = eggName }) end
        end
    end
    return eggs
end

local function hatchEgg(eggName)
    local result, done = nil, false
    local conn
    pcall(function()
        conn = Networking.Egg.ReplicateOpenEgg.OnClientEvent:Connect(function(plr, eName, petName, size)
            if plr == player and eName == eggName then
                result = { petName = petName, size = size }
                done = true
                if conn then conn:Disconnect() end
            end
        end)
    end)

    local ok = pcall(function() Networking.Egg.OpenEgg:Fire(eggName) end)
    if not ok then if conn then conn:Disconnect() end return nil end

    local t = 0
    while not done and t < 5 do task.wait(0.1) t += 0.1 end
    if conn then pcall(function() conn:Disconnect() end) end
    if not result then return nil end

    pcall(function() Networking.Egg.ConfirmEgg:Fire(eggName, result.petName, result.size or "") end)
    return result
end

local function findAndSellPet(petName)
    task.wait(1)
    local bp = player:FindFirstChild("Backpack")
    local char = player.Character
    local function scan(container)
        if not container then return nil end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute("Pet") == petName then
                local petId = tool:GetAttribute("PetId")
                if petId then return { tool = tool, petId = petId } end
            end
        end
        return nil
    end
    local found = scan(bp) or scan(char)
    if not found then return false end
    if char then pcall(function() found.tool.Parent = char end) task.wait(0.3) end
    local ok, result = pcall(function() return Networking.NPCS.SellPet:InvokeServer(found.petId) end)
    return ok and result and result.Success
end

local function startAutoBuyPet()
    if petRunning then return end
    petRunning = true
    Notify:Fire("Auto Hatch enabled")
    task.spawn(function()
        while petRunning do
            pcall(function()
                local eggs = findEggTools()
                if #eggs == 0 then return end

                local result = hatchEgg(eggs[1].eggName)
                if not result then return end

                local rarity = getSpeciesRarity(result.petName)
                local passes = (RARITY_ORDER[rarity] or 1) >= (RARITY_ORDER[Config.PetMinRarity] or 1)

                if passes then
                    Notify:Fire("Kept pet: " .. result.petName .. " (" .. rarity .. ")")
                elseif Config.PetAutoSellUnwanted then
                    if findAndSellPet(result.petName) then
                        Notify:Fire("Sold pet: " .. result.petName)
                    end
                end
            end)
            task.wait(Config.PetHatchInterval)
        end
    end)
end

local function stopAutoBuyPet()
    petRunning = false
    Notify:Fire("Auto Hatch disabled")
end

---------------------------------------------------------------
-- INVENTORY OPTIMIZER (favorite high value, promote, drop junk)
---------------------------------------------------------------
local invRunning = false

local function startInventoryOptimizer()
    if invRunning then return end
    invRunning = true
    Notify:Fire("Inventory Optimizer enabled")
    task.spawn(function()
        while invRunning do
            pcall(function()
                local bp = player:FindFirstChild("Backpack")
                if not bp then return end
                for _, tool in ipairs(bp:GetChildren()) do
                    if not tool:IsA("Tool") then continue end
                    local itemType  = tool:GetAttribute("ItemType") or ""
                    local fruitName = tool:GetAttribute("FruitName") or ""
                    local mutation  = tool:GetAttribute("Mutation") or ""
                    local size      = tool:GetAttribute("Size") or 1

                    local seedName = fruitName ~= "" and fruitName or tool.Name
                    local base = BaseValues[seedName] or 0
                    local mult = Config.MutationMultipliers[mutation] or 1
                    local estValue = base * (size ^ 2.65) * mult

                    if Config.AutoFavorite and estValue >= Config.FavoriteThreshold then
                        pcall(function() Networking.Backpack.SetFruitFavorite:Fire(tool.Name, true) end)
                    end

                    if Config.AutoPromote and (itemType == "HarvestedFruit" or itemType == "Fruit" or fruitName ~= "") then
                        pcall(function() Networking.Backpack.PromoteFruit:Fire(tool.Name) end)
                    end

                    if Config.DropThreshold > 0 and estValue < Config.DropThreshold
                        and itemType ~= "SeedTool" and itemType ~= "WateringCan" and itemType ~= "Sprinkler"
                        and not tool.Name:match("Seed") then
                        pcall(function() Networking.DroppedItem.RequestDrop:Fire(tool.Name, 1) end)
                    end
                end
            end)
            task.wait(Config.InventoryInterval)
        end
    end)
end

local function stopInventoryOptimizer()
    invRunning = false
    Notify:Fire("Inventory Optimizer disabled")
end

---------------------------------------------------------------
-- AUTO CENTER PLOT (one-shot teleport to plot center)
---------------------------------------------------------------
local function startAutoCenterPlot()
    task.spawn(function()
        task.wait(1)
        pcall(function()
            local hrp = getHRP()
            local garden = getMyGarden()
            if hrp and garden then
                local spawnPoint = garden:FindFirstChild("SpawnPoint") or garden:FindFirstChildWhichIsA("BasePart")
                if spawnPoint then
                    hrp.CFrame = spawnPoint.CFrame + Vector3.new(0, 3, 0)
                    Notify:Fire("Centered on plot")
                end
            end
        end)
    end)
end

---------------------------------------------------------------
-- AUTO JOIN SERVER
---------------------------------------------------------------
local joinRunning = false

local function startAutoJoinServer()
    if joinRunning then return end
    if Config.TargetJobId == "" then
        Notify:Fire("Set Target JobId first!")
        return
    end
    joinRunning = true

    if game.JobId == Config.TargetJobId then
        Notify:Fire("Already on target server")
        return
    end

    task.spawn(function()
        local retries = 0
        while joinRunning and retries < 10 do
            retries += 1
            local ok = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, Config.TargetJobId, player)
            end)
            if ok then task.wait(10) end
            task.wait(Config.RejoinDelay)
        end
    end)

    if Config.AutoRejoin then
        pcall(function()
            TeleportService.TeleportInitFailed:Connect(function()
                if not joinRunning then return end
                task.wait(Config.RejoinDelay)
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, Config.TargetJobId, player)
                end)
            end)
        end)
    end
end

local function stopAutoJoinServer()
    joinRunning = false
end

---------------------------------------------------------------
-- ANTI-AFK (default on)
---------------------------------------------------------------
player.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

---------------------------------------------------------------
-- UI
---------------------------------------------------------------
local Window = Rayfield:CreateWindow({
   Name = "Nexera - GAG 2",
   Icon = 0,
   LoadingTitle = "Nexera Scripts",
   LoadingSubtitle = "by Codepikk",
   ShowText = "NexERA",
   Theme = "Default",
   ToggleUIKeybind = "K",
   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false,
   ConfigurationSaving = {
      Enabled = true,
      FolderName = nil,
      FileName = "Big Hub"
   },
   Discord = { Enabled = false, Invite = "noinvitelink", RememberJoins = true },
   KeySystem = false,
   KeySettings = {
      Title = "Untitled", Subtitle = "Key System",
      Note = "No method of obtaining the key is provided",
      FileName = "Key", SaveKey = true, GrabKeyFromSite = false, Key = {"Hello"}
   }
})

---------------------------------------------------------------
-- TAB: FARM
---------------------------------------------------------------
local FarmTab = Window:CreateTab("Farm", "sprout")

FarmTab:CreateToggle({
   Name = "Auto Harvest", CurrentValue = false, Flag = "AutoHarvest",
   Callback = function(v) if v then startAutoHarvest() else stopAutoHarvest() end end,
})
FarmTab:CreateSlider({Name="Harvest Interval", Range={0.2,10}, Increment=0.1, Suffix="s",
   CurrentValue=Config.HarvestInterval, Flag="HarvestInterval",
   Callback=function(v) Config.HarvestInterval = v end})

FarmTab:CreateToggle({
   Name = "Auto Water", CurrentValue = false, Flag = "AutoWater",
   Callback = function(v) if v then startAutoWater() else stopAutoWater() end end,
})
FarmTab:CreateSlider({Name="Water Interval", Range={1,15}, Increment=1, Suffix="s",
   CurrentValue=Config.WaterInterval, Flag="WaterInterval",
   Callback=function(v) Config.WaterInterval = v end})
FarmTab:CreateToggle({Name="Water Fully Grown Too", CurrentValue=false, Flag="WaterFullyGrown",
   Callback=function(v) Config.WaterFullyGrown = v end})
FarmTab:CreateInput({Name="Required Can (blank = any)", PlaceholderText="e.g. Super Watering Can",
   RemoveTextAfterFocusLost=false, Flag="RequiredCan",
   Callback=function(v) Config.RequiredCan = v end})

FarmTab:CreateToggle({
   Name = "Auto Plant", CurrentValue = false, Flag = "AutoPlant",
   Callback = function(v) if v then startAutoPlant() else stopAutoPlant() end end,
})
FarmTab:CreateDropdown({Name="Plant Order", Options={"Top","Bottom","Random"}, CurrentOption=Config.PlantOrder,
   Flag="PlantOrder", Callback=function(v) Config.PlantOrder = v end})
FarmTab:CreateSlider({Name="Grid Spacing", Range={2,8}, Increment=0.5, Suffix=" studs",
   CurrentValue=Config.GridSpacing, Flag="GridSpacing",
   Callback=function(v) Config.GridSpacing = v end})
FarmTab:CreateInput({Name="Prefer Seed (blank = any)", PlaceholderText="e.g. Carrot",
   RemoveTextAfterFocusLost=false, Flag="PreferSeed",
   Callback=function(v) Config.PreferSeed = (v ~= "" and v or nil) end})
FarmTab:CreateToggle({Name="Skip Mutated Seeds", CurrentValue=true, Flag="SkipMutatedSeeds",
   Callback=function(v) Config.SkipMutatedSeeds = v end})

FarmTab:CreateToggle({Name="Auto Center Plot (on load)", CurrentValue=false, Flag="AutoCenterPlot",
   Callback=function(v) if v then startAutoCenterPlot() end end})

---------------------------------------------------------------
-- TAB: ECONOMY
---------------------------------------------------------------
local EconTab = Window:CreateTab("Economy", "dollar-sign")

EconTab:CreateToggle({
   Name = "Auto Sell", CurrentValue = false, Flag = "AutoSell",
   Callback = function(v) if v then startAutoSell() else stopAutoSell() end end,
})

EconTab:CreateSection("Restock Sniper")
EconTab:CreateToggle({Name="Enabled", CurrentValue=false, Flag="RestockSniper",
   Callback=function(v) if v then startRestockSniper() else stopRestockSniper() end end})
EconTab:CreateSlider({Name="Poll Interval", Range={0.5,5}, Increment=0.5, Suffix="s",
   CurrentValue=Config.RestockInterval, Flag="RestockInterval",
   Callback=function(v) Config.RestockInterval = v end})
EconTab:CreateDropdown({Name="Buy Targets", Options=AllSeeds, CurrentOption=Config.RestockTargets,
   MultipleOptions=true, Flag="RestockTargets", Callback=function(v) Config.RestockTargets = v end})
EconTab:CreateDropdown({Name="Blacklist", Options=AllSeeds, CurrentOption=Config.RestockBlacklist,
   MultipleOptions=true, Flag="RestockBlacklist", Callback=function(v) Config.RestockBlacklist = v end})

EconTab:CreateSection("Gear Buyer")
EconTab:CreateToggle({Name="Enabled", CurrentValue=false, Flag="GearBuyer",
   Callback=function(v) if v then startGearBuyer() else stopGearBuyer() end end})
EconTab:CreateDropdown({Name="Buy Gears", Options=AllGears, CurrentOption=Config.GearTargets,
   MultipleOptions=true, Flag="GearTargets", Callback=function(v) Config.GearTargets = v end})

EconTab:CreateSection("Inventory")
EconTab:CreateToggle({Name="Optimizer", CurrentValue=false, Flag="InventoryOptimizer",
   Callback=function(v) if v then startInventoryOptimizer() else stopInventoryOptimizer() end end})
EconTab:CreateSlider({Name="Favorite Threshold", Range={50,5000}, Increment=50, Suffix=" ¢",
   CurrentValue=Config.FavoriteThreshold, Flag="FavoriteThreshold",
   Callback=function(v) Config.FavoriteThreshold = v end})
EconTab:CreateSlider({Name="Drop Threshold", Range={0,50}, Increment=1, Suffix=" ¢",
   CurrentValue=Config.DropThreshold, Flag="DropThreshold",
   Callback=function(v) Config.DropThreshold = v end})

---------------------------------------------------------------
-- TAB: PETS
---------------------------------------------------------------
local PetTab = Window:CreateTab("Pets", "paw-print")

PetTab:CreateSection("Auto Hatch")
PetTab:CreateToggle({Name="Enabled", CurrentValue=false, Flag="AutoBuyPet",
   Callback=function(v) if v then startAutoBuyPet() else stopAutoBuyPet() end end})
PetTab:CreateDropdown({Name="Min Rarity Kept", Options={"Common","Uncommon","Rare","Legendary","Mythic","Super"},
   CurrentOption={Config.PetMinRarity}, MultipleOptions=false, Flag="PetMinRarity",
   Callback=function(opt) Config.PetMinRarity = type(opt)=="table" and opt[1] or opt end})
PetTab:CreateToggle({Name="Sell Unwanted", CurrentValue=false, Flag="PetAutoSell",
   Callback=function(v) Config.PetAutoSellUnwanted = v end})

PetTab:CreateSection("Wild Pet Catch")
PetTab:CreateToggle({Name="Enabled", CurrentValue=false, Flag="AutoPetCatch",
   Callback=function(v) if v then startAutoPetCatch() else stopAutoPetCatch() end end})
PetTab:CreateDropdown({Name="Min Rarity", Options={"Common","Uncommon","Rare","Legendary","Mythic","Super"},
   CurrentOption={Config.PetCatchMinRarity}, MultipleOptions=false, Flag="PetCatchMinRarity",
   Callback=function(opt) Config.PetCatchMinRarity = type(opt)=="table" and opt[1] or opt end})
PetTab:CreateToggle({Name="Return After Catch", CurrentValue=true, Flag="PetCatchAutoReturn",
   Callback=function(v) Config.PetCatchAutoReturn = v end})

---------------------------------------------------------------
-- TAB: EVENTS
---------------------------------------------------------------
local EventTab = Window:CreateTab("Events", "zap")

EventTab:CreateToggle({Name="Mutation Tracker", CurrentValue=false, Flag="MutationTracker",
   Callback=function(v) if v then startMutationTracker() else stopMutationTracker() end end})
EventTab:CreateToggle({Name="Weather Bot", CurrentValue=false, Flag="WeatherBot",
   Callback=function(v) if v then startWeatherBot() else stopWeatherBot() end end})
EventTab:CreateToggle({Name="Seed Pack Claimer", CurrentValue=false, Flag="SeedPackClaimer",
   Callback=function(v) if v then startSeedPackClaimer() else stopSeedPackClaimer() end end})

EventTab:CreateSection("Steal Bot (night-time, unlocked plots only)")
EventTab:CreateToggle({Name="Enabled", CurrentValue=false, Flag="StealBot",
   Callback=function(v) if v then startStealBot() else stopStealBot() end end})
EventTab:CreateSlider({Name="Min Value", Range={100,10000}, Increment=100, Suffix=" ¢",
   CurrentValue=Config.StealMinValue, Flag="StealMinValue",
   Callback=function(v) Config.StealMinValue = v end})
EventTab:CreateSlider({Name="Max Attempts/Night", Range={5,100}, Increment=5,
   CurrentValue=Config.StealMaxPerNight, Flag="StealMaxPerNight",
   Callback=function(v) Config.StealMaxPerNight = v end})

---------------------------------------------------------------
-- TAB: SERVER
---------------------------------------------------------------
local ServerTab = Window:CreateTab("Server", "globe")

ServerTab:CreateParagraph({Title="Your JobId", Content = game.JobId ~= "" and game.JobId or "N/A (studio)"})
ServerTab:CreateButton({Name="Copy JobId", Callback=function()
   if setclipboard then setclipboard(game.JobId) end
   Rayfield:Notify({Title="Copied!", Content="JobId copied to clipboard", Duration=3})
end})

ServerTab:CreateInput({Name="Target JobId", PlaceholderText="Paste server JobId here...",
   RemoveTextAfterFocusLost=false, Flag="TargetJobId",
   Callback=function(v) Config.TargetJobId = v end})
ServerTab:CreateToggle({Name="Auto Join Server", CurrentValue=false, Flag="AutoJoinServer",
   Callback=function(v) if v then startAutoJoinServer() else stopAutoJoinServer() end end})
ServerTab:CreateToggle({Name="Auto Rejoin on Disconnect", CurrentValue=true, Flag="ServerAutoRejoin",
   Callback=function(v) Config.AutoRejoin = v end})

---------------------------------------------------------------
-- TAB: STATUS
---------------------------------------------------------------
local StatusTab = Window:CreateTab("Status", "activity")

local toggleStates = {
   AutoHarvest=false, AutoWater=false, AutoPlant=false, AutoSell=false,
   RestockSniper=false, GearBuyer=false, InventoryOptimizer=false,
   AutoBuyPet=false, AutoPetCatch=false, MutationTracker=false,
   WeatherBot=false, SeedPackClaimer=false, StealBot=false,
}

local StatsParagraph = StatusTab:CreateParagraph({Title="Session", Content="Sheckles: " .. formatNumber(getSheckles())})

task.spawn(function()
   while true do
      pcall(function()
         StatsParagraph:Set({Title="Session", Content="Sheckles: " .. formatNumber(getSheckles())})
      end)
      task.wait(3)
   end
end)

print("GAG Hub (clean edition) loaded!")
Notify:Fire("GAG Hub loaded — toggle in UI")
