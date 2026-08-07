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
    bannerEspEnabled = false,
    bannerDistance = 500,
    carEspEnabled = false,
    carDistance = 500,
    teleportEnabled = false,
    selectedPOI = 0,
}

local emptyScanTracker = {}

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

local function IsJunk(name)
    if not name then return true end
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
    if name == "Neck" then return true end
    if name == "Body" then return true end
    if name == "Torso" then return true end
    if name == "LeftLeg" then return true end
    if name == "RightLeg" then return true end
    if name == "LeftArm" then return true end
    if name == "RightArm" then return true end
    return false
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

local DrawingPool = {}
DrawingPool.__index = DrawingPool

function DrawingPool.new(maxSize)
    local self = {
        objects = {},
        maxSize = maxSize or 100,
        activeCount = 0,
    }
    setmetatable(self, DrawingPool)
    return self
end

function DrawingPool:Ensure(size)
    if size > self.maxSize then
        self.maxSize = size + 10
    end
    
    while #self.objects < self.maxSize do
        local label = Drawing.new("Text")
        label.Font = Drawing.Fonts.System
        label.Size = 11
        label.Outline = true
        label.Center = true
        label.ZIndex = 999
        label.Visible = false
        table.insert(self.objects, label)
    end
end

function DrawingPool:Update(index, pos, text, color, visible)
    if index <= #self.objects then
        local obj = self.objects[index]
        if obj then
            obj.Position = pos or Vector2.new(0, 0)
            obj.Text = text or ""
            obj.Color = color or Color3.fromRGB(255, 255, 255)
            obj.Visible = visible or false
        end
    end
end

function DrawingPool:SetVisible(index, visible)
    if index <= #self.objects and self.objects[index] then
        self.objects[index].Visible = visible
    end
end

function DrawingPool:HideAll()
    for _, obj in ipairs(self.objects) do
        obj.Visible = false
    end
end

function DrawingPool:Clear()
    for _, obj in ipairs(self.objects) do
        pcall(obj.Remove, obj)
    end
    self.objects = {}
    self.activeCount = 0
end

local itemPool = DrawingPool.new(200)
local itemCache = {}
local itemFrameCounter = 0
local ITEM_UPDATE_EVERY_N_FRAMES = 2

local function ClearItemDrawings()
    itemPool:Clear()
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

local function RenderItemESP()
    persistentState.itemEspEnabled = UI.GetValue("item_esp_toggle") or false

    if not persistentState.itemEspEnabled then
        itemPool:HideAll()
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
        itemPool:HideAll()
        itemCache = {}
        return
    end

    local scanKey = ""
    for category, _ in pairs(enabledCategories) do
        scanKey = scanKey .. category .. ","
    end

    if emptyScanTracker[scanKey] then
        itemPool:HideAll()
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
            itemPool:HideAll()
            return
        end
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
        itemPool:HideAll()
        return
    end

    itemPool:Ensure(visibleCount)

    for i = 1, visibleCount do
        local item = visibleItems[i]
        itemPool:Update(i, item.Position, item.Text, item.Color, true)
    end

    for i = visibleCount + 1, #itemPool.objects do
        itemPool:SetVisible(i, false)
    end
end

local corpsePool = DrawingPool.new(100)
local corpseCache = {}
local corpseFrameCounter = 0
local CORPSE_UPDATE_EVERY_N_FRAMES = 3

local function ClearCorpseDrawings()
    corpsePool:Clear()
end

function ScanAllCorpses()
    local corpses = {}
    local corpseFolder = Workspace:FindFirstChild("Corpses")
    if not corpseFolder then
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
                local lootItems = {}
                
                if lootFolder then
                    for _, item in ipairs(lootFolder:GetChildren()) do
                        if item:IsA("Folder") then
                            local name = item.Name
                            for category, categoryItems in pairs(ITEM_TYPES) do
                                for _, itemName in ipairs(categoryItems) do
                                    if name == itemName then
                                        hasLoot = true
                                        table.insert(lootItems, name)
                                        break
                                    end
                                end
                                if hasLoot then break end
                            end
                        end
                    end
                end

                table.insert(corpses, {
                    Name = child.Name,
                    Position = position,
                    HasLoot = hasLoot,
                    LootItems = lootItems,
                })
            end
        end
    end
    
    return corpses
end

local function RefreshCorpseCache()
    corpseCache = ScanAllCorpses()
    if #corpseCache > 0 then
        local lootCount = 0
        for _, c in ipairs(corpseCache) do
            if c.HasLoot then lootCount = lootCount + 1 end
        end
        SafeNotify("Corpse ESP - " .. #corpseCache .. " corpses found (" .. lootCount .. " with loot)", "Corpse ESP", 2)
    else
        SafeNotify("Corpse ESP - No corpses found", "Corpse ESP", 2)
    end
end

local function RenderCorpseESP()
    persistentState.corpseEspEnabled = UI.GetValue("corpse_esp_toggle") or false

    if not persistentState.corpseEspEnabled then
        corpsePool:HideAll()
        corpseCache = {}
        return
    end

    if #corpseCache == 0 then
        corpsePool:HideAll()
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
                })
            end
        end
    end

    local visibleCount = #visibleCorpses

    if visibleCount == 0 then
        corpsePool:HideAll()
        return
    end

    corpsePool:Ensure(visibleCount)

    for i = 1, visibleCount do
        local corpse = visibleCorpses[i]
        corpsePool:Update(i, corpse.Position, corpse.Text, Color3.fromRGB(255, 50, 50), true)
    end

    for i = visibleCount + 1, #corpsePool.objects do
        corpsePool:SetVisible(i, false)
    end
end

local bannerPool = DrawingPool.new(50)
local bannerCache = {}
local bannerFrameCounter = 0
local BANNER_UPDATE_EVERY_N_FRAMES = 3
local bannerScanned = false

local function ClearBannerDrawings()
    bannerPool:Clear()
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

local function RenderBannerESP()
    persistentState.bannerEspEnabled = UI.GetValue("banner_esp_toggle") or false

    if not persistentState.bannerEspEnabled then
        bannerPool:HideAll()
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
        bannerPool:HideAll()
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then return end

    persistentState.bannerDistance = UI.GetValue("banner_distance") or 500
    local cameraPos = camera.Position

    bannerFrameCounter = bannerFrameCounter + 1
    if bannerFrameCounter > BANNER_UPDATE_EVERY_N_FRAMES then
        bannerFrameCounter = 0
    end

    if bannerFrameCounter ~= 0 then
        return
    end

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
        bannerPool:HideAll()
        return
    end

    bannerPool:Ensure(visibleCount)

    for i = 1, visibleCount do
        local banner = visibleBanners[i]
        bannerPool:Update(i, banner.Position, banner.Text, Color3.fromRGB(0, 200, 255), true)
    end

    for i = visibleCount + 1, #bannerPool.objects do
        bannerPool:SetVisible(i, false)
    end
end

local carPool = DrawingPool.new(50)
local carCache = {}
local carFrameCounter = 0
local CAR_UPDATE_EVERY_N_FRAMES = 3
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

local function ClearCarDrawings()
    carPool:Clear()
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

local function RenderCarESP()
    persistentState.carEspEnabled = UI.GetValue("car_esp_toggle") or false

    if not persistentState.carEspEnabled then
        carPool:HideAll()
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
        carPool:HideAll()
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then return end

    persistentState.carDistance = UI.GetValue("car_distance") or 500
    local cameraPos = camera.Position

    carFrameCounter = carFrameCounter + 1
    if carFrameCounter > CAR_UPDATE_EVERY_N_FRAMES then
        carFrameCounter = 0
    end

    if carFrameCounter ~= 0 then
        return
    end

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
        carPool:HideAll()
        return
    end

    carPool:Ensure(visibleCount)

    for i = 1, visibleCount do
        local car = visibleCars[i]
        carPool:Update(i, car.Position, car.Text, Color3.fromRGB(255, 200, 50), true)
    end

    for i = visibleCount + 1, #carPool.objects do
        carPool:SetVisible(i, false)
    end
end


local inspectorObjects = {}
local currentTargetName = ""
local currentData = nil
local lastScanTime = 0
local SCAN_INTERVAL = 0.5
local scanRequested = false
local forcedScanTimer = 0
local FORCED_SCAN_INTERVAL = 0.5

local cachedPlayers = {}
local lastPlayerCacheTime = 0
local PLAYER_CACHE_INTERVAL = 1.0

local function RefreshPlayerCache()
    local players = {}
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    local cameraPos = camera.Position
    
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == player then continue end
        if plr.Character and plr.Character.Parent then
            local head = plr.Character:FindFirstChild("Head")
            if head and head:IsA("BasePart") then
                local pos = head.Position
                table.insert(players, {
                    Player = plr,
                    Position = pos,
                    Distance = (pos - cameraPos).Magnitude,
                })
            end
        end
    end
    
    cachedPlayers = players
    lastPlayerCacheTime = tick()
end

local function CreateInspectorObjects()
    local bg = Drawing.new("Square")
    bg.Filled = true
    bg.Color = Color3.fromRGB(25, 25, 30)
    bg.Transparency = 0.85
    bg.ZIndex = 997
    bg.Corner = 8
    bg.Visible = false
    table.insert(inspectorObjects, bg)
    
    local border = Drawing.new("Square")
    border.Filled = false
    border.Color = Color3.fromRGB(255, 255, 255)
    border.Thickness = 2
    border.ZIndex = 998
    border.Corner = 8
    border.Visible = false
    table.insert(inspectorObjects, border)
    
    local title = Drawing.new("Text")
    title.Font = Drawing.Fonts.System
    title.Size = 16
    title.Color = Color3.fromRGB(255, 255, 255)
    title.Outline = true
    title.Center = false
    title.ZIndex = 999
    title.Text = "TARGET INSPECTOR"
    title.Visible = false
    table.insert(inspectorObjects, title)
    
    for i = 1, 50 do
        local txt = Drawing.new("Text")
        txt.Font = Drawing.Fonts.System
        txt.Size = 13
        txt.Color = Color3.fromRGB(255, 255, 255)
        txt.Outline = true
        txt.Center = false
        txt.ZIndex = 999
        txt.Visible = false
        table.insert(inspectorObjects, txt)
    end
end

local function HideAllInspectorObjects()
    for _, obj in ipairs(inspectorObjects) do
        obj.Visible = false
    end
end

local function UpdateInspectorGUI(data)
    if not data then
        HideAllInspectorObjects()
        return
    end
    
    if #inspectorObjects == 0 then
        CreateInspectorObjects()
    end
    
    local viewport = workspace.CurrentCamera
    if not viewport then return end
    local viewSize = viewport.ViewportSize
    local scale = persistentState.uiScale or 1.0
    
    local lines = {
        {text = "" .. data.Name, color = Color3.fromRGB(255, 255, 255)},
        {text = "", color = Color3.fromRGB(255, 255, 255)},
        {text = data.Type == "Corpse" and "Loot:" or "Backpack:", color = Color3.fromRGB(255, 255, 255)},
    }
    
    if #data.Backpack > 0 then
        for i, item in ipairs(data.Backpack) do
            local isEquipped = string.find(item, "%[equipped%]")
            table.insert(lines, {
                text = "  " .. item,
                color = isEquipped and Color3.fromRGB(255, 200, 100) or Color3.fromRGB(200, 200, 200)
            })
        end
    else
        table.insert(lines, {text = "  (empty)", color = Color3.fromRGB(150, 150, 150)})
    end
    
    local padding = 12 * scale
    local lineH = 18 * scale
    local titleH = 30 * scale
    local totalLines = #lines
    local panelW = 280 * scale
    local panelH = titleH + (totalLines * lineH) + padding
    
    local pX = viewSize.X - panelW - 20 * scale
    local pY = (viewSize.Y / 2) - (panelH / 2)
    
    local bg = inspectorObjects[1]
    bg.Size = Vector2.new(panelW, panelH)
    bg.Position = Vector2.new(pX, pY)
    bg.Visible = true
    
    local border = inspectorObjects[2]
    border.Size = Vector2.new(panelW, panelH)
    border.Position = Vector2.new(pX, pY)
    border.Visible = true
    
    local title = inspectorObjects[3]
    title.Position = Vector2.new(pX + padding, pY + 6 * scale)
    title.Size = 16 * scale
    title.Text = "TARGET INSPECTOR"
    title.Visible = true
    
    local yOff = pY + titleH + 2 * scale
    for i, lineData in ipairs(lines) do
        local txt = inspectorObjects[3 + i]
        if txt then
            txt.Position = Vector2.new(pX + padding, yOff)
            txt.Text = lineData.text
            txt.Color = lineData.color
            txt.Size = 13 * scale
            txt.Visible = true
            yOff = yOff + lineH
        end
    end
    
    for i = 4 + #lines, #inspectorObjects do
        if inspectorObjects[i] then
            inspectorObjects[i].Visible = false
        end
    end
end

local function GetCorpseLoot(corpse)
    for _, cached in ipairs(corpseCache) do
        if cached.Name == corpse.Name then
            return cached.LootItems or {}
        end
    end
    return {}
end

local function GetTargetPlayer()
    local camera = workspace.CurrentCamera
    if not camera then return nil, nil end

    local cameraPos = camera.Position
    local lookDirection = camera.CFrame.LookVector
    local closestTarget = nil
    local closestAngle = math.rad(7)
    local targetType = "Player"

    for _, pData in ipairs(cachedPlayers) do
        local toPlayer = (pData.Position - cameraPos).Unit
        local angle = math.acos(math.clamp(lookDirection:Dot(toPlayer), -1, 1))
        if angle < closestAngle then
            closestAngle = angle
            closestTarget = pData.Player
            targetType = "Player"
        end
    end

    for _, corpse in ipairs(corpseCache) do
        local pos = corpse.Position
        if pos then
            local toCorpse = (pos - cameraPos).Unit
            local angle = math.acos(math.clamp(lookDirection:Dot(toCorpse), -1, 1))
            local corpseAngle = math.rad(10)
            if angle < corpseAngle then
                if not closestTarget or angle < closestAngle then
                    closestAngle = angle
                    closestTarget = corpse
                    targetType = "Corpse"
                end
            end
        end
    end

    return closestTarget, targetType
end

local function GetTargetData(target, targetType)
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
            
            for _, pData in ipairs(cachedPlayers) do
                if pData.Player == plr then
                    info.Distance = math.floor(pData.Distance)
                    break
                end
            end
        end

        local backpack = plr:FindFirstChild("Backpack")
        if backpack then
            for _, item in ipairs(backpack:GetChildren()) do
                local name = item.Name
                if name and name ~= "" and not IsJunk(name) then
                    table.insert(info.Backpack, name)
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
                                    if name and name ~= "" and not IsJunk(name) then
                                        table.insert(info.Backpack, name)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
        if character then
            for _, child in ipairs(character:GetChildren()) do
                local name = child.Name
                if child:IsA("Tool") and child:FindFirstChild("Handle") and child.Handle:IsA("MeshPart") then
                    local found = false
                    for i, bpItem in ipairs(info.Backpack) do
                        if bpItem == name then
                            info.Backpack[i] = name .. " [equipped]"
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(info.Backpack, name .. " [equipped]")
                    end
                end
            end
        end

        table.sort(info.Backpack)
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

        local pos = corpse.Position
        if pos then
            local camera = workspace.CurrentCamera
            if camera then
                info.Distance = math.floor((pos - camera.Position).Magnitude)
            end
        end

        info.Backpack = GetCorpseLoot(corpse)
        return info
    end

    return nil
end

local function RenderInspector()
    persistentState.inspectorEnabled = UI.GetValue("inspector_toggle") or false

    if not persistentState.inspectorEnabled then
        if #inspectorObjects > 0 then
            HideAllInspectorObjects()
        end
        return
    end
    
    if #inspectorObjects == 0 then
        CreateInspectorObjects()
    end
    
    local now = tick()
    
    if now - lastPlayerCacheTime > PLAYER_CACHE_INTERVAL then
        RefreshPlayerCache()
    end
    
    if now - forcedScanTimer > FORCED_SCAN_INTERVAL then
        forcedScanTimer = now
        scanRequested = true
    end
    
    if scanRequested and now - lastScanTime > SCAN_INTERVAL then
        scanRequested = false
        lastScanTime = now
        
        local target, targetType = GetTargetPlayer()
        local newTargetName = target and (targetType == "Player" and target.Name or target.Name) or ""
        
        if newTargetName ~= currentTargetName then
            currentTargetName = newTargetName
            if target then
                local data = GetTargetData(target, targetType)
                if data then
                    currentData = data
                    UpdateInspectorGUI(data)
                end
            else
                currentData = nil
                HideAllInspectorObjects()
            end
        end
    end
end

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        if persistentState.inspectorEnabled then
            scanRequested = true
        end
    end
end)

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if persistentState.inspectorEnabled then
            scanRequested = true
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
    persistentState.itemEspEnabled = false
    persistentState.corpseEspEnabled = false
    persistentState.bannerEspEnabled = false
    persistentState.carEspEnabled = false
    persistentState.teleportEnabled = false
    persistentState.selectedPOI = 0

    itemPool:Clear()
    corpsePool:Clear()
    bannerPool:Clear()
    carPool:Clear()
    HideAllInspectorObjects()
    itemCache = {}
    corpseCache = {}
    bannerCache = {}
    carCache = {}
    cachedPlayers = {}
    currentTargetName = ""
    currentData = nil
end

local function SetAllUITogglesFalse()
    UI.SetValue("inspector_toggle", false)
    UI.SetValue("ui_scale", 1.0)
    UI.SetValue("item_esp_toggle", false)
    UI.SetValue("item_distance", 150)
    UI.SetValue("corpse_esp_toggle", false)
    UI.SetValue("corpse_distance", 1000)
    UI.SetValue("banner_esp_toggle", false)
    UI.SetValue("banner_distance", 500)
    UI.SetValue("car_esp_toggle", false)
    UI.SetValue("car_distance", 500)
    UI.SetValue("teleport_enabled", false)
    UI.SetValue("teleport_poi", 0)
    
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
    UI.SetValue("item_esp_toggle", persistentState.itemEspEnabled or false)
    UI.SetValue("item_distance", persistentState.itemDistance or 150)
    UI.SetValue("corpse_esp_toggle", persistentState.corpseEspEnabled or false)
    UI.SetValue("corpse_distance", persistentState.corpseDistance or 1000)
    UI.SetValue("banner_esp_toggle", persistentState.bannerEspEnabled or false)
    UI.SetValue("banner_distance", persistentState.bannerDistance or 500)
    UI.SetValue("car_esp_toggle", persistentState.carEspEnabled or false)
    UI.SetValue("car_distance", persistentState.carDistance or 500)
    UI.SetValue("teleport_enabled", persistentState.teleportEnabled or false)
    UI.SetValue("teleport_poi", persistentState.selectedPOI or 0)
    
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
            itemPool:HideAll()
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

    for _, cat in ipairs({"Equipment", "Weapons", "Melee", "Ammo", "Food", "Misc", "Keycards"}) do
        MainSection:Toggle("item_category_" .. cat, cat, function(state)
            persistentState.categoryToggles[cat] = state
            for _, itemName in ipairs(ITEM_TYPES[cat] or {}) do
                persistentState.itemToggles[itemName] = state
            end
            if state then
                itemCache = {}
                itemPool:HideAll()
            else
                itemPool:HideAll()
            end
        end)
    end

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
                itemPool:HideAll()
            end
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
            bannerPool:HideAll()
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
            RefreshCorpseCache()
        else
            corpsePool:HideAll()
            corpseCache = {}
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
            carPool:HideAll()
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

    MainSection:Spacing()
    MainSection:Spacing()

    MainSection:Toggle("inspector_toggle", "Enable Target Inspector", function(state)
        persistentState.inspectorEnabled = state
        if state then
            currentTargetName = ""
            currentData = nil
            scanRequested = true
            RefreshPlayerCache()
            HideAllInspectorObjects()
            SafeNotify("Target Inspector enabled", nil, 2)
        else
            HideAllInspectorObjects()
            SafeNotify("Target Inspector disabled", nil, 2)
        end
    end)

    MainSection:SliderFloat("ui_scale", "UI Scale", 0.8, 2.5, 1.0, "%.1f", function(value)
        persistentState.uiScale = value
        if currentData then
            UpdateInspectorGUI(currentData)
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
                itemPool:HideAll()
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
                bannerPool:HideAll()
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
                RefreshCorpseCache()
                SafeNotify("Corpse ESP rescanned", "Rescan", 1)
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
                carPool:HideAll()
                carScanned = false
                SafeNotify("Vehicle ESP rescanning...", "Rescan", 1)
            end)
        end
    end
end)

RunService.RenderStepped:Connect(function()
    RenderItemESP()
    RenderCorpseESP()
    RenderBannerESP()
    RenderCarESP()
    RenderInspector()
end)

ResetAllToggles()
SetAllUITogglesFalse()

SafeNotify("Rick Said The Walking Dead Was Loaded", "Walking Dead", 3)
