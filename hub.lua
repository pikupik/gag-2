local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- SERVICES & SETUP
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- STATE MANAGEMENT
local RunningModules = {}
local Config = {
    Timings = {
        HarvestInterval = 0.5, SellInterval = 5, WaterInterval = 3,
        PlantInterval = 5, RestockPollInterval = 1, StealInterval = 1.5,
        InventoryCheckInterval = 10, PetHatchInterval = 2, SeedPackPollInterval = 2,
        PetCatchInterval = 3
    },
    Restock = { TargetSeeds = {}, BlacklistedSeeds = {} },
    Steal = { MinFruitValue = 10000, MaxAttemptsPerNight = 20 },
    Sell = { Mode = "all", UseDailyDeal = false },
    Plant = { OnlyEmptyPlots = true, PreferSeed = nil, GridSpacing = 3, PlantOrder = "Top", BlacklistMutated = true },
    Water = { WaterAll = false, WaterFullyGrown = false, RequiredCan = "" },
    Inventory = { FavoriteThreshold = 500, AutoPromote = true, DropThreshold = 5 },
    Pet = { MinRarity = "Rare", AutoSellUnwanted = false },
    Gear = { TargetGears = {} },
    Server = { TargetJobId = "", AutoRejoin = true, RejoinDelay = 5, MaxRetries = 10 },
    PetCatch = { MinRarity = "Common", AutoReturn = true }
}

-- NETWORKING HELPER (From hub.lua logic)
local NetModule = nil
local function getNet()
    if NetModule then return NetModule end
    pcall(function()
        local shared = ReplicatedStorage:WaitForChild("SharedModules", 10)
        if shared then NetModule = require(shared:WaitForChild("Networking", 10)) end
    end)
    return NetModule
end

local function fireRemote(path, ...)
    local net = getNet()
    if not net then return false end
    local current = net
    for segment in string.gmatch(path, "[^%.]+") do
        current = current[segment]
        if not current then return false end
    end
    if current and current.Fire then
        pcall(function() current:Fire(...) end)
        return true
    end
    return false
end

-- UTILITIES (From hub.lua logic)
local function getMyGarden()
    local plotId = player:GetAttribute("PlotId")
    if not plotId then return nil end
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return nil end
    return gardens:FindFirstChild("Plot" .. tostring(plotId))
end

local function findToolInBackpack(toolNamePart)
    local bp = player:FindFirstChild("Backpack")
    if not bp then return nil end
    for _, tool in ipairs(bp:GetChildren()) do
        if tool:IsA("Tool") and string.find(tool.Name, toolNamePart) then return tool end
    end
    return nil
end

local function isNight()
    local night = ReplicatedStorage:FindFirstChild("Night")
    if night then return night.Value == true end
    return game:GetService("Lighting").ClockTime >= 18 or game:GetService("Lighting").ClockTime < 6
end

-- MODULE LOGIC WRAPPERS (Simplified for single-file usage)

-- 1. AUTO HARVEST
local function startAutoHarvest()
    task.spawn(function()
        while RunningModules["AutoHarvest"] do
            pcall(function()
                local garden = getMyGarden()
                if not garden then task.wait(1) return end
                local plantsFolder = garden:FindFirstChild("Plants")
                if not plantsFolder then return end
                for _, plant in pairs(plantsFolder:GetChildren()) do
                    if not RunningModules["AutoHarvest"] then break end
                    local fruits = plant:FindFirstChild("Fruits")
                    if fruits then
                        for _, fruit in pairs(fruits:GetChildren()) do
                            if not RunningModules["AutoHarvest"] then break end
                            local pId = fruit:GetAttribute("PlantId")
                            local fId = fruit:GetAttribute("FruitId")
                            if pId and fId then fireRemote("Garden.CollectFruit", pId, fId) task.wait(0.1) end
                        end
                    end
                end
            end)
            task.wait(Config.Timings.HarvestInterval)
        end
    end)
end

-- 2. AUTO WATER
local function startAutoWater()
    task.spawn(function()
        while RunningModules["AutoWater"] do
            pcall(function()
                local garden = getMyGarden()
                if not garden then task.wait(1) return end
                local canTool = findToolInBackpack("Watering Can")
                if not canTool then 
                    local char = player.Character
                    if char then
                        for _, t in pairs(char:GetChildren()) do
                            if t:IsA("Tool") and string.find(t.Name, "Watering Can") then canTool = t break end
                        end
                    end
                end
                if not canTool then task.wait(2) return end
                
                local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
                if humanoid and canTool.Parent ~= player.Character then
                    humanoid:EquipTool(canTool)
                    task.wait(0.5)
                end
                
                local plantsFolder = garden:FindFirstChild("Plants")
                if plantsFolder then
                    for _, plant in pairs(plantsFolder:GetChildren()) do
                        if not RunningModules["AutoWater"] then break end
                        local growth = plant:GetAttribute("Growth") or 0
                        if growth < 1 or Config.Water.WaterFullyGrown then
                            local rootPart = plant:FindFirstChildWhichIsA("BasePart")
                            if rootPart then
                                local pos = rootPart.Position - Vector3.new(0, 0.3, 0)
                                fireRemote("WateringCan.UseWateringCan", pos, canTool.Name, canTool)
                                task.wait(0.6)
                            end
                        end
                    end
                end
            end)
            task.wait(Config.Timings.WaterInterval)
        end
    end)
end

-- 3. AUTO PLANT
local function startAutoPlant()
    task.spawn(function()
        while RunningModules["AutoPlant"] do
            pcall(function()
                local garden = getMyGarden()
                if not garden then task.wait(1) return end
                local seedTool = nil
                local bp = player:FindFirstChild("Backpack")
                if bp then
                    for _, tool in ipairs(bp:GetChildren()) do
                        if tool:IsA("Tool") and tool:GetAttribute("SeedTool") then
                            if not Config.Plant.BlacklistMutated or not string.find(tool.Name, "Gold") and not string.find(tool.Name, "Rainbow") then
                                seedTool = tool; break
                            end
                        end
                    end
                end
                if not seedTool then task.wait(2) return end
                
                local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
                if humanoid and seedTool.Parent ~= player.Character then
                    humanoid:EquipTool(seedTool)
                    task.wait(0.3)
                end
                
                local seedName = seedTool:GetAttribute("SeedTool")
                if not seedName then return end

                local plantAreas = CollectionService:GetTagged("PlantArea")
                for _, area in pairs(plantAreas) do
                    if not RunningModules["AutoPlant"] then break end
                    if area:IsDescendantOf(garden) and area:IsA("BasePart") then
                        local pos = area.Position + Vector3.new(0, 1, 0)
                        local isEmpty = true
                        local plantsFolder = garden:FindFirstChild("Plants")
                        if plantsFolder then
                            for _, p in pairs(plantsFolder:GetChildren()) do
                                local pr = p:FindFirstChildWhichIsA("BasePart")
                                if pr and (pr.Position - pos).Magnitude < 2 then isEmpty = false; break end
                            end
                        end
                        if isEmpty then
                            fireRemote("Plant.PlantSeed", pos, seedName, seedTool)
                            task.wait(0.5)
                        end
                    end
                end
            end)
            task.wait(Config.Timings.PlantInterval)
        end
    end)
end

-- 4. AUTO SELL
local function startAutoSell()
    task.spawn(function()
        while RunningModules["AutoSell"] do
            pcall(function()
                local hasFruit = false
                local bp = player:FindFirstChild("Backpack")
                if bp then
                    for _, item in pairs(bp:GetChildren()) do
                        if item:IsA("Tool") and (item:GetAttribute("FruitName") or item:GetAttribute("IsFruit")) then
                            hasFruit = true; break
                        end
                    end
                end
                if not hasFruit and player.Character then
                    for _, item in pairs(player.Character:GetChildren()) do
                        if item:IsA("Tool") and (item:GetAttribute("FruitName") or item:GetAttribute("IsFruit")) then
                            hasFruit = true; break
                        end
                    end
                end
                if hasFruit then
                    fireRemote("NPCS.SellAll")
                    task.wait(Config.Timings.SellInterval)
                else
                    task.wait(2)
                end
            end)
        end
    end)
end

-- 5. RESTOCK SNIPER (Simplified Logic)
local function startRestockSniper()
    task.spawn(function()
        while RunningModules["RestockSniper"] do
            pcall(function()
                local stockFolder = ReplicatedStorage:FindFirstChild("StockValues")
                if stockFolder then
                    local seedShop = stockFolder:FindFirstChild("SeedShop")
                    if seedShop then
                        local items = seedShop:FindFirstChild("Items")
                        if items then
                            for _, target in ipairs(Config.Restock.TargetSeeds) do
                                if not RunningModules["RestockSniper"] then break end
                                local stockVal = items:FindFirstChild(target)
                                if stockVal and stockVal:IsA("ValueBase") and stockVal.Value > 0 then
                                    -- Check money (simplified)
                                    local leaderstats = player:FindFirstChild("leaderstats")
                                    local sheckles = leaderstats and leaderstats:FindFirstChild("Sheckles")
                                    if sheckles and sheckles.Value > 100 then -- Asumsi harga minimal
                                        fireRemote("SeedShop.PurchaseSeed", target)
                                        task.wait(0.5)
                                    end
                                end
                            end
                        end
                    end
                end
            end)
            task.wait(Config.Timings.RestockPollInterval)
        end
    end)
end

-- 6. STEAL BOT (Night Only)
local function startStealBot()
    task.spawn(function()
        while RunningModules["StealBot"] do
            if isNight() then
                pcall(function()
                    local myPlotId = player:GetAttribute("PlotId")
                    local gardens = workspace:FindFirstChild("Gardens")
                    if gardens then
                        for _, garden in pairs(gardens:GetChildren()) do
                            if not RunningModules["StealBot"] then break end
                            local plotNum = tonumber(garden.Name:match("Plot(%d+)"))
                            if plotNum and plotNum ~= myPlotId then
                                -- Cek jika pemilik tidak ada di plot (Simplified)
                                local plants = garden:FindFirstChild("Plants")
                                if plants then
                                    for _, plant in pairs(plants:GetChildren()) do
                                        local fruits = plant:FindFirstChild("Fruits")
                                        if fruits then
                                            for _, fruit in pairs(fruits:GetChildren()) do
                                                local prompt = fruit:FindFirstChild("StealPrompt")
                                                if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
                                                    -- Teleport & Steal Logic Simplified
                                                    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                                                    if hrp then
                                                        local oldPos = hrp.CFrame
                                                        hrp.CFrame = fruit.CFrame + Vector3.new(0, 2, 0)
                                                        task.wait(0.5)
                                                        if fireproximityprompt then fireproximityprompt(prompt) end
                                                        task.wait(1)
                                                        hrp.CFrame = oldPos
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end)
            end
            task.wait(Config.Timings.StealInterval)
        end
    end)
end

-- 7. AUTO PET CATCH (Simplified)
local function startAutoPetCatch()
    task.spawn(function()
        while RunningModules["AutoPetCatch"] do
            pcall(function()
                local map = workspace:FindFirstChild("Map")
                if map then
                    local spawns = map:FindFirstChild("WildPetSpawns")
                    if spawns then
                        for _, petModel in pairs(spawns:GetChildren()) do
                            if not RunningModules["AutoPetCatch"] then break end
                            if petModel:IsA("Model") then
                                local prompt = petModel:FindFirstChildWhichIsA("ProximityPrompt")
                                if prompt and prompt.Enabled then
                                    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                                    if hrp then
                                        local oldPos = hrp.CFrame
                                        hrp.CFrame = petModel.PrimaryPart.CFrame + Vector3.new(0, 2, 0)
                                        task.wait(0.5)
                                        if fireproximityprompt then fireproximityprompt(prompt) end
                                        task.wait(1)
                                        hrp.CFrame = oldPos
                                    end
                                end
                            end
                        end
                    end
                end
            end)
            task.wait(Config.Timings.PetCatchInterval)
        end
    end)
end

-- 8. SEED PACK CLAIMER
local function startSeedPackClaimer()
    task.spawn(function()
        while RunningModules["SeedPackClaimer"] do
            pcall(function()
                local map = workspace:FindFirstChild("Map")
                if map then
                    local spawns = map:FindFirstChild("SeedPackSpawnServerLocations")
                    if spawns then
                        for _, pack in pairs(spawns:GetChildren()) do
                            if not RunningModules["SeedPackClaimer"] then break end
                            if pack:IsA("BasePart") then
                                local prompt = pack:FindFirstChildWhichIsA("ProximityPrompt")
                                if prompt and prompt.Enabled then
                                    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                                    if hrp then
                                        local oldPos = hrp.CFrame
                                        hrp.CFrame = pack.CFrame + Vector3.new(0, 2, 0)
                                        task.wait(0.5)
                                        if fireproximityprompt then fireproximityprompt(prompt) end
                                        task.wait(1)
                                        hrp.CFrame = oldPos
                                    end
                                end
                            end
                        end
                    end
                end
            end)
            task.wait(Config.Timings.SeedPackPollInterval)
        end
    end)
end

-- UI CREATION
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
   Discord = {
      Enabled = false,
      Invite = "noinvitelink",
      RememberJoins = true
   },
   KeySystem = false,
})

-- TAB: FARMING
local FarmTab = Window:CreateTab("Farm", "sprout")

FarmTab:CreateToggle({
   Name = "Auto Harvest",
   CurrentValue = false,
   Flag = "AutoHarvestToggle",
   Callback = function(Value)
      RunningModules["AutoHarvest"] = Value
      if Value then startAutoHarvest() end
   end,
})

FarmTab:CreateToggle({
   Name = "Auto Water",
   CurrentValue = false,
   Flag = "AutoWaterToggle",
   Callback = function(Value)
      RunningModules["AutoWater"] = Value
      if Value then startAutoWater() end
   end,
})

FarmTab:CreateToggle({
   Name = "Auto Plant",
   CurrentValue = false,
   Flag = "AutoPlantToggle",
   Callback = function(Value)
      RunningModules["AutoPlant"] = Value
      if Value then startAutoPlant() end
   end,
})

-- TAB: ECONOMY
local EconTab = Window:CreateTab("Economy", "dollar-sign")

EconTab:CreateToggle({
   Name = "Auto Sell (All)",
   CurrentValue = false,
   Flag = "AutoSellToggle",
   Callback = function(Value)
      RunningModules["AutoSell"] = Value
      if Value then startAutoSell() end
   end,
})

EconTab:CreateToggle({
   Name = "Restock Sniper",
   CurrentValue = false,
   Flag = "RestockSniperToggle",
   Callback = function(Value)
      RunningModules["RestockSniper"] = Value
      if Value then startRestockSniper() end
   end,
})

EconTab:CreateDropdown({
    Name = "Target Seeds for Restock",
    Options = {"Carrot", "Strawberry", "Blueberry", "Tomato", "Apple"}, -- Tambahkan seed lain sesuai game
    CurrentOption = {"Carrot"},
    MultipleOptions = true,
    Flag = "RestockTargets",
    Callback = function(Options)
        Config.Restock.TargetSeeds = Options
    end
})

-- TAB: EVENTS & MISC
local EventTab = Window:CreateTab("Events", "zap")

EventTab:CreateToggle({
   Name = "Steal Bot (Night Only)",
   CurrentValue = false,
   Flag = "StealBotToggle",
   Callback = function(Value)
      RunningModules["StealBot"] = Value
      if Value then startStealBot() end
   end,
})

EventTab:CreateToggle({
   Name = "Auto Pet Catch",
   CurrentValue = false,
   Flag = "AutoPetCatchToggle",
   Callback = function(Value)
      RunningModules["AutoPetCatch"] = Value
      if Value then startAutoPetCatch() end
   end,
})

EventTab:CreateToggle({
   Name = "Auto Seed Pack Claimer",
   CurrentValue = false,
   Flag = "SeedPackClaimerToggle",
   Callback = function(Value)
      RunningModules["SeedPackClaimer"] = Value
      if Value then startSeedPackClaimer() end
   end,
})

-- TAB: SETTINGS
local SettingsTab = Window:CreateTab("Settings", "settings")

SettingsTab:CreateSlider({
    Name = "Harvest Interval",
    Range = {0.1, 2},
    Increment = 0.1,
    Suffix = "s",
    CurrentValue = 0.5,
    Flag = "HarvestIntervalSlider",
    Callback = function(Value)
        Config.Timings.HarvestInterval = Value
    end
})

SettingsTab:CreateSlider({
    Name = "Water Interval",
    Range = {1, 10},
    Increment = 1,
    Suffix = "s",
    CurrentValue = 3,
    Flag = "WaterIntervalSlider",
    Callback = function(Value)
        Config.Timings.WaterInterval = Value
    end
})

Rayfield:LoadConfiguration()
print("Nexera GAG 2 Full Version Loaded")
