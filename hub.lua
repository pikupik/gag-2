local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- CORE SERVICES & NETWORKING
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local VirtualUser = game:GetService("VirtualUser")
local player = Players.LocalPlayer

-- Resolving Networking Module Safely
local Networking = nil
pcall(function()
    local shared = ReplicatedStorage:WaitForChild("SharedModules", 10)
    if shared then
        Networking = require(shared:WaitForChild("Networking", 10))
    end
end)

if not Networking then
    warn("[GAG Hub] Failed to load Networking module. Script may not work.")
end

-- STATE MANAGEMENT (Untuk mematikan loop dengan aman)
local States = {
    Harvest = false,
    Water = false,
    Plant = false,
    Sell = false,
    Restock = false,
    Gear = false,
    Mutation = false,
    Weather = false,
    Steal = false,
    PetCatch = false,
    PetHatch = false,
    Inventory = false,
    SeedPack = false
}

-- HELPER FUNCTIONS
local function getMyGarden()
    local plotId = player:GetAttribute("PlotId")
    if not plotId then return nil end
    return workspace:FindFirstChild("Gardens") and workspace.Gardens:FindFirstChild("Plot" .. tostring(plotId))
end

local function notify(msg)
    pcall(function()
        game.StarterGui:SetCore("SendNotification", {
            Title = "GAG Hub",
            Text = msg,
            Duration = 5
        })
    end)
end

-- WINDOW CONFIGURATION
local Window = Rayfield:CreateWindow({
   Name = "Nexera - GAG 2",
   Icon = 0,
   LoadingTitle = "Nexera Scripts",
   LoadingSubtitle = "by Codepikk",
   ShowText = "NexERA",
   Theme = "Default",
   ToggleUIKeybind = "K",
   DisableRayfieldPrompts = false,
   ConfigurationSaving = {
      Enabled = true,
      FolderName = nil,
      FileName = "Big Hub"
   },
   KeySystem = false,
})

-- ==========================================
-- TAB 1: FARMING
-- ==========================================
local FarmTab = Window:CreateTab("Farm", 6034510) -- Using icon ID for safety

-- AUTO HARVEST LOGIC
FarmTab:CreateToggle({
   Name = "Auto Harvest",
   CurrentValue = false,
   Flag = "AutoHarvestToggle",
   Callback = function(Value)
      States.Harvest = Value
      if Value then
         notify("🌾 Auto Harvest Started")
         task.spawn(function()
            while States.Harvest do
               pcall(function()
                  local garden = getMyGarden()
                  if garden then
                     local plants = garden:FindFirstChild("Plants")
                     if plants then
                        for _, plant in pairs(plants:GetChildren()) do
                           if not States.Harvest then break end
                           local fruits = plant:FindFirstChild("Fruits")
                           if fruits then
                              for _, fruit in pairs(fruits:GetChildren()) do
                                 if not States.Harvest then break end
                                 local plantId = fruit:GetAttribute("PlantId")
                                 local fruitId = fruit:GetAttribute("FruitId")
                                 if plantId and fruitId and Networking then
                                    Networking.Garden.CollectFruit:Fire(plantId, fruitId)
                                    task.wait(0.1)
                                 end
                              end
                           end
                        end
                     end
                  end
               end)
               task.wait(0.5)
            end
         end)
      else
         notify("⛔ Auto Harvest Stopped")
      end
   end,
})

-- AUTO WATER LOGIC
FarmTab:CreateToggle({
   Name = "Auto Water All Plants",
   CurrentValue = false,
   Flag = "AutoWaterToggle",
   Callback = function(Value)
      States.Water = Value
      if Value then
         notify("💧 Auto Water Started")
         task.spawn(function()
            while States.Water do
               pcall(function()
                  local garden = getMyGarden()
                  if garden then
                     local plants = garden:FindFirstChild("Plants")
                     if plants then
                        for _, plant in pairs(plants:GetChildren()) do
                           if not States.Water then break end
                           local growth = plant:GetAttribute("Growth")
                           if growth and growth < 1 then 
                              local pos = plant.PrimaryPart and plant.PrimaryPart.Position or plant:GetPivot().Position
                              if Networking then
                                 -- Note: You might need to find the specific watering can tool in your backpack first
                                 Networking.WateringCan.UseWateringCan:Fire(pos, "Common Watering Can", nil) 
                                 task.wait(0.5)
                              end
                           end
                        end
                     end
                  end
               end)
               task.wait(3)
            end
         end)
      else
         notify("⛔ Auto Water Stopped")
      end
   end,
})

-- AUTO PLANT LOGIC
FarmTab:CreateToggle({
   Name = "Auto Plant Seeds",
   CurrentValue = false,
   Flag = "AutoPlantToggle",
   Callback = function(Value)
      States.Plant = Value
      if Value then
         notify("🌱 Auto Plant Started")
         task.spawn(function()
            while States.Plant do
               pcall(function()
                  local garden = getMyGarden()
                  if garden then
                     -- Logic for finding empty spots and planting would go here
                     -- This is a simplified version as full grid logic is complex
                     local plantAreas = CollectionService:GetTagged("PlantArea")
                     for _, area in ipairs(plantAreas) do
                        if area:IsDescendantOf(garden) and area:IsA("BasePart") then
                           local pos = area.Position + Vector3.new(0, area.Size.Y/2, 0)
                           if Networking then
                              Networking.Plant.PlantSeed:Fire(pos, "Strawberry", nil) -- Example seed
                              task.wait(0.5)
                           end
                        end
                     end
                  end
               end)
               task.wait(5)
            end
         end)
      else
         notify("⛔ Auto Plant Stopped")
      end
   end,
})

-- ==========================================
-- TAB 2: ECONOMY
-- ==========================================
local EconTab = Window:CreateTab("Economy", 6031790)

-- AUTO SELL LOGIC
EconTab:CreateToggle({
   Name = "Auto Sell (When Full)",
   CurrentValue = false,
   Flag = "AutoSellToggle",
   Callback = function(Value)
      States.Sell = Value
      if Value then
         notify("💰 Auto Sell Active")
         task.spawn(function()
            while States.Sell do
               pcall(function()
                  local fruitCount = player:GetAttribute("FruitCount")
                  local maxFruits = player:GetAttribute("MaxFruitCapacity")
                  
                  if fruitCount and maxFruits and fruitCount >= (maxFruits * 0.8) then
                     if Networking then
                        Networking.NPCS.SellAll:Fire()
                        notify("📦 Backpack Sold!")
                     end
                     task.wait(5)
                  end
               end)
               task.wait(2)
            end
         end)
      else
         notify("⛔ Auto Sell Disabled")
      end
   end,
})

-- RESTOCK SNIPER
EconTab:CreateToggle({
   Name = "Restock Sniper",
   CurrentValue = false,
   Flag = "RestockSniperToggle",
   Callback = function(Value)
      States.Restock = Value
      if Value then
         notify("🎯 Restock Sniper Active")
         task.spawn(function()
            while States.Restock do
               pcall(function()
                  -- Logic to check stock and buy seeds
                  if Networking then
                     Networking.SeedShop.PurchaseSeed:Fire("Strawberry") -- Example
                  end
               end)
               task.wait(1)
            end
         end)
      else
         notify("⛔ Restock Sniper Disabled")
      end
   end,
})

-- ==========================================
-- TAB 3: EVENTS & PETS
-- ==========================================
local EventTab = Window:CreateTab("Events", 6035974)

-- STEAL BOT
EventTab:CreateToggle({
   Name = "Steal Bot (Night Only)",
   CurrentValue = false,
   Flag = "StealBotToggle",
   Callback = function(Value)
      States.Steal = Value
      if Value then
         notify("🌙 Steal Bot Active")
         task.spawn(function()
            while States.Steal do
               pcall(function()
                  -- Logic to find unlocked gardens and steal
                  if Networking then
                     -- Networking.Steal.BeginSteal:Fire(...)
                  end
               end)
               task.wait(1.5)
            end
         end)
      else
         notify("⛔ Steal Bot Disabled")
      end
   end,
})

-- AUTO PET CATCH
EventTab:CreateToggle({
   Name = "Auto Pet Catch",
   CurrentValue = false,
   Flag = "AutoPetCatchToggle",
   Callback = function(Value)
      States.PetCatch = Value
      if Value then
         notify("🐾 Auto Pet Catch Active")
         task.spawn(function()
            while States.PetCatch do
               pcall(function()
                  -- Logic to find wild pets and tame them
                  if Networking then
                     -- Networking.Pets.WildPetTame:Fire(...)
                  end
               end)
               task.wait(3)
            end
         end)
      else
         notify("⛔ Auto Pet Catch Disabled")
      end
   end,
})

-- ==========================================
-- TAB 4: STATUS
-- ==========================================
local StatusTab = Window:CreateTab("Status", 6030690)

StatusTab:CreateButton({Name="✅ Enable All", Callback=function() 
    for k, v in pairs(States) do States[k] = true end 
    notify("All Modules Enabled")
end})

StatusTab:CreateButton({Name="❌ Disable All", Callback=function() 
    for k, v in pairs(States) do States[k] = false end 
    notify("All Modules Disabled")
end})

Rayfield:LoadConfiguration()
print("GAG Hub Clean Edition Loaded Successfully!")
