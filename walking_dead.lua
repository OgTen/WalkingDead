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
}

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

local TeleportKeybind = nil
local character = nil
local hrp = nil

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
        "Battle Hammer", "M40", "VSS Vintorez", "Mace", "Shiv", "Spiked Bat", 
        "Wooden Bat", "Crowbar", "Fire Axe", "Hatchet", "Machete", "karambit",
        "Pipe Wrench", "Claw Hammer", "Pickaxe", "KA-BAR", "Cleaver", "Combat Knife",
        "Hammer", "Nightstick", "Hunting Knife", "Tactical knife",
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
    ["Misc"] = {
        "Bandage", "Improvised Bandage", "FlashLight", "Metal Parts",
        "Weapon Cleaning Kit", "Cloth", "Bunker Access Keycard", "Prison Armory Access Keycard",
        "Satellite outpost Access Keycard", "Police Armory Access Keycard",
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

local CATEGORY_NAMES = {}
local categoryOrder = {"Equipment", "Weapons", "Ammo", "Food", "Misc"}
for _, category in ipairs(categoryOrder) do
    if ITEM_TYPES[category] then
        table.insert(CATEGORY_NAMES, category)
    end
end

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
    elseif category == "Ammo" then
        return Color3.fromRGB(255, 255, 100)
    elseif category == "Food" then
        return Color3.fromRGB(100, 255, 100)
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
local ITEM_UPDATE_EVERY_N_FRAMES = 2

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

    local physicalLoot = Workspace:FindFirstChild("PhysicalLoot")
    if physicalLoot then
        local hasFoodEnabled = false
        for foodName, _ in pairs(ITEM_TYPES["Food"]) do
            if enabledItems[foodName] then
                hasFoodEnabled = true
                break
            end
        end

        if hasFoodEnabled then
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

                    if enabledItems[name] then
                        processedCount = processedCount + 1
                        local itemPos = GetContainerPosition(child)

                        if itemPos then
                            table.insert(foundItems, {
                                Name = name,
                                Position = itemPos,
                                Category = GetItemCategory(name),
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
                    if enabledItems[name] then
                        local itemPos = GetContainerPosition(child)
                        if itemPos then
                            table.insert(foundItems, {
                                Name = name,
                                Position = itemPos,
                                Category = GetItemCategory(name),
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

local function RenderItemESP()
    persistentState.itemEspEnabled = UI.GetValue("item_esp_toggle") or false

    if not persistentState.itemEspEnabled then
        ClearItemDrawings()
        itemCache = {}
        return
    end

    local hasEnabled = false
    for _, enabled in pairs(persistentState.itemToggles) do
        if enabled then
            hasEnabled = true
            break
        end
    end

    if not hasEnabled then
        ClearItemDrawings()
        itemCache = {}
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then return end

    persistentState.itemDistance = UI.GetValue("item_distance") or 150
    local cameraPos = camera.Position

    if #itemCache == 0 then
        itemCache = ScanAllItems()
        if #itemCache == 0 then
            ClearItemDrawings()
            return
        end
        SafeNotify("Item ESP cached " .. #itemCache .. " items", "Item ESP", 1)
    end

    itemFrameCounter = itemFrameCounter + 1
    if itemFrameCounter > ITEM_UPDATE_EVERY_N_FRAMES then
        itemFrameCounter = 0
    end

    if itemFrameCounter ~= 0 then
        return
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
local CORPSE_UPDATE_EVERY_N_FRAMES = 3
local corpseScanned = false

local function ClearCorpseDrawings()
    for _, drawing in ipairs(corpseDrawings) do
        pcall(drawing.Remove, drawing)
    end
    corpseDrawings = {}
end

local function ScanCorpses()
    local corpses = {}
    local corpseFolder = Workspace:FindFirstChild("Corpses")
    if not corpseFolder then
        corpseScanned = true
        return corpses
    end

    for _, child in ipairs(corpseFolder:GetChildren()) do
        if child:IsA("Model") then
            local position = nil
            
            local rootPart = child:FindFirstChild("HumanoidRootPart")
            if rootPart and rootPart:IsA("BasePart") then
                position = rootPart.Position
            end
            
            if not position then
                for _, part in ipairs(child:GetChildren()) do
                    if part:IsA("MeshPart") or part:IsA("Part") or part:IsA("BasePart") then
                        position = part.Position
                        break
                    end
                end
            end
            
            if not position then
                local success, result = pcall(function()
                    return child:GetPivot().Position
                end)
                if success and result and result.Magnitude > 0 then
                    position = result
                end
            end
            
            if position then
                table.insert(corpses, {
                    Name = child.Name,
                    Position = position,
                })
            end
        end
    end
    
    corpseScanned = true
    return corpses
end

local function RenderCorpseESP()
    persistentState.corpseEspEnabled = UI.GetValue("corpse_esp_toggle") or false

    if not persistentState.corpseEspEnabled then
        ClearCorpseDrawings()
        corpseScanned = false
        corpseCache = {}
        return
    end

    if #corpseCache == 0 and not corpseScanned then
        corpseCache = ScanCorpses()
        if #corpseCache == 0 then
            return
        end
        SafeNotify("Corpse ESP Enabled", "Corpse ESP", 2)
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
                table.insert(visibleCorpses, {
                    Text = corpse.Name .. " [" .. math.floor(distance) .. "m]",
                    Position = screenPos,
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
            drawing.Visible = true
        end
    end

    for i = visibleCount + 1, #corpseDrawings do
        if corpseDrawings[i] then
            corpseDrawings[i].Visible = false
        end
    end
end

local panelDrawings = {}
local cachedPlayer = nil
local cachedData = nil
local lastRenderTime = 0
local MIN_SCALE = 0.8
local MAX_SCALE = 2.5
local UI_UPDATE_INTERVAL = 0.5

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

local function GetTargetPlayer()
    local camera = workspace.CurrentCamera
    if not camera then return nil end

    local cameraPos = camera.Position
    local lookDirection = camera.CFrame.LookVector
    local closestPlayer = nil
    local closestAngle = math.rad(7)

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Name == player.Name then continue end
        if plr.Character and plr.Character.Parent then
            local head = plr.Character:FindFirstChild("Head")
            if head then
                local headPos = head.Position
                local toPlayer = (headPos - cameraPos).Unit
                local angle = math.acos(math.clamp(lookDirection:Dot(toPlayer), -1, 1))
                if angle < closestAngle then
                    closestAngle = angle
                    closestPlayer = plr
                end
            end
        end
    end
    return closestPlayer
end

local function ScanEquippedWeapons(plr)
    local items = {}
    local character = plr.Character
    if character then
        for _, child in ipairs(character:GetChildren()) do
            local name = child.Name
            if IsJunk(name) then continue end
            if not IsReadableString(name) then continue end
            if child:IsA("Tool") and child:FindFirstChild("Handle") and child.Handle:IsA("MeshPart") then
                table.insert(items, name)
            end
        end
    end
    return items
end

local function ScanBackpack(plr)
    local items = {}
    local backpack = plr:FindFirstChild("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            local name = item.Name
            if IsReadableString(name) and not IsJunk(name) then
                table.insert(items, name)
            end
        end
    end
    table.sort(items)
    return items
end

local function ScanPlayerGui(plr)
    local items = {}
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
                                    table.insert(items, name)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return items
end

local function GetPlayerData(plr)
    if not plr then return nil end

    local info = {
        Name = plr.Name,
        Backpack = {},
        Health = 0,
        Distance = 0,
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

    local backpackItems = ScanBackpack(plr)
    local guiItems = ScanPlayerGui(plr)

    local allItems = {}
    for _, item in ipairs(backpackItems) do table.insert(allItems, item) end
    for _, item in ipairs(guiItems) do
        local found = false
        for _, existing in ipairs(allItems) do
            if existing == item then found = true break end
        end
        if not found then table.insert(allItems, item) end
    end

    local equippedWeapons = ScanEquippedWeapons(plr)
    for _, weapon in ipairs(equippedWeapons) do
        local found = false
        for i, bpItem in ipairs(allItems) do
            if bpItem == weapon then
                allItems[i] = weapon .. " [equipped]"
                found = true
                break
            end
        end
        if not found then
            table.insert(allItems, weapon .. " [equipped]")
        end
    end

    table.sort(allItems)
    info.Backpack = allItems
    return info
end

local function GetContentLines(data)
    local lines = {}
    if not data then
        table.insert(lines, {text = "No target", color = Color3.fromRGB(150, 150, 150)})
        return lines
    end

    table.insert(lines, {text = "Distance: " .. data.Distance .. "m", color = Color3.fromRGB(200, 200, 200)})

    table.insert(lines, {text = "backpack:", color = Color3.fromRGB(200, 200, 200)})
    if #data.Backpack > 0 then
        for _, item in ipairs(data.Backpack) do
            if string.find(item, "%[equipped%]") then
                table.insert(lines, {text = "  " .. item, color = Color3.fromRGB(255, 200, 100)})
            else
                table.insert(lines, {text = "  " .. item, color = Color3.fromRGB(180, 180, 200)})
            end
        end
    else
        table.insert(lines, {text = "  empty", color = Color3.fromRGB(150, 150, 150)})
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
    local currentTarget = GetTargetPlayer()

    if currentTarget ~= cachedPlayer then
        cachedPlayer = currentTarget
        cachedData = currentTarget and GetPlayerData(currentTarget) or nil
    elseif currentTarget and cachedData then
        local freshData = GetPlayerData(currentTarget)
        if freshData then
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
        title.Outline = false
        title.Center = false
        title.Position = Vector2.new(panelX + padding, panelY + math.floor(8 * scale))
        title.Text = "BACKPACK INSPECTOR"
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

local function ResetAllToggles()
    for category, items in pairs(ITEM_TYPES) do
        persistentState.categoryToggles[category] = false
        for _, itemName in ipairs(items) do
            persistentState.itemToggles[itemName] = false
        end
    end

    persistentState.inspectorEnabled = false
    persistentState.itemEspEnabled = false
    persistentState.corpseEspEnabled = false
    persistentState.teleportEnabled = false
    persistentState.selectedPOI = 0

    ClearItemDrawings()
    ClearPanel()
    ClearCorpseDrawings()
    itemCache = {}
    corpseCache = {}
end

local function SetAllUITogglesFalse()
    UI.SetValue("inspector_toggle", false)
    UI.SetValue("item_esp_toggle", false)
    UI.SetValue("corpse_esp_toggle", false)
    UI.SetValue("corpse_distance", 1000)
    UI.SetValue("teleport_enabled", false)
    UI.SetValue("teleport_poi", 0)
    
    UI.SetValue("item_category_Equipment", false)
    UI.SetValue("item_category_Weapons", false)
    UI.SetValue("item_category_Ammo", false)
    UI.SetValue("item_category_Food", false)
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
    UI.SetValue("item_esp_toggle", persistentState.itemEspEnabled or false)
    UI.SetValue("item_distance", persistentState.itemDistance or 150)
    UI.SetValue("corpse_esp_toggle", persistentState.corpseEspEnabled or false)
    UI.SetValue("corpse_distance", persistentState.corpseDistance or 1000)
    UI.SetValue("teleport_enabled", persistentState.teleportEnabled or false)
    UI.SetValue("teleport_poi", persistentState.selectedPOI or 0)
    
    UI.SetValue("item_category_Equipment", persistentState.categoryToggles["Equipment"] or false)
    UI.SetValue("item_category_Weapons", persistentState.categoryToggles["Weapons"] or false)
    UI.SetValue("item_category_Ammo", persistentState.categoryToggles["Ammo"] or false)
    UI.SetValue("item_category_Food", persistentState.categoryToggles["Food"] or false)
    UI.SetValue("item_category_Misc", persistentState.categoryToggles["Misc"] or false)

    for name, enabled in pairs(persistentState.itemToggles) do
        if toggleRefs[name] then
            toggleRefs[name].Value = enabled
        end
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
            if #itemCache == 0 then
                local camera = workspace.CurrentCamera
                if camera then
                    itemCache = ScanAllItems()
                    if #itemCache > 0 then
                        SafeNotify("Item ESP enabled", "Item ESP", 2)
                    else
                        SafeNotify("No items found. Check your toggles.", "Item ESP", 2)
                    end
                end
            else
                SafeNotify("Item ESP enabled", "Item ESP", 2)
            end
        else
            ClearItemDrawings()
            itemCache = {}
            SafeNotify("Item ESP disabled", "Item ESP", 2)
        end
    end)

    MainSection:SliderInt("item_distance", "Item Distance", 10, 2000, 150, function(value)
        persistentState.itemDistance = value
    end)

    MainSection:Spacing()
    MainSection:Text("Item Categories:")

    MainSection:Toggle("item_category_Equipment", "Equipment", function(state)
        persistentState.categoryToggles["Equipment"] = state
        for _, itemName in ipairs(ITEM_TYPES["Equipment"] or {}) do
            persistentState.itemToggles[itemName] = state
        end
        ClearItemDrawings()
    end)

    MainSection:Toggle("item_category_Weapons", "Weapons", function(state)
        persistentState.categoryToggles["Weapons"] = state
        for _, itemName in ipairs(ITEM_TYPES["Weapons"] or {}) do
            persistentState.itemToggles[itemName] = state
        end
        ClearItemDrawings()
    end)

    MainSection:Toggle("item_category_Ammo", "Ammo", function(state)
        persistentState.categoryToggles["Ammo"] = state
        for _, itemName in ipairs(ITEM_TYPES["Ammo"] or {}) do
            persistentState.itemToggles[itemName] = state
        end
        ClearItemDrawings()
    end)

    MainSection:Toggle("item_category_Food", "Food", function(state)
        persistentState.categoryToggles["Food"] = state
        for _, itemName in ipairs(ITEM_TYPES["Food"] or {}) do
            persistentState.itemToggles[itemName] = state
        end
        ClearItemDrawings()
    end)

    MainSection:Toggle("item_category_Misc", "Misc", function(state)
        persistentState.categoryToggles["Misc"] = state
        for _, itemName in ipairs(ITEM_TYPES["Misc"] or {}) do
            persistentState.itemToggles[itemName] = state
        end
        ClearItemDrawings()
    end)

    MainSection:Spacing()
    MainSection:Spacing()

    MainSection:Toggle("corpse_esp_toggle", "Enable Corpse ESP", function(state)
        persistentState.corpseEspEnabled = state
        if state then
            corpseCache = {}
            SafeNotify("Corpse ESP enabled", nil, 2)
        else
            ClearCorpseDrawings()
            corpseCache = {}
            SafeNotify("Corpse ESP disabled", nil, 2)
        end
    end)

    MainSection:SliderInt("corpse_distance", "Corpse Distance", 10, 2000, 1000, function(value)
        persistentState.corpseDistance = value
    end)

    MainSection:Spacing()
    MainSection:Spacing()

    MainSection:Toggle("inspector_toggle", "Enable Backpack Inspector", function(state)
        persistentState.inspectorEnabled = state
        if state then
            SafeNotify("Backpack Inspector enabled", nil, 2)
        else
            ClearPanel()
            SafeNotify("Backpack Inspector disabled", nil, 2)
        end
    end)

    MainSection:SliderFloat("ui_scale", "UI Scale", MIN_SCALE, MAX_SCALE, 1.0, "%.1f", function(value)
        persistentState.uiScale = value
        ClearPanel()
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

RunService.RenderStepped:Connect(function()
    RenderPanel()
    RenderItemESP()
    RenderCorpseESP()
end)

ResetAllToggles()
SetAllUITogglesFalse()

SafeNotify("Rick Said The Walking Dead Was Loaded", "Walking Dead", 3)
