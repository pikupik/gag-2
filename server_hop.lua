--[[
    GAG2 — Auto Random Server Hop
    Standalone script with simple native Roblox UI menu.
    
    Usage:
      loadstring(game:HttpGet("https://raw.githubusercontent.com/ahmadlagi889-commits/tempek-gag2/main/server_hop.lua"))()
]]

if not game or not game:GetService("Players") then
    error("[ServerHop] Must run inside Roblox game")
end

---------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------

local Players         = game:GetService("Players")
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local StarterGui      = game:GetService("StarterGui")
local VirtualUser     = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local PlaceId = game.PlaceId
local CurrentJobId = game.JobId

---------------------------------------------------------------
-- STATE
---------------------------------------------------------------

local State = {
    MinPlayers    = 1,
    MaxPlayers    = 0,    -- 0 = no limit
    HopInterval   = 0,    -- 0 = single hop
    AutoHop       = false,
    Hopping       = false,
    LastStatus    = "Idle",
    HopsDone      = 0,
}

---------------------------------------------------------------
-- UTILS
---------------------------------------------------------------

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "ServerHop",
            Text = text or "",
            Duration = duration or 5,
        })
    end)
    print("[ServerHop]", title, "—", text)
end

local function httpGet(url)
    local ok, result = pcall(function()
        return HttpService:GetAsync(url)
    end)
    if not ok then
        warn("[ServerHop] HTTP GET failed:", result)
        return nil
    end
    return result
end

---------------------------------------------------------------
-- SERVER LOGIC
---------------------------------------------------------------

local function fetchServers()
    local allServers = {}
    local cursor = ""
    local pages = 0

    while pages < 5 do
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100%s",
            PlaceId,
            cursor ~= "" and ("&cursor=" .. cursor) or ""
        )

        local raw = httpGet(url)
        if not raw then break end

        local ok, data = pcall(function()
            return HttpService:JSONDecode(raw)
        end)
        if not ok or not data then break end

        local servers = data.data
        if not servers or #servers == 0 then break end

        for _, s in ipairs(servers) do
            table.insert(allServers, s)
        end

        pages += 1
        cursor = data.nextPageCursor or ""
        if cursor == "" then break end
        task.wait(0.5)
    end

    print("[ServerHop] Fetched", #allServers, "servers")
    return allServers
end

local function pickRandomServer(servers)
    local candidates = {}

    for _, s in ipairs(servers) do
        if s.id == CurrentJobId then continue end
        if s.playing >= s.maxPlayers then continue end
        if s.playing <= 0 then continue end
        if s.playing < State.MinPlayers then continue end
        if State.MaxPlayers > 0 and s.playing > State.MaxPlayers then continue end
        table.insert(candidates, s)
    end

    if #candidates == 0 then return nil end
    return candidates[math.random(1, #candidates)]
end

local function doHop()
    if State.Hopping then return end
    State.Hopping = true
    State.LastStatus = "Fetching servers..."

    local success = false
    for attempt = 1, 5 do
        State.LastStatus = string.format("Attempt %d/5...", attempt)

        local servers = fetchServers()
        if not servers or #servers == 0 then
            State.LastStatus = "No servers found, retrying..."
            task.wait(3)
            continue
        end

        local target = pickRandomServer(servers)
        if not target then
            State.LastStatus = "No valid server, retrying..."
            task.wait(3)
            continue
        end

        State.LastStatus = string.format("Hopping → %s (%d players)", target.id:sub(1, 8), target.playing)
        task.wait(1)

        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(PlaceId, target.id, LP)
        end)

        if ok then
            State.HopsDone += 1
            success = true
            task.wait(10)
            State.LastStatus = "Teleport pending..."
            break
        else
            State.LastStatus = "Teleport error: " .. tostring(err)
            warn("[ServerHop] Teleport error:", err)
        end

        task.wait(3)
    end

    if not success then
        State.LastStatus = "Failed after 5 attempts"
        notify("ServerHop", "Hop failed", 5)
    end

    State.Hopping = false
end

---------------------------------------------------------------
-- ANTI-AFK
---------------------------------------------------------------

Players.LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

---------------------------------------------------------------
-- TELEPORT FAIL HANDLER
---------------------------------------------------------------

TeleportService.TeleportInitFailed:Connect(function(_, teleportResult, msg)
    warn("[ServerHop] TeleportInitFailed:", teleportResult, msg)
    State.LastStatus = "Teleport failed: " .. tostring(msg)
    task.wait(3)
    if State.AutoHop then
        task.spawn(doHop)
    end
end)

---------------------------------------------------------------
-- UI BUILDER
---------------------------------------------------------------

-- Cleanup old UI if re-executing
local oldGui = LP.PlayerGui:FindFirstChild("ServerHopGui")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ServerHopGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = LP.PlayerGui

-- Main frame
local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.new(0, 260, 0, 320)
frame.Position = UDim2.new(0.5, -130, 0.5, -160)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 8)
frameCorner.Parent = frame

local frameStroke = Instance.new("UIStroke")
frameStroke.Color = Color3.fromRGB(80, 80, 80)
frameStroke.Thickness = 1
frameStroke.Parent = frame

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
titleBar.BorderSizePixel = 0
titleBar.Parent = frame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 8)
titleCorner.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -60, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "🌐 Server Hop"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 14
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -30, 0, 2)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextSize = 12
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Parent = titleBar

local closeBtnCorner = Instance.new("UICorner")
closeBtnCorner.CornerRadius = UDim.new(0, 6)
closeBtnCorner.Parent = closeBtn

-- Content area
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, -20, 1, -42)
content.Position = UDim2.new(0, 10, 0, 38)
content.BackgroundTransparency = 1
content.Parent = frame

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 6)
layout.Parent = content

---------------------------------------------------------------
-- UI HELPER: Create labeled input
---------------------------------------------------------------

local function makeInput(parent, order, label, default, placeholder)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 40)
    container.BackgroundTransparency = 1
    container.LayoutOrder = order
    container.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.45, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    lbl.TextSize = 12
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = container

    local input = Instance.new("TextBox")
    input.Size = UDim2.new(0.5, 0, 0, 26)
    input.Position = UDim2.new(0.5, 0, 0.5, -13)
    input.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    input.BorderSizePixel = 0
    input.Text = tostring(default)
    input.PlaceholderText = placeholder or ""
    input.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
    input.TextColor3 = Color3.fromRGB(255, 255, 255)
    input.TextSize = 13
    input.Font = Enum.Font.Gotham
    input.ClearTextOnFocus = false
    input.Parent = container

    local inputCorner = Instance.new("UICorner")
    inputCorner.CornerRadius = UDim.new(0, 4)
    inputCorner.Parent = input

    local inputPad = Instance.new("UIPadding")
    inputPad.PaddingLeft = UDim.new(0, 6)
    inputPad.Parent = input

    return input
end

---------------------------------------------------------------
-- UI HELPER: Create button
---------------------------------------------------------------

local function makeButton(parent, order, text, color)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 32)
    btn.BackgroundColor3 = color or Color3.fromRGB(60, 60, 60)
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 13
    btn.Font = Enum.Font.GothamMedium
    btn.LayoutOrder = order
    btn.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    return btn
end

---------------------------------------------------------------
-- BUILD UI ELEMENTS
---------------------------------------------------------------

-- MinPlayers input
local minInput = makeInput(content, 1, "Min Players", State.MinPlayers, "1")

-- MaxPlayers input
local maxInput = makeInput(content, 2, "Max Players", State.MaxPlayers, "0 = no limit")

-- Interval input
local intervalInput = makeInput(content, 3, "Hop Interval (s)", State.HopInterval, "0 = once")

-- Hop Now button
local hopBtn = makeButton(content, 4, "⚡ Hop Now", Color3.fromRGB(40, 120, 40))

-- Auto-Hop toggle button
local autoBtn = makeButton(content, 5, "▶ Auto-Hop: OFF", Color3.fromRGB(50, 80, 140))

-- Separator
local sep = Instance.new("Frame")
sep.Size = UDim2.new(1, 0, 0, 1)
sep.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
sep.BorderSizePixel = 0
sep.LayoutOrder = 6
sep.Parent = content

-- Status label
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 20)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Status: Idle"
statusLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
statusLabel.TextSize = 11
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.LayoutOrder = 7
statusLabel.Parent = content

-- Hops counter
local hopsLabel = Instance.new("TextLabel")
hopsLabel.Size = UDim2.new(1, 0, 0, 20)
hopsLabel.BackgroundTransparency = 1
hopsLabel.Text = "Hops: 0"
hopsLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
hopsLabel.TextSize = 11
hopsLabel.Font = Enum.Font.Gotham
hopsLabel.TextXAlignment = Enum.TextXAlignment.Left
hopsLabel.LayoutOrder = 8
hopsLabel.Parent = content

-- Server info
local serverLabel = Instance.new("TextLabel")
serverLabel.Size = UDim2.new(1, 0, 0, 20)
serverLabel.BackgroundTransparency = 1
serverLabel.Text = "Server: " .. CurrentJobId:sub(1, 12) .. "..."
serverLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
serverLabel.TextSize = 11
serverLabel.Font = Enum.Font.Gotham
serverLabel.TextXAlignment = Enum.TextXAlignment.Left
serverLabel.LayoutOrder = 9
serverLabel.Parent = content

---------------------------------------------------------------
-- UI LOGIC
---------------------------------------------------------------

-- Sync inputs → state
local function syncInputs()
    local minVal = tonumber(minInput.Text)
    if minVal and minVal >= 0 then
        State.MinPlayers = math.floor(minVal)
    end

    local maxVal = tonumber(maxInput.Text)
    if maxVal and maxVal >= 0 then
        State.MaxPlayers = math.floor(maxVal)
    end

    local intVal = tonumber(intervalInput.Text)
    if intVal and intVal >= 0 then
        State.HopInterval = intVal
    end
end

-- Status updater
task.spawn(function()
    while gui.Parent do
        statusLabel.Text = "Status: " .. State.LastStatus
        hopsLabel.Text = "Hops: " .. State.HopsDone
        task.wait(0.5)
    end
end)

-- Hop Now
hopBtn.MouseButton1Click:Connect(function()
    syncInputs()
    if State.Hopping then return end
    task.spawn(doHop)
end)

-- Auto-Hop toggle
local autoThread = nil

autoBtn.MouseButton1Click:Connect(function()
    syncInputs()
    State.AutoHop = not State.AutoHop

    if State.AutoHop then
        autoBtn.Text = "⏸ Auto-Hop: ON"
        autoBtn.BackgroundColor3 = Color3.fromRGB(140, 80, 40)

        autoThread = task.spawn(function()
            while State.AutoHop do
                if not State.Hopping then
                    doHop()
                end
                local waitTime = State.HopInterval > 0 and State.HopInterval or 30
                State.LastStatus = string.format("Next hop in %ds...", waitTime)
                task.wait(waitTime)
            end
        end)
    else
        autoBtn.Text = "▶ Auto-Hop: OFF"
        autoBtn.BackgroundColor3 = Color3.fromRGB(50, 80, 140)
        State.LastStatus = "Auto-hop stopped"
    end
end)

-- Close button → destroy UI + stop everything
closeBtn.MouseButton1Click:Connect(function()
    State.AutoHop = false
    gui:Destroy()
end)

-- Toggle UI with RightShift
local uiVisible = true
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        uiVisible = not uiVisible
        frame.Visible = uiVisible
    end
end)

---------------------------------------------------------------
-- ENTRY POINT
---------------------------------------------------------------

math.randomseed(tick())
print("[ServerHop] Script loaded | PlaceId:", PlaceId, "| JobId:", CurrentJobId)
print("[ServerHop] Press RightShift to toggle UI")
notify("ServerHop", "Ready — RightShift to toggle UI")
