local player = game.Players.LocalPlayer
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local lastNotifyTime = 0
local NOTIFY_COOLDOWN = 1.0
local lastNotifiedSkin = nil

local function SafeNotify(message, title, duration)
    local now = tick()
    if title and lastNotifiedSkin == title then
        if now - lastNotifyTime < NOTIFY_COOLDOWN then
            return
        end
    end
    lastNotifyTime = now
    lastNotifiedSkin = title
    pcall(notify, message, title or "Walking Dead", duration or 2)
end

local persistentState = {
    inspectorEnabled = false,
    uiScale = 1.0,
    modPanelScale = 1.0,
    itemEspEnabled = false,
    itemDistance = 150,
    itemToggles = {},
    categoryToggles = {},
    corpseEspEnabled = false,
    corpseDistance = 1000,
    equipmentEspEnabled = false,
    equipmentDistance = 150,
    equipmentToggles = {},
    equipmentCategoryToggles = {},
    teleportEnabled = false,
    selectedPOI = 0,
    bannerEspEnabled = false,
    bannerDistance = 500,
    carEspEnabled = false,
    carDistance = 500,
    modDetectorEnabled = false,
}

local emptyScanTracker = {}

local bannerRenderCounter = 0
local corpseRenderCounter = 0
local carRenderCounter = 0
local frameCounter = 0
local panelFrameCounter = 0
local PANEL_UPDATE_EVERY_N_FRAMES = 3

local POI_LOCATIONS = {
    ["Terminus"] = Vector3.new(1652.68, 199.18, -679.05),
    ["PD"] = Vector3.new(3814.08, 125.18, -686.19),
    ["Prison"] = Vector3.new(5501.63, 117.13, -2493.90),
    ["Bunker"] = Vector3.new(5539.28, 211.88, -6108.75),
    ["Alexandria"] = Vector3.new(71.33, 118.16, -5417.76),
    ["Port"] = Vector3.new(-4520.35, 62.46, -5795.67),
    ["Sanctuary"] = Vector3.new(-4425.31, 104.66, -3455.77),
    ["Hilltop"] = Vector3.new(-4786.34, 140.93, -927.64),
    ["Satellite Outpost"] = Vector3.new(-2196.25, 292.82, 12.23),
    ["King County"] = Vector3.new(-4121.66, 172.43, 3599.39),
    ["Quarry"] = Vector3.new(-5750.19, 283.56, 6282.38),
    ["Hospital"] = Vector3.new(-1805.95, 172.30, 5577.22),
    ["WoodBury"] = Vector3.new(4502.21, 117.22, 1183.52),
    ["Big Spot"] = Vector3.new(2243.32, 248.34, 2089.93),
    ["Air Strip"] = Vector3.new(3626.93, 129.94, 3917.03),
    ["FarmHouse"] = Vector3.new(3175.00, 130.13, 4920.74)
}

local POI_NAMES = {}
for name, _ in pairs(POI_LOCATIONS) do
    table.insert(POI_NAMES, name)
end
table.sort(POI_NAMES)

local character = nil
local hrp = nil
local itemRescanKeybind = nil
local bannerRescanKeybind = nil
local corpseRescanKeybind = nil
local carRescanKeybind = nil

local MOD_LIST_WITH_ROLES = {
    {name = "KiidRagnos", role = "Moderator"},
    {name = "Supply_Runner", role = "Moderator"},
    {name = "bikerr_r", role = "Moderator"},
    {name = "jasper155555", role = "Moderator"},
    {name = "FadeXtoXmyst", role = "Moderator"},
    {name = "Skaflora", role = "Moderator"},
    {name = "HaticeOyunG", role = "Moderator"},
    {name = "Etwanrosa2point0", role = "Moderator"},
    {name = "therealskylad3144", role = "Moderator"},
    {name = "Placvid", role = "Moderator"},
    {name = "Domtwdg", role = "Moderator"},
    {name = "cwiinder", role = "Moderator"},
    {name = "ReiIsReallyShy", role = "Moderator"},
    {name = "mqriahs", role = "Moderator"},
    {name = "CallMeNucu", role = "Moderator"},
    {name = "sephriothgatsuga", role = "Moderator"},
    {name = "TheNotLeq", role = "Moderator"},
    {name = "Forest_Gump04", role = "Moderator"},
    {name = "D4rl1ngGh0ul", role = "Moderator"},
    {name = "VarsityRebel", role = "Moderator"},
    {name = "g1rlwhat666", role = "Moderator"},
    {name = "hachimansolos", role = "Moderator"},
    {name = "chris_03001", role = "Moderator"},
    {name = "IrelventNox", role = "Moderator"},
    {name = "DougAbilities", role = "Moderator"},
    {name = "rewqq0123", role = "Moderator"},
    {name = "XxGlobeX_LeaderxX", role = "Moderator"},
    {name = "aero_luvv", role = "Moderator"},
    {name = "Icon_power0", role = "Moderator"},
    {name = "kruiined", role = "Developer"},
    {name = "RickDGrimesSr", role = "Developer"},
    {name = "LANOLMVURMASANA", role = "Developer"},
    {name = "Mythfuly", role = "Developer"},
    {name = "GRLLTEBU", role = "Developer"},
}

local notifiedMods = {}
local panelObjects = {}
local panelCache = {}
local panelUpdateTime = 0
local PANEL_INTERVAL = 5
local panelVisible = false
local lastModListHash = ""
local modPanelRenderCounter = 0
local MOD_PANEL_UPDATE_INTERVAL = 2
local noModsShown = false
local lastModListHash = ""
local cachedTargetHash = ""
local lastTargetCheck = 0
local TARGET_CHECK_INTERVAL = 0.5
local cachedTargetData = nil
local cachedTargetName = ""
local cachedTargetType = ""
local targetDataCacheTime = 0
local TARGET_DATA_CACHE_INTERVAL = 1.0

local function TruncateText(text, maxLen)
    if not text then return "" end
    if #text <= maxLen then return text end
    return string.sub(text, 1, maxLen - 3) .. "..."
end

local function BuildPanel()
    for _, obj in ipairs(panelObjects) do
        pcall(obj.Remove, obj)
    end
    panelObjects = {}
    
    local scale = persistentState.modPanelScale or 1.0
    local padding = math.floor(14 * scale)
    local lineHeight = math.floor(22 * scale)
    local titleHeight = math.floor(36 * scale)
    local panelWidth = math.floor(340 * scale)
    
    local bg = Drawing.new("Square")
    bg.Filled = true
    bg.Color = Color3.fromRGB(20, 20, 25)
    bg.Transparency = 0.85
    bg.ZIndex = 996
    bg.Corner = math.floor(8 * scale)
    bg.Visible = false
    table.insert(panelObjects, bg)
    
    local outline = Drawing.new("Square")
    outline.Filled = false
    outline.Color = Color3.fromRGB(255, 200, 50)
    outline.Thickness = 2
    outline.ZIndex = 997
    outline.Corner = math.floor(8 * scale)
    outline.Visible = false
    table.insert(panelObjects, outline)
    
    local titleBg = Drawing.new("Square")
    titleBg.Filled = true
    titleBg.Color = Color3.fromRGB(45, 45, 55)
    titleBg.Transparency = 0
    titleBg.ZIndex = 998
    titleBg.Corner = math.floor(8 * scale)
    titleBg.Visible = false
    table.insert(panelObjects, titleBg)
    
    local title = Drawing.new("Text")
    title.Font = Drawing.Fonts.System
    title.Size = math.floor(16 * scale)
    title.Color = Color3.fromRGB(255, 200, 50)
    title.Outline = true
    title.Center = false
    title.ZIndex = 999
    title.Visible = false
    table.insert(panelObjects, title)
    
    local divider = Drawing.new("Line")
    divider.Color = Color3.fromRGB(80, 80, 100)
    divider.Thickness = 1
    divider.ZIndex = 998
    divider.Visible = false
    table.insert(panelObjects, divider)
    
    for i = 1, 25 do
        local nameText = Drawing.new("Text")
        nameText.Font = Drawing.Fonts.System
        nameText.Size = math.floor(13 * scale)
        nameText.Color = Color3.fromRGB(255, 255, 255)
        nameText.Outline = true
        nameText.Center = false
        nameText.ZIndex = 1000
        nameText.Visible = false
        table.insert(panelObjects, nameText)
        
        local roleText = Drawing.new("Text")
        roleText.Font = Drawing.Fonts.System
        roleText.Size = math.floor(12 * scale)
        roleText.Outline = true
        roleText.Center = false
        roleText.ZIndex = 1000
        roleText.Visible = false
        table.insert(panelObjects, roleText)
    end
    
    panelObjects.bg = bg
    panelObjects.outline = outline
    panelObjects.titleBg = titleBg
    panelObjects.title = title
    panelObjects.divider = divider
    panelObjects.padding = padding
    panelObjects.lineHeight = lineHeight
    panelObjects.titleHeight = titleHeight
    panelObjects.panelWidth = panelWidth
    panelObjects.scale = scale
    panelObjects.textStartIndex = 6
    
    panelVisible = false
end

local function UpdatePanel()
    if not persistentState.modDetectorEnabled then
        for _, obj in ipairs(panelObjects) do
            if obj then obj.Visible = false end
        end
        panelVisible = false
        return
    end
    
    if #panelObjects == 0 then
        BuildPanel()
    end
    
    if #panelObjects == 0 or not panelObjects.bg then
        return
    end
    
    local found = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        for _, modData in ipairs(MOD_LIST_WITH_ROLES) do
            if plr.Name == modData.name then
                table.insert(found, {name = plr.Name, role = modData.role})
                break
            end
        end
    end
    
    local currentHash = ""
    for i = 1, #found do
        currentHash = currentHash .. found[i].name .. "|" .. found[i].role .. ","
    end
    
    if currentHash == lastModListHash and panelVisible then
        return
    end
    
    lastModListHash = currentHash
    panelCache = found
    
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    local viewportSize = camera.ViewportSize
    local scale = panelObjects.scale or 1.0
    local padding = panelObjects.padding or 14
    local lineHeight = panelObjects.lineHeight or 22
    local titleHeight = panelObjects.titleHeight or 36
    local panelWidth = panelObjects.panelWidth or 340
    local textStartIndex = panelObjects.textStartIndex or 6
    
    local count = #panelCache
    local maxDisplay = math.min(count, 25)
    local displayCount = math.max(maxDisplay, 1)
    local extraPadding = lineHeight * 0.8
    local contentHeight = titleHeight + (displayCount * lineHeight) + padding + extraPadding
    local panelX = viewportSize.X - panelWidth - math.floor(20 * scale)
    local panelY = math.floor(20 * scale)
    
    local bg = panelObjects.bg
    if bg then
        bg.Size = Vector2.new(panelWidth, contentHeight)
        bg.Position = Vector2.new(panelX, panelY)
        bg.Visible = true
    end
    
    local outline = panelObjects.outline
    if outline then
        outline.Size = Vector2.new(panelWidth, contentHeight)
        outline.Position = Vector2.new(panelX, panelY)
        outline.Visible = true
    end
    
    local titleBg = panelObjects.titleBg
    if titleBg then
        titleBg.Size = Vector2.new(panelWidth, titleHeight)
        titleBg.Position = Vector2.new(panelX, panelY)
        titleBg.Visible = true
    end
    
    local title = panelObjects.title
    if title then
        title.Position = Vector2.new(panelX + padding, panelY + (titleHeight / 2) - (title.Size / 2))
        title.Text = "Mod Inspector"
        title.Visible = true
    end
    
    local divider = panelObjects.divider
    local dividerY = panelY + titleHeight + math.floor(extraPadding * 0.3)
    if divider then
        divider.From = Vector2.new(panelX + 5, dividerY)
        divider.To = Vector2.new(panelX + panelWidth - 5, dividerY)
        divider.Visible = true
    end
    
    local nameMaxLen = math.floor((panelWidth - padding - 80 * scale - padding) / (7 * scale))
    if nameMaxLen < 5 then nameMaxLen = 5 end
    local yOffset = dividerY + math.floor(extraPadding * 0.7)
    
    if count == 0 then
        for i = textStartIndex, #panelObjects do
            if panelObjects[i] then
                if i == textStartIndex then
                    panelObjects[i].Position = Vector2.new(panelX + padding, yOffset)
                    panelObjects[i].Text = "No mods found"
                    panelObjects[i].Color = Color3.fromRGB(150, 150, 150)
                    panelObjects[i].Visible = true
                elseif i == textStartIndex + 1 then
                    panelObjects[i].Visible = false
                else
                    panelObjects[i].Visible = false
                end
            end
        end
    else
        for i = 1, maxDisplay do
            local nameIndex = textStartIndex + ((i - 1) * 2)
            local roleIndex = textStartIndex + ((i - 1) * 2) + 1
            
            if nameIndex > #panelObjects or roleIndex > #panelObjects then break end
            
            local nameObj = panelObjects[nameIndex]
            local roleObj = panelObjects[roleIndex]
            local mod = panelCache[i]
            
            if nameObj and roleObj and mod then
                local displayName = TruncateText(mod.name, nameMaxLen)
                
                nameObj.Position = Vector2.new(panelX + padding, yOffset)
                nameObj.Text = displayName
                nameObj.Color = Color3.fromRGB(255, 255, 255)
                nameObj.Visible = true
                
                local roleColor = Color3.fromRGB(255, 200, 50)
                local roleLower = string.lower(mod.role)
                if roleLower:find("owner") then roleColor = Color3.fromRGB(255, 50, 50)
                elseif roleLower:find("developer") then roleColor = Color3.fromRGB(100, 200, 255)
                elseif roleLower:find("admin") then roleColor = Color3.fromRGB(255, 100, 100) end
                
                roleObj.Position = Vector2.new(panelX + panelWidth - padding - (string.len(mod.role) * 7 * scale), yOffset)
                roleObj.Text = mod.role
                roleObj.Color = roleColor
                roleObj.Visible = true
                
                yOffset = yOffset + lineHeight
            end
        end
        
        for i = maxDisplay + 1, 25 do
            local nameIndex = textStartIndex + ((i - 1) * 2)
            local roleIndex = textStartIndex + ((i - 1) * 2) + 1
            if nameIndex <= #panelObjects and panelObjects[nameIndex] then
                panelObjects[nameIndex].Visible = false
            end
            if roleIndex <= #panelObjects and panelObjects[roleIndex] then
                panelObjects[roleIndex].Visible = false
            end
        end
    end
    
    panelVisible = true
end

local function ClearModPanel()
    for _, obj in ipairs(panelObjects) do
        if obj then
            obj.Visible = false
        end
    end
    panelVisible = false
end

local modPanelRenderCounter = 0
local MOD_PANEL_UPDATE_INTERVAL = 2

local function RenderModPanel()
    if not persistentState.modDetectorEnabled then
        if panelVisible then
            for _, obj in ipairs(panelObjects) do
                if obj then obj.Visible = false end
            end
            panelVisible = false
        end
        return
    end
    
    if panelVisible then
        return
    end
    
    modPanelRenderCounter = modPanelRenderCounter + 1
    if modPanelRenderCounter < MOD_PANEL_UPDATE_INTERVAL then
        return
    end
    modPanelRenderCounter = 0
    
    local now = tick()
    if now - panelUpdateTime < 0.1 then
        return
    end
    
    panelUpdateTime = now
    UpdatePanel()
end

local function ForcePanelShow()
    panelUpdateTime = 0
    lastModListHash = ""
    if #panelObjects == 0 then
        BuildPanel()
    end
    UpdatePanel()
end

local function DestroyModPanel()
    for _, obj in ipairs(panelObjects) do
        pcall(obj.Remove, obj)
    end
    panelObjects = {}
    panelVisible = false
    lastModListHash = ""
end

local function ModNotify(message, title, duration)
    duration = duration or 5
    title = title or "Mod Inspector"
    local ok = pcall(notify, message, title, duration)
    if not ok then
        pcall(SafeNotify, message, title, duration)
    end
end

local function CheckExistingMods()
    local found = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        for _, modData in ipairs(MOD_LIST_WITH_ROLES) do
            if plr.Name == modData.name then
                table.insert(found, plr.Name)
                notifiedMods[plr.Name] = true
                break
            end
        end
    end
    
    if #found > 0 then
        ModNotify("Found " .. #found .. " mod(s) in this server", "Mod Inspector", 3)
        for _, name in ipairs(found) do
            ModNotify(name .. " is a mod", "Mod Inspector", 5)
        end
    else
        ModNotify("No mods found in this server", "Mod Inspector", 2)
    end
end

local modMonitorTask = nil

local function StartModMonitor()
    if modMonitorTask then return end
    
    modMonitorTask = task.spawn(function()
        ForcePanelShow()
        
        CheckExistingMods()
        
        while persistentState.modDetectorEnabled do
            task.wait(5)
            
            local currentMods = {}
            for _, plr in ipairs(Players:GetPlayers()) do
                for _, modData in ipairs(MOD_LIST_WITH_ROLES) do
                    if plr.Name == modData.name then
                        currentMods[plr.Name] = true
                        break
                    end
                end
            end
            
            local modsLeft = false
            for name in pairs(notifiedMods) do
                if not currentMods[name] then
                    ModNotify(name .. " left the game", "Mod Inspector", 3)
                    notifiedMods[name] = nil
                    modsLeft = true
                end
            end
            
            local foundNew = false
            for name in pairs(currentMods) do
                if not notifiedMods[name] then
                    ModNotify(name .. " is a mod", "Mod Inspector", 5)
                    notifiedMods[name] = true
                    foundNew = true
                end
            end
            
            if foundNew or modsLeft then
                lastModListHash = ""
                DestroyModPanel()
                BuildPanel()
                ForcePanelShow()
            end
        end
        
        modMonitorTask = nil
    end)
end

local function ClearModListDrawings()
    ClearModPanel()
end

local function EnsureCharacter()
    if not character or not character.Parent then
        character = player.Character or player.CharacterAdded:Wait()
        if not character then return false end
        hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
    end
    
    if not hrp or not hrp.Parent then
        hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
    end
    
    return true
end

local function TeleportToPOI(index)
    local name = POI_NAMES[index + 1]
    if not name then
        SafeNotify("Invalid POI selected!", "Teleport", 2)
        return
    end
    
    local pos = POI_LOCATIONS[name]
    if not pos then
        SafeNotify("Position not found for " .. name, "Teleport", 2)
        return
    end
    
    if not EnsureCharacter() then
        SafeNotify("Character not found!", "Teleport", 2)
        return
    end
    
    if not hrp then
        SafeNotify("Root part not found!", "Teleport", 2)
        return
    end
    
    hrp.CFrame = CFrame.new(pos.X, pos.Y, pos.Z)
    SafeNotify("Teleported to " .. name, "Teleport", 3)
end

local ITEM_TYPES = {
    ["Weapons"] = {
        "AR15", "AK47", "M4A1", "MP5", "Remington 870", "SKS", "VSS", "AS VAL",
        "SR-25", "M110", "MK14", "M14", "M9", "UMP", "UMP45", "MP5K", "Glock17",
        "M1911", "Colt Python", "BerretaM9", "Kar98K", "M1917", "M82A1", "FN Fal",
        "HK UMP-45", "AKS-74U", "Desert Eagle", "FN Five-seveN", "Model77E",
        "M40", "VSS Vintorez", "MK 2 Grenade", "M67 Grenade", "M18 Smoke Grenade",
    },
    ["Melee"] = {
        "Battle Hammer", "Mace", "Shiv", "Spiked Bat", "Wooden Bat",
        "Crowbar", "Fire Axe", "Hatchet", "Machete", "karambit",
        "Pipe Wrench", "Claw Hammer", "Pickaxe", "KA-BAR", "Cleaver",
        "Combat Knife", "Hammer", "Nightstick", "Hunting Knife", "Tactical knife",
        "Shovel",
    },
    ["Ammo"] = {
        ".12 Gauge", ".22LR", ".357 Magnum", ".45 ACP", ".50 BMG",
        "5.45x39mm", "5.56x45mm", "5.7x28mm", "7.62x39mm", "7.62x51mm",
        "7.62x54mmR", "7.92x57mm", "9x19mm", "9x39mm",
    },
    ["Food"] = {
        "Apple Juice", "Biscuits", "Bottled Water", "Carbonated Water",
        "Chocolate Bar", "Chocolate Cookies", "Cola", "Energy Drink",
        "Grape Soda", "MRE", "Orange Juice", "Orange Soda", "Potato Chips",
        "Protein Bar", "Spicy Barbecue Chips", "Sweet Chili Chips",
        "Applesauce", "Baked Beans", "Beef Jerky", "Canned Peaches",
        "Canned Sardines", "Canned Tuna", "Chocobar", "Chocolate Spread",
        "Gummy Bears", "Milk", "Mixed Vegetables", "Peanut Butter",
        "Pork & Beans", "Salty Crackers", "Tomato Soup", "Chicken Soup",
        "Ham Spread",
    },
    ["Keycards"] = {
        "Bunker Access Keycard", "Prison Armory Access Keycard",
        "Satellite outpost Access Keycard", "Police Armory Access Keycard",
    },
    ["Misc"] = {
        "Bandage", "Improvised Bandage", "FlashLight", "Metal Parts",
        "Weapon Cleaning Kit", "Cloth", "Rag", "Stick",
    },
    ["Equipment"] = {
        "MICH Ballistic Helmet", "Motorcycle Helmet", "M1 Helmet", "Firefighter Helmet",
        "Basic NVGs", "Headlamp", "U.S. National Guard Plate Carrier", "Medic Vest",
        "K9 Vest", "Firefighter Vest", "VestBrownBlueShirt", "Plate Carrier",
        "Military Backpack", "Green School Backpack", "Black School Backpack", "Brown Traveler's Backpack", "Police Vest",
        "Tactical Vest", "Tactical Backpack", "Brown Canvas Backpack", "Military Duffel Bag", 
        "Knight's Chestplate", "Knight's Helmet", "Pinestriped Fedora", "Skate Helmet", "ATE Gen 3 Ballistic Helmet", "Ballistic Helmet",
        "ATE Gen 2 Ballistic Helmet", "BLACK OPS Helmet", "MOLLE Plate Carrier", "Tactical Plate Carrier", "KORUND",
    },
}

local function GetModelPosition(model)
    if not model then return nil end

    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
        return model.PrimaryPart.Position
    end

    local success, result = pcall(function()
        local cframe, size = model:GetBoundingBox()
        if cframe then
            return cframe.Position
        end
        return nil
    end)
    if success and result then
        return result
    end

    local partCount = 0
    for _, part in ipairs(model:GetDescendants()) do
        if partCount > 50 then break end
        if part:IsA("BasePart") then
            return part.Position
        end
        partCount = partCount + 1
    end

    local success2, result2 = pcall(function()
        return model:GetPivot().Position
    end)
    if success2 and result2 and result2.Magnitude > 0 then
        return result2
    end

    return nil
end

local function GetContainerPosition(child)
    if not child then return nil end

    local pos = GetModelPosition(child)
    if pos then
        return pos
    end

    local current = child.Parent
    local attempts = 0
    local maxAttempts = 15

    while current and attempts < maxAttempts do
        attempts = attempts + 1

        if current == Workspace or current == game then
            break
        end

        if current:IsA("Model") or current:IsA("Folder") then
            pos = GetModelPosition(current)
            if pos then
                return pos
            end
        end

        current = current.Parent
    end

    return nil
end

local function GetItemCategory(name)
    for category, items in pairs(ITEM_TYPES) do
        for _, item in ipairs(items) do
            if name == item then
                return category
            end
        end
    end
    return "Unknown"
end

local function GetItemColor(name)
    local category = GetItemCategory(name)
    if category == "Weapons" then
        return Color3.fromRGB(255, 200, 100)
    elseif category == "Melee" then
        return Color3.fromRGB(255, 150, 50)
    elseif category == "Ammo" then
        return Color3.fromRGB(255, 255, 100)
    elseif category == "Food" then
        return Color3.fromRGB(100, 255, 100)
    elseif category == "Keycards" then
        return Color3.fromRGB(255, 215, 0)
    elseif category == "Misc" then
        return Color3.fromRGB(200, 200, 255)
    elseif category == "Equipment" then
        return Color3.fromRGB(0, 255, 200)
    else
        return Color3.fromRGB(200, 200, 255)
    end
end

local itemDrawings = {}
local itemCache = {}
local itemFrameCounter = 0
local ITEM_UPDATE_EVERY_N_FRAMES = 1

local function ClearItemDrawings()
    for _, drawing in ipairs(itemDrawings) do
        pcall(drawing.Remove, drawing)
    end
    itemDrawings = {}
end

local function ScanAllItems()
    local foundItems = {}

    local enabledItems = {}
    local hasEnabled = false
    for name, enabled in pairs(persistentState.itemToggles) do
        if enabled then
            enabledItems[name] = true
            hasEnabled = true
        end
    end

    if not hasEnabled then
        return {}
    end

    local categoriesToScan = {}
    for category, items in pairs(ITEM_TYPES) do
        local hasAnyEnabled = false
        for _, itemName in ipairs(items) do
            if enabledItems[itemName] then
                hasAnyEnabled = true
                break
            end
        end
        if hasAnyEnabled then
            categoriesToScan[category] = true
        end
    end

    local physicalLoot = Workspace:FindFirstChild("PhysicalLoot")
    if physicalLoot and categoriesToScan["Food"] then
        for _, item in ipairs(physicalLoot:GetChildren()) do
            local name = item.Name
            local itemName = string.gsub(name, "^PhysicalLoot_", "")
            if enabledItems[itemName] then
                local itemPos = GetModelPosition(item)
                if itemPos then
                    table.insert(foundItems, {
                        Name = itemName,
                        Position = itemPos,
                        Category = GetItemCategory(itemName),
                        Color = GetItemColor(itemName),
                    })
                end
            end
        end
    end

    local lootables = Workspace:FindFirstChild("Lootables")
    if lootables then
        local processedCount = 0
        local maxItems = 5000

        local function ScanRecursive(parent)
            if processedCount > maxItems then return end

            for _, child in ipairs(parent:GetChildren()) do
                if processedCount > maxItems then break end

                if child:IsA("Model") or child:IsA("Folder") then
                    local name = child.Name
                    local category = GetItemCategory(name)

                    if categoriesToScan[category] and enabledItems[name] then
                        processedCount = processedCount + 1
                        local itemPos = GetContainerPosition(child)

                        if itemPos then
                            table.insert(foundItems, {
                                Name = name,
                                Position = itemPos,
                                Category = category,
                                Color = GetItemColor(name),
                            })
                        end
                    end

                    ScanRecursive(child)
                end
            end
        end

        for _, container in ipairs(lootables:GetChildren()) do
            if container:IsA("Model") or container:IsA("Folder") then
                ScanRecursive(container)
            end
        end
    end

    local loot = Workspace:FindFirstChild("Loot")
    if loot then
        local function ScanRecursive(parent)
            for _, child in ipairs(parent:GetChildren()) do
                if child:IsA("Model") or child:IsA("Folder") then
                    local name = child.Name
                    local category = GetItemCategory(name)

                    if categoriesToScan[category] and enabledItems[name] then
                        local itemPos = GetContainerPosition(child)
                        if itemPos then
                            table.insert(foundItems, {
                                Name = name,
                                Position = itemPos,
                                Category = category,
                                Color = GetItemColor(name),
                            })
                        end
                    end
                    ScanRecursive(child)
                end
            end
        end
        ScanRecursive(loot)
    end

    return foundItems
end

function ScanBanners()
    local banners = {}
    
    local bannerFolder = Workspace:FindFirstChild("Banners")
    if not bannerFolder then
        bannerScanned = true
        return banners
    end
    
    for _, banner in ipairs(bannerFolder:GetChildren()) do
        if banner:IsA("Model") and banner.Name == "Banner" then
            local icon = banner:FindFirstChild("Icon")
            if icon and icon:IsA("BasePart") then
                table.insert(banners, {
                    Name = "Banner",
                    Position = icon.Position,
                    Instance = icon,
                })
            end
        end
    end
    
    bannerScanned = true
    return banners
end

function ScanCorpses()
    local corpses = {}
    
    local success, results = pcall(function()
        local found = {}
        local corpseFolder = Workspace:FindFirstChild("Corpses")
        if not corpseFolder then
            return found
        end

        for _, child in ipairs(corpseFolder:GetChildren()) do
            if child:IsA("Model") then
                local position = nil
                
                local rootPart = child:FindFirstChild("HumanoidRootPart")
                if rootPart and rootPart:IsA("BasePart") then
                    position = rootPart.Position
                end
                
                if not position then
                    for _, part in ipairs(child:GetDescendants()) do
                        if part:IsA("BasePart") then
                            local pos = part.Position
                            if pos and pos.Magnitude > 0 then
                                position = pos
                                break
                            end
                        end
                    end
                end
                
                if not position then
                    local ok, result = pcall(function()
                        return child:GetPivot().Position
                    end)
                    if ok and result and result.Magnitude > 0 then
                        position = result
                    end
                end
                
                if not position then
                    local ok, result = pcall(function()
                        local cframe, size = child:GetBoundingBox()
                        if cframe then
                            return cframe.Position
                        end
                        return nil
                    end)
                    if ok and result and result.Magnitude > 0 then
                        position = result
                    end
                end
                
                if position then
                    local lootFolder = child:FindFirstChild("Loot_Corpse")
                    local hasLoot = false
                    if lootFolder then
                        for _, item in ipairs(lootFolder:GetChildren()) do
                            if item:IsA("Folder") then
                                local name = item.Name
                                for category, categoryItems in pairs(ITEM_TYPES) do
                                    for _, itemName in ipairs(categoryItems) do
                                        if name == itemName then
                                            hasLoot = true
                                            break
                                        end
                                    end
                                    if hasLoot then break end
                                end
                            end
                            if hasLoot then break end
                        end
                    end
                    
                    table.insert(found, {
                        Name = child.Name,
                        Position = position,
                        HasLoot = hasLoot,
                        LootFolder = lootFolder,
                    })
                else
                    warn("[Corpse ESP] Could not find position for: " .. child.Name)
                end
            end
        end
        return found
    end)
    
    if success and results then
        corpses = results
    else
        warn("[Corpse ESP] Error scanning corpses: " .. tostring(success))
    end
    
    corpseScanned = true
    return corpses
end

local function ScanCorpseLoot(corpseModel)
    local items = {}
    local lootFolder = corpseModel:FindFirstChild("Loot_Corpse")
    if lootFolder then
        for _, child in ipairs(lootFolder:GetChildren()) do
            local name = child.Name
            if name and name ~= "" then
                table.insert(items, name)
            end
        end
    end
    table.sort(items)
    return items
end

local function RenderItemESP()
    persistentState.itemEspEnabled = UI.GetValue("item_esp_toggle") or false

    if not persistentState.itemEspEnabled then
        ClearItemDrawings()
        itemCache = {}
        return
    end

    local enabledCategories = {}
    local hasEnabled = false
    for category, items in pairs(ITEM_TYPES) do
        for _, itemName in ipairs(items) do
            if persistentState.itemToggles[itemName] then
                hasEnabled = true
                enabledCategories[category] = true
                break
            end
        end
    end

    if not hasEnabled then
        ClearItemDrawings()
        itemCache = {}
        return
    end

    local scanKey = ""
    for category, _ in pairs(enabledCategories) do
        scanKey = scanKey .. category .. ","
    end

    if emptyScanTracker[scanKey] then
        ClearItemDrawings()
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then return end

    persistentState.itemDistance = UI.GetValue("item_distance") or 150
    local cameraPos = camera.Position

    if #itemCache == 0 then
        itemCache = ScanAllItems()
        if #itemCache == 0 then
            emptyScanTracker[scanKey] = true
            ClearItemDrawings()
            return
        end
    end

    local groupedItems = {}
    local round = function(num)
        return math.floor(num * 100 + 0.5) / 100
    end

    for _, item in ipairs(itemCache) do
        if not persistentState.itemToggles[item.Name] then
            continue
        end

        local distance = (item.Position - cameraPos).Magnitude
        if distance > persistentState.itemDistance then
            continue
        end

        local key = round(item.Position.X) .. "," .. round(item.Position.Y) .. "," .. round(item.Position.Z)
        if not groupedItems[key] then
            groupedItems[key] = {
                Position = item.Position,
                Items = {},
            }
        end
        table.insert(groupedItems[key].Items, item)
    end

    local visibleItems = {}
    for _, group in pairs(groupedItems) do
        table.sort(group.Items, function(a, b) return a.Name < b.Name end)
        local screenPos, onScreen = WorldToScreen(group.Position + Vector3.new(0, 0.5, 0))
        if onScreen then
            for i, item in ipairs(group.Items) do
                local distance = (item.Position - cameraPos).Magnitude
                local offsetY = (i - 1) * 14
                table.insert(visibleItems, {
                    Text = item.Name .. " [" .. math.floor(distance) .. "m]",
                    Position = Vector2.new(screenPos.X, screenPos.Y - offsetY),
                    Color = item.Color,
                })
            end
        end
    end

    local visibleCount = #visibleItems

    if visibleCount == 0 then
        ClearItemDrawings()
        return
    end

    local drawingCount = #itemDrawings

    if visibleCount ~= drawingCount then
        if visibleCount < drawingCount then
            for i = visibleCount + 1, drawingCount do
                if itemDrawings[i] then
                    pcall(itemDrawings[i].Remove, itemDrawings[i])
                end
            end
            for i = #itemDrawings, visibleCount + 1, -1 do
                table.remove(itemDrawings, i)
            end
        end
        
        while #itemDrawings < visibleCount do
            local label = Drawing.new("Text")
            label.Font = Drawing.Fonts.System
            label.Size = 11
            label.Outline = true
            label.Center = true
            label.ZIndex = 999
            label.Visible = true
            table.insert(itemDrawings, label)
        end
    end

    for i, item in ipairs(visibleItems) do
        local drawing = itemDrawings[i]
        if drawing then
            drawing.Position = item.Position
            drawing.Text = item.Text
            drawing.Color = item.Color
            drawing.Visible = true
        end
    end

    for i = visibleCount + 1, #itemDrawings do
        if itemDrawings[i] then
            itemDrawings[i].Visible = false
        end
    end
end

local corpseDrawings = {}
local corpseCache = {}
local corpseFrameCounter = 0
local CORPSE_UPDATE_EVERY_N_FRAMES = 1
local corpseScanned = false

local function ClearCorpseDrawings()
    for _, drawing in ipairs(corpseDrawings) do
        pcall(drawing.Remove, drawing)
    end
    corpseDrawings = {}
end

local function RenderCorpseESP()
    persistentState.corpseEspEnabled = UI.GetValue("corpse_esp_toggle") or false

    if not persistentState.corpseEspEnabled then
        ClearCorpseDrawings()
        corpseCache = {}
        corpseScanned = false
        return
    end

    if not corpseScanned then
        corpseCache = ScanCorpses()
        corpseScanned = true
        if #corpseCache > 0 then
            SafeNotify("Corpse ESP - " .. #corpseCache .. " corpses found", "Corpse ESP", 2)
        end
    end
    
    if #corpseCache == 0 then
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then return end

    persistentState.corpseDistance = UI.GetValue("corpse_distance") or 1000
    local cameraPos = camera.Position

    corpseFrameCounter = corpseFrameCounter + 1
    if corpseFrameCounter > CORPSE_UPDATE_EVERY_N_FRAMES then
        corpseFrameCounter = 0
    end

    if corpseFrameCounter ~= 0 then
        return
    end

    local visibleCorpses = {}
    for _, corpse in ipairs(corpseCache) do
        local distance = (corpse.Position - cameraPos).Magnitude
        if distance <= persistentState.corpseDistance then
            local screenPos, onScreen = WorldToScreen(corpse.Position + Vector3.new(0, 1.5, 0))
            if onScreen then
                local status = corpse.HasLoot and " [LOOT]" or ""
                table.insert(visibleCorpses, {
                    Text = corpse.Name .. status .. " [" .. math.floor(distance) .. "m]",
                    Position = screenPos,
                    HasLoot = corpse.HasLoot,
                })
            end
        end
    end

    local visibleCount = #visibleCorpses
    local drawingCount = #corpseDrawings

    if visibleCount ~= drawingCount then
        if visibleCount < drawingCount then
            for i = visibleCount + 1, drawingCount do
                if corpseDrawings[i] then
                    pcall(corpseDrawings[i].Remove, corpseDrawings[i])
                end
            end
            for i = #corpseDrawings, visibleCount + 1, -1 do
                table.remove(corpseDrawings, i)
            end
        end
        
        while #corpseDrawings < visibleCount do
            local label = Drawing.new("Text")
            label.Font = Drawing.Fonts.System
            label.Size = 11
            label.Color = Color3.fromRGB(255, 50, 50)
            label.Outline = true
            label.Center = true
            label.ZIndex = 999
            label.Visible = true
            table.insert(corpseDrawings, label)
        end
    end

    for i, corpse in ipairs(visibleCorpses) do
        local drawing = corpseDrawings[i]
        if drawing then
            drawing.Position = corpse.Position
            drawing.Text = corpse.Text
            drawing.Color = Color3.fromRGB(255, 50, 50)
            drawing.Visible = true
        end
    end

    for i = visibleCount + 1, #corpseDrawings do
        if corpseDrawings[i] then
            corpseDrawings[i].Visible = false
        end
    end
end

local bannerDrawings = {}
local bannerCache = {}
local bannerFrameCounter = 0
local BANNER_UPDATE_EVERY_N_FRAMES = 1
local bannerScanned = false

local function ClearBannerDrawings()
    for _, drawing in ipairs(bannerDrawings) do
        pcall(drawing.Remove, drawing)
    end
    bannerDrawings = {}
end

local function RenderBannerESP()
    persistentState.bannerEspEnabled = UI.GetValue("banner_esp_toggle") or false

    if not persistentState.bannerEspEnabled then
        ClearBannerDrawings()
        bannerCache = {}
        bannerScanned = false
        return
    end

    if not bannerScanned then
        bannerCache = ScanBanners()
        bannerScanned = true
        if #bannerCache > 0 then
            SafeNotify("Banner ESP - " .. #bannerCache .. " banners found", "Banner ESP", 2)
        end
    end
    
    if #bannerCache == 0 then
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then return end

    persistentState.bannerDistance = UI.GetValue("banner_distance") or 500
    local cameraPos = camera.Position


    local visibleBanners = {}
    for _, banner in ipairs(bannerCache) do
        local distance = (banner.Position - cameraPos).Magnitude
        if distance <= persistentState.bannerDistance then
            local screenPos, onScreen = WorldToScreen(banner.Position + Vector3.new(0, 1.5, 0))
            if onScreen then
                table.insert(visibleBanners, {
                    Text = "Banner [" .. math.floor(distance) .. "m]",
                    Position = screenPos,
                })
            end
        end
    end

    local visibleCount = #visibleBanners

    if visibleCount == 0 then
        ClearBannerDrawings()
        return
    end

    local drawingCount = #bannerDrawings

    if visibleCount ~= drawingCount then
        if visibleCount < drawingCount then
            for i = visibleCount + 1, drawingCount do
                if bannerDrawings[i] then
                    pcall(bannerDrawings[i].Remove, bannerDrawings[i])
                end
            end
            for i = #bannerDrawings, visibleCount + 1, -1 do
                table.remove(bannerDrawings, i)
            end
        end
        
        while #bannerDrawings < visibleCount do
            local label = Drawing.new("Text")
            label.Font = Drawing.Fonts.System
            label.Size = 11
            label.Color = Color3.fromRGB(0, 200, 255)
            label.Outline = true
            label.Center = true
            label.ZIndex = 999
            label.Visible = true
            table.insert(bannerDrawings, label)
        end
    end

    for i, banner in ipairs(visibleBanners) do
        local drawing = bannerDrawings[i]
        if drawing then
            drawing.Position = banner.Position
            drawing.Text = banner.Text
            drawing.Visible = true
        end
    end

    for i = visibleCount + 1, #bannerDrawings do
        if bannerDrawings[i] then
            bannerDrawings[i].Visible = false
        end
    end
end

local carDrawings = {}
local carCache = {}
local carFrameCounter = 0
local CAR_UPDATE_EVERY_N_FRAMES = 1
local carScanned = false
local Cars = Workspace:FindFirstChild("Cars")

local function ToAscii(text)
    if not text then return "Unknown" end
    local result = ""
    for i = 1, #text do
        local byte = text:byte(i)
        if byte >= 32 and byte <= 126 then
            result = result .. string.char(byte)
        end
    end
    result = result:gsub("^%s*(.-)%s*$", "%1")
    result = result:gsub("%s+", " ")
    if result == "" then result = "Vehicle" end
    return result
end

local function ScanCars()
    carCache = {}
    local count = 0
    
    if not Cars then
        Cars = Workspace:FindFirstChild("Cars")
        if not Cars then return 0 end
    end
    
    for _, vehicle in ipairs(Cars:GetChildren()) do
        if vehicle:IsA("Model") then
            local crashPart = nil
            
            local body = vehicle:FindFirstChild("Body")
            if body then
                crashPart = body:FindFirstChild("CrashPart")
            end
            
            if not crashPart then
                for _, obj in ipairs(vehicle:GetDescendants()) do
                    if obj.Name == "CrashPart" and obj:IsA("BasePart") then
                        crashPart = obj
                        break
                    end
                end
            end
            
            if crashPart and crashPart:IsA("BasePart") then
                local pos = crashPart.Position
                if pos and typeof(pos) == "Vector3" and pos.Magnitude > 0 then
                    table.insert(carCache, {
                        Vehicle = vehicle,
                        Part = crashPart,
                        RawName = vehicle.Name,
                        Position = pos,
                    })
                    count = count + 1
                end
            end
        end
    end
    
    carScanned = true
    return count
end

local function ClearCarDrawings()
    for _, drawing in ipairs(carDrawings) do
        pcall(drawing.Remove, drawing)
    end
    carDrawings = {}
end

local function RenderCarESP()
    persistentState.carEspEnabled = UI.GetValue("car_esp_toggle") or false

    if not persistentState.carEspEnabled then
        ClearCarDrawings()
        carCache = {}
        carScanned = false
        return
    end

    if not carScanned then
        local count = ScanCars()
        if count > 0 then
            SafeNotify("Car ESP - " .. count .. " vehicles found", "Car ESP", 2)
        end
    end
    
    if #carCache == 0 then
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then return end

    persistentState.carDistance = UI.GetValue("car_distance") or 500
    local cameraPos = camera.Position


    local visibleCars = {}
    for i, car in ipairs(carCache) do
        if not car.Part or not car.Part.Parent then
            table.remove(carCache, i)
            continue
        end
        
        local pos = car.Part.Position
        if not pos or typeof(pos) ~= "Vector3" then
            table.remove(carCache, i)
            continue
        end
        
        car.Position = pos
        
        local distance = (pos - cameraPos).Magnitude
        if distance > persistentState.carDistance then
            continue
        end
        
        local screenPos, onScreen = WorldToScreen(pos + Vector3.new(0, 2, 0))
        if onScreen then
            local displayName = ToAscii(car.RawName)
            table.insert(visibleCars, {
                Text = displayName .. " [" .. math.floor(distance) .. "m]",
                Position = screenPos,
            })
        end
    end

    local visibleCount = #visibleCars

    if visibleCount == 0 then
        ClearCarDrawings()
        return
    end

    local drawingCount = #carDrawings

    if visibleCount ~= drawingCount then
        if visibleCount < drawingCount then
            for i = visibleCount + 1, drawingCount do
                if carDrawings[i] then
                    pcall(carDrawings[i].Remove, carDrawings[i])
                end
            end
            for i = #carDrawings, visibleCount + 1, -1 do
                table.remove(carDrawings, i)
            end
        end
        
        while #carDrawings < visibleCount do
            local label = Drawing.new("Text")
            label.Font = Drawing.Fonts.System
            label.Size = 11
            label.Color = Color3.fromRGB(255, 200, 50)
            label.Outline = true
            label.Center = true
            label.ZIndex = 999
            label.Visible = true
            table.insert(carDrawings, label)
        end
    end

    for i, car in ipairs(visibleCars) do
        local drawing = carDrawings[i]
        if drawing then
            drawing.Position = car.Position
            drawing.Text = car.Text
            drawing.Visible = true
        end
    end

    for i = visibleCount + 1, #carDrawings do
        if carDrawings[i] then
            carDrawings[i].Visible = false
        end
    end
end

local panelDrawings = {}
local cachedPlayer = nil
local cachedData = nil
local lastRenderTime = 0
local MIN_SCALE = 0.8
local MAX_SCALE = 2.5
local UI_UPDATE_INTERVAL = 0.3

local currentTarget = nil
local currentTargetType = nil
local targetDirty = true
local lastScanTime = 0
local SCAN_INTERVAL = 0.1

local function IsReadableString(str)
    if not str or str == "" then return false end
    if #str < 2 then return false end
    return true
end

local function IsJunk(name)
    if string.find(name, "Hair") then return true end
    if string.find(name, "Hitbox") then return true end
    if string.find(name, "Bald") then return true end
    if string.find(name, "Breath") then return true end
    if string.find(name, "Anims") then return true end
    if string.find(name, "CharServer") then return true end
    if string.find(name, "Animator") then return true end
    if string.find(name, "Humanoid") then return true end
    if string.find(name, "RootPart") then return true end
    if string.find(name, "Torso") then return true end
    if string.find(name, "Leg") then return true end
    if string.find(name, "Arm") then return true end
    if string.find(name, "Foot") then return true end
    if string.find(name, "Hand") then return true end
    if name == "Head" then return true end
    return false
end

local function ClearPanel()
    for _, drawing in ipairs(panelDrawings) do
        pcall(drawing.Remove, drawing)
    end
    panelDrawings = {}
end

local function DestroyPanel()
    for _, drawing in ipairs(panelDrawings) do
        pcall(drawing.Remove, drawing)
    end
    panelDrawings = {}
end

local function QuickTargetCheck()
    local camera = workspace.CurrentCamera
    if not camera then return nil, nil end

    local cameraPos = camera.Position
    local lookDirection = camera.CFrame.LookVector
    local closestTarget = nil
    local closestAngle = math.rad(2)
    local targetType = "Player"

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == player then continue end
        if plr.Character and plr.Character.Parent then
            local head = plr.Character:FindFirstChild("Head")
            if head then
                local toPlayer = (head.Position - cameraPos).Unit
                local angle = math.acos(math.clamp(lookDirection:Dot(toPlayer), -1, 1))
                if angle < closestAngle then
                    closestAngle = angle
                    closestTarget = plr
                    targetType = "Player"
                end
            end
        end
    end

    if not closestTarget then
        local corpseFolder = Workspace:FindFirstChild("Corpses")
        if corpseFolder then
            local corpseAngle = math.rad(12)
            for _, corpse in ipairs(corpseFolder:GetChildren()) do
                if corpse:IsA("Model") then
                    local pos = nil
                    local rootPart = corpse:FindFirstChild("HumanoidRootPart")
                    if rootPart and rootPart:IsA("BasePart") then
                        pos = rootPart.Position
                    end
                    if not pos then
                        for _, part in ipairs(corpse:GetDescendants()) do
                            if part:IsA("BasePart") then
                                pos = part.Position
                                if pos and pos.Magnitude > 0 then break end
                            end
                        end
                    end
                    if pos then
                        local toCorpse = (pos - cameraPos).Unit
                        local angle = math.acos(math.clamp(lookDirection:Dot(toCorpse), -1, 1))
                        if angle < corpseAngle then
                            if not closestTarget or angle < closestAngle then
                                closestAngle = angle
                                closestTarget = corpse
                                targetType = "Corpse"
                            end
                        end
                    end
                end
            end
        end
    end

    return closestTarget, targetType
end

local function FullTargetScan(target, targetType)
    if not target then return nil end

    if targetType == "Player" then
        local plr = target
        local info = {
            Name = plr.Name,
            Backpack = {},
            Health = 0,
            Distance = 0,
            Type = "Player",
        }

        local character = plr.Character
        if character then
            local humanoid = character:FindFirstChild("Humanoid")
            if humanoid then info.Health = math.floor(humanoid.Health) end
            local head = character:FindFirstChild("Head")
            if head then
                local camera = workspace.CurrentCamera
                if camera then
                    info.Distance = math.floor((head.Position - camera.Position).Magnitude)
                end
            end
        end

        local backpack = plr:FindFirstChild("Backpack")
        local allItems = {}
        if backpack then
            for _, item in ipairs(backpack:GetChildren()) do
                local name = item.Name
                if IsReadableString(name) and not IsJunk(name) then
                    table.insert(allItems, name)
                end
            end
        end

        local playerGui = plr:FindFirstChild("PlayerGui")
        if playerGui then
            local userGui = playerGui:FindFirstChild("UserGUI")
            if userGui then
                local frame = userGui:FindFirstChild("Frame")
                if frame then
                    local invFrame = frame:FindFirstChild("InvFrame")
                    if invFrame then
                        local inventory = invFrame:FindFirstChild("Inventory")
                        if inventory then
                            local itemGrid = inventory:FindFirstChild("ItemGrid")
                            if itemGrid then
                                for _, child in ipairs(itemGrid:GetChildren()) do
                                    local name = child.Name
                                    if IsReadableString(name) and not IsJunk(name) then
                                        table.insert(allItems, name)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        local character = plr.Character
        if character then
            for _, child in ipairs(character:GetChildren()) do
                local name = child.Name
                if IsJunk(name) then continue end
                if not IsReadableString(name) then continue end
                if child:IsA("Tool") and child:FindFirstChild("Handle") and child.Handle:IsA("MeshPart") then
                    local found = false
                    for i, bpItem in ipairs(allItems) do
                        if bpItem == name then
                            allItems[i] = name .. " [equipped]"
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(allItems, name .. " [equipped]")
                    end
                end
            end
        end

        table.sort(allItems)
        info.Backpack = allItems
        return info

    elseif targetType == "Corpse" then
        local corpse = target
        local info = {
            Name = corpse.Name,
            Backpack = {},
            Health = 0,
            Distance = 0,
            Type = "Corpse",
        }

        local pos = nil
        local rootPart = corpse:FindFirstChild("HumanoidRootPart")
        if rootPart and rootPart:IsA("BasePart") then
            pos = rootPart.Position
        end
        if not pos then
            for _, part in ipairs(corpse:GetDescendants()) do
                if part:IsA("BasePart") then
                    pos = part.Position
                    if pos and pos.Magnitude > 0 then break end
                end
            end
        end
        if pos then
            local camera = workspace.CurrentCamera
            if camera then
                info.Distance = math.floor((pos - camera.Position).Magnitude)
            end
        end

        local lootFolder = corpse:FindFirstChild("Loot_Corpse")
        if lootFolder then
            for _, child in ipairs(lootFolder:GetChildren()) do
                if child:IsA("Folder") then
                    local name = child.Name
                    for category, categoryItems in pairs(ITEM_TYPES) do
                        for _, itemName in ipairs(categoryItems) do
                            if name == itemName then
                                table.insert(info.Backpack, name)
                                break
                            end
                        end
                    end
                end
            end
        end
        table.sort(info.Backpack)
        return info
    end

    return nil
end

local function GetContentLines(data)
    local lines = {}
    if not data then
        table.insert(lines, {text = "No target", color = Color3.fromRGB(150, 150, 150)})
        return lines
    end

    local typeLabel = data.Type == "Corpse" and "[Corpse] " or ""
    table.insert(lines, {text = typeLabel .. data.Name, color = Color3.fromRGB(255, 255, 255)})
    table.insert(lines, {text = "Distance: " .. data.Distance .. "m", color = Color3.fromRGB(200, 200, 200)})

    local backpackLabel = data.Type == "Corpse" and "loot:" or "backpack:"
    table.insert(lines, {text = backpackLabel, color = Color3.fromRGB(200, 200, 200)})
    
    if #data.Backpack > 0 then
        for _, item in ipairs(data.Backpack) do
            if string.find(item, "%[equipped%]") then
                table.insert(lines, {text = "  " .. item, color = Color3.fromRGB(255, 200, 100)})
            else
                table.insert(lines, {text = "  " .. item, color = Color3.fromRGB(180, 180, 200)})
            end
        end
    else
        local emptyText = data.Type == "Corpse" and "  no loot" or "  empty"
        table.insert(lines, {text = emptyText, color = Color3.fromRGB(150, 150, 150)})
    end
    return lines
end

local function RenderPanel()
    persistentState.inspectorEnabled = UI.GetValue("inspector_toggle") or false

    if not persistentState.inspectorEnabled then
        ClearPanel()
        return
    end

    local now = tick()
    if now - lastRenderTime < UI_UPDATE_INTERVAL then return end
    lastRenderTime = now

    local viewport = workspace.CurrentCamera
    if not viewport then return end
    local viewportSize = viewport.ViewportSize

    if targetDirty or now - lastScanTime > 0.3 then
        targetDirty = false
        lastScanTime = now
        
        local quickTarget, quickType = QuickTargetCheck()
        
        if quickTarget then
            if quickTarget ~= cachedPlayer then
                cachedPlayer = quickTarget
                cachedData = FullTargetScan(quickTarget, quickType)
                ClearPanel()
            elseif cachedData then
                if now - (cachedData._lastUpdate or 0) > 2 then
                    local freshData = FullTargetScan(quickTarget, quickType)
                    if freshData then
                        freshData._lastUpdate = now
                        local changed = false
                        if #freshData.Backpack ~= #cachedData.Backpack then
                            changed = true
                        else
                            for i, item in ipairs(freshData.Backpack) do
                                if cachedData.Backpack[i] ~= item then
                                    changed = true
                                    break
                                end
                            end
                        end
                        if changed then
                            cachedData = freshData
                            ClearPanel()
                        end
                    end
                end
            end
        else
            if cachedPlayer then
                cachedPlayer = nil
                cachedData = nil
                ClearPanel()
            end
        end
    end

    local lines = GetContentLines(cachedData)
    local totalLines = #lines

    persistentState.uiScale = UI.GetValue("ui_scale") or 1.0
    local scale = persistentState.uiScale
    local padding = math.floor(10 * scale)
    local headerHeight = math.floor(32 * scale)
    local lineHeight = math.floor(16 * scale)
    local titleSize = math.floor(13 * scale)
    local textSize = math.floor(12 * scale)
    local panelWidth = math.floor(320 * scale)
    local cornerRadius = math.floor(8 * scale)

    local contentHeight = headerHeight + (totalLines * lineHeight) + padding
    local centerY = viewportSize.Y / 2
    local panelY = centerY - (contentHeight / 2)
    local panelX = viewportSize.X - panelWidth - math.floor(20 * scale)

    if #panelDrawings == 0 then
        local bg = Drawing.new("Square")
        bg.Filled = true
        bg.Color = Color3.fromRGB(20, 20, 25)
        bg.Transparency = 0.85
        bg.Size = Vector2.new(panelWidth, contentHeight)
        bg.Position = Vector2.new(panelX, panelY)
        bg.ZIndex = 997
        bg.Visible = true
        bg.Corner = cornerRadius
        table.insert(panelDrawings, bg)

        local outline = Drawing.new("Square")
        outline.Filled = false
        outline.Color = Color3.fromRGB(255, 255, 255)
        outline.Thickness = 2
        outline.Size = Vector2.new(panelWidth, contentHeight)
        outline.Position = Vector2.new(panelX, panelY)
        outline.ZIndex = 998
        outline.Visible = true
        outline.Corner = cornerRadius
        table.insert(panelDrawings, outline)

        local headerBg = Drawing.new("Square")
        headerBg.Filled = true
        headerBg.Color = Color3.fromRGB(45, 45, 55)
        headerBg.Transparency = 0
        headerBg.Size = Vector2.new(panelWidth, headerHeight)
        headerBg.Position = Vector2.new(panelX, panelY)
        headerBg.ZIndex = 999
        headerBg.Visible = true
        headerBg.Corner = cornerRadius
        table.insert(panelDrawings, headerBg)

        local divider = Drawing.new("Line")
        divider.Color = Color3.fromRGB(80, 80, 100)
        divider.Thickness = 1
        divider.From = Vector2.new(panelX + 10, panelY + headerHeight)
        divider.To = Vector2.new(panelX + panelWidth - 10, panelY + headerHeight)
        divider.ZIndex = 1000
        divider.Visible = true
        table.insert(panelDrawings, divider)

        local title = Drawing.new("Text")
        title.Font = Drawing.Fonts.System
        title.Size = titleSize
        title.Color = Color3.fromRGB(255, 255, 255)
        title.Outline = true
        title.Center = false
        title.Position = Vector2.new(panelX + padding, panelY + math.floor(8 * scale))
        title.Text = "Target Inspector"
        title.ZIndex = 1001
        title.Visible = true
        table.insert(panelDrawings, title)
    end

    if #panelDrawings >= 1 and panelDrawings[1] then
        local bg = panelDrawings[1]
        bg.Position = Vector2.new(panelX, panelY)
        bg.Size = Vector2.new(panelWidth, contentHeight)
        bg.Corner = cornerRadius
    end
    if #panelDrawings >= 2 and panelDrawings[2] then
        local outline = panelDrawings[2]
        outline.Position = Vector2.new(panelX, panelY)
        outline.Size = Vector2.new(panelWidth, contentHeight)
        outline.Corner = cornerRadius
    end
    if #panelDrawings >= 3 and panelDrawings[3] then
        local headerBg = panelDrawings[3]
        headerBg.Position = Vector2.new(panelX, panelY)
        headerBg.Size = Vector2.new(panelWidth, headerHeight)
        headerBg.Corner = cornerRadius
    end
    if #panelDrawings >= 4 and panelDrawings[4] then
        local divider = panelDrawings[4]
        divider.From = Vector2.new(panelX + 10, panelY + headerHeight)
        divider.To = Vector2.new(panelX + panelWidth - 10, panelY + headerHeight)
    end
    if #panelDrawings >= 5 and panelDrawings[5] then
        local title = panelDrawings[5]
        title.Position = Vector2.new(panelX + padding, panelY + math.floor(8 * scale))
        title.Size = titleSize
    end

    for i = #panelDrawings, 6, -1 do
        pcall(panelDrawings[i].Remove, panelDrawings[i])
        table.remove(panelDrawings, i)
    end

    local yOffset = panelY + headerHeight + 2
    for _, lineData in ipairs(lines) do
        local textObj = Drawing.new("Text")
        textObj.Font = Drawing.Fonts.System
        textObj.Size = textSize
        textObj.Color = lineData.color
        textObj.Position = Vector2.new(panelX + padding, yOffset)
        textObj.Text = lineData.text
        textObj.Center = false
        textObj.ZIndex = 1002
        textObj.Visible = true
        table.insert(panelDrawings, textObj)
        yOffset = yOffset + lineHeight
    end
end

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        if persistentState.inspectorEnabled then
            targetDirty = true
            lastRenderTime = 0
        end
    end
end)

local function ResetAllToggles()
    for category, items in pairs(ITEM_TYPES) do
        persistentState.categoryToggles[category] = false
        for _, itemName in ipairs(items) do
            persistentState.itemToggles[itemName] = false
        end
    end

    persistentState.inspectorEnabled = false
    persistentState.uiScale = 1.0
    persistentState.modPanelScale = 1.0
    persistentState.itemEspEnabled = false
    persistentState.corpseEspEnabled = false
    persistentState.teleportEnabled = false
    persistentState.selectedPOI = 0
    persistentState.bannerEspEnabled = false
    persistentState.carEspEnabled = false
    persistentState.modDetectorEnabled = false

    ClearItemDrawings()
    ClearPanel()
    ClearCorpseDrawings()
    ClearBannerDrawings()
    ClearCarDrawings()
    ClearModPanel()
    itemCache = {}
    corpseCache = {}
    bannerCache = {}
    carCache = {}
    notifiedMods = {}
    panelCache = {}
end

local function SetAllUITogglesFalse()
    UI.SetValue("inspector_toggle", false)
    UI.SetValue("ui_scale", 1.0)
    UI.SetValue("mod_panel_scale", 1.0)
    UI.SetValue("item_esp_toggle", false)
    UI.SetValue("corpse_esp_toggle", false)
    UI.SetValue("corpse_distance", 1000)
    UI.SetValue("teleport_enabled", false)
    UI.SetValue("teleport_poi", 0)
    UI.SetValue("banner_esp_toggle", false)
    UI.SetValue("banner_distance", 500)
    UI.SetValue("car_esp_toggle", false)
    UI.SetValue("car_distance", 500)
    UI.SetValue("mod_detector_toggle", false)
    
    UI.SetValue("item_category_Equipment", false)
    UI.SetValue("item_category_Weapons", false)
    UI.SetValue("item_category_Melee", false)
    UI.SetValue("item_category_Ammo", false)
    UI.SetValue("item_category_Food", false)
    UI.SetValue("item_category_Keycards", false)
    UI.SetValue("item_category_Misc", false)

    for categoryName, categoryItems in pairs(ITEM_TYPES) do
        for _, itemName in ipairs(categoryItems) do
            UI.SetValue("item_" .. itemName, false)
        end
    end
end

local toggleRefs = {}

local function RestoreUIState()
    UI.SetValue("inspector_toggle", persistentState.inspectorEnabled or false)
    UI.SetValue("ui_scale", persistentState.uiScale or 1.0)
    UI.SetValue("mod_panel_scale", persistentState.modPanelScale or 1.0)
    UI.SetValue("item_esp_toggle", persistentState.itemEspEnabled or false)
    UI.SetValue("item_distance", persistentState.itemDistance or 150)
    UI.SetValue("corpse_esp_toggle", persistentState.corpseEspEnabled or false)
    UI.SetValue("corpse_distance", persistentState.corpseDistance or 1000)
    UI.SetValue("teleport_enabled", persistentState.teleportEnabled or false)
    UI.SetValue("teleport_poi", persistentState.selectedPOI or 0)
    UI.SetValue("banner_esp_toggle", persistentState.bannerEspEnabled or false)
    UI.SetValue("banner_distance", persistentState.bannerDistance or 500)
    UI.SetValue("car_esp_toggle", persistentState.carEspEnabled or false)
    UI.SetValue("car_distance", persistentState.carDistance or 500)
    UI.SetValue("mod_detector_toggle", persistentState.modDetectorEnabled or false)
    
    UI.SetValue("item_category_Equipment", persistentState.categoryToggles["Equipment"] or false)
    UI.SetValue("item_category_Weapons", persistentState.categoryToggles["Weapons"] or false)
    UI.SetValue("item_category_Melee", persistentState.categoryToggles["Melee"] or false)
    UI.SetValue("item_category_Ammo", persistentState.categoryToggles["Ammo"] or false)
    UI.SetValue("item_category_Food", persistentState.categoryToggles["Food"] or false)
    UI.SetValue("item_category_Keycards", persistentState.categoryToggles["Keycards"] or false)
    UI.SetValue("item_category_Misc", persistentState.categoryToggles["Misc"] or false)

    for name, enabled in pairs(persistentState.itemToggles) do
        if toggleRefs[name] then
            toggleRefs[name].Value = enabled
        end
    end

    if persistentState.modDetectorEnabled then
        StartModMonitor()
    end

    for category, enabled in pairs(persistentState.categoryToggles) do
        local refName = "item_category_all_" .. category
        if toggleRefs[refName] then
            toggleRefs[refName].Value = enabled
        end
    end
end

UI.AddTab("Walking Dead", function(tab)
    local MainSection = tab:Section("Main", "Left")
    
    MainSection:Toggle("item_esp_toggle", "Enable Item ESP", function(state)
        persistentState.itemEspEnabled = state
        if state then
            emptyScanTracker = {}
            if #itemCache == 0 then
                local camera = workspace.CurrentCamera
                if camera then
                    itemCache = ScanAllItems()
                    if #itemCache > 0 then
                        SafeNotify("Item ESP enabled", "Item ESP", 2)
                    else
                        SafeNotify("Item ESP enabled - no items nearby", "Item ESP", 2)
                    end
                end
            else
                SafeNotify("Item ESP enabled", "Item ESP", 2)
            end
        else
            ClearItemDrawings()
            itemCache = {}
            emptyScanTracker = {}
            SafeNotify("Item ESP disabled", "Item ESP", 2)
        end
    end)
    
    itemRescanKeybind = MainSection:Keybind("item_rescan_kb", 0x49, "click")
    itemRescanKeybind:AddToHotkey("Rescan Item ESP", "item_esp_toggle")
    
    MainSection:SliderInt("item_distance", "Item Distance", 10, 3000, 150, function(value)
        persistentState.itemDistance = value
    end)
    
    MainSection:Spacing()
    MainSection:Text("Item Categories:")
    
    MainSection:Toggle("item_category_Equipment", "Equipment", function(state)
        persistentState.categoryToggles["Equipment"] = state
        for _, itemName in ipairs(ITEM_TYPES["Equipment"] or {}) do
            persistentState.itemToggles[itemName] = state
        end
        if state then
            itemCache = {}
            ClearItemDrawings()
        else
            ClearItemDrawings()
        end
    end)
    
    MainSection:Toggle("item_category_Weapons", "Weapons", function(state)
        persistentState.categoryToggles["Weapons"] = state
        for _, itemName in ipairs(ITEM_TYPES["Weapons"] or {}) do
            persistentState.itemToggles[itemName] = state
        end
        if state then
            itemCache = {}
            ClearItemDrawings()
        else
            ClearItemDrawings()
        end
    end)

    MainSection:Toggle("item_category_Melee", "Melee", function(state)
        persistentState.categoryToggles["Melee"] = state
        for _, itemName in ipairs(ITEM_TYPES["Melee"] or {}) do
            persistentState.itemToggles[itemName] = state
        end
        if state then
            itemCache = {}
            ClearItemDrawings()
        else
            ClearItemDrawings()
        end
    end)
    
    MainSection:Toggle("item_category_Ammo", "Ammo", function(state)
        persistentState.categoryToggles["Ammo"] = state
        
        local filterText = UI.GetValue("ammo_filter") or ""
        
        if state then
            if filterText == "" or filterText:lower() == "all" then
                for _, itemName in ipairs(ITEM_TYPES["Ammo"] or {}) do
                    persistentState.itemToggles[itemName] = true
                end
            elseif filterText:lower() ~= "none" then
                for _, itemName in ipairs(ITEM_TYPES["Ammo"] or {}) do
                    persistentState.itemToggles[itemName] = false
                end
                for word in string.gmatch(filterText, "[^,]+") do
                    local trimmed = word:gsub("^%s*(.-)%s*$", "%1")
                    if trimmed ~= "" then
                        for _, itemName in ipairs(ITEM_TYPES["Ammo"] or {}) do
                            if string.lower(itemName):find(string.lower(trimmed), 1, true) then
                                persistentState.itemToggles[itemName] = true
                            end
                        end
                    end
                end
            else
                for _, itemName in ipairs(ITEM_TYPES["Ammo"] or {}) do
                    persistentState.itemToggles[itemName] = false
                end
            end
            itemCache = {}
            ClearItemDrawings()
        else
            for _, itemName in ipairs(ITEM_TYPES["Ammo"] or {}) do
                persistentState.itemToggles[itemName] = false
            end
            ClearItemDrawings()
        end
    end)
    
    MainSection:InputText("ammo_filter", "Filter Ammo (comma separated)", "", function(text)
        if persistentState.categoryToggles["Ammo"] then
            for _, itemName in ipairs(ITEM_TYPES["Ammo"] or {}) do
                persistentState.itemToggles[itemName] = false
            end
            
            if text == "" or text:lower() == "all" then
                for _, itemName in ipairs(ITEM_TYPES["Ammo"] or {}) do
                    persistentState.itemToggles[itemName] = true
                end
            elseif text:lower() ~= "none" then
                for word in string.gmatch(text, "[^,]+") do
                    local trimmed = word:gsub("^%s*(.-)%s*$", "%1")
                    if trimmed ~= "" then
                        for _, itemName in ipairs(ITEM_TYPES["Ammo"] or {}) do
                            if string.lower(itemName):find(string.lower(trimmed), 1, true) then
                                persistentState.itemToggles[itemName] = true
                            end
                        end
                    end
                end
            end
            
            itemCache = {}
            if persistentState.itemEspEnabled then
                ClearItemDrawings()
            end
        end
    end)
    
    MainSection:Toggle("item_category_Food", "Food", function(state)
        persistentState.categoryToggles["Food"] = state
        for _, itemName in ipairs(ITEM_TYPES["Food"] or {}) do
            persistentState.itemToggles[itemName] = state
        end
        if state then
            itemCache = {}
            ClearItemDrawings()
        else
            ClearItemDrawings()
        end
    end)
    
    MainSection:Toggle("item_category_Misc", "Misc", function(state)
        persistentState.categoryToggles["Misc"] = state
        for _, itemName in ipairs(ITEM_TYPES["Misc"] or {}) do
            persistentState.itemToggles[itemName] = state
        end
        if state then
            itemCache = {}
            ClearItemDrawings()
        else
            ClearItemDrawings()
        end
    end)

    MainSection:Toggle("item_category_Keycards", "Keycards", function(state)
        persistentState.categoryToggles["Keycards"] = state
        for _, itemName in ipairs(ITEM_TYPES["Keycards"] or {}) do
            persistentState.itemToggles[itemName] = state
        end
        if state then
            itemCache = {}
            ClearItemDrawings()
        else
            ClearItemDrawings()
        end
    end)

    MainSection:Spacing()
    MainSection:Spacing()
    
    MainSection:Toggle("banner_esp_toggle", "Enable Banner ESP", function(state)
        persistentState.bannerEspEnabled = state
        if state then
            bannerCache = {}
            bannerScanned = false
            SafeNotify("Banner ESP enabled", "Banner ESP", 2)
        else
            ClearBannerDrawings()
            bannerCache = {}
            bannerScanned = false
            SafeNotify("Banner ESP disabled", "Banner ESP", 2)
        end
    end)

    bannerRescanKeybind = MainSection:Keybind("banner_rescan_kb", 0x42, "click")
    bannerRescanKeybind:AddToHotkey("Rescan Banner ESP", "banner_esp_toggle")
    
    MainSection:SliderInt("banner_distance", "Banner Distance", 10, 3000, 500, function(value)
        persistentState.bannerDistance = value
    end)
    
    MainSection:Spacing()
    MainSection:Spacing()
    
    MainSection:Toggle("corpse_esp_toggle", "Enable Corpse ESP", function(state)
        persistentState.corpseEspEnabled = state
        if state then
            corpseCache = {}
            corpseScanned = false
            SafeNotify("Corpse ESP enabled", nil, 2)
        else
            ClearCorpseDrawings()
            corpseCache = {}
            corpseScanned = false
            SafeNotify("Corpse ESP disabled", nil, 2)
        end
    end)
    
    corpseRescanKeybind = MainSection:Keybind("corpse_rescan_kb", 0x43, "click")
    corpseRescanKeybind:AddToHotkey("Rescan Corpse ESP", "corpse_esp_toggle")
    
    MainSection:SliderInt("corpse_distance", "Corpse Distance", 10, 3000, 1000, function(value)
        persistentState.corpseDistance = value
    end)
    
    MainSection:Spacing()
    MainSection:Spacing()

    MainSection:Toggle("car_esp_toggle", "Enable Vehicle ESP", function(state)
        persistentState.carEspEnabled = state
        if state then
            carCache = {}
            carScanned = false
            SafeNotify("Vehicle ESP enabled", "Vehicle ESP", 2)
        else
            ClearCarDrawings()
            carCache = {}
            carScanned = false
            SafeNotify("Vehicle ESP disabled", "Vehicle ESP", 2)
        end
    end)

    carRescanKeybind = MainSection:Keybind("car_rescan_kb", 0x56, "click")
    carRescanKeybind:AddToHotkey("Rescan Vehicle ESP", "car_esp_toggle")
    
    MainSection:SliderInt("car_distance", "Vehicle Distance", 10, 3000, 500, function(value)
        persistentState.carDistance = value
    end)

    local InspectorSection = tab:Section("Inspectors", "Right")
    
    InspectorSection:Toggle("inspector_toggle", "Enable Target Inspector", function(state)
        persistentState.inspectorEnabled = state
        if state then
            DestroyPanel()
            currentTargetData = nil
            currentTargetName = ""
            currentTargetType = ""
            targetDirty = true
            lastRenderTime = 0
            SafeNotify("Target Inspector enabled", nil, 2)
        else
            DestroyPanel()
            SafeNotify("Target Inspector disabled", nil, 2)
        end
    end)
    
    InspectorSection:SliderFloat("ui_scale", "Target Inspector Scale", 0.8, 2.5, 1.0, "%.1f", function(value)
        persistentState.uiScale = value
        if persistentState.inspectorEnabled then
            DestroyPanel()
            lastRenderTime = 0
        end
    end)
    
    InspectorSection:Spacing()
    
    InspectorSection:Toggle("mod_detector_toggle", "Enable Mod Inspector", function(state)
        persistentState.modDetectorEnabled = state
        if state then
            SafeNotify("Mod Detector enabled", "Mod Detector", 2)
            notifiedMods = {}
            lastModListHash = ""
            DestroyModPanel()
            BuildPanel()
            task.spawn(function()
                StartModMonitor()
            end)
        else
            SafeNotify("Mod Detector disabled", "Mod Detector", 2)
            notifiedMods = {}
            lastModListHash = ""
            DestroyModPanel()
        end
    end)
        
    InspectorSection:SliderFloat("mod_panel_scale", "Mod Panel Scale", 0.8, 2.5, 1.0, "%.1f", function(value)
        persistentState.modPanelScale = value
        if persistentState.modDetectorEnabled then
            DestroyModPanel()
            BuildPanel()
            lastModListHash = ""
            UpdatePanel()
        end
    end)

    local teleportSection = tab:Section("Teleport", "Right")
    
    teleportSection:Combo("teleport_poi", "Select Location", POI_NAMES, 0, function(index, text)
        persistentState.selectedPOI = index
        SafeNotify("Selected: " .. text, "Teleport", 1)
    end)
    
    teleportSection:Button("Teleport to Selected", function()
        local selectedIndex = UI.GetValue("teleport_poi") or 0
        TeleportToPOI(selectedIndex)
    end)

    local infoSection = tab:Section("Info", "Right")

    infoSection:Text("We Can Olive Together - Rick")
    infoSection:Spacing()
    infoSection:Text("As you move throughout the map rescan items")
    infoSection:Text("so they get updated since the game uses")
    infoSection:Text("a dynamic loot system which means items")
    infoSection:Text("spawn and despawn as you move around the map.")
    infoSection:Spacing()
    infoSection:Tip("by og_ten")

    task.wait(0.1)
    RestoreUIState()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    local key = input.KeyCode
    
    if UI.GetValue("item_esp_toggle") == true and itemRescanKeybind then
        local boundKey = itemRescanKeybind:GetKey()
        if boundKey >= 65 and boundKey <= 90 then
            boundKey = boundKey + 32
        end
        if key == boundKey then
            pcall(function()
                itemCache = {}
                ClearItemDrawings()
                emptyScanTracker = {}
                itemCache = ScanAllItems()
                if #itemCache > 0 then
                    SafeNotify("Item ESP rescanned - found " .. #itemCache .. " items", "Rescan", 2)
                else
                    SafeNotify("Item ESP rescanned - no items nearby", "Rescan", 2)
                end
            end)
        end
    end
    
    if UI.GetValue("banner_esp_toggle") == true and bannerRescanKeybind then
        local boundKey = bannerRescanKeybind:GetKey()
        if boundKey >= 65 and boundKey <= 90 then
            boundKey = boundKey + 32
        end
        if key == boundKey then
            pcall(function()
                bannerCache = {}
                ClearBannerDrawings()
                bannerScanned = false
                SafeNotify("Banner ESP rescanning...", "Rescan", 1)
            end)
        end
    end
    
    if UI.GetValue("corpse_esp_toggle") == true and corpseRescanKeybind then
        local boundKey = corpseRescanKeybind:GetKey()
        if boundKey >= 65 and boundKey <= 90 then
            boundKey = boundKey + 32
        end
        if key == boundKey then
            pcall(function()
                corpseCache = {}
                ClearCorpseDrawings()
                corpseScanned = false
                SafeNotify("Corpse ESP rescanning...", "Rescan", 1)
            end)
        end
    end
    
    if UI.GetValue("car_esp_toggle") == true and carRescanKeybind then
        local boundKey = carRescanKeybind:GetKey()
        if boundKey >= 65 and boundKey <= 90 then
            boundKey = boundKey + 32
        end
        if key == boundKey then
            pcall(function()
                carCache = {}
                ClearCarDrawings()
                carScanned = false
                SafeNotify("Vehicle ESP rescanning...", "Rescan", 1)
            end)
        end
    end
end)

local renderFrameCounter = 0

RunService.RenderStepped:Connect(function()
    renderFrameCounter = renderFrameCounter + 1
    local shouldRenderESP = (renderFrameCounter % 2 == 0)
    local shouldRenderPanel = (renderFrameCounter % 3 == 0)
    
    if persistentState.inspectorEnabled and shouldRenderPanel then
        RenderPanel()
    end
    
    if persistentState.itemEspEnabled and shouldRenderESP then
        RenderItemESP()
    end
    
    if persistentState.corpseEspEnabled and shouldRenderESP then
        RenderCorpseESP()
    end
    
    if persistentState.bannerEspEnabled and shouldRenderESP then
        RenderBannerESP()
    end
    
    if persistentState.carEspEnabled and shouldRenderESP then
        RenderCarESP()
    end
    
    if persistentState.modDetectorEnabled then
        RenderModPanel()
    end
    
    if renderFrameCounter > 1000 then
        renderFrameCounter = 0
    end
end)

ResetAllToggles()
SetAllUITogglesFalse()

SafeNotify("Rick Said The Walking Dead Was Loaded", "Walking Dead", 3)
