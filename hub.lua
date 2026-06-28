--[[
    GAG HUB - All-in-One
    Single file. No sub-module loading. Paste & play.
    Usage: loadstring(game:HttpGet("https://raw.githubusercontent.com/ahmadlagi889-commits/tempek-gag2/main/hub.lua"))()
]]

if not game or not game:GetService("Players") then
    error("[GAG Hub] Must run inside Roblox game")
end

---------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------

local VERSION = "1.2.3"

local Config = {
    Features = {
        AutoHarvest = false, AutoSell = false, AutoWater = false,
        AutoPlant = false, RestockSniper = false, MutationTracker = false,
        WeatherBot = false, StealBot = false, InventoryOptimizer = false,
        AutoBuyPet = false, AntiAfk = true, SeedPackClaimer = false,
        AutoJoinServer = false, AutoPetCatch = false, AutoCenterPlot = false,
    },
    Timings = {
        HarvestInterval = 0.2, SellInterval = 5, WaterInterval = 3,
        PlantInterval = 5, RestockPollInterval = 1, MutationScanInterval = 3,
        WeatherPollInterval = 5, StealInterval = 1.5, InventoryCheckInterval = 10,
        PetHatchInterval = 2, SeedPackPollInterval = 2, PetCatchInterval = 3,
        CenterPlotInterval = 5,
    },
    Restock = {
        TargetSeeds = {},
        BlacklistedSeeds = {},
    },
    Steal = { MinFruitValue = 10000, MaxAttemptsPerNight = 20, PreferMutations = true },
    Sell = { Mode = "all", UseDailyDeal = false },
    Plant = { OnlyEmptyPlots = true, PreferSeed = nil, GridSpacing = 3, PlantOrder = "Top", BlacklistMutated = true },
    Water = { WaterAll = false, WaterFullyGrown = false, RequiredCan = "" },
    Inventory = { FavoriteThreshold = 500, AutoPromote = true, DropThreshold = 5 },
    Pet = { MinRarity = "Rare", AutoSellUnwanted = false },
    Gear = { TargetGears = {} },
    Mutation = {
        AlertMutations = { "Rainbow", "Starstruck", "Gold", "Frozen", "Electric", "Bloodlit", "Chained" },
        PriceMultipliers = { Gold = 20, Rainbow = 50, Electric = 12, Frozen = 10, Bloodlit = 5, Chained = 8, Starstruck = 100 },
        LogToConsole = true,
    },
    UI = { Title = "GAG Hub", Subtitle = "Grow A Garden Automation", NotifyDuration = 5 },
    Server = { TargetJobId = "", AutoRejoin = true, RejoinDelay = 5, MaxRetries = 10 },
    PetCatch = { MinRarity = "Common", AutoReturn = true },
}

function Config.Notify(title, text, duration)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title or "GAG Hub", Text = text or "",
            Duration = duration or Config.UI.NotifyDuration,
        })
    end)
end

---------------------------------------------------------------
-- CORE: NETWORKING (inlined from core/networking.lua)
---------------------------------------------------------------

local Networking = {}
local RS = game:GetService("ReplicatedStorage")

-- Internal cache
Networking._module = nil
Networking._cache = {}
Networking._connections = {}
Networking._log = true

---------------------------------------------------------------
-- RESOLVE NETWORKING MODULE
---------------------------------------------------------------

function Networking._resolve()
    if Networking._module then return Networking._module end

    -- Method 1: try require()
    local ok, result = pcall(function()
        local shared = RS:WaitForChild("SharedModules", 10)
        if not shared then error("SharedModules not found") end
        local net = shared:WaitForChild("Networking", 10)
        if not net then error("Networking not found") end
        return require(net)
    end)

    if ok and result and type(result) == "table" then
        Networking._module = result
        return result
    end

    -- Method 2: getgc — find already-loaded Networking table by checking for known keys
    local gcOk, gcResult = pcall(function()
        if not getgc then return nil end
        for _, v in pairs(getgc(true)) do
            if type(v) == "table" then
                -- Check for unique Networking structure: has Plant.PlantSeed AND Garden.CollectFruit AND SeedShop.PurchaseSeed
                local hasPlant = type(v.Plant) == "table" and type(v.Plant.PlantSeed) ~= "nil"
                local hasGarden = type(v.Garden) == "table" and type(v.Garden.CollectFruit) ~= "nil"
                local hasSeedShop = type(v.SeedShop) == "table" and type(v.SeedShop.PurchaseSeed) ~= "nil"
                if hasPlant and hasGarden and hasSeedShop then
                    return v
                end
            end
        end
        return nil
    end)

    if gcOk and gcResult and type(gcResult) == "table" then
        print("[GAG Hub] Networking resolved via getgc")
        Networking._module = gcResult
        return gcResult
    end

    -- Method 3: try require Packet directly, then build minimal net
    local pktOk, pktResult = pcall(function()
        local shared = RS:WaitForChild("SharedModules", 10)
        if not shared then error("SharedModules not found") end
        local pkt = shared:WaitForChild("Packet", 5)
        local net = shared:WaitForChild("Networking", 5)
        if not pkt or not net then return nil end
        -- Pre-require Packet so it's in module cache, then require Networking
        require(pkt)
        return require(net)
    end)

    if pktOk and pktResult and type(pktResult) == "table" then
        print("[GAG Hub] Networking resolved via Packet pre-require")
        Networking._module = pktResult
        return pktResult
    end

    warn("[GAG Hub] Failed to resolve Networking module (all methods failed):", result or gcResult or pktResult)
    return nil
end

---------------------------------------------------------------
-- RESOLVE REMOTE BY DOT PATH
-- e.g., "Garden.CollectFruit" → Networking.Garden.CollectFruit
---------------------------------------------------------------

function Networking._resolveRemote(path)
    -- Check cache
    if Networking._cache[path] then return Networking._cache[path] end

    local net = Networking._resolve()
    if not net then return nil end

    local current = net
    for segment in string.gmatch(path, "[^%.]+") do
        if type(current) ~= "table" then
            warn("[GAG Hub] Remote path broken at segment:", segment, "in", path)
            return nil
        end
        current = current[segment]
        if current == nil then
            -- Try searching by iterating keys (case-insensitive fallback)
            for k, v in pairs(current or {}) do
                if string.lower(k) == string.lower(segment) then
                    current = v
                    break
                end
            end
            if current == nil then
                warn("[GAG Hub] Remote not found:", segment, "in path", path)
                return nil
            end
        end
    end

    Networking._cache[path] = current
    return current
end

---------------------------------------------------------------
-- FIRE (RemoteEvent → server)
---------------------------------------------------------------

function Networking.fire(path, ...)
    local remote = Networking._resolveRemote(path)
    if not remote then
        warn("[GAG Hub] Cannot fire - remote not found:", path)
        return false
    end

    local args = {...}
    local argc = select("#", ...)
    local ok, err = pcall(function()
        if remote.Fire then
            remote:Fire(unpack(args, 1, argc))
        elseif type(remote) == "table" and remote.fire then
            remote:fire(unpack(args, 1, argc))
        else
            error("Remote has no :Fire method - type: " .. typeof(remote))
        end
    end)

    if not ok then
        warn("[GAG Hub] Fire error on", path, ":", err)
        return false
    end

    if Networking._log then
        print("[GAG Hub] Fired:", path)
    end
    return true
end

---------------------------------------------------------------
-- INVOKE (RemoteFunction → server → response)
---------------------------------------------------------------

function Networking.invoke(path, ...)
    local remote = Networking._resolveRemote(path)
    if not remote then
        warn("[GAG Hub] Cannot invoke - remote not found:", path)
        return nil
    end

    local args = {...}
    local argc = select("#", ...)
    local ok, result = pcall(function()
        if remote.Invoke then
            return remote:Invoke(unpack(args, 1, argc))
        else
            error("Remote has no :Invoke method")
        end
    end)

    if not ok then
        warn("[GAG Hub] Invoke error on", path, ":", result)
        return nil
    end

    return result
end

---------------------------------------------------------------
-- LISTEN (RemoteEvent ← server)
---------------------------------------------------------------

function Networking.on(path, callback)
    local remote = Networking._resolveRemote(path)
    if not remote then
        warn("[GAG Hub] Cannot listen - remote not found:", path)
        return nil
    end

    local ok, connection = pcall(function()
        if remote.OnClientEvent then
            return remote.OnClientEvent:Connect(callback)
        elseif remote.Connect then
            return remote:Connect(callback)
        else
            -- Try the .Changed pattern or direct connect
            warn("[GAG Hub] Remote has no OnClientEvent:", path)
            return nil
        end
    end)

    if ok and connection then
        table.insert(Networking._connections, connection)
        return connection
    end
    return nil
end

---------------------------------------------------------------
-- BATCH LISTEN (connect multiple events at once)
---------------------------------------------------------------

function Networking.onMany(map)
    local connections = {}
    for path, callback in pairs(map) do
        local conn = Networking.on(path, callback)
        if conn then
            connections[path] = conn
        end
    end
    return connections
end

---------------------------------------------------------------
-- GET RAW REMOTE (for advanced usage)
---------------------------------------------------------------

function Networking.get(path)
    return Networking._resolveRemote(path)
end

---------------------------------------------------------------
-- CHECK IF REMOTE EXISTS
---------------------------------------------------------------

function Networking.exists(path)
    return Networking._resolveRemote(path) ~= nil
end

---------------------------------------------------------------
-- LOGGING
---------------------------------------------------------------

function Networking.setLogging(enabled)
    Networking._log = enabled
end

---------------------------------------------------------------
-- DISCONNECT ALL
---------------------------------------------------------------

function Networking.disconnectAll()
    for _, conn in ipairs(Networking._connections) do
        pcall(function() conn:Disconnect() end)
    end
    Networking._connections = {}
end

---------------------------------------------------------------
-- CACHE REFRESH (call after game update)
---------------------------------------------------------------

function Networking.refreshCache()
    Networking._module = nil
    Networking._cache = {}
    Networking._resolve()
end

---------------------------------------------------------------
-- AUTO-INIT
---------------------------------------------------------------

Networking._resolve()


---------------------------------------------------------------
-- CORE: UTILITIES (inlined from core/utils.lua)
---------------------------------------------------------------

local Utils = {}
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

---------------------------------------------------------------
-- INSTANCE RESOLVER
---------------------------------------------------------------

-- Resolve dot-path: "A.B.C" → A.B.C
function Utils.resolve(root, path)
    if not root or not path then return nil end
    local current = root
    for segment in string.gmatch(path, "[^%.]+") do
        current = current:FindFirstChild(segment)
        if not current then return nil end
    end
    return current
end

-- Safe resolve with WaitForChild (timeout)
function Utils.resolveWait(root, path, timeout)
    if not root or not path then return nil end
    local current = root
    for segment in string.gmatch(path, "[^%.]+") do
        current = current:WaitForChild(segment, timeout or 10)
        if not current then return nil end
    end
    return current
end

---------------------------------------------------------------
-- PLAYER HELPERS
---------------------------------------------------------------

function Utils.getLocalPlayer()
    return Players.LocalPlayer
end

function Utils.getCharacter()
    local lp = Players.LocalPlayer
    return lp and lp.Character or nil
end

function Utils.getHumanoidRootPart()
    local char = Utils.getCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

function Utils.getHumanoid()
    local char = Utils.getCharacter()
    return char and char:FindFirstChildWhichIsA("Humanoid")
end

function Utils.getPlotId()
    local lp = Players.LocalPlayer
    return lp and lp:GetAttribute("PlotId")
end

function Utils.getMyGarden()
    local plotId = Utils.getPlotId()
    if not plotId then return nil end
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return nil end
    return gardens:FindFirstChild("Plot" .. tostring(plotId))
end

---------------------------------------------------------------
-- GARDEN HELPERS
---------------------------------------------------------------

-- Get all plants in a garden plot
function Utils.getPlantsInGarden(garden)
    if not garden then return {} end
    local plants = {}
    for _, child in ipairs(garden:GetDescendants()) do
        if child:IsA("Model") and child:GetAttribute("SeedName") then
            table.insert(plants, child)
        end
    end
    return plants
end

-- Get plant info from attributes
function Utils.getPlantInfo(plant)
    if not plant then return nil end
    return {
        Name     = plant:GetAttribute("SeedName") or plant.Name,
        Growth   = plant:GetAttribute("Growth") or 0,
        Mutation = plant:GetAttribute("Mutation"),
        Age      = plant:GetAttribute("Age") or 0,
        Size     = plant:GetAttribute("Size") or 1,
        IsRipe   = (plant:GetAttribute("Growth") or 0) >= 1,
        Owner    = plant:GetAttribute("Owner"),
        Instance = plant,
    }
end

-- Get all fruits in a garden
function Utils.getFruitsInGarden(garden)
    if not garden then return {} end
    local fruits = {}
    for _, child in ipairs(garden:GetDescendants()) do
        if child:GetAttribute("FruitName") or child:GetAttribute("IsFruit") then
            table.insert(fruits, child)
        end
    end
    return fruits
end

-- Get all gardens in workspace
function Utils.getAllGardens()
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return {} end
    local result = {}
    for _, garden in ipairs(gardens:GetChildren()) do
        table.insert(result, garden)
    end
    return result
end

---------------------------------------------------------------
-- VALUE CALCULATOR
---------------------------------------------------------------

-- Calculate fruit sell value (mirrors FruitValueCalc)
-- baseValue * size^exponent * mutationMult * sizeMult
function Utils.calculateFruitValue(seedName, size, mutation, sellData, mutationData)
    local base = sellData and sellData[seedName] or 0
    local sizeExponent = 2.65
    local sizeMult = 1
    local mutationMult = 1

    if mutation and mutationData then
        local mData = mutationData[mutation]
        mutationMult = mData and mData.PriceMultiplier or 1
    end

    local value = base * (size ^ sizeExponent) * sizeMult * mutationMult
    return math.floor(value)
end

---------------------------------------------------------------
-- INVENTORY HELPERS
---------------------------------------------------------------

-- Get backpack contents
function Utils.getBackpackItems()
    local lp = Players.LocalPlayer
    local bp = lp and lp:FindFirstChild("Backpack")
    if not bp then return {} end
    local items = {}
    for _, tool in ipairs(bp:GetChildren()) do
        if tool:IsA("Tool") then
            table.insert(items, {
                Name = tool.Name,
                Instance = tool,
                Type = tool:GetAttribute("ItemType") or "Unknown",
            })
        end
    end
    return items
end

-- Get equipped tool
function Utils.getEquippedTool()
    local char = Utils.getCharacter()
    if not char then return nil end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then
            return child
        end
    end
    return nil
end

---------------------------------------------------------------
-- NIGHT CHECK
---------------------------------------------------------------

function Utils.isNight()
    local night = RS:FindFirstChild("Night")
    if night then return night.Value == true end
    -- Fallback: check lighting
    local clock = game:GetService("Lighting").ClockTime
    return clock >= 18 or clock < 6
end

---------------------------------------------------------------
-- SHECKLE BALANCE
---------------------------------------------------------------

function Utils.getSheckles()
    local lp = Players.LocalPlayer
    local leaderstats = lp and lp:FindFirstChild("leaderstats")
    if not leaderstats then return 0 end
    local sheckles = leaderstats:FindFirstChild("Sheckles")
    return sheckles and sheckles.Value or 0
end

---------------------------------------------------------------
-- SAFE CALL
---------------------------------------------------------------

function Utils.safeCall(fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        warn("[GAG Hub] Error:", result)
    end
    return ok, result
end

---------------------------------------------------------------
-- TABLE HELPERS
---------------------------------------------------------------

function Utils.tableContains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then return true end
    end
    return false
end

function Utils.tableKeys(tbl)
    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, k)
    end
    return keys
end

function Utils.deepCopy(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then
            copy[k] = Utils.deepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

---------------------------------------------------------------
-- STRING HELPERS
---------------------------------------------------------------

function Utils.formatNumber(n)
    if n >= 1e12 then return string.format("%.1fT", n / 1e12) end
    if n >= 1e9  then return string.format("%.1fB", n / 1e9) end
    if n >= 1e6  then return string.format("%.1fM", n / 1e6) end
    if n >= 1e3  then return string.format("%.1fK", n / 1e3) end
    return tostring(n)
end

function Utils.formatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then return string.format("%dh %dm %ds", h, m, s) end
    if m > 0 then return string.format("%dm %ds", m, s) end
    return string.format("%ds", s)
end

---------------------------------------------------------------
-- SIGNAL (simple event)
---------------------------------------------------------------

function Utils.createSignal()
    local signal = {}
    signal._bindables = {}

    function signal:Connect(fn)
        local connection = { _fn = fn, _connected = true }
        table.insert(signal._bindables, connection)
        function connection:Disconnect()
            self._connected = false
        end
        return connection
    end

    function signal:Fire(...)
        for _, conn in ipairs(signal._bindables) do
            if conn._connected then
                task.spawn(conn._fn, ...)
            end
        end
    end

    return signal
end


---------------------------------------------------------------
-- CORE: ANTI-AFK (inlined from core/antiafk.lua)
---------------------------------------------------------------

local AntiAfk = {}
local Players    = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local GuiService  = game:GetService("GuiService")
local RS          = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer

AntiAfk._running = false
AntiAfk._thread  = nil
AntiAfk._rejoinThread = nil
AntiAfk._stats   = { actions = 0, rejoins = 0, lastAction = 0 }

---------------------------------------------------------------
-- ANTI-AFK
---------------------------------------------------------------

function AntiAfk.start(config)
    if AntiAfk._running then return end
    AntiAfk._running = true

    local interval = config.Timings.AntiAfkInterval or 60

    AntiAfk._thread = task.spawn(function()
        while AntiAfk._running do
            -- Method 1: VirtualUser click (most reliable)
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)

            -- Method 2: Simulate movement
            pcall(function()
                local humanoid = LP.Character
                    and LP.Character:FindFirstChildWhichIsA("Humanoid")
                if humanoid then
                    humanoid.Jump = true
                end
            end)

            -- Method 3: Fire game's anti-AFK remote if available
            pcall(function()
                local Net = require(
                    RS:WaitForChild("SharedModules"):WaitForChild("Networking")
                )
                if Net.AntiAfk and Net.AntiAfk.RequestHop then
                    -- Only fire if idle long enough (game tracks this)
                end
            end)

            AntiAfk._stats.actions += 1
            AntiAfk._stats.lastAction = os.time()
            task.wait(interval)
        end
    end)

    -- Also handle the idle kicked event
    LP.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)

    print("[GAG Hub] Anti-AFK started (interval: " .. interval .. "s)")
end

function AntiAfk.stop()
    AntiAfk._running = false
    if AntiAfk._thread then
        task.cancel(AntiAfk._thread)
        AntiAfk._thread = nil
    end
end

---------------------------------------------------------------
-- AUTO-REJOIN
---------------------------------------------------------------

function AntiAfk.startAutoRejoin(config)
    if AntiAfk._rejoinThread then return end

    local delay = config.Timings.RejoinDelay or 5

    -- Handle disconnection
    game:GetService("CoreGui").RobloxPromptGui.promptOverlay
        .ChildAdded:Connect(function(child)
            if child.Name == "ErrorPrompt" or child.Name == "TeleportPrompt" then
                AntiAfk._stats.rejoins += 1
                task.wait(delay)
                pcall(function()
                    game:GetService("TeleportService"):TeleportToPlaceInstance(
                        game.PlaceId,
                        game.JobId,
                        LP
                    )
                end)
            end
        end)

    -- Handle kick messages
    game:GetService("GuiService").ErrorMessageChanged:Connect(function()
        AntiAfk._stats.rejoins += 1
        task.wait(delay)
        pcall(function()
            game:GetService("TeleportService"):Teleport(game.PlaceId, LP)
        end)
    end)

    -- Handle character death (auto-respawn)
    LP.CharacterAdded:Connect(function(char)
        local humanoid = char:WaitForChild("Humanoid", 10)
        if humanoid then
            humanoid.Died:Connect(function()
                task.wait(3)
                pcall(function()
                    LP:LoadCharacter()
                end)
            end)
        end
    end)

    print("[GAG Hub] Auto-Rejoin enabled")
end

function AntiAfk.getStats()
    return AntiAfk._stats
end


---------------------------------------------------------------
-- MODULE REGISTRY
---------------------------------------------------------------

local Modules = {}
local Running = {}

local function startModule(name)
    if Running[name] then return end
    local mod = Modules[name]
    if mod and mod.start then
        mod.start(Config, Networking, Utils)
        Running[name] = true
        print("[GAG Hub] Started:", name)
    end
end

local function stopModule(name)
    if not Running[name] then return end
    local mod = Modules[name]
    if mod and mod.stop then
        mod.stop()
        Running[name] = false
        print("[GAG Hub] Stopped:", name)
    end
end

local function toggleModule(name)
    if Running[name] then stopModule(name) else startModule(name) end
    Config.Features[name] = Running[name]
end

---------------------------------------------------------------
-- RESOURCES: Prices & Meta (loaded from resources.lua)
---------------------------------------------------------------

local Resources = nil
pcall(function()
    -- Try loading from GitHub raw (always latest)
    local url = "https://raw.githubusercontent.com/ahmadlagi889-commits/tempek-gag2/main/resources.lua"
    local src = game:HttpGet(url, true)
    if src and #src > 100 then
        Resources = loadstring(src)()
    end
end)
if not Resources then
    -- Fallback: inline minimal prices
    Resources = { SeedPrices = {}, GearPrices = {}, SeedMeta = {}, GearMeta = {}, AllSeeds = {}, AllGears = {} }
    warn("[GAG Hub] Failed to load resources.lua, affordability guard disabled")
end

---------------------------------------------------------------
-- MODULE: AUTO HARVEST
---------------------------------------------------------------

Modules.AutoHarvest = {}
do
    local M = Modules.AutoHarvest
    local Harvest = M
    local Players = game:GetService("Players")
    Harvest._running = false
    Harvest._thread  = nil
    Harvest._connections = {}
    Harvest._stats = { harvested = 0, scans = 0, errors = 0 }

    ---------------------------------------------------------------
    -- GET MY PLOT (dynamic)
    ---------------------------------------------------------------

    function Harvest._getMyPlot()
        local lp = Players.LocalPlayer
        if not lp then return nil end
        local plotId = lp:GetAttribute("PlotId")
        if not plotId then return nil end
        local gardens = workspace:FindFirstChild("Gardens")
        if not gardens then return nil end
        return gardens:FindFirstChild("Plot" .. tostring(plotId))
    end

    function Harvest._isAlive()
        local lp = Players.LocalPlayer
        if not lp then return false end
        local char = lp.Character
        if not char then return false end
        local hum = char:FindFirstChildWhichIsA("Humanoid")
        return hum and hum.Health > 0
    end

    function Harvest._isHarvestable(fruitModel)
        if not fruitModel or not fruitModel.Parent then return false end
        local harvestPart = fruitModel:FindFirstChild("HarvestPart")
        if not harvestPart then return false end
        local prompt = harvestPart:FindFirstChild("HarvestPrompt")
        if not prompt then return false end
        if not prompt.Enabled then return false end
        return true
    end

    ---------------------------------------------------------------
    -- COLLECT ALL FRUITS ON MY PLOT (direct remote, no prompt)
    -- Two harvest paths:
    --   Multi: Plant → Fruits → FruitModel(HarvestPart.HarvestPrompt) → CollectFruit(plantId, fruitId)
    --   Single: Plant → HarvestPart.HarvestPrompt (no Fruits folder) → CollectFruit(plantId, "")
    ---------------------------------------------------------------

    function Harvest._collectAll(Net)
        if not Harvest._isAlive() then return 0 end

        local plot = Harvest._getMyPlot()
        if not plot then return 0 end
        local count = 0
        local plantsFolder = plot:FindFirstChild("Plants")
        if not plantsFolder then return 0 end
        for _, plantModel in ipairs(plantsFolder:GetChildren()) do
            if not Harvest._running then break end
            local plantId = plantModel:GetAttribute("PlantId")
            if not plantId then continue end

            -- Path A: Multi-harvest (has Fruits folder)
            local fruitsFolder = plantModel:FindFirstChild("Fruits")
            if fruitsFolder then
                for _, fruitModel in ipairs(fruitsFolder:GetChildren()) do
                    if not Harvest._running then break end
                    if not Harvest._isHarvestable(fruitModel) then continue end
                    local fruitId = fruitModel:GetAttribute("FruitId")
                    pcall(function()
                        Net.fire("Garden.CollectFruit", plantId, fruitId or "")
                    end)
                    count += 1
                    task.wait(0.1)
                end
            end

            -- Path B: Single-harvest (HarvestPrompt directly on plant)
            if Harvest._isHarvestable(plantModel) then
                pcall(function()
                    Net.fire("Garden.CollectFruit", plantId, "")
                end)
                count += 1
                task.wait(0.1)
            end
        end
        return count
    end

    ---------------------------------------------------------------
    -- START
    ---------------------------------------------------------------

    function Harvest.start(config, Net, Utils)
        if Harvest._running then return end
        Harvest._running = true

        local interval = config.Timings.HarvestInterval or 0.5

        -- [METHOD 1] Listen for new fruits and collect immediately
        local fruitAddedConn = Net.on("Garden.FruitAdded", function(plantId, fruitId, fruitName, data)
            if not Harvest._running then return end
            if not Harvest._isAlive() then return end
            task.wait(0.15)
            pcall(function()
                Net.fire("Garden.CollectFruit", plantId, fruitId or "")
            end)
            Harvest._stats.harvested += 1
        end)
        if fruitAddedConn then
            table.insert(Harvest._connections, fruitAddedConn)
        end

        -- [METHOD 2] Periodic scan — walk garden tree, fire CollectFruit directly
        Harvest._thread = task.spawn(function()
            while Harvest._running do
                Harvest._stats.scans += 1
                local count = Harvest._collectAll(Net)
                Harvest._stats.harvested += count
                task.wait(interval)
            end
        end)

        print("[GAG Hub] Auto-Harvest started")
    end

    ---------------------------------------------------------------
    -- STOP / STATUS
    ---------------------------------------------------------------

    function Harvest.stop()
        Harvest._running = false
        if Harvest._thread then
            Harvest._thread = nil
        end
        for _, conn in ipairs(Harvest._connections) do
            pcall(function() conn:Disconnect() end)
        end
        Harvest._connections = {}
    end

    function Harvest.getStats()
        return Harvest._stats
    end
end

---------------------------------------------------------------
-- MODULE: AUTO SELL
---------------------------------------------------------------

Modules.AutoSell = {}
do
    local M = Modules.AutoSell
    local Sell = M
Sell._running = false
Sell._thread  = nil
Sell._connections = {}
Sell._stats = { sold = 0, totalEarned = 0, errors = 0 }

---------------------------------------------------------------
-- START
---------------------------------------------------------------

function Sell.start(config, Net, Utils)
    if Sell._running then return end
    Sell._running = true

    local interval = config.Timings.SellInterval or 5
    local sellConfig = config.Sell or {}

    Sell._thread = task.spawn(function()
        while Sell._running do
            Sell._autoSell(sellConfig, Net, Utils)
            task.wait(interval)
        end
    end)

    print("[GAG Hub] Auto-Sell started (mode: " .. (sellConfig.Mode or "all") .. ")")
end

---------------------------------------------------------------
-- AUTO SELL LOGIC
---------------------------------------------------------------

function Sell._autoSell(sellConfig, Net, Utils)
    -- Guard: skip if no fruits in backpack
    local lp = Players.LocalPlayer
    local bp = lp and lp:FindFirstChild("Backpack")
    local hasFruit = false
    if bp then
        for _, tool in ipairs(bp:GetChildren()) do
            if tool:IsA("Tool") and (tool:GetAttribute("FruitName") or tool:GetAttribute("IsFruit")) then
                hasFruit = true
                break
            end
        end
    end
    -- Also check character (equipped tool)
    if not hasFruit and lp and lp.Character then
        for _, tool in ipairs(lp.Character:GetChildren()) do
            if tool:IsA("Tool") and (tool:GetAttribute("FruitName") or tool:GetAttribute("IsFruit")) then
                hasFruit = true
                break
            end
        end
    end
    if not hasFruit then return end

    local mode = sellConfig.Mode or "all"

    if mode == "all" then
        -- Sell everything
        local ok = Net.fire("NPCS.SellAll")
        if ok then
            Sell._stats.sold += 1
        else
            Sell._stats.errors += 1
        end

    elseif mode == "below_threshold" then
        -- Sell individual fruits below value threshold
        Sell._sellBelowThreshold(sellConfig, Net, Utils)

    elseif mode == "keep_best" then
        -- Sell all except top N
        Sell._sellKeepBest(sellConfig, Net, Utils)
    end

    -- Use daily deal if configured
    if sellConfig.UseDailyDeal then
        Net.fire("NPCS.UseDailyDealAll")
    end
end

-- Sell fruits below a certain value threshold
function Sell._sellBelowThreshold(sellConfig, Net, Utils)
    local threshold = sellConfig.ValueThreshold or 100

    -- Get backpack items
    local items = Utils.getBackpackItems()
    for _, item in ipairs(items) do
        if item.Type == "HarvestedFruit" or string.find(item.Name, "Fruit") then
            -- Try to sell this individual fruit
            local ok = Net.fire("NPCS.SellFruit", item.Name)
            if ok then
                Sell._stats.sold += 1
            end
        end
    end
end

-- Sell all except keep top N valuable fruits
function Sell._sellKeepBest(sellConfig, Net, Utils)
    -- Just sell all for now - more complex logic needs inventory API
    local ok = Net.fire("NPCS.SellAll")
    if ok then
        Sell._stats.sold += 1
    end
end

---------------------------------------------------------------
-- MANUAL SELL ALL
---------------------------------------------------------------

function Sell.sellAll(Net)
    local ok = Net.fire("NPCS.SellAll")
    if ok then
        Sell._stats.sold += 1
    end
    return ok
end

---------------------------------------------------------------
-- SELL SPECIFIC FRUIT
---------------------------------------------------------------

function Sell.sellFruit(Net, fruitName)
    local ok = Net.fire("NPCS.SellFruit", fruitName)
    if ok then
        Sell._stats.sold += 1
    end
    return ok
end

---------------------------------------------------------------
-- USE DAILY DEAL
---------------------------------------------------------------

function Sell.useDailyDeal(Net, single)
    if single then
        return Net.fire("NPCS.UseDailyDealSingle")
    else
        return Net.fire("NPCS.UseDailyDealAll")
    end
end

---------------------------------------------------------------
-- STOP / STATUS
---------------------------------------------------------------

function Sell.stop()
    Sell._running = false
    for _, conn in ipairs(Sell._connections) do
        pcall(function() conn:Disconnect() end)
    end
    Sell._connections = {}
end

function Sell.getStats()
    return Sell._stats
end

end

---------------------------------------------------------------
-- MODULE: AUTO WATER
---------------------------------------------------------------

Modules.AutoWater = {}
do
    local M = Modules.AutoWater
    local Water = M
    local Players = game:GetService("Players")
Water._running = false
Water._thread  = nil
Water._connections = {}
Water._stats = { watered = 0, scans = 0, errors = 0, noCan = 0 }
Water._debug = true -- set false to silence debug

---------------------------------------------------------------
-- FIND WATERING CAN TOOL IN BACKPACK/CHARACTER
-- Tool attribute: "WateringCan" = can name string
-- Can types: "Common Watering Can", "Super Watering Can"
---------------------------------------------------------------

function Water._findCan(requiredCan)
    local LP = Players.LocalPlayer
    if not LP then
        if Water._debug then warn("[Water][DEBUG] No LocalPlayer") end
        return nil, nil
    end

    -- Normalize: trim whitespace
    local function trim(s)
        if type(s) ~= "string" then return "" end
        return s:match("^%s*(.-)%s*$") or ""
    end

    local reqNorm = trim(requiredCan)
    if Water._debug then
        warn("[Water][DEBUG] RequiredCan raw:", string.format("%q", tostring(requiredCan or "")),
             "| norm:", string.format("%q", reqNorm),
             "| type:", type(requiredCan),
             "| len:", #reqNorm)
    end

    -- If no specific can required, use first found
    local matchFn = function(canName)
        if reqNorm == "" then return true end
        return trim(canName) == reqNorm
    end

    local function scanContainer(container, label)
        if not container then return nil end
        local tools = container:GetChildren()
        if Water._debug then
            warn("[Water][DEBUG] Scanning", label, "- items:", #tools)
        end
        for _, tool in ipairs(tools) do
            if tool:IsA("Tool") then
                local wcAttr = tool:GetAttribute("WateringCan")
                if Water._debug then
                    warn("[Water][DEBUG] Tool:", tool.Name,
                         "| WateringCan attr:", string.format("%q", tostring(wcAttr)),
                         "| attr type:", type(wcAttr),
                         "| Class:", tool.ClassName)
                end
                -- WateringCan attribute = flag for watering can tools
                if wcAttr ~= nil then
                    local canName = tool.Name
                    local matched = matchFn(canName)
                    if Water._debug then
                        warn("[Water][DEBUG] Found can:", string.format("%q", canName),
                             "| match:", matched,
                             "| compare:", string.format("%q", trim(canName)), "==", string.format("%q", reqNorm))
                    end
                    if matched then
                        return tool, canName
                    end
                end
            end
        end
        return nil
    end

    -- Check character first (already equipped)
    local char = LP.Character
    local tool, canName = scanContainer(char, "Character")
    if tool then return tool, canName end

    -- Check backpack
    local backpack = LP:FindFirstChild("Backpack")
    tool, canName = scanContainer(backpack, "Backpack")

    if not tool and Water._debug then
        warn("[Water][DEBUG] No watering can found! RequiredCan:", string.format("%q", tostring(requiredCan or "")))
    end

    return tool, canName
end

---------------------------------------------------------------
-- EQUIP WATERING CAN
---------------------------------------------------------------

function Water._equipCan(tool)
    local LP = Players.LocalPlayer
    local char = LP and LP.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        if Water._debug then warn("[Water][DEBUG] No humanoid for equip") end
        return false
    end

    -- Already in character?
    if tool.Parent == char then
        if Water._debug then warn("[Water][DEBUG] Can already equipped:", tool.Name) end
        return true
    end

    if Water._debug then warn("[Water][DEBUG] Equipping:", tool.Name, "from:", tool.Parent and tool.Parent.Name) end
    pcall(function() humanoid:EquipTool(tool) end)
    task.wait(0.2)
    local success = tool.Parent == char
    if Water._debug then warn("[Water][DEBUG] Equip result:", success, "parent:", tool.Parent and tool.Parent.Name) end
    return success
end

---------------------------------------------------------------
-- START
---------------------------------------------------------------

function Water.start(config, Net, Utils)
    if Water._running then return end
    Water._running = true

    local interval = config.Timings.WaterInterval or 3

    Water._thread = task.spawn(function()
        while Water._running do
            Water._waterPlants(config, Net, Utils)
            task.wait(interval)
        end
    end)

    print("[GAG Hub] Auto-Water started")
end

---------------------------------------------------------------
-- WATER PLANTS
-- Reference: Controllers_WateringcanController.TryWater()
-- Remote: WateringCan.UseWateringCan(position, canName, toolInstance)
---------------------------------------------------------------

function Water._waterPlants(config, Net, Utils)
    local garden = Utils.getMyGarden()
    if not garden then
        if Water._debug then warn("[Water][DEBUG] No garden found") end
        return
    end

    Water._stats.scans += 1

    -- 1. Find + equip watering can
    local canTool, canName = Water._findCan(config.Water.RequiredCan)
    if not canTool then
        Water._stats.noCan += 1
        if Water._debug then warn("[Water][DEBUG] noCan, scan:", Water._stats.scans) end
        return
    end

    local equipped = Water._equipCan(canTool)
    if not equipped then
        Water._stats.errors += 1
        if Water._debug then warn("[Water][DEBUG] Failed to equip can") end
        return
    end

    -- 2. Scan plants
    local plants = Utils.getPlantsInGarden(garden)
    local waterFullyGrown = config.Water.WaterFullyGrown or false
    if Water._debug then
        warn("[Water][DEBUG] Garden:", garden.Name, "| Plants:", #plants,
             "| WaterAll:", tostring(config.Water.WaterAll),
             "| WaterFullyGrown:", tostring(waterFullyGrown),
             "| RequiredCan:", tostring(config.Water.RequiredCan))
    end

    local wateredThisRound = 0
    for _, plant in ipairs(plants) do
        if not Water._running then break end

        local info = Utils.getPlantInfo(plant)
        if not info then
            if Water._debug then warn("[Water][DEBUG] No info for plant:", plant.Name) end
            continue
        end

        -- Skip fully grown unless toggle enabled
        local growth = info.Growth or 0
        local isFullyGrown = growth >= 1
        if isFullyGrown and not waterFullyGrown then
            if Water._debug then warn("[Water][DEBUG] Skip fully grown:", info.Name, "growth:", growth) end
            continue
        end

        -- Water all mode OR needs water (growth < 1)
        local needsWater = growth < 1
        if not needsWater and not waterFullyGrown and not config.Water.WaterAll then
            if Water._debug then warn("[Water][DEBUG] Skip no-water-need:", info.Name, "growth:", growth) end
            continue
        end

        -- 3. Get plant position
        local rootPart = plant:FindFirstChildWhichIsA("BasePart")
        if not rootPart then
            if Water._debug then warn("[Water][DEBUG] No BasePart for plant:", info.Name) end
            continue
        end

        -- 4. Fire UseWateringCan(position, canName, toolInstance)
        -- Position offset -0.3 Y like decompiled TryWater
        local pos = rootPart.Position - Vector3.new(0, 0.3, 0)
        if Water._debug then
            warn("[Water][DEBUG] Watering:", info.Name,
                 "| pos:", tostring(pos),
                 "| can:", canName)
        end
        local ok = pcall(function()
            Net.fire("WateringCan.UseWateringCan", pos, canName, canTool)
        end)

        if ok then
            Water._stats.watered += 1
            wateredThisRound += 1
        else
            Water._stats.errors += 1
            if Water._debug then warn("[Water][DEBUG] Fire failed for:", info.Name) end
        end

        task.wait(0.5) -- cooldown between plants (match TryWater 0.5s cooldown)
    end

    if Water._debug and wateredThisRound > 0 then
        warn("[Water][DEBUG] Round done. Watered:", wateredThisRound,
             "| Total:", Water._stats.watered,
             "| Errors:", Water._stats.errors)
    end
end

---------------------------------------------------------------
-- PLACE SPRINKLER (utility)
---------------------------------------------------------------

function Water.placeSprinkler(Net, Utils, sprinklerType)
    local garden = Utils.getMyGarden()
    if not garden then return false end

    local spawnPoint = garden:FindFirstChild("SpawnPoint")
    local position = spawnPoint and spawnPoint.Position or Vector3.new(0, 0, 0)

    local ok = Net.fire("Place.PlaceSprinkler", position, sprinklerType or "Common Sprinkler")
    return ok
end

---------------------------------------------------------------
-- STOP / STATUS
---------------------------------------------------------------

function Water.stop()
    Water._running = false
    for _, conn in ipairs(Water._connections) do
        pcall(function() conn:Disconnect() end)
    end
    Water._connections = {}
end

function Water.getStats()
    return Water._stats
end

end

---------------------------------------------------------------
-- MODULE: AUTO PLANT
-- Reference: Controllers_PlantController.module.lua
-- Remote: Plant.PlantSeed(position: Vector3, seedName: String, toolInstance: Instance)
-- Plant areas: CollectionService:GetTagged("PlantArea")
-- Seed tool: Character tool with "SeedTool" attribute
-- Flow: find seed in backpack → equip → fire PlantSeed
---------------------------------------------------------------

Modules.AutoPlant = {}
do
    local M = Modules.AutoPlant
    local Plant = M
    local Players = game:GetService("Players")
    local CollectionService = game:GetService("CollectionService")
Plant._running = false
Plant._thread  = nil
Plant._connections = {}
Plant._stats = { planted = 0, scans = 0, errors = 0, noSeeds = 0, equipped = 0 }

---------------------------------------------------------------
-- GET EQUIPPED SEED TOOL (matching decompiled GetEquippedTool)
-- Must be a Tool with "SeedTool" attribute = seed name
---------------------------------------------------------------

function Plant._getEquippedSeed()
    local lp = Players.LocalPlayer
    local char = lp and lp.Character
    if not char then return nil, nil end
    local tool = char:FindFirstChildWhichIsA("Tool")
    if not tool then return nil, nil end
    if tool:GetAttribute("MainCategory") ~= "Seed" then return nil, nil end
    local seedName = tool:GetAttribute("SeedTool")
    if not seedName then return nil, nil end
    return seedName, tool
end

---------------------------------------------------------------
-- FIND SEED TOOLS IN BACKPACK
-- Returns list of {tool, seedName} sorted by seed name
---------------------------------------------------------------

function Plant._isMutatedSeed(seedToolValue)
    if not seedToolValue then return false end
    -- Match "Gold", "Gold Carrot", "Rainbow", "Rainbow Tomato", etc.
    if seedToolValue == "Gold" or seedToolValue == "Rainbow" then return true end
    return string.match(seedToolValue, "^Gold ") ~= nil
        or string.match(seedToolValue, "^Rainbow ") ~= nil
end

function Plant._findSeedsInBackpack(preferSeed, skipMutated)
    local lp = Players.LocalPlayer
    local bp = lp and lp:FindFirstChild("Backpack")
    if not bp then return {} end
    local seeds = {}
    for _, tool in ipairs(bp:GetChildren()) do
        if tool:IsA("Tool") then
            local cat = tool:GetAttribute("MainCategory")
            local sn = tool:GetAttribute("SeedTool")
            if sn and cat == "Seed" then
                -- Skip Gold/Rainbow mutated seeds if filter enabled
                local include = true
                if skipMutated and Plant._isMutatedSeed(sn) then
                    include = false
                end
                if include then
                    table.insert(seeds, { tool = tool, seedName = sn })
                end
            end
        end
    end
    -- Sort: preferred seed first, then alphabetical
    table.sort(seeds, function(a, b)
        if preferSeed then
            local aMatch = (a.seedName == preferSeed) and 1 or 0
            local bMatch = (b.seedName == preferSeed) and 1 or 0
            if aMatch ~= bMatch then return aMatch > bMatch end
        end
        return a.seedName < b.seedName
    end)
    return seeds
end

---------------------------------------------------------------
-- EQUIP SEED TOOL FROM BACKPACK
-- Uses Humanoid:EquipTool() — same as game's internal flow
-- Returns seedName, toolInstance on success
---------------------------------------------------------------

function Plant._equipSeed(preferSeed, skipMutated)
    local lp = Players.LocalPlayer
    local char = lp and lp.Character
    if not char then return nil, nil end
    local humanoid = char:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return nil, nil end

    -- Check if already equipped (and not Gold/Rainbow mutated if filter on)
    local sn, tool = Plant._getEquippedSeed()
    if sn then
        if skipMutated then
            if not Plant._isMutatedSeed(sn) then return sn, tool end
        else
            return sn, tool
        end
    end

    -- Find seed in backpack
    local seeds = Plant._findSeedsInBackpack(preferSeed, skipMutated)
    if #seeds == 0 then return nil, nil end

    -- Equip first seed (preferred or first available)
    local target = seeds[1]
    local ok = pcall(function()
        humanoid:EquipTool(target.tool)
    end)
    if not ok then return nil, nil end

    -- Wait for tool to appear in character
    local waited = 0
    while waited < 2 do
        task.wait(0.1)
        waited += 0.1
        local equipped = char:FindFirstChild(target.tool.Name)
        if equipped and equipped:IsA("Tool") and equipped:GetAttribute("SeedTool") then
            Plant._stats.equipped += 1
            return target.seedName, target.tool
        end
    end

    return nil, nil
end

---------------------------------------------------------------
-- UNEQUIP CURRENT TOOL (back to backpack)
---------------------------------------------------------------

function Plant._unequipTool()
    local lp = Players.LocalPlayer
    local char = lp and lp.Character
    if not char then return end
    local tool = char:FindFirstChildWhichIsA("Tool")
    if not tool then return end
    pcall(function()
        tool.Parent = lp:FindFirstChild("Backpack")
    end)
end

---------------------------------------------------------------
-- GET MY PLOT (matching decompiled GetPlayerPlot)
---------------------------------------------------------------

function Plant._getMyPlot()
    local lp = Players.LocalPlayer
    if not lp then return nil end
    local plotId = lp:GetAttribute("PlotId")
    if not plotId then return nil end
    return workspace:FindFirstChild("Gardens") and workspace.Gardens:FindFirstChild("Plot" .. tostring(plotId))
end

---------------------------------------------------------------
-- CHECK IF POSITION IS EMPTY (no existing plant within range)
-- Returns true if position is clear
---------------------------------------------------------------

function Plant._isPosEmpty(pos, myPlot, minDist)
    minDist = minDist or 2.5 -- minimum spacing between plants
    local plantsFolder = myPlot:FindFirstChild("Plants")
    if not plantsFolder then return true end
    for _, plantModel in ipairs(plantsFolder:GetChildren()) do
        local plantId = plantModel:GetAttribute("PlantId")
        if plantId then
            local root = plantModel.PrimaryPart or plantModel:FindFirstChildWhichIsA("BasePart")
            if root then
                local dist = (Vector2.new(root.Position.X, root.Position.Z) - Vector2.new(pos.X, pos.Z)).Magnitude
                if dist < minDist then
                    return false
                end
            end
        end
    end
    return true
end

---------------------------------------------------------------
-- GENERATE GRID POSITIONS FROM A PLANTAREA PART
-- Covers the entire part surface with evenly spaced points
-- spacing: studs between each grid point (default 3)
---------------------------------------------------------------

function Plant._generateGridFromPart(part, spacing)
    spacing = spacing or 3
    local positions = {}
    local size = part.Size
    local cf = part.CFrame

    -- Calculate grid steps in local X and Z axes
    local halfX = size.X / 2
    local halfZ = size.Z / 2
    local stepsX = math.max(1, math.floor(size.X / spacing))
    local stepsZ = math.max(1, math.floor(size.Z / spacing))

    -- Generate evenly spaced points across the part surface
    for ix = 0, stepsX do
        for iz = 0, stepsZ do
            -- Map to local coordinates: -halfX to +halfX
            local localX = -halfX + (ix / stepsX) * size.X
            local localZ = -halfZ + (iz / stepsZ) * size.Z
            -- Transform to world position (use top surface Y)
            local worldPos = cf * Vector3.new(localX, size.Y / 2, localZ)
            table.insert(positions, worldPos)
        end
    end
    return positions
end

---------------------------------------------------------------
-- FIND ALL EMPTY PLANT POSITIONS
-- 1. Get all PlantArea parts in my plot
-- 2. Generate grid across each part's surface
-- 3. Filter out positions too close to existing plants
-- Returns sorted list of empty world positions
---------------------------------------------------------------

function Plant._findEmptySpots(myPlot, spacing, sortMode)
    spacing = spacing or 3

    -- Collect all PlantArea parts belonging to my plot
    local plantAreaParts = {}
    for _, part in ipairs(CollectionService:GetTagged("PlantArea")) do
        if part:IsA("BasePart") and part:IsDescendantOf(myPlot) then
            table.insert(plantAreaParts, part)
        end
    end

    -- Also check for PlantArea tagged via attribute (some plots use this)
    for _, desc in ipairs(myPlot:GetDescendants()) do
        if desc:IsA("BasePart") and desc:GetAttribute("PlantArea") then
            if not table.find(plantAreaParts, desc) then
                table.insert(plantAreaParts, desc)
            end
        end
    end

    if #plantAreaParts == 0 then
        -- Fallback: use GardenTotalArea if no PlantArea found
        for _, part in ipairs(CollectionService:GetTagged("GardenTotalArea")) do
            if part:IsA("BasePart") and part:IsDescendantOf(myPlot) then
                table.insert(plantAreaParts, part)
            end
        end
    end

    -- Generate grid positions across all parts
    local allPositions = {}
    for _, part in ipairs(plantAreaParts) do
        local grid = Plant._generateGridFromPart(part, spacing)
        for _, pos in ipairs(grid) do
            table.insert(allPositions, pos)
        end
    end

    -- Filter: only keep empty positions
    local emptySpots = {}
    for _, pos in ipairs(allPositions) do
        if Plant._isPosEmpty(pos, myPlot) then
            table.insert(emptySpots, pos)
        end
    end

    -- Sort based on mode
    sortMode = sortMode or "Top"
    if sortMode == "Top" then
        table.sort(emptySpots, function(a, b) return a.Y > b.Y end)
    elseif sortMode == "Bottom" then
        table.sort(emptySpots, function(a, b) return a.Y < b.Y end)
    else -- Random
        for i = #emptySpots, 2, -1 do
            local j = math.random(1, i)
            emptySpots[i], emptySpots[j] = emptySpots[j], emptySpots[i]
        end
    end

    return emptySpots
end

---------------------------------------------------------------
-- START
---------------------------------------------------------------

function Plant.start(config, Net, Utils)
    if Plant._running then return end
    Plant._running = true

    local interval = config.Timings.PlantInterval or 5
    local plantConfig = config.Plant or {}

    Plant._thread = task.spawn(function()
        while Plant._running do
            Plant._autoPlant(plantConfig, Net, Utils)
            task.wait(interval)
        end
    end)

    print("[GAG Hub] Auto-Plant started")
end

---------------------------------------------------------------
-- AUTO PLANT LOGIC
-- Flow: equip seed from backpack → fill all empty spots → unequip
---------------------------------------------------------------

function Plant._autoPlant(plantConfig, Net, Utils)
    Plant._stats.scans += 1

    local preferSeed = plantConfig.PreferSeed -- optional: preferred seed name

    -- Step 1: USE SEED — equip from backpack before planting
    local seedName, toolInstance = Plant._equipSeed(preferSeed, plantConfig.BlacklistMutated)
    if not seedName then
        Plant._stats.noSeeds += 1
        return
    end

    -- Step 2: Get plot
    local myPlot = Plant._getMyPlot()
    if not myPlot then
        Plant._unequipTool()
        return
    end

    -- Step 3: Find empty spots — grid scan across all PlantArea parts
    local spacing = plantConfig.GridSpacing or 3
    local sortMode = plantConfig.PlantOrder or "Top"
    local spots = Plant._findEmptySpots(myPlot, spacing, sortMode)
    if #spots == 0 then
        Plant._unequipTool()
        return
    end

    print("[GAG Hub] Found", #spots, "empty spots in plot")

    -- Step 4: Plant in ALL empty spots (fill the entire plot)
    local planted = 0
    for _, pos in ipairs(spots) do
        if not Plant._running then break end

        -- Verify still equipped before each fire
        local curSn, curTool = Plant._getEquippedSeed()
        if not curSn then
            -- Re-equip if tool got consumed
            seedName, toolInstance = Plant._equipSeed(preferSeed, plantConfig.BlacklistMutated)
            if not seedName then break end
        end

        local ok = pcall(function()
            Net.fire("Plant.PlantSeed", pos, seedName, toolInstance)
        end)

        if ok then
            planted += 1
            Plant._stats.planted += 1
            print("[GAG Hub] Planted:", seedName, "at", tostring(pos))
        else
            Plant._stats.errors += 1
        end

        task.wait(0.3) -- small delay between plants
    end

    -- Step 5: Unequip after planting
    Plant._unequipTool()

    if planted > 0 then
        print("[GAG Hub] Auto-Plant cycle: planted", planted, seedName)
    end
end

---------------------------------------------------------------
-- STOP / STATUS
---------------------------------------------------------------

function Plant.stop()
    Plant._running = false
    for _, conn in ipairs(Plant._connections) do
        pcall(function() conn:Disconnect() end)
    end
    Plant._connections = {}
end

function Plant.getStats()
    return Plant._stats
end

end

---------------------------------------------------------------
-- MODULE: RESTOCK SNIPER
---------------------------------------------------------------

Modules.RestockSniper = {}
do
    local M = Modules.RestockSniper
    local Restock = M
Restock._running = false
Restock._thread  = nil
Restock._connections = {}
Restock._stats = { bought = 0, scanned = 0, moneySpent = 0, errors = 0, skipped = 0 }

-- Seed prices loaded from Resources (resources.lua via loadstring)
local SeedPrices = Resources.SeedPrices or {}

---------------------------------------------------------------
-- GET STOCK VALUES
---------------------------------------------------------------

function Restock._getStockFolder()
    local ok, folder = pcall(function()
        return game:GetService("ReplicatedStorage")
            :WaitForChild("StockValues", 5)
            :WaitForChild("SeedShop", 5)
            :WaitForChild("Items", 5)
    end)
    return ok and folder or nil
end

function Restock._getStock(seedName)
    local folder = Restock._getStockFolder()
    if not folder then return -1 end -- unknown
    local val = folder:FindFirstChild(seedName)
    if not val then return 0 end
    if val:IsA("ValueBase") then return (val.Value or 0) end
    -- might be a NumberValue / IntValue directly
    return 0
end

function Restock._getRestockTime()
    local ok, val = pcall(function()
        local unix = game:GetService("ReplicatedStorage")
            :WaitForChild("StockValues", 5)
            :WaitForChild("SeedShop", 5)
            :WaitForChild("UnixNextRestock", 5)
        return unix.Value or 0
    end)
    return ok and val or 0
end

---------------------------------------------------------------
-- START
---------------------------------------------------------------

function Restock.start(config, Net, Utils)
    if Restock._running then return end
    Restock._running = true

    local interval = config.Timings.RestockPollInterval or 1
    local restockConfig = config.Restock or {}

    Restock._thread = task.spawn(function()
        while Restock._running do
            Restock._pollAndBuy(restockConfig, Net, Utils)
            task.wait(interval)
        end
    end)

    print("[GAG Hub] Restock Sniper started (targets: " ..
        #(restockConfig.TargetSeeds or {}) .. " seeds)")
end

---------------------------------------------------------------
-- POLL AND BUY — DRAIN STOCK
-- For each target seed: buy in loop until stock == 0
---------------------------------------------------------------

function Restock._pollAndBuy(restockConfig, Net, Utils)
    Restock._stats.scanned += 1

    local targets = restockConfig.TargetSeeds or {}
    if #targets == 0 then return end

    local blacklist = {}
    for _, name in ipairs(restockConfig.BlacklistedSeeds or {}) do
        blacklist[name] = true
    end

    for _, seedName in ipairs(targets) do
        if not Restock._running then break end
        if blacklist[seedName] then continue end

        -- Affordability check
        local price = SeedPrices[seedName] or 0
        local sheckles = Utils.getSheckles()
        if price > 0 and sheckles < price then
            Restock._stats.skipped += 1
            continue -- can't afford
        end

        local stock = Restock._getStock(seedName)
        if stock == 0 then
            Restock._stats.skipped += 1
            continue -- out of stock
        end

        -- DRAIN: buy in loop until stock empty
        local buyCount = 0
        local maxBuys = (stock > 0 and stock) or 50 -- stock=-1 unknown, try 50
        for i = 1, maxBuys do
            if not Restock._running then break end

            -- Re-check affordability inside loop
            if price > 0 and Utils.getSheckles() < price then break end

            local prevStock = Restock._getStock(seedName)
            Restock._buySeed(Net, seedName)
            task.wait(0.15) -- wait for server to update stock
            local newStock = Restock._getStock(seedName)

            if newStock < prevStock then
                buyCount += 1
                Restock._stats.bought += 1
                Restock._stats.moneySpent += price
            else
                break -- stock didn't change, buy failed
            end
        end

        if buyCount > 0 then
            print("[GAG Hub] Drained:", seedName, "x" .. buyCount, "(stock was:", stock .. ")")
        end
    end
end

---------------------------------------------------------------
-- BUY SEED (actual remote) — returns ok, price
---------------------------------------------------------------

function Restock._buySeed(Net, seedName)
    local ok, err = pcall(function()
        Net.fire("SeedShop.PurchaseSeed", seedName)
    end)
    if ok then
        return true, 0
    end
    Restock._stats.errors += 1
    return false, 0
end

---------------------------------------------------------------
-- STOP / STATUS
---------------------------------------------------------------

function Restock.stop()
    Restock._running = false
    Restock._thread = nil
    for _, conn in ipairs(Restock._connections) do
        pcall(function() conn:Disconnect() end)
    end
    Restock._connections = {}
end

function Restock.getStats()
    return Restock._stats
end
end

---------------------------------------------------------------
-- MODULE: MUTATION TRACKER
---------------------------------------------------------------

Modules.MutationTracker = {}
do
    local M = Modules.MutationTracker
    local Mutation = M
Mutation._running = false
Mutation._thread  = nil
Mutation._connections = {}
Mutation._stats = { tracked = 0, alerts = 0, totalValue = 0 }
Mutation._mutationLog = {}

---------------------------------------------------------------
-- START
---------------------------------------------------------------

function Mutation.start(config, Net, Utils)
    if Mutation._running then return end
    Mutation._running = true

    local interval = config.Timings.MutationScanInterval or 3
    local mutConfig = config.Mutation or {}

    -- Load mutation data for price multipliers
    local RS = game:GetService("ReplicatedStorage")
    local mutationData = {}
    pcall(function()
        local shared = RS:WaitForChild("SharedModules", 10)
        if shared then
            local mData = shared:FindFirstChild("MutationData")
            if mData then
                mutationData = require(mData)
            end
        end
    end)

    -- Listen for real-time mutation events
    local plantMutConn = Net.on("Garden.PlantMutationUpdated",
        function(plantId, mutation)
            Mutation._onMutation("plant", plantId, mutation, mutConfig, Utils)
        end
    )
    if plantMutConn then
        table.insert(Mutation._connections, plantMutConn)
    end

    local fruitMutConn = Net.on("Garden.FruitMutationUpdated",
        function(plantId, fruitId, mutation)
            Mutation._onMutation("fruit", plantId, mutation, mutConfig, Utils)
        end
    )
    if fruitMutConn then
        table.insert(Mutation._connections, fruitMutConn)
    end

    -- Also listen for plant growth (sometimes mutation comes with growth update)
    local growthConn = Net.on("Garden.PlantGrowthUpdated",
        function(plantId, growth, size, mutation)
            if mutation and mutation ~= "" then
                Mutation._onMutation("growth", plantId, mutation, mutConfig, Utils)
            end
        end
    )
    if growthConn then
        table.insert(Mutation._connections, growthConn)
    end

    -- Periodic scan of own garden
    Mutation._thread = task.spawn(function()
        while Mutation._running do
            Mutation._scanGarden(mutConfig, Utils)
            task.wait(interval)
        end
    end)

    print("[GAG Hub] Mutation Tracker started")
end

---------------------------------------------------------------
-- ON MUTATION EVENT
---------------------------------------------------------------

function Mutation._onMutation(source, plantId, mutation, config, Utils)
    if not mutation or mutation == "" then return end

    Mutation._stats.tracked += 1

    local entry = {
        source   = source,
        plantId  = plantId,
        mutation = mutation,
        time     = os.time(),
        priceMult = config.PriceMultipliers[mutation] or 1,
    }

    table.insert(Mutation._mutationLog, entry)

    -- Keep log manageable
    if #Mutation._mutationLog > 500 then
        table.remove(Mutation._mutationLog, 1)
    end

    -- Check if this is an alert-worthy mutation
    local isAlert = false
    if config.TrackAll then
        isAlert = true
    else
        for _, name in ipairs(config.AlertMutations or {}) do
            if name == mutation then
                isAlert = true
                break
            end
        end
    end

    if isAlert then
        Mutation._stats.alerts += 1
        local mult = config.PriceMultipliers[mutation] or 1

        local msg = string.format("[%s] %s mutation: %s (x%d value)",
            source, tostring(plantId), mutation, mult)

        if config.LogToConsole then
            print("[GAG Hub] 🧬 " .. msg)
        end

        Config.Notify("🧬 Mutation Detected!", msg, 8)

        -- Play sound if available
        pcall(function()
            local SoundService = game:GetService("SoundService")
            local sound = Instance.new("Sound")
            sound.SoundId = "rbxassetid://6518811702" -- notification sound
            sound.Volume = 0.5
            sound.Parent = SoundService
            sound:Play()
            game:GetService("Debris"):AddItem(sound, 3)
        end)
    end
end

---------------------------------------------------------------
-- SCAN GARDEN FOR EXISTING MUTATIONS
---------------------------------------------------------------

function Mutation._scanGarden(config, Utils)
    local garden = Utils.getMyGarden()
    if not garden then return end

    local plants = Utils.getPlantsInGarden(garden)
    for _, plant in ipairs(plants) do
        local info = Utils.getPlantInfo(plant)
        if info and info.Mutation and info.Mutation ~= "" then
            -- Already tracked mutations are skipped
            -- This is mainly for initial discovery
            Mutation._stats.tracked += 1
        end
    end
end

---------------------------------------------------------------
-- GET MUTATION PRICE MULTIPLIER
---------------------------------------------------------------

function Mutation.getPriceMultiplier(mutationName, config)
    if config and config.PriceMultipliers then
        return config.PriceMultipliers[mutationName] or 1
    end
    return 1
end

---------------------------------------------------------------
-- GET MUTATION LOG
---------------------------------------------------------------

function Mutation.getLog()
    return Mutation._mutationLog
end

function Mutation.getLogByMutation(mutationName)
    local filtered = {}
    for _, entry in ipairs(Mutation._mutationLog) do
        if entry.mutation == mutationName then
            table.insert(filtered, entry)
        end
    end
    return filtered
end

---------------------------------------------------------------
-- STOP / STATUS
---------------------------------------------------------------

function Mutation.stop()
    Mutation._running = false
    for _, conn in ipairs(Mutation._connections) do
        pcall(function() conn:Disconnect() end)
    end
    Mutation._connections = {}
end

function Mutation.getStats()
    return Mutation._stats
end

end

---------------------------------------------------------------
-- MODULE: WEATHER BOT
---------------------------------------------------------------

Modules.WeatherBot = {}
do
    local M = Modules.WeatherBot
    local Weather = M
Weather._running = false
Weather._thread  = nil
Weather._connections = {}
Weather._stats = { events = 0, alerts = 0, scans = 0 }
Weather._currentWeather = "Unknown"
Weather._currentPhase   = "Unknown"
Weather._weatherLog = {}

---------------------------------------------------------------
-- WEATHER TYPES (from decompiled TimeCycleController)
---------------------------------------------------------------

Weather.Phases = {
    Day         = { color = "☀️", value = "Day" },
    Sunset      = { color = "🌅", value = "Sunset" },
    Moon        = { color = "🌙", value = "Moon" },
    Bloodmoon   = { color = "🔴", value = "Bloodmoon", rare = true },
    Goldmoon    = { color = "🟡", value = "Goldmoon", rare = true },
    Rainbow     = { color = "🌈", value = "Rainbow", rare = true },
    Chained     = { color = "⛓️", value = "Chained Moon", rare = true },
    Pizza       = { color = "🍕", value = "Pizza Moon" },
}

---------------------------------------------------------------
-- START
---------------------------------------------------------------

function Weather.start(config, Net, Utils)
    if Weather._running then return end
    Weather._running = true

    local interval = config.Timings.WeatherPollInterval or 5
    local weatherConfig = config.Weather or {}

    -- Listen for weather effect events
    local weatherEvents = {
        "WeatherEffects.BloodmoonBeam",
        "WeatherEffects.RainbowStart",
        "WeatherEffects.RainbowEnd",
        "WeatherEffects.GoldMoonStrike",
        "WeatherEffects.RainbowMoonStrike",
        "WeatherEffects.BlizzardStart",
        "WeatherEffects.BlizzardEnd",
        "WeatherEffects.ShootingStar",
        "WeatherEffects.ChainPull",
    }

    for _, eventPath in ipairs(weatherEvents) do
        local conn = Net.on(eventPath, function(...)
            Weather._onWeatherEvent(eventPath, weatherConfig, Utils, ...)
        end)
        if conn then
            table.insert(Weather._connections, conn)
        end
    end

    -- Listen for time cycle changes
    local RS = game:GetService("ReplicatedStorage")
    local nightValue = RS:FindFirstChild("Night")
    if nightValue then
        local conn = nightValue.Changed:Connect(function(isNight)
            if isNight then
                Weather._currentPhase = "Night"
                Weather._logEvent("Night", "Night cycle started")
            else
                Weather._currentPhase = "Day"
                Weather._logEvent("Day", "Day cycle started")
            end
        end)
        table.insert(Weather._connections, conn)
    end

    -- Periodic scan of weather state
    Weather._thread = task.spawn(function()
        while Weather._running do
            Weather._scanWeather(weatherConfig, Utils)
            task.wait(interval)
        end
    end)

    print("[GAG Hub] Weather Bot started")
end

---------------------------------------------------------------
-- ON WEATHER EVENT
---------------------------------------------------------------

function Weather._onWeatherEvent(eventPath, config, Utils, ...)
    local args = {...}
    Weather._stats.events += 1

    -- Extract weather type from event path
    local weatherType = eventPath:match("WeatherEffects%.(.+)")
    if not weatherType then return end

    -- Determine if this is an alert-worthy event
    local isSpecial = false
    for _, name in ipairs(config.AlertEvents or {}) do
        if weatherType:match(name) then
            isSpecial = true
            break
        end
    end

    -- Alert for all start events
    if weatherType:match("Start") or weatherType:match("Strike") or
       weatherType:match("Beam") or weatherType:match("Star") then
        isSpecial = true
    end

    if isSpecial then
        Weather._stats.alerts += 1
        local emoji = "🌤️"
        for _, phase in pairs(Weather.Phases) do
            if weatherType:match(phase.value) then
                emoji = phase.color
                break
            end
        end

        local msg = emoji .. " " .. weatherType .. " event detected!"
        print("[GAG Hub] " .. msg)
        Config.Notify("Weather Event!", msg, 10)

        -- Execute configured action
        local action = config.Actions and config.Actions[weatherType]
        if action == "harvest_priority" then
            print("[GAG Hub] Priority harvest triggered by weather event")
        end

        -- Play sound
        if config.PlaySound then
            pcall(function()
                local SoundService = game:GetService("SoundService")
                local sound = Instance.new("Sound")
                sound.SoundId = "rbxassetid://6518811702"
                sound.Volume = 0.8
                sound.Parent = SoundService
                sound:Play()
                game:GetService("Debris"):AddItem(sound, 3)
            end)
        end
    end

    Weather._logEvent(weatherType, "Weather event fired")
end

---------------------------------------------------------------
-- SCAN WEATHER STATE
---------------------------------------------------------------

function Weather._scanWeather(config, Utils)
    Weather._stats.scans += 1

    -- Check moon phase from workspace or ReplicatedStorage
    local RS = game:GetService("ReplicatedStorage")

    -- Check if night
    local isNight = Utils.isNight()

    -- Try to read current moon phase
    local moonPhase = nil
    pcall(function()
        local lighting = game:GetService("Lighting")
        -- Some games store weather in lighting attributes
        moonPhase = lighting:GetAttribute("MoonPhase")
            or lighting:GetAttribute("CurrentPhase")
    end)

    -- Check workspace for weather indicators
    pcall(function()
        local weatherFolder = workspace:FindFirstChild("Weather")
            or workspace:FindFirstChild("WeatherEffects")
        if weatherFolder then
            for _, child in ipairs(weatherFolder:GetChildren()) do
                if child:IsA("BoolValue") and child.Value then
                    Weather._currentWeather = child.Name
                end
            end
        end
    end)

    -- Update phase
    if isNight and Weather._currentPhase == "Day" then
        Weather._currentPhase = "Night"
        Weather._logEvent("Phase", "Transition to Night")
    elseif not isNight and Weather._currentPhase ~= "Day" then
        Weather._currentPhase = "Day"
        Weather._logEvent("Phase", "Transition to Day")
    end
end

---------------------------------------------------------------
-- LOG
---------------------------------------------------------------

function Weather._logEvent(eventType, description)
    table.insert(Weather._weatherLog, {
        type = eventType,
        desc = description,
        time = os.time(),
        phase = Weather._currentPhase,
    })
    if #Weather._weatherLog > 200 then
        table.remove(Weather._weatherLog, 1)
    end
end

---------------------------------------------------------------
-- GETTERS
---------------------------------------------------------------

function Weather.getCurrentWeather()
    return Weather._currentWeather
end

function Weather.getCurrentPhase()
    return Weather._currentPhase
end

function Weather.getLog()
    return Weather._weatherLog
end

---------------------------------------------------------------
-- STOP / STATUS
---------------------------------------------------------------

function Weather.stop()
    Weather._running = false
    for _, conn in ipairs(Weather._connections) do
        pcall(function() conn:Disconnect() end)
    end
    Weather._connections = {}
end

function Weather.getStats()
    return Weather._stats
end

end

---------------------------------------------------------------
-- MODULE: STEAL BOT
---------------------------------------------------------------

Modules.StealBot = {}
do
    local M = Modules.StealBot
    local Steal = M
    local Players = game:GetService("Players")
    Steal._running = false
    Steal._thread  = nil
    Steal._connections = {}
    Steal._stats = { attempts = 0, stolen = 0, returned = 0, errors = 0, nightCycles = 0, skipped = 0 }

    ---------------------------------------------------------------
    -- GET MY PLOT ID
    ---------------------------------------------------------------

    function Steal._getMyPlotId()
        local lp = Players.LocalPlayer
        return lp and lp:GetAttribute("PlotId")
    end

    ---------------------------------------------------------------
    -- CHECK IF GARDEN IS UNLOCKED (owner left plot)
    -- Checks: attribute Locked, BoolValue Locked, owner proximity
    -- Returns true if garden is STEALABLE (unlocked)
    ---------------------------------------------------------------

    function Steal._isGardenUnlocked(garden)
        -- Check: owner player inside plot → locked
        local ownerUserId = garden:GetAttribute("OwnerUserId")
            or garden:GetAttribute("Owner")
        if ownerUserId then
            ownerUserId = tonumber(ownerUserId)
            if ownerUserId then
                local Players = game:GetService("Players")
                local owner = Players:GetPlayerByUserId(ownerUserId)
                if owner and owner.Character then
                    local ownerHRP = owner.Character:FindFirstChild("HumanoidRootPart")
                    if ownerHRP then
                        -- Check if owner position is inside any PlantArea part
                        for _, part in ipairs(garden:GetDescendants()) do
                            if part:IsA("BasePart") then
                                local relPos = part.CFrame:PointToObjectSpace(ownerHRP.Position)
                                local halfSize = part.Size / 2
                                if math.abs(relPos.X) <= halfSize.X
                                    and math.abs(relPos.Y) <= halfSize.Y + 10
                                    and math.abs(relPos.Z) <= halfSize.Z then
                                    return false -- owner inside plot boundary → locked
                                end
                            end
                        end
                    end
                end
            end
        end

        return true -- owner not found or not in plot → unlocked → stealable
    end

    ---------------------------------------------------------------
    -- FIND STEALABLE PROMPTS ON OTHER PLAYERS' GARDENS
    -- Matching decompiled u87 guard logic:
    --   gate: Night.Value == true
    --   prompt.Enabled == true
    --   prompt:GetAttribute("Collected") != true
    --   StealPrompt + HoldDuration > 0 → SKIP (Bamboo)
    --   garden must be UNLOCKED (owner left plot)
    --   get PlantId/FruitId from parent fruit Model
    ---------------------------------------------------------------

    function Steal._findStealablePrompts(myPlotId)
        local results = {}
        local gardens = workspace:FindFirstChild("Gardens")
        if not gardens then return results end

        for _, garden in ipairs(gardens:GetChildren()) do
            local plotNum = tonumber(garden.Name:match("Plot(%d+)"))
            if plotNum and plotNum ~= myPlotId then
                -- Gate: only steal from unlocked gardens
                if not Steal._isGardenUnlocked(garden) then continue end

                local plantsFolder = garden:FindFirstChild("Plants")
                if plantsFolder then
                    for _, plantModel in ipairs(plantsFolder:GetChildren()) do
                        local fruitsFolder = plantModel:FindFirstChild("Fruits")
                        if fruitsFolder then
                            for _, fruitModel in ipairs(fruitsFolder:GetChildren()) do
                                local prompt = fruitModel:FindFirstChild("StealPrompt", true)
                                if not prompt then continue end
                                if not prompt:IsA("ProximityPrompt") then continue end

                                -- Guard: must be enabled, not already collected
                                if not prompt.Enabled then continue end
                                if prompt:GetAttribute("Collected") then continue end

                                -- Guard: Bamboo has HoldDuration > 0, can't steal
                                if prompt.HoldDuration > 0 then continue end

                                -- Read attrs from fruit MODEL (not prompt)
                                local userId = tonumber(fruitModel:GetAttribute("UserId"))
                                local plantId = fruitModel:GetAttribute("PlantId")
                                local fruitId = fruitModel:GetAttribute("FruitId")

                                if userId and plantId then
                                    table.insert(results, {
                                        prompt   = prompt,
                                        userId   = userId,
                                        plantId  = plantId,
                                        fruitId  = fruitId or "",
                                        gardenName = garden.Name,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
        return results
    end

    ---------------------------------------------------------------
    -- START
    ---------------------------------------------------------------

    function Steal.start(config, Net, Utils)
        if Steal._running then return end
        Steal._running = true

        local interval = config.Timings.StealInterval or 1.5
        local stealConfig = config.Steal or {}

        -- Listen for server steal confirmation events
        local startedConn = Net.on("Steal.StealStarted", function(fruitInstance)
            print("[GAG Hub] StealStarted confirmed by server:", fruitInstance and fruitInstance.Name or "?")
        end)
        local cancelledConn = Net.on("Steal.StealCancelled", function(fruitInstance)
            print("[GAG Hub] StealCancelled by server:", fruitInstance and fruitInstance.Name or "?")
        end)
        if startedConn then table.insert(Steal._connections, startedConn) end
        if cancelledConn then table.insert(Steal._connections, cancelledConn) end

        Steal._thread = task.spawn(function()
            local wasNight = false
            while Steal._running do
                local isNight = Utils.isNight()
                if isNight and not wasNight then
                    Steal._stats.nightCycles += 1
                    Steal._stats.attempts = 0 -- reset per night
                    print("[GAG Hub] 🌙 Night cycle started - Steal Bot active")
                end
                if isNight then
                    Steal._stealLoop(stealConfig, Net, Utils)
                elseif wasNight then
                    print("[GAG Hub] ☀️ Day started - Steal Bot sleeping")
                    pcall(function() Net.fire("Steal.CancelSteal") end)
                end
                wasNight = isNight
                task.wait(interval)
            end
        end)

        print("[GAG Hub] Steal Bot started (waits for night)")
    end

    ---------------------------------------------------------------
    -- STEAL LOOP
    ---------------------------------------------------------------

    function Steal._stealLoop(stealConfig, Net, Utils)
        local LP = Players.LocalPlayer

        -- If already carrying → return to plot first
        local carrying = LP:GetAttribute("CarryingStolenFruit")
        if carrying then
            Steal._returnFruit(Net, Utils)
            return
        end

        -- Max attempts guard
        local maxAttempts = stealConfig.MaxAttemptsPerNight or 20
        if Steal._stats.attempts >= maxAttempts then return end

        local myPlotId = Steal._getMyPlotId()
        if not myPlotId then return end

        local entries = Steal._findStealablePrompts(myPlotId)
        if #entries == 0 then return end

        -- Sort by value descending (high value first)
        local minValue = stealConfig.MinFruitValue or 0
        table.sort(entries, function(a, b)
            return (Steal._estimateValue(a.plantId) or 0) > (Steal._estimateValue(b.plantId) or 0)
        end)

        for _, entry in ipairs(entries) do
            if not Steal._running then break end
            if Steal._stats.attempts >= maxAttempts then break end

            -- Value filter
            local sellValue = Steal._estimateValue(entry.plantId)
            if minValue > 0 and sellValue < minValue then
                Steal._stats.skipped += 1
                continue
            end

            -- Teleport to fruit → fire prompt → teleport back
            local success = Steal._attemptSteal(entry, Net, Utils)
            if success then
                Steal._stats.stolen += 1
                print("[GAG Hub] Stolen from", entry.gardenName, "plant:", entry.plantId, "value:", sellValue)
                return
            end

            task.wait(0.5)
        end
    end

    ---------------------------------------------------------------
    -- ATTEMPT STEAL (teleport flow)
    -- 1. Get HRP + save old CFrame
    -- 2. Teleport to fruit position (near prompt)
    -- 3. Fire proximity prompt (HoldDuration=0)
    -- 4. Wait for CarryingStolenFruit
    -- 5. Teleport back to own plot
    ---------------------------------------------------------------

    function Steal._attemptSteal(entry, Net, Utils)
        local prompt = entry.prompt
        if not prompt or not prompt.Parent then return false end
        if not prompt.Enabled then return false end
        if prompt:GetAttribute("Collected") then return false end

        Steal._stats.attempts += 1

        local hrp = Utils.getHumanoidRootPart()
        if not hrp then return false end

        -- Save position
        local savedCFrame = hrp.CFrame

        -- Get fruit position (parent of prompt)
        local fruitPart = prompt.Parent
        if not fruitPart or not fruitPart:IsA("BasePart") then
            -- Try finding a BasePart in the fruit model
            fruitPart = prompt.Parent and prompt.Parent:FindFirstChildWhichIsA("BasePart")
        end
        if not fruitPart then return false end

        -- Step 1: Teleport to fruit
        pcall(function()
            hrp.CFrame = fruitPart.CFrame + Vector3.new(0, 3, 0)
        end)
        task.wait(0.8) -- wait for server to register position

        -- Step 2: Fire proximity prompt
        local triggered = false
        pcall(function()
            if fireproximityprompt then
                fireproximityprompt(prompt)
                triggered = true
            else
                -- Fallback: InputHoldBegin/End
                prompt:InputHoldBegin()
                task.wait(math.max(0.09, prompt.HoldDuration + 0.1))
                if prompt and prompt:IsDescendantOf(workspace) then
                    prompt:InputHoldEnd()
                end
                triggered = true
            end
        end)

        if not triggered then
            -- Restore position on failure
            pcall(function() hrp.CFrame = savedCFrame end)
            return false
        end

        -- Step 3: Wait for server to confirm carrying
        task.wait(0.5)
        local carrying = Players.LocalPlayer:GetAttribute("CarryingStolenFruit")

        -- Step 4: Teleport back to own plot (base)
        local garden = Utils.getMyGarden()
        if garden then
            local spawnPoint = garden:FindFirstChild("SpawnPoint") or garden:FindFirstChildWhichIsA("BasePart")
            if spawnPoint then
                pcall(function()
                    hrp.CFrame = spawnPoint.CFrame + Vector3.new(0, 3, 0)
                end)
            end
        else
            -- Fallback: restore old position
            pcall(function() hrp.CFrame = savedCFrame end)
        end

        if carrying then
            Steal._stats.returned += 1
            print("[GAG Hub] Stolen + returned to base")
        end

        return carrying and true or false
    end

    ---------------------------------------------------------------
    -- RETURN FRUIT TO OWN PLOT
    ---------------------------------------------------------------

    function Steal._returnFruit(Net, Utils)
        local LP = Players.LocalPlayer
        local carrying = LP:GetAttribute("CarryingStolenFruit")
        if not carrying then return end
        local garden = Utils.getMyGarden()
        if not garden then return end
        local hrp = Utils.getHumanoidRootPart()
        local spawnPoint = garden:FindFirstChild("SpawnPoint") or garden:FindFirstChildWhichIsA("BasePart")
        if hrp and spawnPoint then
            hrp.CFrame = spawnPoint.CFrame + Vector3.new(0, 3, 0)
            task.wait(1)
        end
        Steal._stats.returned += 1
        print("[GAG Hub] Returned stolen fruit to plot")
    end

    ---------------------------------------------------------------
    -- ESTIMATE FRUIT VALUE
    ---------------------------------------------------------------

    function Steal._estimateValue(seedName)
        local values = {
            ["Carrot"] = 5, ["Strawberry"] = 3, ["Blueberry"] = 5,
            ["Tomato"] = 9, ["Apple"] = 12, ["Cactus"] = 40,
            ["Pineapple"] = 30, ["Banana"] = 35, ["Corn"] = 34,
            ["Grape"] = 45, ["Mango"] = 90, ["Coconut"] = 60,
            ["Cherry"] = 350, ["Pomegranate"] = 900,
            ["Dragon Fruit"] = 150, ["Mushroom"] = 13000,
            ["Sunflower"] = 1750, ["Venus Fly Trap"] = 3000,
            ["Moon Bloom"] = 9000, ["Dragon's Breath"] = 3400,
            ["Ghost Pepper"] = 2500, ["Lotus"] = 6500,
        }
        return values[seedName] or 0
    end

    ---------------------------------------------------------------
    -- STOP / STATUS
    ---------------------------------------------------------------

    function Steal.stop()
        Steal._running = false
        for _, conn in ipairs(Steal._connections) do
            pcall(function() conn:Disconnect() end)
        end
        Steal._connections = {}
    end

    function Steal.getStats()
        return Steal._stats
    end
end

---------------------------------------------------------------
-- MODULE: AUTO BUY PET (Egg Hatch + Rarity Filter)
-- Reference: Controllers_EggHandleController, EggOpenController
-- Remotes: Egg.OpenEgg(eggName), Egg.ConfirmEgg(eggName, petName, size)
--          SellPet(petId)
-- Data: SharedModules.EggData, SharedData.PetData
---------------------------------------------------------------

Modules.AutoBuyPet = {}
do
    local M = Modules.AutoBuyPet
    local Pet = M
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
Pet._running = false
Pet._thread  = nil
Pet._connections = {}
Pet._stats = { hatched = 0, kept = 0, sold = 0, errors = 0, noEggs = 0 }

-- Rarity priority (lower = more common)
local RARITY_ORDER = {
    Common = 1, Uncommon = 2, Rare = 3,
    Legendary = 4, Epic = 4, Mythic = 5, Super = 6,
}

-- Load PetData for species rarity lookup
local PetData = nil
pcall(function()
    PetData = require(ReplicatedStorage:WaitForChild("SharedData"):WaitForChild("PetData"))
end)

-- Get rarity of a pet species from PetData
function Pet._getSpeciesRarity(petName)
    if PetData and PetData[petName] then
        return PetData[petName].Rarity or "Common"
    end
    return "Common"
end

-- Check if a pet passes the rarity filter
function Pet._passesFilter(petName, size, minRarity)
    local speciesRarity = Pet._getSpeciesRarity(petName)
    local gotRank = RARITY_ORDER[speciesRarity] or 1
    local wantRank = RARITY_ORDER[minRarity] or 1
    if gotRank < wantRank then return false end
    -- Also check size filter (Huge always passes)
    if size == "Huge" then return true end
    return true
end

---------------------------------------------------------------
-- FIND EGG TOOLS IN BACKPACK
-- Tools with "Egg" attribute = egg name
---------------------------------------------------------------

function Pet._findEggTools()
    local lp = Players.LocalPlayer
    local backpack = lp and lp:FindFirstChild("Backpack")
    if not backpack then return {} end
    local eggs = {}
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") then
            local eggName = tool:GetAttribute("Egg")
            if eggName and eggName ~= "" then
                table.insert(eggs, { tool = tool, eggName = eggName })
            end
        end
    end
    return eggs
end

---------------------------------------------------------------
-- HATCH ONE EGG
-- 1. Listen for ReplicateOpenEgg once
-- 2. Fire Egg.OpenEgg(eggName)
-- 3. Wait for result (petName, size, type)
-- 4. Fire Egg.ConfirmEgg(eggName, petName, size)
---------------------------------------------------------------

function Pet._hatchEgg(eggName, Net)
    local result = nil
    local done = false

    -- Hook ReplicateOpenEgg once
    local conn
    conn = Net.on("Egg.ReplicateOpenEgg", function(player, eName, petName, size, pos, petType, extra)
        if player == Players.LocalPlayer and eName == eggName then
            result = { petName = petName, size = size, petType = petType }
            done = true
            if conn then conn:Disconnect() end
        end
    end)

    -- Fire OpenEgg
    local fireOk = pcall(function()
        Net.fire("Egg.OpenEgg", eggName)
    end)

    if not fireOk then
        if conn then conn:Disconnect() end
        return nil
    end

    -- Wait for result (max 5s)
    local t = 0
    while not done and t < 5 do
        task.wait(0.1)
        t = t + 0.1
    end

    if conn then pcall(function() conn:Disconnect() end) end

    if not result then return nil end

    -- Confirm the egg
    pcall(function()
        Net.fire("Egg.ConfirmEgg", eggName, result.petName, result.size or "")
    end)

    return result
end

---------------------------------------------------------------
-- SELL PET (find pet tool in backpack by species, sell via NPCS.SellPet)
-- Pet tool attributes: "Pet" = species name, "PetId" = unique ID
---------------------------------------------------------------

function Pet._findAndSellPet(petName, Net)
    -- Wait a bit for pet tool to appear in backpack after ConfirmEgg
    task.wait(1)
    local lp = Players.LocalPlayer
    local backpack = lp and lp:FindFirstChild("Backpack")
    if not backpack then return false end

    -- Also check character (might be equipped)
    local char = lp.Character
    local function scanContainer(container)
        if not container then return nil end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") then
                local toolPetName = tool:GetAttribute("Pet")
                if toolPetName == petName then
                    local petId = tool:GetAttribute("PetId")
                    if petId then
                        return { tool = tool, petId = petId }
                    end
                end
            end
        end
        return nil
    end

    local found = scanContainer(backpack) or scanContainer(char)
    if not found then
        print("[GAG Hub] Sell: pet tool not found for", petName)
        return false
    end

    -- Equip the tool first (NPC sell requires holding it)
    if char then
        pcall(function() found.tool.Parent = char end)
        task.wait(0.3)
    end

    -- Fire NPCS.SellPet(petId) — invoke for response
    local ok, result = pcall(function()
        return Net.invoke("NPCS.SellPet", found.petId)
    end)

    if ok and result and result.Success then
        print("[GAG Hub] Sold pet:", petName, "for", tostring(result.SellPrice or "?"))
        return true
    end

    return false
end

---------------------------------------------------------------
-- AUTO HATCH LOOP
---------------------------------------------------------------

function Pet._autoHatch(petConfig, Net, Utils)
    local minRarity = petConfig.MinRarity or "Rare"
    local autoSell = petConfig.AutoSellUnwanted or false

    -- Find egg tools in backpack
    local eggs = Pet._findEggTools()
    if #eggs == 0 then
        Pet._stats.noEggs += 1
        return
    end

    -- Hatch one egg per cycle
    local egg = eggs[1]
    local result = Pet._hatchEgg(egg.eggName, Net)

    if not result then
        Pet._stats.errors += 1
        return
    end

    Pet._stats.hatched += 1
    local speciesRarity = Pet._getSpeciesRarity(result.petName)
    local passes = Pet._passesFilter(result.petName, result.size, minRarity)

    local sizeStr = result.size and (" [" .. result.size .. "]") or ""
    print("[GAG Hub] Hatched:", result.petName, sizeStr, "(" .. speciesRarity .. ")")

    if passes then
        Pet._stats.kept += 1
        print("[GAG Hub] KEPT - matches rarity filter:", minRarity .. "+")
    else
        if autoSell then
            local sold = Pet._findAndSellPet(result.petName, Net)
            if sold then
                Pet._stats.sold += 1
                print("[GAG Hub] SOLD - below rarity filter")
            end
        else
            print("[GAG Hub] Below filter (" .. minRarity .. "+), kept in inventory")
        end
    end
end

---------------------------------------------------------------
-- START / STOP
---------------------------------------------------------------

function Pet.start(config, Net, Utils)
    if Pet._running then return end
    Pet._running = true

    local interval = config.Timings.PetHatchInterval or 2
    local petConfig = config.Pet or {}

    Pet._thread = task.spawn(function()
        while Pet._running do
            Pet._autoHatch(petConfig, Net, Utils)
            task.wait(interval)
        end
    end)

    print("[GAG Hub] Auto-Buy Pet started")
end

function Pet.stop()
    Pet._running = false
    for _, conn in ipairs(Pet._connections) do
        pcall(function() conn:Disconnect() end)
    end
    Pet._connections = {}
end

function Pet.getStats()
    return Pet._stats
end

end
---------------------------------------------------------------

Modules.InventoryOptimizer = {}
do
    local M = Modules.InventoryOptimizer
    local Inventory = M
Inventory._running = false
Inventory._thread  = nil
Inventory._connections = {}
Inventory._stats = { favorited = 0, promoted = 0, dropped = 0, scanned = 0 }

---------------------------------------------------------------
-- START
---------------------------------------------------------------

function Inventory.start(config, Net, Utils)
    if Inventory._running then return end
    Inventory._running = true

    local interval = config.Timings.InventoryCheckInterval or 10
    local invConfig = config.Inventory or {}

    Inventory._thread = task.spawn(function()
        while Inventory._running do
            Inventory._optimize(invConfig, Net, Utils)
            task.wait(interval)
        end
    end)

    print("[GAG Hub] Inventory Optimizer started")
end

---------------------------------------------------------------
-- OPTIMIZE LOGIC
---------------------------------------------------------------

function Inventory._optimize(invConfig, Net, Utils)
    Inventory._stats.scanned += 1
    local LP = Utils.getLocalPlayer()
    local backpack = LP and LP:FindFirstChild("Backpack")
    if not backpack then return end

    for _, tool in ipairs(backpack:GetChildren()) do
        if not tool:IsA("Tool") then continue end

        local itemName = tool.Name
        local itemType = tool:GetAttribute("ItemType") or ""
        local fruitName = tool:GetAttribute("FruitName") or ""
        local mutation  = tool:GetAttribute("Mutation") or ""
        local size      = tool:GetAttribute("Size") or 1

        -- Get base value for this item
        local seedName = fruitName ~= "" and fruitName or itemName
        local baseValue = Inventory._getBaseValue(seedName)
        local mult = Inventory._getMutationMult(mutation, config)
        local estimatedValue = baseValue * (size ^ 2.65) * mult

        -- AUTO-FAVORITE high value fruits
        if invConfig.AutoFavorite ~= false and
           estimatedValue >= (invConfig.FavoriteThreshold or 500) then
            local ok = pcall(function()
                Net.fire("Backpack.SetFruitFavorite", tool.Name, true)
            end)
            if ok then
                Inventory._stats.favorited += 1
            end
        end

        -- AUTO-PROMOTE fruits to inventory
        if invConfig.AutoPromote then
            if itemType == "HarvestedFruit" or
               itemType == "Fruit" or
               fruitName ~= "" then
                local ok = pcall(function()
                    Net.fire("Backpack.PromoteFruit", tool.Name)
                end)
                if ok then
                    Inventory._stats.promoted += 1
                end
            end
        end

        -- AUTO-DROP low value items
        if invConfig.DropThreshold and
           invConfig.DropThreshold > 0 and
           estimatedValue < invConfig.DropThreshold then
            -- Don't drop seeds or tools
            if itemType ~= "SeedTool" and
               itemType ~= "WateringCan" and
               itemType ~= "Sprinkler" and
               not itemName:match("Seed") then
                local ok = pcall(function()
                    Net.fire("DroppedItem.RequestDrop", tool.Name, 1)
                end)
                if ok then
                    Inventory._stats.dropped += 1
                end
            end
        end
    end
end

---------------------------------------------------------------
-- VALUE HELPERS
---------------------------------------------------------------

function Inventory._getBaseValue(seedName)
    local values = {
        ["Carrot"] = 5, ["Strawberry"] = 3, ["Blueberry"] = 5,
        ["Tomato"] = 9, ["Apple"] = 12, ["Cactus"] = 40,
        ["Pineapple"] = 30, ["Banana"] = 35, ["Corn"] = 34,
        ["Grape"] = 45, ["Mango"] = 90, ["Coconut"] = 60,
        ["Cherry"] = 350, ["Pomegranate"] = 900,
        ["Dragon Fruit"] = 150, ["Mushroom"] = 13000,
        ["Sunflower"] = 1750, ["Venus Fly Trap"] = 3000,
        ["Moon Bloom"] = 9000, ["Dragon's Breath"] = 3400,
        ["Ghost Pepper"] = 2500, ["Lotus"] = 6500,
        ["Romanesco"] = 1500, ["Poison Apple"] = 900,
        ["Poison Ivy"] = 1700, ["Glow Mushroom"] = 700,
        ["Horned Melon"] = 200, ["Baby Cactus"] = 70,
        ["Tulip"] = 60, ["Bamboo"] = 800, ["Pumpkin"] = 350,
        ["Pinetree"] = 100, ["Green Bean"] = 10,
        ["Beanstalk"] = 2000, ["Thorn Rose"] = 140,
        ["Acorn"] = 200, ["Moon Bloom"] = 9000,
    }
    return values[seedName] or 0
end

function Inventory._getMutationMult(mutation, config)
    if not mutation or mutation == "" then return 1 end
    if config and config.Mutation and config.Mutation.PriceMultipliers then
        return config.Mutation.PriceMultipliers[mutation] or 1
    end
    local defaults = {
        Gold = 20, Rainbow = 50, Electric = 12,
        Frozen = 10, Bloodlit = 5, Chained = 8, Starstruck = 100,
    }
    return defaults[mutation] or 1
end

---------------------------------------------------------------
-- MANUAL OPERATIONS
---------------------------------------------------------------

function Inventory.favoriteAll(Net, Utils, threshold)
    local count = 0
    local backpack = Utils.getLocalPlayer():FindFirstChild("Backpack")
    if not backpack then return 0 end

    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") then
            pcall(function()
                Net.fire("Backpack.SetFruitFavorite", tool.Name, true)
                count += 1
            end)
        end
    end
    Inventory._stats.favorited += count
    return count
end

function Inventory.dropAllLowValue(Net, Utils, threshold)
    local count = 0
    local backpack = Utils.getLocalPlayer():FindFirstChild("Backpack")
    if not backpack then return 0 end

    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") then
            local fruitName = tool:GetAttribute("FruitName") or tool.Name
            local baseValue = Inventory._getBaseValue(fruitName)
            if baseValue < threshold then
                pcall(function()
                    Net.fire("DroppedItem.RequestDrop", tool.Name, 1)
                    count += 1
                end)
            end
        end
    end
    Inventory._stats.dropped += count
    return count
end

---------------------------------------------------------------
-- STOP / STATUS
---------------------------------------------------------------

function Inventory.stop()
    Inventory._running = false
    for _, conn in ipairs(Inventory._connections) do
        pcall(function() conn:Disconnect() end)
    end
    Inventory._connections = {}
end

function Inventory.getStats()
    return Inventory._stats
end

end

---------------------------------------------------------------
-- GEAR BUYER MODULE
---------------------------------------------------------------

Modules.GearBuyer = {}
do
    local Gear = Modules.GearBuyer
    Gear._running = false
    Gear._thread = nil
    Gear._stats = { scanned = 0, bought = 0, skipped = 0, errors = 0, moneySpent = 0 }

    -- Gear prices loaded from Resources (resources.lua via loadstring)
    local GearCosts = Resources.GearPrices or {}

    function Gear._getGearStockFolder()
        local ok, folder = pcall(function()
            return game:GetService("ReplicatedStorage")
                :WaitForChild("StockValues", 5)
                :WaitForChild("GearShop", 5)
                :WaitForChild("Items", 5)
        end)
        return ok and folder or nil
    end

    function Gear._getStock(gearName)
        local folder = Gear._getGearStockFolder()
        if not folder then return -1 end
        local val = folder:FindFirstChild(gearName)
        if not val then return 0 end
        if val:IsA("ValueBase") then return (val.Value or 0) end
        return 0
    end

    function Gear._buyGear(Net, gearName)
        local ok, err = pcall(function()
            Net.fire("GearShop.PurchaseGear", gearName)
        end)
        if ok then
            return true, 0
        end
        Gear._stats.errors += 1
        return false, 0
    end

    function Gear._pollAndBuy(gearConfig, Net, Utils)
        Gear._stats.scanned += 1

        local targets = gearConfig.TargetGears or {}
        if #targets == 0 then return end

        for _, gearName in ipairs(targets) do
            if not Gear._running then break end

            local stock = Gear._getStock(gearName)
            if stock == 0 then
                Gear._stats.skipped += 1
                continue
            end

            local cost = GearCosts[gearName] or 0
            local sheckles = Utils.getSheckles()
            if cost > 0 and sheckles < cost then
                Gear._stats.skipped += 1
                continue -- can't afford
            end

            local buyCount = 0
            local maxBuys = (stock > 0 and stock) or 10
            for i = 1, maxBuys do
                if not Gear._running then break end

                -- Re-check affordability inside loop
                if cost > 0 and Utils.getSheckles() < cost then break end

                local prevStock = Gear._getStock(gearName)
                local ok, price = Gear._buyGear(Net, gearName)
                if ok then
                    task.wait(0.15) -- wait for server to update stock
                    local newStock = Gear._getStock(gearName)
                    if newStock < prevStock or newStock < 0 then
                        buyCount += 1
                        Gear._stats.bought += 1
                        Gear._stats.moneySpent += cost
                    else
                        break -- stock didn't change, buy failed
                    end
                else
                    break
                end
            end

            if buyCount > 0 then
                print("[GAG Hub] Gear bought:", gearName, "x" .. buyCount)
            end
        end
    end

    function Gear.start(config, Net, Utils)
        if Gear._running then return end
        Gear._running = true

        local gearConfig = config.Gear or {}
        local interval = gearConfig.PollInterval or 2

        Gear._thread = task.spawn(function()
            while Gear._running do
                Gear._pollAndBuy(gearConfig, Net, Utils)
                task.wait(interval)
            end
        end)

        print("[GAG Hub] Gear Buyer started")
    end

    function Gear.stop()
        Gear._running = false
    end

    function Gear.getStats()
        return Gear._stats
    end
end
---------------------------------------------------------------
-- SEED PACK CLAIMER MODULE
---------------------------------------------------------------

Modules.SeedPackClaimer = {}
do
    local M = Modules.SeedPackClaimer
    local SeedPack = M
    SeedPack._running = false
    SeedPack._thread = nil
    SeedPack._connections = {}
    SeedPack._stats = { claimed = 0, rainbow = 0, gold = 0, regular = 0, scanned = 0, errors = 0 }
    SeedPack._claimed = {} -- track already-claimed packs by instance

    ---------------------------------------------------------------
    -- SCAN & CLAIM
    ---------------------------------------------------------------

    function SeedPack._scanAndClaim(config, Net, Utils)
        SeedPack._stats.scanned += 1
        local LP = Utils.getLocalPlayer()
        if not LP or not LP.Character or not LP.Character:FindFirstChild("HumanoidRootPart") then return end

        local root = LP.Character.HumanoidRootPart
        local spawnFolder = workspace:FindFirstChild("Map")
            and workspace.Map:FindFirstChild("SeedPackSpawnServerLocations")
        if not spawnFolder then return end

        -- Collect all spawn parts, sort by priority (Rainbow > Gold > Regular)
        local spawns = {}
        for _, part in ipairs(spawnFolder:GetChildren()) do
            if part:IsA("BasePart") and not SeedPack._claimed[part] then
                local isRainbow = part:GetAttribute("RainbowSeed") == true
                local isGold = part:GetAttribute("GoldSeed") == true
                local packName = part:GetAttribute("SeedPack")
                local priority = isRainbow and 3 or (isGold and 2 or 1)
                table.insert(spawns, {
                    part = part,
                    rainbow = isRainbow,
                    gold = isGold,
                    pack = packName,
                    priority = priority,
                    dist = (part.Position - root.Position).Magnitude,
                })
            end
        end

        if #spawns == 0 then return end

        -- Sort: priority desc, then distance asc
        table.sort(spawns, function(a, b)
            if a.priority ~= b.priority then return a.priority > b.priority end
            return a.dist < b.dist
        end)

        for _, spawn in ipairs(spawns) do
            if not SeedPack._running then break end
            SeedPack._claimOne(spawn, Net, root)
        end
    end

    function SeedPack._claimOne(spawn, Net, root)
        local part = spawn.part
        if not part or not part.Parent then return end
        if SeedPack._claimed[part] then return end

        local packId = part:GetAttribute("SeedPack") or ""
        local claimed = false

        -- Save original position, teleport near part for server distance check
        local origCFrame = root.CFrame
        pcall(function()
            root.CFrame = part.CFrame * CFrame.new(0, 3, 0)
        end)
        task.wait(0.3)

        -- Method 1: Fire ProximityPrompt (search recursively)
        local prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            local pOk = pcall(function()
                prompt.HoldDuration = 0
                prompt:InputHoldBegin()
                task.wait(0.1)
                prompt:InputHoldEnd()
                claimed = true
            end)
            if claimed then
                print("[GAG Hub] SeedPack ProximityPrompt fired:", spawn.pack or part.Name)
            end
        end

        -- Method 2: ClickPack remote (fallback)
        if not claimed then
            local ok1 = pcall(function()
                Net.fire("SeedPack.ClickPack", part)
            end)
            if ok1 then claimed = true end
        end

        -- Method 3: OpenSeedPack invoke (fallback)
        if not claimed then
            local ok2 = pcall(function()
                Net.invoke("SeedPack.OpenSeedPack", packId)
            end)
            if ok2 then claimed = true end
        end

        task.wait(0.1)

        -- Mark as claimed regardless (avoid re-attempt)
        SeedPack._claimed[part] = true

        -- Track stats
        if spawn.rainbow then
            SeedPack._stats.rainbow += 1
            SeedPack._stats.claimed += 1
            print("[GAG Hub] 🌈 RAINBOW SEED claimed!")
            Config.Notify("Rainbow Seed!", "Rainbow Seed pack claimed!", 10)
        elseif spawn.gold then
            SeedPack._stats.gold += 1
            SeedPack._stats.claimed += 1
            print("[GAG Hub] 🥇 GOLD SEED claimed!")
            Config.Notify("Gold Seed!", "Gold Seed pack claimed!", 10)
        else
            SeedPack._stats.regular += 1
            SeedPack._stats.claimed += 1
            if packId ~= "" then
                print("[GAG Hub] Seed pack claimed:", packId)
            end
        end

        -- Cleanup: remove from claimed list after part despawns
        task.spawn(function()
            while part and part.Parent do
                task.wait(1)
            end
            SeedPack._claimed[part] = nil
        end)

        -- Return to original position
        task.wait(0.1)
        pcall(function()
            root.CFrame = origCFrame
        end)
    end

    ---------------------------------------------------------------
    -- LISTEN FOR NEW SPAWNS (real-time)
    ---------------------------------------------------------------

    function SeedPack._listenSpawns(config, Net, Utils)
        local spawnFolder = workspace:FindFirstChild("Map")
            and workspace.Map:FindFirstChild("SeedPackSpawnServerLocations")
        if not spawnFolder then return end

        local conn = spawnFolder.ChildAdded:Connect(function(part)
            if not SeedPack._running then return end
            if not part:IsA("BasePart") then return end
            if SeedPack._claimed[part] then return end

            -- Wait for attributes to replicate
            task.wait(0.5)

            local isRainbow = part:GetAttribute("RainbowSeed") == true
            local isGold = part:GetAttribute("GoldSeed") == true

            local LP = Utils.getLocalPlayer()
            local root = LP and LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if not root then return end
            SeedPack._claimOne({
                part = part,
                rainbow = isRainbow,
                gold = isGold,
                pack = part:GetAttribute("SeedPack") or "",
                priority = isRainbow and 3 or (isGold and 2 or 1),
            }, Net)
        end)
        table.insert(SeedPack._connections, conn)
    end

    ---------------------------------------------------------------
    -- START / STOP / STATS
    ---------------------------------------------------------------

    function SeedPack.start(config, Net, Utils)
        if SeedPack._running then return end
        SeedPack._running = true

        local interval = config.Timings.SeedPackPollInterval or 2

        -- Listen for real-time spawns (instant claim for rainbow/gold)
        SeedPack._listenSpawns(config, Net, Utils)

        -- Periodic scan for existing unclaimed packs
        SeedPack._thread = task.spawn(function()
            while SeedPack._running do
                pcall(function()
                    SeedPack._scanAndClaim(config, Net, Utils)
                end)
                task.wait(interval)
            end
        end)

        print("[GAG Hub] Seed Pack Claimer started")
    end

    function SeedPack.stop()
        SeedPack._running = false
        for _, conn in ipairs(SeedPack._connections) do
            pcall(function() conn:Disconnect() end)
        end
        SeedPack._connections = {}
    end

    function SeedPack.getStats()
        return SeedPack._stats
    end
end
---------------------------------------------------------------
-- MODULE: AUTO JOIN SERVER (teleport all accounts to same server)
---------------------------------------------------------------

Modules.AutoJoinServer = {}
do
    local M = Modules.AutoJoinServer
    local TS = game:GetService("TeleportService")
    M._running = false
    M._thread = nil
    M._stats = { teleports = 0, errors = 0 }

    function M.start(config, Net, Utils)
        if M._running then return end
        M._running = true

        local serverConfig = config.Server or {}
        local targetJobId = serverConfig.TargetJobId or ""
        local autoRejoin = serverConfig.AutoRejoin ~= false
        local rejoinDelay = serverConfig.RejoinDelay or 5
        local maxRetries = serverConfig.MaxRetries or 10

        if targetJobId == "" then
            warn("[GAG Hub] AutoJoinServer: no TargetJobId set — set Config.Server.TargetJobId first")
            M._running = false
            return
        end

        -- If already on target server, just enable auto-rejoin
        if game.JobId == targetJobId then
            print("[GAG Hub] Already on target server:", targetJobId)
            if autoRejoin then
                M._setupAutoRejoin(config, Utils)
            end
            return
        end

        -- Teleport to target server
        M._thread = task.spawn(function()
            local LP = Utils.getLocalPlayer()
            local retries = 0

            while M._running and retries < maxRetries do
                retries += 1
                print("[GAG Hub] AutoJoinServer: teleporting to", targetJobId, "(attempt " .. retries .. ")")

                local ok, err = pcall(function()
                    TS:TeleportToPlaceInstance(game.PlaceId, targetJobId, LP)
                end)

                if ok then
                    M._stats.teleports += 1
                    print("[GAG Hub] AutoJoinServer: teleport initiated")
                    -- Wait for teleport to process
                    task.wait(10)
                    -- If still here, teleport may have failed
                    if game.JobId ~= targetJobId then
                        warn("[GAG Hub] AutoJoinServer: still on old server, retrying...")
                    end
                else
                    M._stats.errors += 1
                    warn("[GAG Hub] AutoJoinServer: teleport error:", err)
                end

                task.wait(rejoinDelay)
            end

            if retries >= maxRetries then
                warn("[GAG Hub] AutoJoinServer: max retries reached")
                Config.Notify("Server Join Failed", "Could not join target server after " .. maxRetries .. " attempts", 10)
            end
        end)

        -- Setup auto-rejoin if enabled
        if autoRejoin then
            M._setupAutoRejoin(config, Utils)
        end

        print("[GAG Hub] AutoJoinServer started → JobId:", targetJobId)
    end

    function M._setupAutoRejoin(config, Utils)
        local serverConfig = config.Server or {}
        local targetJobId = serverConfig.TargetJobId or ""
        local rejoinDelay = serverConfig.RejoinDelay or 5

        -- On teleport failure (kicked/disconnected), rejoin target server
        TS.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
            if not M._running then return end
            if targetJobId == "" then return end

            warn("[GAG Hub] TeleportInitFailed:", teleportResult, errorMessage, "— rejoining in", rejoinDelay, "s")
            task.wait(rejoinDelay)

            local LP = Utils.getLocalPlayer()
            local retries = 0
            while M._running and retries < 5 do
                retries += 1
                local ok = pcall(function()
                    TS:TeleportToPlaceInstance(game.PlaceId, targetJobId, LP)
                end)
                if ok then break end
                task.wait(rejoinDelay)
            end
        end)

        -- On character respawn (server change), check if we need to rejoin
        local LP = Utils.getLocalPlayer()
        LP.CharacterAdded:Connect(function()
            task.wait(5) -- wait for game to load
            if not M._running then return end
            if targetJobId == "" then return end

            -- Check if we're on wrong server after respawn
            if game.JobId ~= targetJobId then
                print("[GAG Hub] AutoJoinServer: respawned on wrong server, rejoining target...")
                task.wait(rejoinDelay)
                pcall(function()
                    TS:TeleportToPlaceInstance(game.PlaceId, targetJobId, LP)
                end)
            end
        end)
    end

    function M.stop()
        M._running = false
    end

    function M.getStats()
        return M._stats
    end

    -- Helper: get current JobId for sharing
    function M.getCurrentJobId()
        return game.JobId
    end

    -- Helper: set target and start
    function M.setTargetAndStart(jobId, config, Net, Utils)
        if not jobId or jobId == "" then return end
        config.Server.TargetJobId = jobId
        if M._running then M.stop() end
        task.wait(0.5)
        M.start(config, Net, Utils)
    end
end
---------------------------------------------------------------
-- MODULE: AUTO PET CATCH (wild pet tame + purchase)
---------------------------------------------------------------

Modules.AutoPetCatch = {}
do
    local M = Modules.AutoPetCatch
    local CS = game:GetService("CollectionService")
    M._running = false
    M._thread = nil
    M._connections = {}
    M._stats = { caught = 0, scanned = 0, errors = 0, skipped = 0 }
    M._tamed = {} -- track already-tamed pets by instance

    -- Rarity priority: higher = better
    local RARITY_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Legendary = 4, Mythic = 5, Super = 6 }

    function M._passesFilter(refPart, petCatchConfig)
        local price = refPart:GetAttribute("Price") or 0
        local rarity = refPart:GetAttribute("Rarity") or "Common"
        local ownerUserId = refPart:GetAttribute("OwnerUserId") or 0
        local state = refPart:GetAttribute("State") or ""

        -- Skip if already owned
        if ownerUserId ~= 0 then return false end
        -- Skip if not wandering
        if state ~= "wandering" then return false end
        -- Rarity filter
        local minRarity = petCatchConfig.MinRarity or "Common"
        local petRarityVal = RARITY_ORDER[rarity] or 0
        local minRarityVal = RARITY_ORDER[minRarity] or 0
        if petRarityVal < minRarityVal then return false end

        return true
    end

    function M._getWildPetModels()
        local spawnFolder = workspace:FindFirstChild("Map")
            and workspace.Map:FindFirstChild("WildPetSpawns")
        if not spawnFolder then return {} end

        local pets = {}
        for _, model in ipairs(spawnFolder:GetChildren()) do
            if model:IsA("Model") then
                local petName = model:GetAttribute("PetName") or model.Name
                -- Extract UUID from name: WildPet_Bunny_WildPet_uuid
                local uuid = model.Name:match("WildPet_%w+_WildPet_(.+)")
                table.insert(pets, {
                    model = model,
                    petName = petName,
                    uuid = uuid,
                })
            end
        end
        return pets
    end

    function M._getRefPart(uuid)
        local refFolder = workspace:FindFirstChild("Map")
            and workspace.Map:FindFirstChild("WildPetRef")
        if not refFolder then return nil end
        return refFolder:FindFirstChild("WildPet_" .. uuid)
    end

    function M._catchPet(petInfo, petCatchConfig, Net, root)
        local model = petInfo.model
        if not model or not model.Parent then return false end
        if M._tamed[model] then return false end

        -- Get ref part for attributes
        local refPart = petInfo.uuid and M._getRefPart(petInfo.uuid)
        if refPart and not M._passesFilter(refPart, petCatchConfig) then
            M._stats.skipped += 1
            return false
        end

        local rootPart = model:FindFirstChild("RootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
        if not rootPart then return false end

        local petName = petInfo.petName or "Unknown"
        local rarity = refPart and refPart:GetAttribute("Rarity") or "?"
        local price = refPart and refPart:GetAttribute("Price") or 0

        -- Save original position
        local origCFrame = root.CFrame

        -- Teleport to pet
        pcall(function()
            root.CFrame = rootPart.CFrame * CFrame.new(0, 5, 0)
        end)
        task.wait(0.8)

        -- Find nearest ProximityPrompt to player after teleport
        local nearestPrompt = nil
        local nearestDist = math.huge
        for _, desc in ipairs(workspace:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and desc.Enabled then
                local promptParent = desc.Parent
                if promptParent and promptParent:IsA("BasePart") then
                    local dist = (promptParent.Position - root.Position).Magnitude
                    if dist < nearestDist and dist <= desc.MaxActivationDistance then
                        nearestDist = dist
                        nearestPrompt = desc
                    end
                end
            end
        end

        local caught = false

        -- Method 1: Fire nearest ProximityPrompt (primary)
        if nearestPrompt then
            local pOk = pcall(function()
                nearestPrompt.HoldDuration = 0
                nearestPrompt:InputHoldBegin()
                task.wait(0.2)
                nearestPrompt:InputHoldEnd()
                caught = true
            end)
            if caught then
                print("[GAG Hub] 🐾 ProximityPrompt fired for:", petName, "dist:", math.floor(nearestDist))
            end
        end

        -- Method 2: WildPetTame remote (backup)
        if not caught then
            local ok1, err1 = pcall(function()
                Net.fire("Pets.WildPetTame", model)
            end)
            if ok1 then
                caught = true
                print("[GAG Hub] 🐾 WildPetTame fired for:", petName)
            else
                warn("[GAG Hub] WildPetTame error:", err1)
            end
        end

        -- Method 3: WildPetCollected (backup)
        if not caught then
            pcall(function()
                Net.fire("Pets.WildPetCollected", model)
                caught = true
            end)
        end

        task.wait(1) -- wait for server to process

        -- Return to original position
        if petCatchConfig.AutoReturn ~= false then
            task.wait(0.2)
            pcall(function()
                root.CFrame = origCFrame
            end)
        end

        M._tamed[model] = true

        -- Track stats
        M._stats.caught += 1
        local priceStr = Utils.formatNumber and Utils.formatNumber(price) or tostring(price)
        print("[GAG Hub] 🐾 Caught:", petName, rarity, "¢" .. priceStr)
        Config.Notify("Pet Caught!", petName .. " (" .. rarity .. ") for ¢" .. priceStr, 8)

        -- Cleanup after pet despawns
        task.spawn(function()
            while model and model.Parent do
                task.wait(1)
            end
            M._tamed[model] = nil
        end)

        return true
    end

    function M._scan(petCatchConfig, Net, Utils)
        M._stats.scanned += 1
        local LP = Utils.getLocalPlayer()
        local root = LP and LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not root then return end

        local petModels = M._getWildPetModels()
        if #petModels == 0 then return end

        -- Build list with ref data, sort by rarity desc then price asc
        local candidates = {}
        for _, pet in ipairs(petModels) do
            if not M._tamed[pet.model] then
                local refPart = pet.uuid and M._getRefPart(pet.uuid)
                local rarity = refPart and refPart:GetAttribute("Rarity") or "Common"
                local price = refPart and refPart:GetAttribute("Price") or 0
                local ownerUserId = refPart and refPart:GetAttribute("OwnerUserId") or 0
                local state = refPart and refPart:GetAttribute("State") or ""

                if ownerUserId == 0 and state == "wandering" then
                    local petPart = pet.model:FindFirstChild("RootPart") or pet.model:FindFirstChildWhichIsA("BasePart")
                    local petPos = petPart and petPart.Position or root.Position
                    table.insert(candidates, {
                        pet = pet,
                        rarity = rarity,
                        price = price,
                        rarityVal = RARITY_ORDER[rarity] or 0,
                        dist = (petPos - root.Position).Magnitude,
                    })
                end
            end
        end

        -- Sort: rarity desc, then price asc (prefer expensive = rare), then distance asc
        table.sort(candidates, function(a, b)
            if a.rarityVal ~= b.rarityVal then return a.rarityVal > b.rarityVal end
            if a.price ~= b.price then return a.price > b.price end
            return a.dist < b.dist
        end)

        -- Catch each
        for _, cand in ipairs(candidates) do
            if not M._running then break end
            if M._passesFilter(cand.pet.uuid and M._getRefPart(cand.pet.uuid) or nil, petCatchConfig) then
                M._catchPet(cand.pet, petCatchConfig, Net, root)
                task.wait(0.5)
            end
        end
    end

    function M._listenSpawns(petCatchConfig, Net, Utils)
        local spawnFolder = workspace:FindFirstChild("Map")
            and workspace.Map:FindFirstChild("WildPetSpawns")
        if not spawnFolder then return end

        local conn = spawnFolder.ChildAdded:Connect(function(model)
            if not M._running then return end
            if not model:IsA("Model") then return end

            -- Wait for attributes to replicate
            task.wait(1)

            local petName = model:GetAttribute("PetName") or model.Name
            local uuid = model.Name:match("WildPet_%w+_WildPet_(.+)")
            local refPart = uuid and M._getRefPart(uuid)

            if refPart and M._passesFilter(refPart, petCatchConfig) then
                local LP = Utils.getLocalPlayer()
                local root = LP and LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    print("[GAG Hub] 🐾 New wild pet spawned:", petName)
                    M._catchPet({
                        model = model,
                        petName = petName,
                        uuid = uuid,
                    }, petCatchConfig, Net, root)
                end
            end
        end)
        table.insert(M._connections, conn)
    end

    function M.start(config, Net, Utils)
        if M._running then return end
        M._running = true

        local petCatchConfig = config.PetCatch or {}
        local interval = config.Timings.PetCatchInterval or 3

        -- Listen for real-time spawns
        M._listenSpawns(petCatchConfig, Net, Utils)

        -- Periodic scan
        M._thread = task.spawn(function()
            while M._running do
                pcall(function()
                    M._scan(petCatchConfig, Net, Utils)
                end)
                task.wait(interval)
            end
        end)

        print("[GAG Hub] Auto Pet Catch started")
    end

    function M.stop()
        M._running = false
        for _, conn in ipairs(M._connections) do
            pcall(function() conn:Disconnect() end)
        end
        M._connections = {}
    end

    function M.getStats()
        return M._stats
    end
end

---------------------------------------------------------------
-- MODULE: AUTO CENTER PLOT
-- Periodically teleport player to center of their garden plot
---------------------------------------------------------------

Modules.AutoCenterPlot = {}
do
    local M = Modules.AutoCenterPlot
    local Center = M
    Center._running = false
    Center._thread = nil
    Center._connections = {}

    function Center.start(config, Net, Utils)
        if Center._running then return end
        Center._running = true

        -- One-shot: teleport to soil center on load, then stop
        task.spawn(function()
            task.wait(1) -- brief wait for character to load
            local hrp = Utils.getHumanoidRootPart()
            local garden = Utils.getMyGarden()
            if hrp and garden then
                -- Find center of PlantArea
                local CollectionService = game:GetService("CollectionService")
                local totalPos = Vector3.new(0, 0, 0)
                local count = 0
                for _, part in ipairs(CollectionService:GetTagged("PlantArea")) do
                    if part:IsA("BasePart") and part:IsDescendantOf(garden) then
                        totalPos = totalPos + part.Position
                        count = count + 1
                    end
                end
                if count > 0 then
                    local center = totalPos / count
                    pcall(function()
                        hrp.CFrame = CFrame.new(center + Vector3.new(0, 3, 0))
                    end)
                    print("[GAG Hub] Centered to soil")
                end
            end
            Center._running = false
        end)
    end

    function Center.stop()
        Center._running = false
        for _, conn in ipairs(Center._connections) do
            pcall(function() conn:Disconnect() end)
        end
        Center._connections = {}
    end
end

---------------------------------------------------------------
-- STATUS
---------------------------------------------------------------

local function getFullStatus()
    local lines = {"GAG HUB STATUS", "Sheckles: " .. Utils.formatNumber(Utils.getSheckles()), ""}
    for name, mod in pairs(Modules) do
        local st = Running[name] and "ON" or "OFF"
        local info = ""
        if name == "RestockSniper" then
            local t = Config.Restock.TargetSeeds or {}
            info = #t > 0 and table.concat(t, ", ") or "(none)"
        elseif name == "GearBuyer" then
            local t = Config.Gear.TargetGears or {}
            info = #t > 0 and table.concat(t, ", ") or "(none)"
        elseif name == "AutoPlant" then
            info = (Config.Plant.PlantOrder or "Top") .. " | " .. (Config.Plant.PreferSeed or "any")
        elseif name == "AutoBuyPet" then
            info = "min: " .. (Config.Pet.MinRarity or "Rare")
        elseif name == "MutationTracker" then
            info = "min: " .. (Config.Mutation.MinRarity or "Common")
        elseif name == "AutoSell" then
            info = Config.Sell.AutoSell and "auto" or "manual"
        elseif name == "AutoWater" then
            info = Config.Water.WaterAll and "all" or "dry only"
        elseif name == "StealBot" then
            info = Config.Steal.Enabled and "night mode" or "off"
        end
        lines[#lines+1] = "  " .. st .. " " .. name .. ": " .. info
    end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------
-- LIVE STATS TRACKER
---------------------------------------------------------------

local Stats = {
    startSheckles = 0,
    startTime = os.clock(),
    sessionHarvested = 0,
    sessionPlanted = 0,
    sessionSold = 0,
    sessionBought = 0,
}

-- Capture initial state on load
function Stats.init()
    Stats.startSheckles = Utils.getSheckles()
    Stats.startTime = os.clock()
end

-- Get elapsed time since start
function Stats.getElapsed()
    return os.clock() - Stats.startTime
end

-- Calculate profit/loss since start
function Stats.getProfit()
    return Utils.getSheckles() - Stats.startSheckles
end

-- Count plants in my garden
function Stats.getPlantCount()
    local garden = Utils.getMyGarden()
    if not garden then return 0 end
    local plants = garden:FindFirstChild("Plants")
    return plants and #plants:GetChildren() or 0
end

-- Calculate approximate garden value (all fruits on all plants)
-- Uses SellValueData * size^2.65 as base estimate
function Stats.getGardenValue()
    local garden = Utils.getMyGarden()
    if not garden then return 0 end
    local total = 0
    local plants = garden:FindFirstChild("Plants")
    if not plants then return 0 end
    for _, plantModel in ipairs(plants:GetChildren()) do
        local seedName = plantModel:GetAttribute("SeedName")
        if not seedName then continue end
        local fruitsFolder = plantModel:FindFirstChild("Fruits")
        if fruitsFolder then
            for _, fruitModel in ipairs(fruitsFolder:GetChildren()) do
                local size = fruitModel:GetAttribute("SizeMultiplier") or 1
                local mutation = fruitModel:GetAttribute("Mutation")
                local baseVal = Stats._sellData[seedName] or 0
                local sizeMult = size ^ 2.65
                local mutMult = 1
                if mutation and Stats._mutData and Stats._mutData[mutation] then
                    mutMult = Stats._mutData[mutation].PriceMultiplier or 1
                end
                total += math.floor(baseVal * sizeMult * mutMult)
            end
        else
            -- Single-harvest: plant itself has value
            local size = plantModel:GetAttribute("SizeMultiplier") or 1
            local baseVal = Stats._sellData[seedName] or 0
            total += math.floor(baseVal * (size ^ 2.65))
        end
    end
    return total
end

-- Count backpack items and estimate seed value
function Stats.getBackpackInfo()
    local lp = Players and Players.LocalPlayer
    local bp = lp and lp:FindFirstChild("Backpack")
    if not bp then return 0, 0, 0 end
    local totalItems = 0
    local seedCount = 0
    local fruitCount = 0
    for _, tool in ipairs(bp:GetChildren()) do
        if tool:IsA("Tool") then
            totalItems += 1
            if tool:GetAttribute("SeedTool") then
                seedCount += 1
            elseif tool:GetAttribute("FruitName") or tool:GetAttribute("IsFruit") then
                fruitCount += 1
            end
        end
    end
    return totalItems, seedCount, fruitCount
end

-- Count active modules
function Stats.getActiveModules()
    local count = 0
    local names = {}
    for name, active in pairs(Running) do
        if active then
            count += 1
            table.insert(names, name)
        end
    end
    return count, names
end

-- Build full live stats text for Status tab
function Stats.buildText()
    local sheckles = Utils.getSheckles()
    local profit = Stats.getProfit()
    local elapsed = Stats.getElapsed()
    local gardenVal = Stats.getGardenValue()
    local plantCount = Stats.getPlantCount()
    local totalItems, seedCount, fruitCount = Stats.getBackpackInfo()
    local activeCount, activeNames = Stats.getActiveModules()

    local profitSign = profit >= 0 and "+" or ""
    local profitColor = profit >= 0 and "🟢" or "🔴"

    local lines = {}

    -- Money section
    table.insert(lines, "💰 **Money**")
    table.insert(lines, string.format("  Current: %s", Utils.formatNumber(sheckles)))
    table.insert(lines, string.format("  Start:   %s", Utils.formatNumber(Stats.startSheckles)))
    table.insert(lines, string.format("  Profit:  %s%s%s", profitColor, profitSign, Utils.formatNumber(profit)))
    table.insert(lines, "")

    -- Session
    table.insert(lines, "⏱ **Session**")
    table.insert(lines, string.format("  Runtime: %s", Utils.formatTime(elapsed)))
    table.insert(lines, "")

    -- Garden
    table.insert(lines, "🌱 **Garden**")
    table.insert(lines, string.format("  Plants: %d", plantCount))
    table.insert(lines, string.format("  Value:  %s", Utils.formatNumber(gardenVal)))
    table.insert(lines, "")

    -- Backpack
    table.insert(lines, "🎒 **Backpack**")
    table.insert(lines, string.format("  Items: %d  (Seeds: %d, Fruits: %d)", totalItems, seedCount, fruitCount))
    table.insert(lines, "")

    -- Module configs
    table.insert(lines, string.format("⚡ **Modules** (%d active)", activeCount))
    for name, mod in pairs(Modules) do
        local st = Running[name] and "✅" or "⬜"
        local info = ""
        if name == "RestockSniper" then
            local t = Config.Restock.TargetSeeds or {}
            info = #t > 0 and table.concat(t, ", ") or "(none)"
        elseif name == "GearBuyer" then
            local t = Config.Gear.TargetGears or {}
            info = #t > 0 and table.concat(t, ", ") or "(none)"
        elseif name == "AutoPlant" then
            info = (Config.Plant.PlantOrder or "Top") .. " | " .. (Config.Plant.PreferSeed or "any")
        elseif name == "AutoBuyPet" then
            info = "min: " .. (Config.Pet.MinRarity or "Rare")
        elseif name == "MutationTracker" then
            info = "min: " .. (Config.Mutation.MinRarity or "Common")
        elseif name == "AutoSell" then
            info = Config.Sell.AutoSell and "auto" or "manual"
        elseif name == "AutoWater" then
            info = Config.Water.WaterAll and "all" or "dry only"
        elseif name == "StealBot" then
            info = Config.Steal.Enabled and "night mode" or "off"
        end
        table.insert(lines, string.format("  %s %s: %s", st, name, info))
    end

    return table.concat(lines, "\n")
end

-- SellValueData cache (loaded lazily)
Stats._sellData = {}
Stats._mutData = {}
task.spawn(function()
    pcall(function()
        local RS = game:GetService("ReplicatedStorage")
        local shared = RS:WaitForChild("SharedModules", 10)
        if shared then
            local svd = shared:WaitForChild("SellValueData", 5)
            if svd then Stats._sellData = require(svd) end
            local md = shared:WaitForChild("MutationData", 5)
            if md then Stats._mutData = require(md) end
        end
    end)
end)

---------------------------------------------------------------
-- RAYFIELD UI
---------------------------------------------------------------

local AllSeeds = Resources.AllSeeds or {
    "Strawberry","Carrot","Blueberry","Tomato","Green Bean",
    "Apple","Pineapple","Corn","Banana","Cactus","Grape",
    "Coconut","Tulip","Baby Cactus","Mango","Pinetree",
    "Thorn Rose","Dragon Fruit","Acorn","Horned Melon",
    "Pumpkin","Cherry","Glow Mushroom","Bamboo",
    "Pomegranate","Poison Apple","Romanesco","Poison Ivy",
    "Sunflower","Beanstalk","Ghost Pepper","Venus Fly Trap",
    "Dragon's Breath","Lotus","Moon Bloom","Mushroom",
}

local AllGears = Resources.AllGears or {
    "Trowel","Speed Mushroom","Jump Mushroom","Common Watering Can",
    "Common Sprinkler","Sign","Shrink Mushroom","Supersize Mushroom",
    "Flashbang","Uncommon Sprinkler","Lantern","Teleporter",
    "Rare Sprinkler","Gnome","Basic Pot","Legendary Sprinkler",
    "Super Watering Can","Super Sprinkler","Wheelbarrow",
}

local function createUI()
    local Rayfield = nil
    local ok = pcall(function()
        Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
    end)
    if not ok or not Rayfield then warn("[GAG Hub] Rayfield failed") return false end

    -- Init live stats tracker (capture starting money)
    Stats.init()

    local Window = Rayfield:CreateWindow({
        Name = "🌿 " .. Config.UI.Title .. " v" .. VERSION,
        Icon = 0,
        LoadingTitle = Config.UI.Title .. " v" .. VERSION,
        LoadingSubtitle = "by Brave",
        ShowText = "GAG Hub",
        Theme = "Default",
        ToggleUIKeybind = "K",
        DisableRayfieldPrompts = false,
        DisableBuildWarnings = false,
        ConfigurationSaving = { Enabled = true, FolderName = "GAGHub", FileName = "config" },
        Discord = { Enabled = false },
        KeySystem = false,
        KeySettings = {
            Title = "GAG Hub", Subtitle = "Key System",
            Note = "No key required", FileName = "GAGHubKey",
            SaveKey = true, GrabKeyFromSite = false, Key = {""}
        }
    })

    -------------------------------------------------------
    -- TAB 1: FARMING (harvest + sell + water + plant)
    -------------------------------------------------------
    local FarmTab = Window:CreateTab("Farming", 6034510) -- leaf icon

    FarmTab:CreateSection("⚡ Auto Modules")
    for _, e in ipairs({
        {"Auto Harvest",   "AutoHarvest"},
        {"Auto Sell",      "AutoSell"},
        {"Auto Water",     "AutoWater"},
        {"Auto Plant",     "AutoPlant"},
    }) do
        FarmTab:CreateToggle({
            Name = e[1], CurrentValue = false, Flag = e[2],
            Callback = function(v) if v then startModule(e[2]) else stopModule(e[2]) end end
        })
    end

    FarmTab:CreateSection("⏱ Intervals")
    FarmTab:CreateSlider({Name="Harvest", Range={0.5,10}, Increment=0.5, Suffix="s", CurrentValue=Config.Timings.HarvestInterval, Flag="HarvestInterval", Callback=function(v) Config.Timings.HarvestInterval=v end})
    FarmTab:CreateSlider({Name="Sell", Range={1,30}, Increment=1, Suffix="s", CurrentValue=Config.Timings.SellInterval, Flag="SellInterval", Callback=function(v) Config.Timings.SellInterval=v end})
    FarmTab:CreateSlider({Name="Water", Range={1,15}, Increment=1, Suffix="s", CurrentValue=Config.Timings.WaterInterval, Flag="WaterInterval", Callback=function(v) Config.Timings.WaterInterval=v end})
    FarmTab:CreateSlider({Name="Plant", Range={1,15}, Increment=1, Suffix="s", CurrentValue=Config.Timings.PlantInterval, Flag="PlantInterval", Callback=function(v) Config.Timings.PlantInterval=v end})

    FarmTab:CreateSection("💧 Water Config")
    FarmTab:CreateToggle({Name="Water Fully Grown", CurrentValue=false, Flag="WaterFullyGrown", Callback=function(v) Config.Water.WaterFullyGrown=v end})
    FarmTab:CreateDropdown({Name="Required Can (empty=any)", Options={"","Common Watering Can","Super Watering Can"}, CurrentOption={Config.Water.RequiredCan}, Flag="RequiredCan", MultipleOptions=false, Callback=function(opts) Config.Water.RequiredCan = type(opts)=="table" and opts[1] or opts end})

    FarmTab:CreateSection("🌱 Plant Config")
    FarmTab:CreateDropdown({Name="Plant Order", Options={"Top","Bottom","Random"}, CurrentOption={Config.Plant.PlantOrder}, Flag="PlantOrder", MultipleOptions=false, Callback=function(opts) Config.Plant.PlantOrder = type(opts)=="table" and opts[1] or opts end})
    FarmTab:CreateSlider({Name="Grid Spacing", Range={2,8}, Increment=0.5, Suffix=" studs", CurrentValue=Config.Plant.GridSpacing, Flag="GridSpacing", Callback=function(v) Config.Plant.GridSpacing=v end})
    FarmTab:CreateInput({Name="Prefer Seed (empty=any)", CurrentValue="", PlaceholderText="e.g. Carrot", RemoveTextAfterFocusLost=false, Flag="PreferSeed", Callback=function(v) Config.Plant.PreferSeed = (v~="" and v or nil) end})
    FarmTab:CreateToggle({Name="Skip Mutated Seeds", CurrentValue=Config.Plant.BlacklistMutated, Flag="BlacklistMutated", Callback=function(v) Config.Plant.BlacklistMutated=v end})

    -------------------------------------------------------
    -- TAB 2: SHOP & PETS (restock + inventory + pets)
    -------------------------------------------------------
    local ShopTab = Window:CreateTab("Shop", 6031790) -- shopping-cart icon

    ShopTab:CreateSection("🎯 Restock Sniper")
    ShopTab:CreateToggle({Name="Enabled", CurrentValue=false, Flag="RestockSniper", Callback=function(v) if v then startModule("RestockSniper") else stopModule("RestockSniper") end end})
    ShopTab:CreateSlider({Name="Poll", Range={0.5,5}, Increment=0.5, Suffix="s", CurrentValue=Config.Timings.RestockPollInterval, Flag="RestockPollInterval", Callback=function(v) Config.Timings.RestockPollInterval=v end})
    ShopTab:CreateDropdown({Name="Buy Targets", Options=AllSeeds, CurrentOption=Config.Restock.TargetSeeds, MultipleOptions=true, Flag="RestockTargets", Callback=function(opts) Config.Restock.TargetSeeds = type(opts)=="table" and opts or {opts} end})
    ShopTab:CreateDropdown({Name="Blacklist", Options=AllSeeds, CurrentOption=Config.Restock.BlacklistedSeeds, MultipleOptions=true, Flag="RestockBlacklist", Callback=function(opts) Config.Restock.BlacklistedSeeds = type(opts)=="table" and opts or {opts} end})

    ShopTab:CreateSection("🔧 Auto Buy Gear")
    ShopTab:CreateToggle({Name="Enabled", CurrentValue=false, Flag="GearBuyer", Callback=function(v) if v then startModule("GearBuyer") else stopModule("GearBuyer") end end})
    ShopTab:CreateSlider({Name="Poll Interval", Range={1,10}, Increment=1, Suffix="s", CurrentValue=5, Flag="GearPollInterval", Callback=function(v) Config.Gear.PollInterval=v end})
    ShopTab:CreateDropdown({Name="Buy Gears", Options=AllGears, CurrentOption=Config.Gear.TargetGears, MultipleOptions=true, Flag="GearTargets", Callback=function(opts) Config.Gear.TargetGears = type(opts)=="table" and opts or {opts} end})

    ShopTab:CreateSection("📦 Inventory")
    ShopTab:CreateToggle({Name="Optimizer", CurrentValue=false, Flag="InventoryOptimizer", Callback=function(v) if v then startModule("InventoryOptimizer") else stopModule("InventoryOptimizer") end end})
    ShopTab:CreateSlider({Name="Check", Range={5,60}, Increment=5, Suffix="s", CurrentValue=Config.Timings.InventoryCheckInterval, Flag="InventoryCheckInterval", Callback=function(v) Config.Timings.InventoryCheckInterval=v end})

    ShopTab:CreateSection("🐾 Pets")
    ShopTab:CreateToggle({Name="Auto Hatch", CurrentValue=false, Flag="AutoBuyPet", Callback=function(v) if v then startModule("AutoBuyPet") else stopModule("AutoBuyPet") end end})
    ShopTab:CreateSlider({Name="Hatch", Range={1,10}, Increment=0.5, Suffix="s", CurrentValue=Config.Timings.PetHatchInterval, Flag="PetHatchInterval", Callback=function(v) Config.Timings.PetHatchInterval=v end})
    ShopTab:CreateDropdown({Name="Min Rarity", Options={"Common","Uncommon","Rare","Legendary","Mythic","Super"}, CurrentOption={Config.Pet.MinRarity}, MultipleOptions=false, Flag="PetMinRarity", Callback=function(opt) Config.Pet.MinRarity = type(opt)=="table" and opt[1] or opt end})
    ShopTab:CreateToggle({Name="Sell Unwanted", CurrentValue=Config.Pet.AutoSellUnwanted, Flag="PetAutoSell", Callback=function(v) Config.Pet.AutoSellUnwanted=v end})

    -------------------------------------------------------
    -- TAB 3: EVENTS (mutations + weather + steal)
    -------------------------------------------------------
    local EventTab = Window:CreateTab("Events", 6035974) -- zap icon

    EventTab:CreateSection("🧬 Mutations")
    EventTab:CreateToggle({Name="Tracker", CurrentValue=false, Flag="MutationTracker", Callback=function(v) if v then startModule("MutationTracker") else stopModule("MutationTracker") end end})
    EventTab:CreateSlider({Name="Scan", Range={1,10}, Increment=1, Suffix="s", CurrentValue=Config.Timings.MutationScanInterval, Flag="MutationScanInterval", Callback=function(v) Config.Timings.MutationScanInterval=v end})

    EventTab:CreateSection("🌧 Weather")
    EventTab:CreateToggle({Name="Weather Bot", CurrentValue=false, Flag="WeatherBot", Callback=function(v) if v then startModule("WeatherBot") else stopModule("WeatherBot") end end})
    EventTab:CreateSlider({Name="Poll", Range={1,15}, Increment=1, Suffix="s", CurrentValue=Config.Timings.WeatherPollInterval, Flag="WeatherPollInterval", Callback=function(v) Config.Timings.WeatherPollInterval=v end})

    EventTab:CreateSection("🌱 Seed Pack Claimer")
    EventTab:CreateToggle({Name="Auto Claim", CurrentValue=false, Flag="SeedPackClaimer", Callback=function(v) if v then startModule("SeedPackClaimer") else stopModule("SeedPackClaimer") end end})
    EventTab:CreateSlider({Name="Poll", Range={0.1,5}, Increment=0.1, Suffix="s", CurrentValue=Config.Timings.SeedPackPollInterval, Flag="SeedPackPollInterval", Callback=function(v) Config.Timings.SeedPackPollInterval=v end})

    EventTab:CreateSection("🐾 Wild Pet Catch")
    EventTab:CreateToggle({Name="Auto Catch", CurrentValue=false, Flag="AutoPetCatch", Callback=function(v) if v then startModule("AutoPetCatch") else stopModule("AutoPetCatch") end end})
    EventTab:CreateSlider({Name="Scan", Range={1,15}, Increment=1, Suffix="s", CurrentValue=Config.Timings.PetCatchInterval, Flag="PetCatchInterval", Callback=function(v) Config.Timings.PetCatchInterval=v end})
    EventTab:CreateDropdown({Name="Min Rarity", Options={"Common","Uncommon","Rare","Legendary","Mythic","Super"}, CurrentOption={Config.PetCatch.MinRarity}, MultipleOptions=false, Flag="PetCatchMinRarity", Callback=function(opt) Config.PetCatch.MinRarity = type(opt)=="table" and opt[1] or opt end})
    EventTab:CreateToggle({Name="Return After Catch", CurrentValue=Config.PetCatch.AutoReturn, Flag="PetCatchAutoReturn", Callback=function(v) Config.PetCatch.AutoReturn=v end})

    EventTab:CreateSection("🌙 Steal Bot")
    EventTab:CreateToggle({Name="Enabled (Night)", CurrentValue=false, Flag="StealBot", Callback=function(v) if v then startModule("StealBot") else stopModule("StealBot") end end})
    EventTab:CreateSlider({Name="Interval", Range={0.5,5}, Increment=0.5, Suffix="s", CurrentValue=Config.Timings.StealInterval, Flag="StealInterval", Callback=function(v) Config.Timings.StealInterval=v end})
    EventTab:CreateSlider({Name="Max/Night", Range={5,100}, Increment=5, Suffix="", CurrentValue=Config.Steal.MaxAttemptsPerNight, Flag="MaxStealAttempts", Callback=function(v) Config.Steal.MaxAttemptsPerNight=v end})
    EventTab:CreateSlider({Name="Min Value", Range={100,10000}, Increment=100, Suffix=" $", CurrentValue=Config.Steal.MinFruitValue, Flag="MinFruitValue", Callback=function(v) Config.Steal.MinFruitValue=v end})

    EventTab:CreateSection("🏡 Auto Center Plot")
    EventTab:CreateToggle({Name="Enabled (on load)", CurrentValue=false, Flag="AutoCenterPlot", Callback=function(v) if v then startModule("AutoCenterPlot") else stopModule("AutoCenterPlot") end end})

    -------------------------------------------------------
    -- TAB: SERVER (auto join / boost)
    -------------------------------------------------------
    local ServerTab = Window:CreateTab("Server", 6035172) -- globe icon

    ServerTab:CreateSection("📡 Current Server")
    local CurrentJobParagraph = ServerTab:CreateParagraph({
        Title = "Your JobId",
        Content = game.JobId ~= "" and game.JobId or "N/A (studio)"
    })
    ServerTab:CreateButton({Name="📋 Copy JobId", Callback=function()
        if setclipboard then
            setclipboard(game.JobId)
            Rayfield:Notify({Title="Copied!", Content="JobId copied to clipboard", Duration=3})
        else
            Rayfield:Notify({Title="JobId", Content=game.JobId, Duration=10})
        end
    end})

    ServerTab:CreateSection("🚀 Join Target Server")
    ServerTab:CreateInput({
        Name = "Target JobId",
        CurrentValue = "",
        PlaceholderText = "Paste server JobId here...",
        RemoveTextAfterFocusLost = false,
        Flag = "TargetJobId",
        Callback = function(v)
            Config.Server.TargetJobId = v
        end
    })
    ServerTab:CreateToggle({
        Name = "Auto Join Server",
        CurrentValue = false,
        Flag = "AutoJoinServer",
        Callback = function(v)
            if v then
                if Config.Server.TargetJobId == "" then
                    Rayfield:Notify({Title="Error", Content="Set Target JobId first!", Duration=5})
                    return
                end
                startModule("AutoJoinServer")
            else
                stopModule("AutoJoinServer")
            end
        end
    })
    ServerTab:CreateToggle({Name="Auto Rejoin on Disconnect", CurrentValue=Config.Server.AutoRejoin, Flag="ServerAutoRejoin", Callback=function(v) Config.Server.AutoRejoin=v end})
    ServerTab:CreateSlider({Name="Rejoin Delay", Range={3,30}, Increment=1, Suffix="s", CurrentValue=Config.Server.RejoinDelay, Flag="ServerRejoinDelay", Callback=function(v) Config.Server.RejoinDelay=v end})
    ServerTab:CreateSlider({Name="Max Retries", Range={1,50}, Increment=1, Suffix="", CurrentValue=Config.Server.MaxRetries, Flag="ServerMaxRetries", Callback=function(v) Config.Server.MaxRetries=v end})

    -- Quick join: paste JobId + 1-click
    ServerTab:CreateSection("⚡ Quick Join")
    ServerTab:CreateButton({Name="🔄 Join Now (use input above)", Callback=function()
        if Config.Server.TargetJobId == "" then
            Rayfield:Notify({Title="Error", Content="Set Target JobId first!", Duration=5})
            return
        end
        print("[GAG Hub] Quick join →", Config.Server.TargetJobId)
        local LP = game:GetService("Players").LocalPlayer
        pcall(function()
            game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, Config.Server.TargetJobId, LP)
        end)
    end})

    -------------------------------------------------------
    -- TAB 4: LIVE STATUS
    -------------------------------------------------------
    local StatusTab = Window:CreateTab("Status", 6030690) -- activity icon

    StatusTab:CreateSection("📊 Live Stats (auto-refresh)")

    local StatsParagraph = StatusTab:CreateParagraph({
        Title = "Session Overview",
        Content = "Loading stats..."
    })

    StatusTab:CreateSection("🎮 Controls")
    StatusTab:CreateButton({Name="✅ Enable All", Callback=function()
        for n in pairs(Modules) do startModule(n) end
        Rayfield:Notify({Title="GAG Hub",Content="All modules enabled",Duration=3})
    end})
    StatusTab:CreateButton({Name="❌ Disable All", Callback=function()
        for n in pairs(Modules) do stopModule(n) end
        Rayfield:Notify({Title="GAG Hub",Content="All modules disabled",Duration=3})
    end})

    -- Live update loop (every 2 seconds)
    task.spawn(function()
        while true do
            pcall(function()
                StatsParagraph:Set({Title="Session Overview", Content=Stats.buildText()})
            end)
            task.wait(2)
        end
    end)

    pcall(function() Rayfield:LoadConfiguration() end)
    return true
end

---------------------------------------------------------------
-- CONSOLE API
---------------------------------------------------------------

_G.GAGHub = {
    Config = Config, Modules = Modules, Net = Networking, Utils = Utils,
    toggle = function(name) toggleModule(name) print("[GAG Hub] " .. name .. ": " .. (Running[name] and "ON" or "OFF")) end,
    start = startModule, stop = stopModule,
    status = function() print(getFullStatus()) end,
    enableAll = function() for n in pairs(Modules) do startModule(n) end end,
    disableAll = function() for n in pairs(Modules) do stopModule(n) end end,
    stats = function(name) if Modules[name] and Modules[name].getStats then for k,v in pairs(Modules[name].getStats()) do print("  "..k..": "..tostring(v)) end end end,
}

---------------------------------------------------------------
-- STARTUP
---------------------------------------------------------------

local LP = Utils.getLocalPlayer()

LP.CharacterAdded:Connect(function()
    task.wait(3)
    for name, active in pairs(Running) do
        if active then task.spawn(function() stopModule(name) task.wait(1) startModule(name) end) end
    end
end)

task.spawn(function()
    local VirtualUser = game:GetService("VirtualUser")
    LP.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

task.spawn(createUI)
Config.Notify("GAG Hub Loaded!", "Toggle in UI or use _G.GAGHub API.", 5)
print("GAG HUB loaded! Console: _G.GAGHub")
