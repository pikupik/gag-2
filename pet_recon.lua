--[[
    Pet Catch Recon — saves output to workspace/pet_recon.txt
    Usage: loadstring(game:HttpGet("URL"))() or paste in executor
]]

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local CS = game:GetService("CollectionService")

local out = {}
local function log(s) table.insert(out, s) end
local function logf(fmt, ...)
    local args = {...}
    for i = 1, select("#", ...) do
        args[i] = tostring(args[i])
    end
    table.insert(out, string.format(fmt, unpack(args)))
end

log("=== PET CATCH RECON ===")
logf("Player: %s", LP.Name)
logf("PlaceId: %s", game.PlaceId)
logf("JobId: %s", game.JobId)
log("")

---------------------------------------------------------------
-- 1. SCAN WORKSPACE FOR PET-RELATED MODELS/PARTS
---------------------------------------------------------------
log("--- 1. PET-RELATED INSTANCES IN WORKSPACE ---")
local petKeywords = {"pet", "catch", "animal", "creature", "wild", "spawn", "net", "trap"}
local found = {}

for _, desc in ipairs(workspace:GetDescendants()) do
    local name = string.lower(desc.Name)
    for _, kw in ipairs(petKeywords) do
        if string.find(name, kw) then
            table.insert(found, {
                path = desc:GetFullName(),
                class = desc.ClassName,
                name = desc.Name,
            })
            break
        end
    end
end

-- CollectionService tags
local petTags = {}
for _, tag in ipairs(CS:GetAllTags()) do
    local tagLower = string.lower(tag)
    for _, kw in ipairs(petKeywords) do
        if string.find(tagLower, kw) then
            local instances = CS:GetTagged(tag)
            table.insert(petTags, { tag = tag, count = #instances })
            for _, inst in ipairs(instances) do
                table.insert(found, {
                    path = inst:GetFullName(),
                    class = inst.ClassName,
                    name = inst.Name,
                    tag = tag,
                })
            end
            break
        end
    end
end

if #petTags > 0 then
    log("Pet-related CollectionService tags:")
    for _, t in ipairs(petTags) do
        logf("  [%s] x%d", t.tag, t.count)
    end
end

logf("Found %d pet-related instances:", #found)
for i, f in ipairs(found) do
    local tagStr = f.tag and (" [tag:" .. f.tag .. "]") or ""
    logf("  %d. %s -> %s%s", i, f.class, f.path, tagStr)
end
log("")

---------------------------------------------------------------
-- 2. SCAN FOR PROXIMITYPROMPTS NEAR PET-RELATED AREAS
---------------------------------------------------------------
log("--- 2. PROXIMITYPROMPTS ON PET-RELATED INSTANCES ---")
local promptCount = 0
for _, desc in ipairs(workspace:GetDescendants()) do
    if desc:IsA("ProximityPrompt") then
        local parent = desc.Parent
        local grandparent = parent and parent.Parent
        local context = string.lower((parent and parent.Name or "") .. " " .. (grandparent and grandparent.Name or ""))

        local isPetRelated = false
        for _, kw in ipairs(petKeywords) do
            if string.find(context, kw) then
                isPetRelated = true
                break
            end
        end

        if isPetRelated then
            promptCount += 1
            logf("  ProximityPrompt in: %s", desc.Parent:GetFullName())
            logf("    ActionText: %s", desc.ActionText)
            logf("    ObjectText: %s", desc.ObjectText)
            logf("    HoldDuration: %s", tostring(desc.HoldDuration))
            logf("    MaxActivationDistance: %s", tostring(desc.MaxActivationDistance))
            logf("    Enabled: %s", tostring(desc.Enabled))
        end
    end
end
if promptCount == 0 then
    log("  (none found near pet-related instances)")
end
log("")

---------------------------------------------------------------
-- 3. SCAN ATTRIBUTES ON FOUND PET INSTANCES
---------------------------------------------------------------
log("--- 3. ATTRIBUTES ON PET INSTANCES ---")
local attrCount = 0
for _, f in ipairs(found) do
    local parts = {}
    for seg in string.gmatch(f.path, "[^%.]+") do
        table.insert(parts, seg)
    end

    local inst = workspace
    for _, seg in ipairs(parts) do
        inst = inst:FindFirstChild(seg)
        if not inst then break end
    end

    if inst then
        local attrs = inst:GetAttributes()
        local hasAttrs = false
        for _ in pairs(attrs) do hasAttrs = true break end

        if hasAttrs then
            attrCount += 1
            logf("  %s (%s)", f.path, f.class)
            for k, v in pairs(attrs) do
                logf("    %s = %s (%s)", k, tostring(v), typeof(v))
            end
        end
    end
end
if attrCount == 0 then
    log("  (no attributes found)")
end
log("")

---------------------------------------------------------------
-- 4. SCAN FOR PET/CATCH REMOTES IN REPLICATEDSTORAGE
---------------------------------------------------------------
log("--- 4. PET/CATCH REMOTES IN REPLICATEDSTORAGE ---")
local remoteCount = 0
for _, desc in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
    local name = string.lower(desc.Name)
    local isPet = false
    for _, kw in ipairs(petKeywords) do
        if string.find(name, kw) then
            isPet = true
            break
        end
    end

    if isPet and (desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction")) then
        remoteCount += 1
        logf("  %s -> %s", desc.ClassName, desc:GetFullName())
    end
end
if remoteCount == 0 then
    log("  (no pet-related remotes found)")
end
log("")

---------------------------------------------------------------
-- 5. NETWORKING MODULE - ALL KEYS AND METHODS
---------------------------------------------------------------
log("--- 5. NETWORKING MODULE - ALL KEYS ---")
local ok, net = pcall(function()
    local shared = game:GetService("ReplicatedStorage"):WaitForChild("SharedModules", 5)
    if not shared then return nil end
    local netMod = shared:FindFirstChild("Networking")
    if not netMod then return nil end
    return require(netMod)
end)

if ok and net and type(net) == "table" then
    log("All top-level Networking keys:")
    for key, val in pairs(net) do
        if type(val) == "table" then
            local methods = {}
            for m, _ in pairs(val) do table.insert(methods, m) end
            logf("  %s -> {%s}", key, table.concat(methods, ", "))
        end
    end

    -- Highlight pet/catch related
    log("")
    log("Pet/Catch related keys:")
    for key, val in pairs(net) do
        if type(val) == "table" then
            local keyLower = string.lower(key)
            local isPet = false
            for _, kw in ipairs(petKeywords) do
                if string.find(keyLower, kw) then
                    isPet = true
                    break
                end
            end

            if isPet then
                logf("  Networking.%s:", key)
                for method, _ in pairs(val) do
                    logf("    .%s", tostring(method))
                end
            end
        end
    end
else
    log("  (Networking module not accessible)")
end
log("")

---------------------------------------------------------------
-- 6. SCAN PLAYER BACKPACK/CHARACTER FOR CATCH TOOLS
---------------------------------------------------------------
log("--- 6. CATCH-RELATED TOOLS ---")
local bp = LP:FindFirstChild("Backpack")
local function scanTools(container, label)
    if not container then return end
    for _, tool in ipairs(container:GetChildren()) do
        if tool:IsA("Tool") then
            local tname = string.lower(tool.Name)
            for _, kw in ipairs(petKeywords) do
                if string.find(tname, kw) then
                    logf("  %s: %s", label, tool.Name)
                    for k, v in pairs(tool:GetAttributes()) do
                        logf("    %s = %s", k, tostring(v))
                    end
                    break
                end
            end
        end
    end
end
scanTools(bp, "Backpack")
scanTools(LP.Character, "Equipped")
if bp then
    local anyTools = false
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") then anyTools = true break end
    end
    if not anyTools then log("  (no tools in backpack)") end
end
log("")

---------------------------------------------------------------
-- 7. CHECK MAP FOLDERS FOR PET SPAWN LOCATIONS
---------------------------------------------------------------
log("--- 7. MAP FOLDERS WITH PET/SPAWN ---")
local map = workspace:FindFirstChild("Map")
if map then
    for _, child in ipairs(map:GetChildren()) do
        local name = string.lower(child.Name)
        for _, kw in ipairs(petKeywords) do
            if string.find(name, kw) then
                local childCount = #child:GetChildren()
                logf("  Folder: %s (%d children)", child.Name, childCount)
                for i, c in ipairs(child:GetChildren()) do
                    if i > 10 then
                        logf("    ... and %d more", childCount - 10)
                        break
                    end
                    logf("    %s: %s", c.ClassName, c.Name)
                    for k, v in pairs(c:GetAttributes()) do
                        logf("      %s = %s", k, tostring(v))
                    end
                end
                break
            end
        end
    end
else
    log("  (no Map folder found)")
end
log("")

---------------------------------------------------------------
-- 8. ALL PROXIMITYPROMPTS IN WORKSPACE (full dump)
---------------------------------------------------------------
log("--- 8. ALL PROXIMITYPROMPTS (full) ---")
local allPrompts = 0
for _, desc in ipairs(workspace:GetDescendants()) do
    if desc:IsA("ProximityPrompt") then
        allPrompts += 1
        if allPrompts <= 50 then
            logf("  %s", desc.Parent:GetFullName())
            logf("    Action=%s Object=%s Hold=%s Dist=%s",
                tostring(desc.ActionText), tostring(desc.ObjectText), tostring(desc.HoldDuration), tostring(desc.MaxActivationDistance))
        end
    end
end
logf("  Total ProximityPrompts: %d", allPrompts)
log("")

---------------------------------------------------------------
-- 9. ALL REMOTE EVENTS/FUNCTIONS (full dump)
---------------------------------------------------------------
log("--- 9. ALL REMOTES IN REPLICATEDSTORAGE ---")
for _, desc in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
    if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
        logf("  %s: %s", desc.ClassName, desc:GetFullName())
    end
end
log("")

log("=== RECON COMPLETE ===")

-- Save to file
local filename = "pet_recon.txt"
local content = table.concat(out, "\n")

if writefile then
    writefile(filename, content)
    logf("Saved to: %s", filename)
    print("[Pet Recon] Saved to workspace/" .. filename .. " (" .. #out .. " lines)")
else
    -- Fallback: print everything
    print(content)
    print("[Pet Recon] writefile not available, printed to console")
end
