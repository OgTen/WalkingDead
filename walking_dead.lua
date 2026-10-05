local _nexaSource = game:HttpGet("https://raw.githubusercontent.com/OgTen/Nexa-UI/refs/heads/main/nexa-ui.lua")
local _nexaChunk, _nexaCompileError = loadstring(_nexaSource, "Nexa")
if not _nexaChunk then
    warn("[Walking Dead] Nexa compile failed: " .. tostring(_nexaCompileError))
    return
end

_nexaChunk()

local Lib
if type(getgenv) == "function" then
    local env = getgenv()
    Lib = env.Nexa or env.DrawingUI or env.UI
end
if type(Lib) ~= "table" and type(shared) == "table" then
    Lib = shared.Nexa or shared.DrawingUI or shared.UI
end
if type(Lib) ~= "table" and type(Nexa) == "table" then Lib = Nexa end
if type(Lib) ~= "table" and type(DrawingUI) == "table" then Lib = DrawingUI end
if type(Lib) ~= "table" and type(UI) == "table" then Lib = UI end

if type(Lib) ~= "table" or type(Lib.CreateWindow) ~= "function" then
    warn("[Walking Dead] Nexa loaded, but its Library API was not exported.")
    return
end

local RICK_LOGO = "https://i.ibb.co/xty8DqSq/rick-rick-grimes.png"

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

local _base = 0
for attempt = 1, 10 do
    local ok, b = pcall(getbase)
    if ok and b and b > 0 then _base = b break end
    task.wait(0.1)
end

local HAS_MEM = _base > 0 and type(memory_read) == "function" and type(memory_write) == "function"

local OFF = {
    FakeDM = 0x8ee1728, RealDM = 0x1f8,
    Children = 0x78, NameBox = 0x70,
    ClassDesc = 0x18, ClassName = 0x8,
}

local function isPtr(p)
    return type(p) == "number" and p > 0x2000000000 and p < 0x800000000000
end

local function rptr(a)
    if not HAS_MEM then return nil end
    local ok, v = pcall(memory_read, "uintptr_t", a)
    return ok and v or nil
end

local function readStr(a)
    if not HAS_MEM then return nil end
    local ok, s = pcall(memory_read, "string", a)
    if ok and type(s) == "string" and s ~= "" and #s < 64 and not s:find("[^%w%p ]") then
        return s
    end
end

local function readName(p)
    local np = rptr(p + OFF.NameBox)
    if not isPtr(np) then return nil end
    return readStr(np + 0x8) or readStr(np)
end

local function children(p)
    local out = {}
    local cp = rptr(p + OFF.Children)
    if not isPtr(cp) then return out end
    local b, e = rptr(cp), rptr(cp + 0x8)
    if not b or not e or e <= b then return out end
    for i = 0, math.min(math.floor((e - b) / 8), 2000) - 1 do
        local c = rptr(b + i * 8)
        if isPtr(c) then out[#out + 1] = c end
    end
    return out
end

local function findChild(p, name)
    for _, c in ipairs(children(p)) do
        if readName(c) == name then return c end
    end
end

local WorldState = {
    lightingPtr = 0, terrainPtr = 0, cloudsPtr = 0,
    atmoPtr = 0, sunRaysPtr = 0, skyPtr = 0,
    blurPtr = 0, colorCorrectionPtr = 0,
    ready = false,
    originals = {},
}

local DEFAULTS = {
    Lighting_Brightness    = 2,
    Lighting_ClockTime     = 14,
    Lighting_GlobalShadows = 1,
    Lighting_AmbientR      = 0,
    Lighting_AmbientG      = 0,
    Lighting_AmbientB      = 0,

    Terrain_GrassLength    = 0.5,
    Terrain_WaterR         = 0,
    Terrain_WaterG         = 0.5,
    Terrain_WaterB         = 1.0,
    Terrain_WaterReflect   = 0.5,
    Terrain_WaterTrans     = 0,
    Terrain_WaveSize       = 0.15,
    Terrain_WaveSpeed      = 0.5,

    Atmo_Density           = 0.3,
    Atmo_Glare             = 0,
    Atmo_Haze              = 0,

    SunRays_Enabled        = 1,
    Blur_Enabled           = 1,
    CC_Enabled             = 1,

    Cloud_Enabled          = 1,
}

local function memWalkInit()
    WorldState.lightingPtr = 0
    WorldState.terrainPtr = 0
    WorldState.cloudsPtr = 0
    WorldState.atmoPtr = 0
    WorldState.sunRaysPtr = 0
    WorldState.skyPtr = 0
    WorldState.blurPtr = 0
    WorldState.colorCorrectionPtr = 0

    if not HAS_MEM then return false end

    local fakeDM = rptr(_base + OFF.FakeDM)
    if not fakeDM then return false end
    local realDM = rptr(fakeDM + OFF.RealDM)
    if not isPtr(realDM) then return false end

    local lighting = findChild(realDM, "Lighting")
    if isPtr(lighting) then
        WorldState.lightingPtr = lighting
        for _, c in ipairs(children(lighting)) do
            local n = readName(c)
            if n == "Atmosphere" then WorldState.atmoPtr = c
            elseif n == "SunRays" then WorldState.sunRaysPtr = c
            elseif n == "Sky" then WorldState.skyPtr = c
            elseif n == "ColorCorrection" then WorldState.colorCorrectionPtr = c
            elseif n == "StaminaBlur" then WorldState.blurPtr = c
            elseif n == "Blur" and WorldState.blurPtr == 0 then WorldState.blurPtr = c
            end
        end
    end

    local ws = findChild(realDM, "Workspace")
    if isPtr(ws) then
        local terrain = findChild(ws, "Terrain")
        if isPtr(terrain) then
            WorldState.terrainPtr = terrain
            for _, c in ipairs(children(terrain)) do
                if readName(c) == "Clouds" then WorldState.cloudsPtr = c break end
            end
        end
    end

    WorldState.ready = true
    return true
end

local function safeWrite(memType, addr, value)
    if not addr or addr == 0 then return false end
    return pcall(memory_write, memType, addr, value)
end

local function resetToDefaults()
    if not WorldState.ready then return end

    local lp = WorldState.lightingPtr
    if lp and lp ~= 0 then
        safeWrite("float", lp + 0x108, DEFAULTS.Lighting_Brightness)
        safeWrite("float", lp + 0xb8,  DEFAULTS.Lighting_ClockTime)
        safeWrite("byte",  lp + 0x134, DEFAULTS.Lighting_GlobalShadows)
        safeWrite("float", lp + 0xc0,  DEFAULTS.Lighting_AmbientR)
        safeWrite("float", lp + 0xc4,  DEFAULTS.Lighting_AmbientG)
        safeWrite("float", lp + 0xc8,  DEFAULTS.Lighting_AmbientB)

        if isPtr(WorldState.atmoPtr) then
            safeWrite("uintptr_t", lp + 0x1c8, WorldState.atmoPtr)
        end
    end

    local tp = WorldState.terrainPtr
    if tp and tp ~= 0 then
        safeWrite("float", tp + 0x1e0, DEFAULTS.Terrain_GrassLength)
        safeWrite("float", tp + 0x1e8, DEFAULTS.Terrain_WaterReflect)
        safeWrite("float", tp + 0x1ec, DEFAULTS.Terrain_WaterTrans)
        safeWrite("float", tp + 0x1f0, DEFAULTS.Terrain_WaveSize)
        safeWrite("float", tp + 0x1f4, DEFAULTS.Terrain_WaveSpeed)
    end

    local ap = WorldState.atmoPtr
    if ap and ap ~= 0 then
        safeWrite("float", ap + 0xc0, DEFAULTS.Atmo_Density)
        safeWrite("float", ap + 0xc4, DEFAULTS.Atmo_Glare)
        safeWrite("float", ap + 0xc8, DEFAULTS.Atmo_Haze)
    end

    local sp = WorldState.sunRaysPtr
    if sp and sp ~= 0 then
        safeWrite("byte", sp + 0xa0, DEFAULTS.SunRays_Enabled)
    end

    local bp = WorldState.blurPtr
    if bp and bp ~= 0 then
        safeWrite("byte", bp + 0xa0, DEFAULTS.Blur_Enabled)
    end

    local ccp = WorldState.colorCorrectionPtr
    if ccp and ccp ~= 0 then
        safeWrite("byte", ccp + 0xa0, DEFAULTS.CC_Enabled)
    end

    local cp = WorldState.cloudsPtr
    if cp and cp ~= 0 then
        safeWrite("byte", cp + 0xB4, DEFAULTS.Cloud_Enabled)
    end

end

local function captureOriginals()
    if not WorldState.ready then return end
    WorldState.originals = {}
    local o = WorldState.originals

    local lp = WorldState.lightingPtr
    if isPtr(lp) then
        o.Lighting_Brightness    = rptr(lp + 0x108) and select(2, pcall(memory_read, "float", lp + 0x108)) or DEFAULTS.Lighting_Brightness
        local ok
        ok, o.Lighting_Brightness    = pcall(memory_read, "float", lp + 0x108)
        ok, o.Lighting_ClockTime     = pcall(memory_read, "float", lp + 0xb8)
        ok, o.Lighting_GlobalShadows = pcall(memory_read, "byte",  lp + 0x134)
        ok, o.Lighting_AmbientR      = pcall(memory_read, "float", lp + 0xc0)
        ok, o.Lighting_AmbientG      = pcall(memory_read, "float", lp + 0xc4)
        ok, o.Lighting_AmbientB      = pcall(memory_read, "float", lp + 0xc8)
    end

    local tp = WorldState.terrainPtr
    if isPtr(tp) then
        local ok
        ok, o.Terrain_GrassLength  = pcall(memory_read, "float", tp + 0x1e0)
        ok, o.Terrain_WaterR       = pcall(memory_read, "float", tp + 0x1d0)
        ok, o.Terrain_WaterG       = pcall(memory_read, "float", tp + 0x1d4)
        ok, o.Terrain_WaterB       = pcall(memory_read, "float", tp + 0x1d8)
        ok, o.Terrain_WaterReflect = pcall(memory_read, "float", tp + 0x1e8)
        ok, o.Terrain_WaterTrans   = pcall(memory_read, "float", tp + 0x1ec)
        ok, o.Terrain_WaveSize     = pcall(memory_read, "float", tp + 0x1f0)
        ok, o.Terrain_WaveSpeed    = pcall(memory_read, "float", tp + 0x1f4)
    end

    local ap = WorldState.atmoPtr
    if isPtr(ap) then
        local ok
        ok, o.Atmo_Density = pcall(memory_read, "float", ap + 0xc0)
        ok, o.Atmo_Glare   = pcall(memory_read, "float", ap + 0xc4)
        ok, o.Atmo_Haze    = pcall(memory_read, "float", ap + 0xc8)
    end

    local sp = WorldState.sunRaysPtr
    if isPtr(sp) then
        local ok
        ok, o.SunRays_Enabled = pcall(memory_read, "byte", sp + 0xa0)
    end

    local bp = WorldState.blurPtr
    if isPtr(bp) then
        local ok
        ok, o.Blur_Enabled = pcall(memory_read, "byte", bp + 0xa0)
    end

    local ccp = WorldState.colorCorrectionPtr
    if isPtr(ccp) then
        local ok
        ok, o.CC_Enabled = pcall(memory_read, "byte", ccp + 0xa0)
    end

    local skp = WorldState.skyPtr
    if isPtr(skp) then
        local ok
    end

    local cp = WorldState.cloudsPtr
    if isPtr(cp) then
        local ok
        ok, o.Cloud_Enabled = pcall(memory_read, "byte", cp + 0xB4)
    end
end

memWalkInit()
resetToDefaults()
captureOriginals()

task.spawn(function()
    task.wait(1.0)
    resetToDefaults()
    task.wait(2.0)
    resetToDefaults()
end)

local modViewerBox = Lib:CreateOverlay({
    Title = "Mod Viewer",
    X = 24,
    Y = 340,
    Width = 150,
    DynamicWidth = "expand",
    DynamicHeight = true,
    Visible = false,
    Font = "SystemBold",
    FontSize = 13,
    HeaderSize = 12,
    LineSpacing = 2,
    LineHeight = 18,
})
modViewerBox:SetVisible(false)

local SCAN_RANGE = 5000

local _fpCamPos, _fpCamLook, _fpCamRight, _fpCamUp
local _fpVpW, _fpVpH, _fpFocal

local function _updateProjectionCache()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local camCF = cam.CFrame
    _fpCamPos = camCF.Position
    _fpCamLook = camCF.LookVector
    _fpCamRight = camCF.RightVector
    _fpCamUp = camCF.UpVector
    local vp = cam.ViewportSize
    _fpVpW = vp.X
    _fpVpH = vp.Y
    local fov = math.rad(cam.FieldOfView)
    _fpFocal = (vp.Y * 0.5) / math.tan(fov * 0.5)
end

local function _project(worldPos)
    if not worldPos or not _fpCamPos then return Vector2.new(0, 0), false end
    local dx = worldPos.X - _fpCamPos.X
    local dy = worldPos.Y - _fpCamPos.Y
    local dz = worldPos.Z - _fpCamPos.Z
    local forwardDist = dx*_fpCamLook.X + dy*_fpCamLook.Y + dz*_fpCamLook.Z
    if forwardDist <= 0.1 then return Vector2.new(0, 0), false end
    local rightDist = dx*_fpCamRight.X + dy*_fpCamRight.Y + dz*_fpCamRight.Z
    local upDist    = dx*_fpCamUp.X    + dy*_fpCamUp.Y    + dz*_fpCamUp.Z
    local invFwd = _fpFocal / forwardDist
    local sx = rightDist * invFwd + _fpVpW * 0.5
    local sy = -(upDist) * invFwd + _fpVpH * 0.5
    if sx ~= sx or sy ~= sy then return Vector2.new(0, 0), false end
    return Vector2.new(sx, sy), true
end

local lastNotifyTime = 0
local NOTIFY_COOLDOWN = 2.0
local lastNotifiedSkin = nil

local function SafeNotify(message, title, duration)
    local now = tick()
    if title and lastNotifiedSkin == title then
        if now - lastNotifyTime < NOTIFY_COOLDOWN then return end
    end
    lastNotifyTime = now
    lastNotifiedSkin = title
    pcall(notify, message, title or "Walking Dead", duration or 2)
end

local DEFAULT_COLORS = {
    itemWeapons = { r = 255, g = 200, b = 100 },
    itemMelee = { r = 255, g = 150, b = 50 },
    itemAmmo = { r = 255, g = 255, b = 100 },
    itemFood = { r = 100, g = 255, b = 100 },
    itemKeycards = { r = 255, g = 215, b = 0 },
    itemMisc = { r = 200, g = 200, b = 255 },
    itemEquipment = { r = 0, g = 255, b = 200 },
    itemAccessory = { r = 255, g = 215, b = 0 },
    corpseLoot = { r = 50, g = 255, b = 50 },
    banner = { r = 0, g = 200, b = 255 },
    car = { r = 255, g = 200, b = 50 },
    privateStorage = { r = 255, g = 120, b = 120 },
}

local COLORS = {}
for key, color in pairs(DEFAULT_COLORS) do
    COLORS[key] = { r = color.r, g = color.g, b = color.b }
end

local function GetColor3(key)
    local color = COLORS[key]
    if color then return Color3.fromRGB(color.r, color.g, color.b) end
    return Color3.fromRGB(255, 255, 255)
end

local persistentState = {
    inspectorEnabled = false,
    inspectorAlwaysVisible = false,
    uiScale = 1.0,
    modDetectionEnabled = false,
    modViewerAlwaysVisible = false,
    autoLeaveEnabled = false,
    autoLeaveDelay = 1.0,
    itemEspEnabled = false,
    itemDistance = 2500,
    itemToggles = {},
    categoryToggles = {},
    filterWeapons = {},
    filterMelee = {},
    filterAmmo = {},
    filterFood = {},
    filterMisc = {},
    filterKeycards = {},
    filterEquipment = {},
    filterAccessory = {},
    corpseEspEnabled = false,
    corpseDistance = 2500,
    corpseCache = {},
    corpseScanned = false,
    bannerEspEnabled = false,
    bannerDistance = 2500,
    bannerCache = {},
    bannerScanned = false,
    vehicleEspEnabled = false,
    vehicleDistance = 2500,
    vehicleCache = {},
    vehicleScanned = false,
    privateStorageEspEnabled = false,
    privateStorageDistance = 2500,
    privateStorageCache = {},
    privateStorageScanned = false,
}

local ITEM_TYPES = {
    ["Weapons"] = {"AR15", "AK47", "SCAR H", "MP5", "USP .45", "Model 331H", "Remington 870", "SKS", "SVD", "FN FAL", "Glock17", "M1911", "Colt Python", "BerretaM9", "Kar98K", "M1917", "M82A1", "FN Fal", "HK UMP-45", "AKS-74U", "Desert Eagle", "FN Five-seveN", "Model77E", "M40", "VSS Vintorez", "Mk 2 Grenade", "M67 Grenade", "M18 Smoke Grenade", "SPAS-12", "M16", "Ruger 10/22", "RPK"},
    ["Melee"] = {"Battle Hammer", "Mace", "Shiv", "Spiked Bat", "Wooden Bat", "Crowbar", "Fire Axe", "Hatchet", "Machete", "karambit", "Pipe Wrench", "Claw Hammer", "Pickaxe", "KA-BAR", "Cleaver", "Combat Knife", "Hammer", "Nightstick", "Hunting Knife", "Tactical knife", "Shovel", "Breaching Hammer", "Ice Pick", "Taiga Machete", "Felling Axe", "Military Machete"},
    ["Ammo"] = {".12 Gauge", ".22LR", ".357 Magnum", ".45 ACP", ".50 BMG", "5.45x39mm", "5.56x45mm", "5.7x28mm", "7.62x39mm", "7.62x51mm", "7.62x54mmR", "7.92x57mm", "9x19mm", "9x39mm", "USP .45"},
    ["Food"] = {"Apple Juice", "Biscuits", "Bottled Water", "Carbonated Water", "Chocolate Bar", "Chocolate Cookies", "Cola", "Energy Drink", "Grape Soda", "MRE", "Orange Juice", "Orange Soda", "Potato Chips", "Protein Bar", "Spicy Barbecue Chips", "Sweet Chili Chips", "Applesauce", "Baked Beans", "Beef Jerky", "Canned Peaches", "Canned Sardines", "Canned Tuna", "Chocobar", "Chocolate Spread", "Gummy Bears", "Milk", "Mixed Vegetables", "Peanut Butter", "Pork & Beans", "Salty Crackers", "Tomato Soup", "Chicken Soup", "Ham Spread"},
    ["Keycards"] = {"Bunker Access Keycard", "Prison Armory Access Keycard", "Satellite outpost Access Keycard", "Police Armory Access Keycard"},
    ["Misc"] = {"Bandage", "Improvised Bandage", "FlashLight", "Metal Parts", "Weapon Cleaning Kit", "Cloth", "Rag", "Stick", "IFAK", "First Aid Kit", "Disinfected Bandage", "Disinfectant", "Jerry Can", "Armor Repair Kit"},
    ["Equipment"] = {"MICH Ballistic Helmet", "Motorcycle Helmet", "M1 Helmet", "FAST Helmet", "Firefighter Helmet", "Basic NVGs", "Headlamp", "U.S. National Guard Plate Carrier", "Medic Vest", "K9 Vest", "Firefighter Vest", "VestBrownBlueShirt", "Plate Carrier", "Military Backpack", "Green School Backpack", "Black School Backpack", "Brown Traveler's Backpack", "Police Vest", "Tactical Vest", "Tactical Backpack", "Brown Canvas Backpack", "Military Duffel Bag", "Knight's Chestplate", "Knight's Helmet", "Pinestriped Fedora", "Skate Helmet", "ATE Gen 3 Ballistic Helmet", "Ballistic Helmet", "ATE Gen 2 Ballistic Helmet", "BLACK OPS Helmet", "MOLLE Plate Carrier", "Tactical Plate Carrier","ALTYN Helmet", "KORUND Body Armor"},
    ["Accessory"] = {"Black Paintball Mask", "Black Ski Mask", "Farmer's Straw Hat", "Mysterious Black Cowboy Hat", "Pinstriped Fedora", "Red Basic Bandana", "Shield Shades", "Surgical Mask", "Welding Mask", "White Basic Bandana"},
}

local ITEM_LOOKUP = {}
for category, items in pairs(ITEM_TYPES) do
    for _, item in ipairs(items) do ITEM_LOOKUP[item] = category end
end

local function GetModelPosition(model)
    if not model then return nil end
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
        return model.PrimaryPart.Position
    end
    local success, result = pcall(function()
        local cframe, size = model:GetBoundingBox()
        if cframe then return cframe.Position end
        return nil
    end)
    if success and result then return result end
    local partCount = 0
    for _, part in ipairs(model:GetDescendants()) do
        if partCount > 50 then break end
        if part:IsA("BasePart") then return part.Position end
        partCount = partCount + 1
    end
    local success2, result2 = pcall(function() return model:GetPivot().Position end)
    if success2 and result2 and result2.Magnitude > 0 then return result2 end
    return nil
end

local function GetContainerPosition(child)
    if not child then return nil end
    local pos = GetModelPosition(child)
    if pos then return pos end
    local current = child.Parent
    local attempts = 0
    while current and attempts < 15 do
        attempts = attempts + 1
        if current == Workspace or current == game then break end
        if current:IsA("Model") or current:IsA("Folder") then
            pos = GetModelPosition(current)
            if pos then return pos end
        end
        current = current.Parent
    end
    return nil
end

local function GetItemCategory(name) return ITEM_LOOKUP[name] or "Unknown" end

local function GetItemColor(name)
    local category = GetItemCategory(name)
    if category == "Weapons" then return GetColor3("itemWeapons")
    elseif category == "Melee" then return GetColor3("itemMelee")
    elseif category == "Ammo" then return GetColor3("itemAmmo")
    elseif category == "Food" then return GetColor3("itemFood")
    elseif category == "Keycards" then return GetColor3("itemKeycards")
    elseif category == "Misc" then return GetColor3("itemMisc")
    elseif category == "Equipment" then return GetColor3("itemEquipment")
    elseif category == "Accessory" then return GetColor3("itemAccessory")
    else return Color3.fromRGB(200, 200, 200) end
end

local function IsJunk(name)
    if not name or name == "" then return true end
    local lowerName = string.lower(name)
    local junkPatterns = {
        "moss", "corpse", "originalsize", "texture", "decals",
        "part", "mesh", "basepart", "handle", "weld", "motor6d",
        "attachment", "constraint", "rig", "body", "head",
    }
    for _, pattern in ipairs(junkPatterns) do
        if lowerName == pattern or string.find(lowerName, pattern, 1, true) then return true end
    end
    local exactMatch = {"Moss", "Corpse", "OriginalSize"}
    for _, valid in ipairs(exactMatch) do
        if valid == name then return true end
    end
    return false
end

local DrawingPool = {}
DrawingPool.__index = DrawingPool

function DrawingPool.new(maxSize)
    local self = { objects = {}, cache = {}, maxSize = maxSize or 100, activeCount = 0 }
    setmetatable(self, DrawingPool)
    return self
end

function DrawingPool:Ensure(size)
    if size > self.maxSize then self.maxSize = size + 10 end
    while #self.objects < self.maxSize do
        local label = Drawing.new("Text")
        label.Font = Drawing.Fonts.System
        label.Size = 11
        label.Outline = true
        label.Center = true
        label.ZIndex = 999
        label.Visible = false
        table.insert(self.objects, label)
        self.cache[#self.objects] = { Visible = false }
    end
end

function DrawingPool:Update(index, pos, text, color, visible)
    if index <= #self.objects then
        local obj = self.objects[index]
        if obj then
            local c = self.cache[index]
            if not c then c = {}; self.cache[index] = c end
            pos = pos or Vector2.new(0, 0)
            text = text or ""
            color = color or Color3.fromRGB(255, 255, 255)
            visible = visible and true or false

            if c.Position ~= pos then obj.Position = pos; c.Position = pos end
            if c.Text ~= text then obj.Text = text; c.Text = text end
            if c.Color ~= color then obj.Color = color; c.Color = color end
            if c.Visible ~= visible then obj.Visible = visible; c.Visible = visible end
        end
    end
end

function DrawingPool:SetVisible(index, visible)
    if index <= #self.objects and self.objects[index] then
        local c = self.cache[index]
        visible = visible and true or false
        if not c then c = {}; self.cache[index] = c end
        if c.Visible ~= visible then
            self.objects[index].Visible = visible
            c.Visible = visible
        end
    end
end

function DrawingPool:HideAll()
    for i, obj in ipairs(self.objects) do
        local c = self.cache[i]
        if not c then c = {}; self.cache[i] = c end
        if c.Visible ~= false then
            obj.Visible = false
            c.Visible = false
        end
    end
end

function DrawingPool:Clear()
    for _, obj in ipairs(self.objects) do pcall(obj.Remove, obj) end
    self.objects = {}
    self.cache = {}
    self.activeCount = 0
end

local itemPool = DrawingPool.new(200)
local itemCache = {}
local itemLastCount = -1

local function ScanAllItems()
    local foundItems = {}
    local enabledItems = {}
    for name, enabled in pairs(persistentState.itemToggles) do
        if enabled then enabledItems[name] = true end
    end

    local camera = workspace.CurrentCamera
    local cameraPos = camera and camera.Position
    if not cameraPos then return {} end

    local lootables = Workspace:FindFirstChild("Lootables")
    if lootables then
        local function ScanRecursive(parent)
            for _, child in ipairs(parent:GetChildren()) do
                if child:IsA("Model") or child:IsA("Folder") then
                    local name = child.Name
                    local category = GetItemCategory(name)
                    local showItem = false
                    local filterKey = "filter" .. category
                    local hasFilters = persistentState[filterKey] and #persistentState[filterKey] > 0
                    if hasFilters then
                        for _, selectedItem in ipairs(persistentState[filterKey]) do
                            if selectedItem == name then showItem = true; break end
                        end
                    else
                        if persistentState.categoryToggles[category] and enabledItems[name] then
                            showItem = true
                        end
                    end
                    if showItem then
                        local itemPos = GetContainerPosition(child)
                        if itemPos and (itemPos - cameraPos).Magnitude <= SCAN_RANGE then
                            table.insert(foundItems, {
                                Name = name, Position = itemPos,
                                Category = category, Color = GetItemColor(name),
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
                    local showItem = false
                    local filterKey = "filter" .. category
                    local hasFilters = persistentState[filterKey] and #persistentState[filterKey] > 0
                    if hasFilters then
                        for _, selectedItem in ipairs(persistentState[filterKey]) do
                            if selectedItem == name then showItem = true; break end
                        end
                    else
                        if persistentState.categoryToggles[category] and enabledItems[name] then
                            showItem = true
                        end
                    end
                    if showItem then
                        local itemPos = GetContainerPosition(child)
                        if itemPos and (itemPos - cameraPos).Magnitude <= SCAN_RANGE then
                            table.insert(foundItems, {
                                Name = name, Position = itemPos,
                                Category = category, Color = GetItemColor(name),
                            })
                        end
                    end
                    ScanRecursive(child)
                end
            end
        end
        ScanRecursive(loot)
    end

    local physicalLoot = Workspace:FindFirstChild("PhysicalLoot")
    if physicalLoot then
        for _, item in ipairs(physicalLoot:GetChildren()) do
            local name = item.Name
            local itemName = string.gsub(name, "^PhysicalLoot_", "")
            for _, cat in ipairs({"Weapons_", "Melee_", "Ammo_", "Food_", "Misc_", "Keycards_", "Equipment_", "Accessory_"}) do
                itemName = string.gsub(itemName, "^" .. cat, "")
            end
            local category = GetItemCategory(itemName)
            local showItem = false
            local filterKey = "filter" .. category
            local hasFilters = persistentState[filterKey] and #persistentState[filterKey] > 0
            if hasFilters then
                for _, selectedItem in ipairs(persistentState[filterKey]) do
                    if selectedItem == itemName then showItem = true; break end
                end
            else
                if persistentState.categoryToggles[category] and enabledItems[itemName] then
                    showItem = true
                end
            end
            if showItem then
                local itemPos = GetModelPosition(item)
                if itemPos and (itemPos - cameraPos).Magnitude <= SCAN_RANGE then
                    table.insert(foundItems, {
                        Name = itemName, Position = itemPos,
                        Category = category, Color = GetItemColor(itemName),
                    })
                end
            end
        end
    end
    return foundItems
end

local function PerformItemScan()
    itemCache = ScanAllItems()
    itemLastCount = #itemCache
    if itemLastCount > 0 then
        SafeNotify("Item ESP - " .. itemLastCount .. " items found", "Item ESP", 2)
    else
        SafeNotify("Item ESP - No items found", "Item ESP", 2)
    end
end

local function RenderItemESP()
    if not persistentState.itemEspEnabled then
        itemPool:HideAll(); itemCache = {}; itemLastCount = -1
        return
    end
    if #itemCache == 0 then itemPool:HideAll() return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local cameraPos = camera.Position
    local groupedItems = {}

    for _, item in ipairs(itemCache) do
        local distance = (item.Position - cameraPos).Magnitude
        if distance <= persistentState.itemDistance then
            local key = math.floor(item.Position.X * 100 + 0.5) .. "," .. math.floor(item.Position.Y * 100 + 0.5) .. "," .. math.floor(item.Position.Z * 100 + 0.5)
            if not groupedItems[key] then
                groupedItems[key] = { Position = item.Position, Items = {} }
            end
            table.insert(groupedItems[key].Items, item)
        end
    end

    local visibleItems = {}
    for _, group in pairs(groupedItems) do
        table.sort(group.Items, function(a, b) return a.Name < b.Name end)
        local screenPos, onScreen = _project(group.Position + Vector3.new(0, 0.5, 0))
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
    if visibleCount == 0 then itemPool:HideAll() return end
    itemPool:Ensure(visibleCount)
    for i = 1, visibleCount do
        local item = visibleItems[i]
        itemPool:Update(i, item.Position, item.Text, item.Color, true)
    end
    for i = visibleCount + 1, #itemPool.objects do itemPool:SetVisible(i, false) end
end

local corpsePool = DrawingPool.new(100)
local corpseCache = {}
local corpseScanned = false

local function ScanAllCorpses()
    local corpses = {}
    local corpseFolder = Workspace:FindFirstChild("Corpses")
    if not corpseFolder then return corpses end

    for _, child in ipairs(corpseFolder:GetChildren()) do
        if child:IsA("Model") then
            local position = nil
            local rootPart = child:FindFirstChild("HumanoidRootPart")
            if rootPart and rootPart:IsA("BasePart") then position = rootPart.Position end
            if not position then
                for _, part in ipairs(child:GetDescendants()) do
                    if part:IsA("BasePart") then
                        local pos = part.Position
                        if pos and pos.Magnitude > 0 then position = pos; break end
                    end
                end
            end
            if not position then
                local ok, result = pcall(function() return child:GetPivot().Position end)
                if ok and result and result.Magnitude > 0 then position = result end
            end
            if position then
                local lootFolder = child:FindFirstChild("Loot_Corpse")
                local lootItems = {}
                local hasLoot = false
                if lootFolder then
                    for _, item in ipairs(lootFolder:GetChildren()) do
                        if item:IsA("Folder") then
                            local name = item.Name
                            if name and name ~= "" and not IsJunk(name) then
                                if name ~= "Moss" and name ~= "Corpse" and name ~= "OriginalSize" then
                                    hasLoot = true
                                    table.insert(lootItems, name)
                                end
                            end
                        end
                    end
                end
                table.sort(lootItems)
                table.insert(corpses, {
                    Name = child.Name, Position = position,
                    HasLoot = hasLoot, LootItems = lootItems,
                })
            end
        end
    end
    table.sort(corpses, function(a, b) return a.Name < b.Name end)
    return corpses
end

local function PerformCorpseScan()
    corpseCache = ScanAllCorpses()
    corpseScanned = true
    local count = #corpseCache
    local lootCount = 0
    for _, c in ipairs(corpseCache) do
        if c.HasLoot then lootCount = lootCount + 1 end
    end
    if count > 0 then
        SafeNotify("Corpse ESP - " .. count .. " corpses found (" .. lootCount .. " with loot)", "Corpse ESP", 2)
    else
        SafeNotify("Corpse ESP - No corpses found", "Corpse ESP", 2)
    end
end

local function RenderCorpseESP()
    if not persistentState.corpseEspEnabled then
        corpsePool:HideAll(); corpseCache = {}; corpseScanned = false
        return
    end
    if not corpseScanned or #corpseCache == 0 then corpsePool:HideAll() return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local cameraPos = camera.Position
    local visibleCorpses = {}

    for _, corpse in ipairs(corpseCache) do
        if corpse.Position and corpse.HasLoot then
            local distance = (corpse.Position - cameraPos).Magnitude
            if distance <= persistentState.corpseDistance then
                local screenPos, onScreen = _project(corpse.Position + Vector3.new(0, 1.5, 0))
                if onScreen then
                    table.insert(visibleCorpses, {
                        Text = corpse.Name .. " [LOOT] [" .. math.floor(distance) .. "m]",
                        Position = screenPos,
                    })
                end
            end
        end
    end

    local visibleCount = #visibleCorpses
    if visibleCount == 0 then corpsePool:HideAll() return end
    corpsePool:Ensure(visibleCount)
    for i = 1, visibleCount do
        local corpse = visibleCorpses[i]
        corpsePool:Update(i, corpse.Position, corpse.Text, GetColor3("corpseLoot"), true)
    end
    for i = visibleCount + 1, #corpsePool.objects do corpsePool:SetVisible(i, false) end
end

local bannerPool = DrawingPool.new(50)
local bannerCache = {}
local bannerScanned = false

local function ScanAllBanners()
    local banners = {}
    local bannerFolder = Workspace:FindFirstChild("Banners")
    if not bannerFolder then return banners end
    for _, banner in ipairs(bannerFolder:GetChildren()) do
        if banner:IsA("Model") and banner.Name == "Banner" then
            local icon = banner:FindFirstChild("Icon")
            if icon and icon:IsA("BasePart") then
                table.insert(banners, { Name = "Banner", Position = icon.Position })
            end
        end
    end
    return banners
end

local function PerformBannerScan()
    bannerCache = ScanAllBanners()
    bannerScanned = true
    if #bannerCache > 0 then
        SafeNotify("Banner ESP - " .. #bannerCache .. " banners found", "Banner ESP", 2)
    else
        SafeNotify("Banner ESP - No banners found", "Banner ESP", 2)
    end
end

local function RenderBannerESP()
    if not persistentState.bannerEspEnabled then
        bannerPool:HideAll(); bannerCache = {}; bannerScanned = false
        return
    end
    if #bannerCache == 0 then bannerPool:HideAll() return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local cameraPos = camera.Position
    local visibleBanners = {}

    for _, banner in ipairs(bannerCache) do
        local distance = (banner.Position - cameraPos).Magnitude
        if distance <= persistentState.bannerDistance then
            local screenPos, onScreen = _project(banner.Position + Vector3.new(0, 1.5, 0))
            if onScreen then
                table.insert(visibleBanners, {
                    Text = "Banner [" .. math.floor(distance) .. "m]",
                    Position = screenPos,
                })
            end
        end
    end

    local visibleCount = #visibleBanners
    if visibleCount == 0 then bannerPool:HideAll() return end
    bannerPool:Ensure(visibleCount)
    for i = 1, visibleCount do
        local banner = visibleBanners[i]
        bannerPool:Update(i, banner.Position, banner.Text, GetColor3("banner"), true)
    end
    for i = visibleCount + 1, #bannerPool.objects do bannerPool:SetVisible(i, false) end
end

local vehiclePool = DrawingPool.new(50)
local vehicleCache = {}
local vehicleScanned = false

local function ToAscii(text)
    if not text then return "Unknown" end
    local result = ""
    for i = 1, #text do
        local byte = text:byte(i)
        if byte >= 32 and byte <= 126 then result = result .. string.char(byte) end
    end
    result = result:gsub("^%s*(.-)%s*$", "%1")
    result = result:gsub("%s+", " ")
    if result == "" then result = "Vehicle" end
    return result
end

local function ScanAllVehicles()
    local vehicles = {}
    local Vehicles = Workspace:FindFirstChild("Cars")
    if not Vehicles then return vehicles end
    for _, vehicle in ipairs(Vehicles:GetChildren()) do
        if vehicle:IsA("Model") then
            local crashPart = nil
            local body = vehicle:FindFirstChild("Body")
            if body then crashPart = body:FindFirstChild("CrashPart") end
            if not crashPart then
                for _, obj in ipairs(vehicle:GetDescendants()) do
                    if obj.Name == "CrashPart" and obj:IsA("BasePart") then
                        crashPart = obj; break
                    end
                end
            end
            if not crashPart then
                for _, obj in ipairs(vehicle:GetDescendants()) do
                    if obj:IsA("BasePart") then crashPart = obj; break end
                end
            end
            if crashPart and crashPart:IsA("BasePart") then
                local pos = crashPart.Position
                if pos and typeof(pos) == "Vector3" and pos.Magnitude > 0 then
                    table.insert(vehicles, {
                        Name = vehicle.Name, Position = pos, RawName = vehicle.Name,
                    })
                end
            end
        end
    end
    return vehicles
end

local function PerformVehicleScan()
    vehicleCache = ScanAllVehicles()
    vehicleScanned = true
    if #vehicleCache > 0 then
        SafeNotify("Vehicle ESP - " .. #vehicleCache .. " vehicles found", "Vehicle ESP", 2)
    else
        SafeNotify("Vehicle ESP - No vehicles found", "Vehicle ESP", 2)
    end
end

local function RenderVehicleESP()
    if not persistentState.vehicleEspEnabled then
        vehiclePool:HideAll(); vehicleCache = {}; vehicleScanned = false
        return
    end
    if #vehicleCache == 0 then vehiclePool:HideAll() return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local cameraPos = camera.Position
    local visibleVehicles = {}

    for _, vehicle in ipairs(vehicleCache) do
        if vehicle.Position then
            local distance = (vehicle.Position - cameraPos).Magnitude
            if distance <= persistentState.vehicleDistance then
                local screenPos, onScreen = _project(vehicle.Position + Vector3.new(0, 2, 0))
                if onScreen then
                    local displayName = ToAscii(vehicle.RawName)
                    table.insert(visibleVehicles, {
                        Text = displayName .. " [" .. math.floor(distance) .. "m]",
                        Position = screenPos,
                    })
                end
            end
        end
    end

    local visibleCount = #visibleVehicles
    if visibleCount == 0 then vehiclePool:HideAll() return end
    vehiclePool:Ensure(visibleCount)
    for i = 1, visibleCount do
        local vehicle = visibleVehicles[i]
        vehiclePool:Update(i, vehicle.Position, vehicle.Text, GetColor3("car"), true)
    end
    for i = visibleCount + 1, #vehiclePool.objects do vehiclePool:SetVisible(i, false) end
end

local storagePool = DrawingPool.new(20)
local privateStorageCache = {}
local privateStorageScanned = false
local storagePoolHidden = true

local STORAGE_TARGET_FOLDERS = { StorageBoxes = true, StorageBoxesSmall = true }
local STORAGE_CHILD_NAME = "Interact_PlayerStorage"

local function ScanAllPrivateStorage()
    local found = {}
    local ok, children = pcall(function() return Workspace:GetChildren() end)
    if not ok or not children then return found end

    for _, child in ipairs(children) do
        if STORAGE_TARGET_FOLDERS[child.Name] then
            local ok2, kids = pcall(function() return child:GetChildren() end)
            if ok2 and kids then
                for _, kid in ipairs(kids) do
                    if kid.Name == STORAGE_CHILD_NAME then
                        local isPart = pcall(function() return kid:IsA("BasePart") end)
                        if isPart then
                            local posOk, pos = pcall(function() return kid.Position end)
                            if posOk and pos and pos.Magnitude > 0 then
                                table.insert(found, { Name = "Private Storage", Position = pos })
                            end
                        end
                    end
                end
            end
        end
    end
    return found
end

local function PerformPrivateStorageScan()
    privateStorageCache = ScanAllPrivateStorage()
    privateStorageScanned = true
    if #privateStorageCache > 0 then
        SafeNotify("Private Storage ESP - " .. #privateStorageCache .. " found", "Private Storage ESP", 2)
    else
        SafeNotify("Private Storage ESP - None found", "Private Storage ESP", 2)
    end
end

local function RenderPrivateStorageESP()
    if not persistentState.privateStorageEspEnabled then
        if not storagePoolHidden then storagePool:HideAll(); storagePoolHidden = true end
        privateStorageCache = {}; privateStorageScanned = false
        return
    end
    if not privateStorageScanned or #privateStorageCache == 0 then
        if not storagePoolHidden then storagePool:HideAll(); storagePoolHidden = true end
        return
    end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local cameraPos = camera.Position
    local visibleStorage = {}

    for _, entry in ipairs(privateStorageCache) do
        local distance = (entry.Position - cameraPos).Magnitude
        if distance <= persistentState.privateStorageDistance then
            local screenPos, onScreen = _project(entry.Position + Vector3.new(0, 1, 0))
            if onScreen then
                table.insert(visibleStorage, {
                    Text = entry.Name .. " [" .. math.floor(distance) .. "m]",
                    Position = screenPos,
                    Color = GetColor3("privateStorage"),
                })
            end
        end
    end

    local visibleCount = #visibleStorage
    if visibleCount == 0 then
        if not storagePoolHidden then storagePool:HideAll(); storagePoolHidden = true end
        return
    end
    storagePool:Ensure(visibleCount)
    for i = 1, visibleCount do
        local entry = visibleStorage[i]
        storagePool:Update(i, entry.Position, entry.Text, entry.Color, true)
    end
    for i = visibleCount + 1, #storagePool.objects do storagePool:SetVisible(i, false) end
    storagePoolHidden = false
end


local GROUP_ID     = 34088407
local MOD_MIN_RANK = 100

local GROUP_SYNC_INTERVAL = 300

local MOD_SET = {}

local groupSyncing     = false
local groupSyncedCount = 0
local syncedRoster     = {}
local lastGroupSync    = 0
local initialSyncDone  = false

local modMonitorConnection = nil
local modRemoveConnection  = nil
local monitorActive        = false

local function Fetch(url)
    local ok, result = pcall(function()
        return game:HttpGet(url)
    end)
    if ok and result then return result end
    return nil
end

local function DecodeJson(str)
    if type(str) ~= "string" or str == "" then return nil end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(str)
    end)
    return ok and decoded or nil
end

local function IsPlayerMod(plr)
    if not plr or plr == player then return false end
    local name = plr.Name
    if name and MOD_SET[string.lower(name)] then return true end
    local displayName = plr.DisplayName
    if displayName and MOD_SET[string.lower(displayName)] then return true end
    return false
end

local function GetModsInGame()
    local found = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if IsPlayerMod(plr) then table.insert(found, plr.Name) end
    end
    return found
end

local function UpdateModViewer()
    if not modViewerBox then return end
    if not persistentState.modDetectionEnabled then
        modViewerBox:SetVisible(false)
        return
    end

    local found = GetModsInGame()
    modViewerBox:Clear()

    if not initialSyncDone then
        modViewerBox:Line("(syncing…)")
    elseif groupSyncedCount > 0 then
        modViewerBox:Line("Moderators:")
    else
        modViewerBox:Line("(sync empty)")
    end

    if #found > 0 then
        for i, name in ipairs(found) do
            if i <= 10 then modViewerBox:Line("- " .. name) end
        end
        if #found > 10 then
            modViewerBox:Line("... and " .. (#found - 10) .. " more")
        end
    else
        modViewerBox:Line(initialSyncDone and "Scanning for mods..." or "Syncing mod list...")
    end

    modViewerBox:SetVisible(#found > 0 or persistentState.modViewerAlwaysVisible)
end

local function AutoLeaveGame()
    local delay = persistentState.autoLeaveDelay or 1.0
    SafeNotify("Leaving game in " .. math.floor(delay) .. " seconds...", "Auto-Leave", delay + 1)
    task.wait(delay)
    SafeNotify("Leaving now...", "Auto-Leave", 1)
    task.wait(0.3)
    pcall(function() keypress(0x1B) end); task.wait(0.25); pcall(function() keyrelease(0x1B) end)
    task.wait(0.25)
    pcall(function() keypress(0x4C) end); task.wait(0.25); pcall(function() keyrelease(0x4C) end)
    task.wait(0.25)
    pcall(function() keypress(0x0D) end); task.wait(0.25); pcall(function() keyrelease(0x0D) end)
end

local function TriggerAutoLeave(reason)
    reason = reason or "Mod detected"
    SafeNotify(reason .. " - Leaving in 1s", "Auto-Leave", 3)
    task.wait(1)
    AutoLeaveGame()
end

local function PerformModScan(notifyResults)
    if not initialSyncDone then
        if notifyResults then
            SafeNotify("Waiting for group sync…", "Mod Detection", 2)
        end
        return {}
    end

    local found = GetModsInGame()
    if #found > 0 then
        local modList = table.concat(found, ", ")
        SafeNotify(#found .. " mod(s) in server: " .. modList, "Mod detected", 5)
        if persistentState.modDetectionEnabled then
            task.spawn(function() UpdateModViewer() end)
        end
        if persistentState.autoLeaveEnabled then
            TriggerAutoLeave(#found .. " mod(s) found: " .. modList)
        end
        return found
    else
        if notifyResults then
            SafeNotify("No mods found in server", "Mod Detection", 2)
        end
        if persistentState.modDetectionEnabled then
            task.spawn(function() UpdateModViewer() end)
        end
        return {}
    end
end

local function SyncGroupMods()
    if groupSyncing then return end

    groupSyncing = true

    local ok, err = pcall(function()
        local rolesDoc = DecodeJson(Fetch(
            "https://groups.roblox.com/v1/groups/" .. GROUP_ID .. "/roles"
        ))
        if not rolesDoc or type(rolesDoc.roles) ~= "table" then
            error("roles fetch failed or malformed")
        end

        local fresh, freshCount, roster = {}, 0, {}

        for i = 1, #rolesDoc.roles do
            local role = rolesDoc.roles[i]
            if type(role) == "table" and type(role.rank) == "number"
               and role.rank >= MOD_MIN_RANK and role.id then

                local roleName = type(role.name) == "string" and role.name or "staff"
                local cursor, pages = "", 0

                while pages < 5 do
                    pages = pages + 1

                    local url = "https://groups.roblox.com/v1/groups/"
                        .. GROUP_ID .. "/roles/" .. tostring(role.id)
                        .. "/users?limit=100"

                    if cursor ~= "" then
                        url = url .. "&cursor=" .. cursor
                    end

                    local usersDoc = DecodeJson(Fetch(url))
                    if not usersDoc or type(usersDoc.data) ~= "table" then break end

                    for k = 1, #usersDoc.data do
                        local entry = usersDoc.data[k]
                        if type(entry) == "table" then
                            if type(entry.username) == "string" and entry.username ~= "" then
                                local key = string.lower(entry.username)
                                if not fresh[key] then
                                    fresh[key] = true
                                    freshCount = freshCount + 1
                                    roster[#roster + 1] = { name = entry.username, role = roleName }
                                end
                            end
                        end
                    end

                    if type(usersDoc.nextPageCursor) == "string"
                       and usersDoc.nextPageCursor ~= "" then
                        cursor = usersDoc.nextPageCursor
                    else
                        break
                    end
                end
            end
        end

        for k in pairs(MOD_SET) do MOD_SET[k] = nil end
        for k in pairs(fresh) do MOD_SET[k] = true end

        groupSyncedCount = #roster
        syncedRoster     = roster
        lastGroupSync    = tick()
        initialSyncDone  = true

        print("[Walking Dead] Group sync: " .. #roster .. " users (group " .. GROUP_ID .. ")")

        UpdateModViewer()

        local inServer = GetModsInGame()

        if #inServer > 0 then
            local preview = table.concat(inServer, ", ")

            SafeNotify(
                #inServer .. " mod(s) in server: " .. preview,
                "Mod detected",
                5
            )

            if persistentState.autoLeaveEnabled then
                task.spawn(function()
                    TriggerAutoLeave(#inServer .. " mod(s) found: " .. preview)
                end)
            end
        end

        if persistentState.modDetectionEnabled then
            PerformModScan(false)
        end
    end)

    groupSyncing = false

    if not ok then
        warn("[Walking Dead] mod list sync failed: " .. tostring(err))
    end
end

local function StartModDetection()
    if monitorActive then return end
    monitorActive = true

    if modMonitorConnection then
        pcall(function() modMonitorConnection:Disconnect() end)
        modMonitorConnection = nil
    end
    if modRemoveConnection then
        pcall(function() modRemoveConnection:Disconnect() end)
        modRemoveConnection = nil
    end

    if not persistentState.modDetectionEnabled then
        monitorActive = false
        return
    end

    task.spawn(SyncGroupMods)

    UpdateModViewer()

    task.spawn(function()
        while monitorActive do
            task.wait(GROUP_SYNC_INTERVAL)
            if not monitorActive then break end
            SyncGroupMods()
        end
    end)

    if Players.PlayerAdded then
        modMonitorConnection = Players.PlayerAdded:Connect(function(plr)
            if persistentState.modDetectionEnabled and IsPlayerMod(plr) then
                SafeNotify("MOD JOINED: " .. plr.Name, "Mod detected", 5)
                if persistentState.modDetectionEnabled then
                    task.spawn(function() UpdateModViewer() end)
                end
                if persistentState.autoLeaveEnabled then
                    if modMonitorConnection then
                        pcall(function() modMonitorConnection:Disconnect() end)
                        modMonitorConnection = nil
                    end
                    monitorActive = false
                    TriggerAutoLeave("Mod joined: " .. plr.Name)
                end
            end
        end)
    end

    if Players.PlayerRemoving then
        modRemoveConnection = Players.PlayerRemoving:Connect(function(plr)
            if persistentState.modDetectionEnabled and IsPlayerMod(plr) then
                SafeNotify("MOD LEFT: " .. plr.Name, "Mod left", 3)
                if persistentState.modDetectionEnabled then
                    task.spawn(function() UpdateModViewer() end)
                end
            end
        end)
    end
end

local function StopModDetection()
    monitorActive = false
    if modMonitorConnection then
        pcall(function() modMonitorConnection:Disconnect() end)
        modMonitorConnection = nil
    end
    if modRemoveConnection then
        pcall(function() modRemoveConnection:Disconnect() end)
        modRemoveConnection = nil
    end
    if modViewerBox then modViewerBox:SetVisible(false) end
end

persistentState.inspectorBox = Lib:CreateOverlay({
    Title = "Target Inspector",
    X = 24,
    Y = 520,
    Width = 150,
    DynamicWidth = "expand",
    DynamicHeight = true,
    Visible = false,
    Font = "SystemBold",
    FontSize = 13,
    HeaderSize = 12,
    LineSpacing = 2,
    LineHeight = 18,
})
persistentState.inspectorBox:SetVisible(false)

local currentTargetName = ""
local currentData = nil
local lastScanTime = 0
local SCAN_INTERVAL = 0.5
local scanRequested = false
local forcedScanTimer = 0
local FORCED_SCAN_INTERVAL = 0.5
local cachedPlayers = {}
local lastPlayerCacheTime = 0
local PLAYER_CACHE_INTERVAL = 5.0

local function RefreshPlayerCache()
    local players = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character and plr.Character.Parent then
            local head = plr.Character:FindFirstChild("Head")
            if head and head:IsA("BasePart") then
                table.insert(players, { Player = plr, Head = head, Position = head.Position, Distance = 0 })
            end
        end
    end
    cachedPlayers = players
    lastPlayerCacheTime = tick()
end

local function GetCorpseLoot(corpse)
    for _, cached in ipairs(corpseCache) do
        if cached == corpse then
            local coloredItems = {}
            for _, item in ipairs(cached.LootItems or {}) do
                table.insert(coloredItems, { name = item, color = GetItemColor(item) })
            end
            return coloredItems
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
    local bestDot = math.cos(math.rad(4))
    local targetType = "Player"

    for _, pData in ipairs(cachedPlayers) do
        local head = pData.Head
        if head and head.Parent then
            local pos = head.Position
            pData.Position = pos
            local offset = pos - cameraPos
            local magnitude = offset.Magnitude
            if magnitude > 0.001 then
                local dot = lookDirection:Dot(offset / magnitude)
                if dot > bestDot then
                    bestDot = dot; closestTarget = pData.Player; targetType = "Player"
                end
            end
        end
    end

    for _, corpse in ipairs(corpseCache) do
        local pos = corpse.Position
        if pos then
            local offset = pos - cameraPos
            local magnitude = offset.Magnitude
            if magnitude > 0.001 then
                local dot = lookDirection:Dot(offset / magnitude)
                if dot > bestDot then
                    bestDot = dot; closestTarget = corpse; targetType = "Corpse"
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
        local info = { Name = plr.Name, Backpack = {}, Health = 0, Distance = 0, Type = "Player" }
        local character = plr.Character
        if character then
            local humanoid = character:FindFirstChild("Humanoid")
            if humanoid then info.Health = math.floor(humanoid.Health) end
            for _, pData in ipairs(cachedPlayers) do
                if pData.Player == plr then
                    info.Distance = math.floor((pData.Position - workspace.CurrentCamera.Position).Magnitude)
                    break
                end
            end
        end
        local backpack = plr:FindFirstChild("Backpack")
        if backpack then
            for _, item in ipairs(backpack:GetChildren()) do
                local name = item.Name
                if name and name ~= "" and not IsJunk(name) then table.insert(info.Backpack, name) end
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
                                    if name and name ~= "" then
                                        local category = GetItemCategory(name)
                                        if category ~= "Unknown" and not IsJunk(name) then
                                            table.insert(info.Backpack, name)
                                        end
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
                    if not IsJunk(name) then
                        local found = false
                        for i, bpItem in ipairs(info.Backpack) do
                            if bpItem == name then
                                info.Backpack[i] = name .. " [equipped]"; found = true; break
                            end
                        end
                        if not found then table.insert(info.Backpack, name .. " [equipped]") end
                    end
                end
            end
        end
        local cleaned = {}
        for _, item in ipairs(info.Backpack) do
            if not IsJunk(item) then table.insert(cleaned, item) end
        end
        info.Backpack = cleaned
        table.sort(info.Backpack)
        return info
    elseif targetType == "Corpse" then
        local corpse = target
        local info = { Name = corpse.Name, Backpack = {}, Health = 0, Distance = 0, Type = "Corpse" }
        local pos = corpse.Position
        if pos then
            local camera = workspace.CurrentCamera
            if camera then info.Distance = math.floor((pos - camera.Position).Magnitude) end
        end
        local lootData = GetCorpseLoot(corpse)
        for _, item in ipairs(lootData) do
            if not IsJunk(item.name) then table.insert(info.Backpack, item.name) end
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
    table.insert(lines, {text = data.Name, color = Color3.fromRGB(255, 255, 255)})
    local label = data.Type == "Corpse" and "Loot:" or "Backpack:"
    table.insert(lines, {text = label, color = Color3.fromRGB(255, 255, 255)})
    if #data.Backpack > 0 then
        for _, item in ipairs(data.Backpack) do
            local isEquipped = string.find(item, "%[equipped%]")
            local color = isEquipped and Color3.fromRGB(255, 200, 100) or GetItemColor(item)
            table.insert(lines, {text = "  " .. item, color = color})
        end
    else
        table.insert(lines, {text = "  (empty)", color = Color3.fromRGB(150, 150, 150)})
    end
    return lines
end

local function UpdateInspectorGUI(data)
    if not persistentState.inspectorBox then return end
    persistentState.inspectorBox:Clear()

    if not data then
        if persistentState.inspectorEnabled and persistentState.inspectorAlwaysVisible then
            persistentState.inspectorBox:Line("Scanning for target...", Color3.fromRGB(150, 150, 150))
            persistentState.inspectorBox:SetVisible(true)
        else
            persistentState.inspectorBox:SetVisible(false)
        end
        return
    end

    local lines = GetContentLines(data)
    for i = 1, #lines do
        local lineData = lines[i]
        persistentState.inspectorBox:Line(lineData.text, lineData.color)
    end

    persistentState.inspectorBox:SetVisible(true)
end

local function RenderInspector()
    if not persistentState.inspectorEnabled then
        if persistentState.inspectorBox then persistentState.inspectorBox:SetVisible(false) end
        currentTargetName = ""
        return
    end

    local target, targetType = GetTargetPlayer()
    local newTargetName = target and target.Name or ""

    if newTargetName ~= currentTargetName then
        currentTargetName = newTargetName
        persistentState.inspectorPendingTarget = target
        persistentState.inspectorPendingType = targetType
        persistentState.inspectorPendingSerial = (persistentState.inspectorPendingSerial or 0) + 1

        if not target then
            currentData = nil
            UpdateInspectorGUI(nil)
        end
    end
end

task.spawn(function()
    local handledSerial = -1
    while true do
        if persistentState.inspectorEnabled then
            local now = tick()

            if now - lastPlayerCacheTime > PLAYER_CACHE_INTERVAL then
                pcall(RefreshPlayerCache)
            end

            local serial = persistentState.inspectorPendingSerial or 0
            if serial ~= handledSerial then
                handledSerial = serial
                local target = persistentState.inspectorPendingTarget
                local targetType = persistentState.inspectorPendingType

                if target then
                    local ok, data = pcall(GetTargetData, target, targetType)
                    if ok and data and handledSerial == (persistentState.inspectorPendingSerial or 0) then
                        currentData = data
                        UpdateInspectorGUI(data)
                    end
                end
            end
        end
        task.wait(0.05)
    end
end)

local win = Lib:CreateWindow({
    Title = "Walking Dead",
    Subtitle = "by og_ten",
    Size = Vector2.new(700, 540),
    MenuKey = "p",

    Logo = RICK_LOGO,
    ShowLogo = true,
    LogoSize = 38,
    ShowGameName = true,

    Theme = "Obsidian",
    Background = "Snow",

    Splash = {
        Title = "Walking Dead",
        Image = RICK_LOGO,
        ShowLogo = true,
        ShowGameName = true,
        LogoSize = 58,
        Border = true,
        AccentBar = true,
        FooterAccent = true,
        Duration = 5.0,
    },
})

Lib:Notify({
    Title = "Walking Dead",
    Content = "Press P to toggle the menu",
    Duration = 4,
    Type = "info",
})

local espTab = Lib:AddTab({ Title = "ESP", Icon = "eye", Select = true })
local itemSection = espTab:AddSection("Item ESP", "Find Items Near You", { Column = "left" })

itemSection:AddSlider({
    Title = "Item Render Distance",
    ConfigKey = "esp.itemDistance",
    Default = persistentState.itemDistance, Min = 0, Max = 5000, Step = 100, Suffix = "m",
    Callback = function(v) persistentState.itemDistance = v end,
})

local itemToggle = itemSection:AddToggle({
    Title = "Enable Item ESP",
    ConfigKey = "esp.itemEnabled",
    Default = false,
    InlineGap = 10,
    InlineOrder = {"Keybind"},
    Callback = function(state)
        persistentState.itemEspEnabled = state
        if state then
            itemCache = {}; itemLastCount = -1
            task.spawn(function() task.wait(0.1); PerformItemScan() end)
        else
            itemPool:HideAll(); itemCache = {}; itemLastCount = -1
            SafeNotify("Item ESP disabled", "Item ESP", 2)
        end
    end,
})

itemToggle:AddKeybind({
    Title = "Refresh Item ESP",
    Default = "i",
    Mode = "Hold",
    Pressed = function()
        if persistentState.itemEspEnabled then
            itemCache = {}; itemLastCount = -1
            task.spawn(function() task.wait(0.1); PerformItemScan() end)
        else
            SafeNotify("Item ESP is disabled. Enable it first.", "Item ESP", 2)
        end
    end,
})

local filterDropdowns = {}
local categories = {"Weapons", "Melee", "Equipment", "Ammo", "Food", "Misc", "Keycards", "Accessory"}
local categoryKeys = {
    Equipment = "itemEquipment", Weapons = "itemWeapons", Melee = "itemMelee",
    Ammo = "itemAmmo", Food = "itemFood", Misc = "itemMisc",
    Keycards = "itemKeycards", Accessory = "itemAccessory",
}

for _, cat in ipairs(categories) do
    local categoryToggle = itemSection:AddToggle({
        Title = cat,
        ConfigKey = "esp.category." .. cat,
        Default = false,
        InlineGap = 10,
        InlineOrder = {"ColorPicker"},
        Callback = function(state)
            persistentState.categoryToggles[cat] = state
            for _, itemName in ipairs(ITEM_TYPES[cat] or {}) do
                persistentState.itemToggles[itemName] = state
            end
            if state then itemCache = {}; itemPool:HideAll() else itemPool:HideAll() end
        end,
    })

    local colorKey = categoryKeys[cat]
    local color = COLORS[colorKey] or { r = 255, g = 255, b = 255 }
    categoryToggle:AddColorPicker({
        ConfigKey = "esp.color." .. colorKey,
        Default = Color3.fromRGB(color.r, color.g, color.b),
        Callback = function(newColor, alpha)
            COLORS[colorKey] = {
                r = math.floor(newColor.R * 255),
                g = math.floor(newColor.G * 255),
                b = math.floor(newColor.B * 255),
            }
        end,
    })

    local filterKey = "filter" .. cat
    local dropdown = itemSection:AddDropdown({
        Title = cat .. " Filter",
        ConfigKey = "esp.filter." .. cat,
        Options = ITEM_TYPES[cat] or {},
        Default = persistentState[filterKey] or {},
        Multi = true,
        VisibleRows = 6,
        Callback = function(selected)
            selected = selected or {}
            persistentState[filterKey] = selected
            SafeNotify(cat .. " Filter", #selected .. " items selected", 2)
        end,
    })
    filterDropdowns[cat] = dropdown
end

itemSection:AddButton({
    Title = "",
    ButtonText = "Clear All Filters",
    Expand = true,
    Variant = "danger",
    Callback = function()
        persistentState.filterWeapons = {}
        persistentState.filterMelee = {}
        persistentState.filterAmmo = {}
        persistentState.filterFood = {}
        persistentState.filterMisc = {}
        persistentState.filterKeycards = {}
        persistentState.filterEquipment = {}
        persistentState.filterAccessory = {}
        for _, dropdown in pairs(filterDropdowns) do
            dropdown:SetValue({})
        end
        SafeNotify("Filters", "All filters cleared", 2)
    end,
})

local corpseSection = espTab:AddSection("Corpse ESP", "Find Corpses Near You", { Column = "right" })
corpseSection:AddSlider({
    Title = "Corpse Render Distance",
    ConfigKey = "esp.corpseDistance",
    Default = persistentState.corpseDistance, Min = 0, Max = 5000, Step = 100, Suffix = "m",
    Callback = function(v) persistentState.corpseDistance = v end,
})

local corpseToggle = corpseSection:AddToggle({
    Title = "Enable Corpse ESP",
    ConfigKey = "esp.corpseEnabled",
    Default = false,
    InlineGap = 10,
    InlineOrder = {"Keybind"},
    Callback = function(state)
        persistentState.corpseEspEnabled = state
        if state then
            corpseCache = {}; corpseScanned = false
            task.spawn(function() task.wait(0.1); PerformCorpseScan() end)
        else
            corpsePool:HideAll(); corpseCache = {}; corpseScanned = false
            SafeNotify("Corpse ESP disabled", "Corpse ESP", 2)
        end
    end,
})
corpseToggle:AddKeybind({
    Title = "Refresh Corpse ESP",
    Default = "c",
    Mode = "Hold",
    Pressed = function()
        if persistentState.corpseEspEnabled then
            corpseCache = {}; corpseScanned = false
            task.spawn(function() task.wait(0.1); PerformCorpseScan() end)
        else
            SafeNotify("Corpse ESP is disabled. Enable it first.", "Corpse ESP", 2)
        end
    end,
})

local corpseLootColor = COLORS["corpseLoot"] or { r = 50, g = 255, b = 50 }
corpseSection:AddColorPicker({
    Title = "Corpse Loot Color",
    ConfigKey = "esp.color.corpseLoot",
    Default = Color3.fromRGB(corpseLootColor.r, corpseLootColor.g, corpseLootColor.b),
    Callback = function(newColor, alpha)
        COLORS["corpseLoot"] = { r = math.floor(newColor.R * 255), g = math.floor(newColor.G * 255), b = math.floor(newColor.B * 255) }
    end,
})

local bannerSection = espTab:AddSection("Banner ESP", "Find Banners Near You", { Column = "right" })
bannerSection:AddSlider({
    Title = "Banner Render Distance",
    ConfigKey = "esp.bannerDistance",
    Default = persistentState.bannerDistance, Min = 0, Max = 5000, Step = 100, Suffix = "m",
    Callback = function(v) persistentState.bannerDistance = v end,
})
local bannerToggle = bannerSection:AddToggle({
    Title = "Enable Banner ESP",
    ConfigKey = "esp.bannerEnabled",
    Default = false,
    InlineGap = 10,
    InlineOrder = {"Keybind"},
    Callback = function(state)
        persistentState.bannerEspEnabled = state
        if state then
            bannerCache = {}; bannerScanned = false
            task.spawn(function() task.wait(0.1); PerformBannerScan() end)
        else
            bannerPool:HideAll(); bannerCache = {}; bannerScanned = false
            SafeNotify("Banner ESP disabled", "Banner ESP", 2)
        end
    end,
})
bannerToggle:AddKeybind({
    Title = "Refresh Banner ESP",
    Default = "b",
    Mode = "Hold",
    Pressed = function()
        if persistentState.bannerEspEnabled then
            bannerCache = {}; bannerScanned = false
            task.spawn(function() task.wait(0.1); PerformBannerScan() end)
        else
            SafeNotify("Banner ESP is disabled. Enable it first.", "Banner ESP", 2)
        end
    end,
})
local bannerColor = COLORS["banner"] or { r = 0, g = 200, b = 255 }
bannerSection:AddColorPicker({
    Title = "Banner Color",
    ConfigKey = "esp.color.banner",
    Default = Color3.fromRGB(bannerColor.r, bannerColor.g, bannerColor.b),
    Callback = function(newColor, alpha)
        COLORS["banner"] = { r = math.floor(newColor.R * 255), g = math.floor(newColor.G * 255), b = math.floor(newColor.B * 255) }
    end,
})

local vehicleSection = espTab:AddSection("Vehicle ESP", "Find Vehicles Near You", { Column = "right" })
vehicleSection:AddSlider({
    Title = "Vehicle Render Distance",
    ConfigKey = "esp.vehicleDistance",
    Default = persistentState.vehicleDistance, Min = 0, Max = 5000, Step = 100, Suffix = "m",
    Callback = function(v) persistentState.vehicleDistance = v end,
})
local vehicleToggle = vehicleSection:AddToggle({
    Title = "Enable Vehicle ESP",
    ConfigKey = "esp.vehicleEnabled",
    Default = false,
    InlineGap = 10,
    InlineOrder = {"Keybind"},
    Callback = function(state)
        persistentState.vehicleEspEnabled = state
        if state then
            vehicleCache = {}; vehicleScanned = false
            task.spawn(function() task.wait(0.1); PerformVehicleScan() end)
        else
            vehiclePool:HideAll(); vehicleCache = {}; vehicleScanned = false
            SafeNotify("Vehicle ESP disabled", "Vehicle ESP", 2)
        end
    end,
})
vehicleToggle:AddKeybind({
    Title = "Refresh Vehicle ESP",
    Default = "v",
    Mode = "Hold",
    Pressed = function()
        if persistentState.vehicleEspEnabled then
            vehicleCache = {}; vehicleScanned = false
            task.spawn(function() task.wait(0.1); PerformVehicleScan() end)
        else
            SafeNotify("Vehicle ESP is disabled. Enable it first.", "Vehicle ESP", 2)
        end
    end,
})
local vehicleColor = COLORS["car"] or { r = 255, g = 200, b = 50 }
vehicleSection:AddColorPicker({
    Title = "Vehicle Color",
    ConfigKey = "esp.color.car",
    Default = Color3.fromRGB(vehicleColor.r, vehicleColor.g, vehicleColor.b),
    Callback = function(newColor, alpha)
        COLORS["car"] = { r = math.floor(newColor.R * 255), g = math.floor(newColor.G * 255), b = math.floor(newColor.B * 255) }
    end,
})

local privateStorageSection = espTab:AddSection("Private Storage", "Find Your Personal Storage", { Column = "right" })
privateStorageSection:AddSlider({
    Title = "Storage Render Distance",
    ConfigKey = "esp.privateStorageDistance",
    Default = persistentState.privateStorageDistance, Min = 0, Max = 5000, Step = 100, Suffix = "m",
    Callback = function(v) persistentState.privateStorageDistance = v end,
})
local privateStorageToggle = privateStorageSection:AddToggle({
    Title = "Enable Private Storage",
    ConfigKey = "esp.privateStorageEnabled",
    Default = false,
    InlineGap = 10,
    InlineOrder = {"Keybind"},
    Callback = function(state)
        persistentState.privateStorageEspEnabled = state
        if state then
            privateStorageCache = {}; privateStorageScanned = false
            task.spawn(function() task.wait(0.1); PerformPrivateStorageScan() end)
        else
            storagePool:HideAll(); privateStorageCache = {}; privateStorageScanned = false
            SafeNotify("Private Storage disabled", "Private Storage ESP", 2)
        end
    end,
})
privateStorageToggle:AddKeybind({
    Title = "Refresh Private Storage",
    Default = "p",
    Mode = "Hold",
    Pressed = function()
        if persistentState.privateStorageEspEnabled then
            privateStorageCache = {}; privateStorageScanned = false
            task.spawn(function() task.wait(0.1); PerformPrivateStorageScan() end)
        else
            SafeNotify("Private Storage ESP is disabled. Enable it first.", "Private Storage ESP", 2)
        end
    end,
})
local privateStorageColor = COLORS["privateStorage"] or { r = 255, g = 120, b = 120 }
privateStorageSection:AddColorPicker({
    Title = "Private Storage Color",
    ConfigKey = "esp.color.privateStorage",
    Default = Color3.fromRGB(privateStorageColor.r, privateStorageColor.g, privateStorageColor.b),
    Callback = function(newColor, alpha)
        COLORS["privateStorage"] = { r = math.floor(newColor.R * 255), g = math.floor(newColor.G * 255), b = math.floor(newColor.B * 255) }
    end,
})

local inspectorsTab = Lib:AddTab({ Title = "Inspectors", Icon = "search" })
local inspectorMain = inspectorsTab:AddSection("Target Inspector", "See Equipped Items")
inspectorMain:AddToggle({
    Title = "Enable Inspector",
    ConfigKey = "inspectors.targetInspector",
    Default = false,
    Callback = function(state)
        persistentState.inspectorEnabled = state
        if state then
            currentTargetName = ""; currentData = nil; scanRequested = true
            RefreshPlayerCache()
            UpdateInspectorGUI(nil)
            SafeNotify("Target Inspector enabled", nil, 2)
        else
            if persistentState.inspectorBox then persistentState.inspectorBox:SetVisible(false) end
            SafeNotify("Target Inspector disabled", nil, 2)
        end
    end,
})

inspectorMain:AddToggle({
    Title = "Always Show Inspector",
    ConfigKey = "inspectors.targetInspectorAlwaysVisible",
    Default = false,
    Callback = function(state)
        persistentState.inspectorAlwaysVisible = state
        if persistentState.inspectorEnabled then
            if currentData then
                UpdateInspectorGUI(currentData)
            else
                UpdateInspectorGUI(nil)
            end
        elseif persistentState.inspectorBox then
            persistentState.inspectorBox:SetVisible(false)
        end
    end,
})

local modMain = inspectorsTab:AddSection("Mod Detection", "Detect Mods")
local modToggle = modMain:AddToggle({
    Title = "Enable Mod Scan",
    ConfigKey = "inspectors.modScan",
    Default = false,
    Callback = function(state)
        persistentState.modDetectionEnabled = state
        if state then
            SafeNotify("Scanning for mods...", "Scanning", 2)
            task.spawn(function()
                task.wait(0.3)
                PerformModScan(true)
                StartModDetection()
            end)
        else
            StopModDetection()
            SafeNotify("Mod Detection disabled", "Mod Detection", 2)
        end
    end,
})

modMain:AddToggle({
    Title = "Always Show Mod Viewer",
    ConfigKey = "inspectors.modViewerAlwaysVisible",
    Default = false,
    Callback = function(state)
        persistentState.modViewerAlwaysVisible = state
        if persistentState.modDetectionEnabled then
            UpdateModViewer()
        elseif modViewerBox then
            modViewerBox:SetVisible(false)
        end
    end,
})

local autoLeaveToggle
autoLeaveToggle = modMain:AddToggle({
    Title = "Auto-Leave on Mod Detection",
    ConfigKey = "inspectors.autoLeave",
    Default = false,
    Callback = function(state)
        persistentState.autoLeaveEnabled = state
        if state then
            if persistentState.modDetectionEnabled then
                SafeNotify("Auto-Leave enabled - will leave when mod is detected", "Auto-Leave", 2)
                task.spawn(function()
                    local waited = 0
                    while not initialSyncDone and waited < 10 do
                        task.wait(0.25)
                        waited = waited + 0.25
                    end
                    task.wait(0.2)
                    local found = GetModsInGame()
                    if #found > 0 then
                        local modList = table.concat(found, ", ")
                        SafeNotify(#found .. " mod(s) in server! Leaving in " .. math.floor(persistentState.autoLeaveDelay) .. "s", "Auto-Leave", persistentState.autoLeaveDelay + 2)
                        task.wait(persistentState.autoLeaveDelay)
                        AutoLeaveGame()
                    end
                end)
            else
                SafeNotify("Auto-Leave requires Mod Detection to be enabled", "Auto-Leave", 3)
                task.spawn(function()
                    task.wait(0.1)
                    if autoLeaveToggle then autoLeaveToggle:SetValue(false, true) end
                    persistentState.autoLeaveEnabled = false
                end)
            end
        else
            SafeNotify("Auto-Leave disabled", "Auto-Leave", 2)
        end
    end,
})
modMain:AddSlider({
    Title = "Leave Delay",
    ConfigKey = "inspectors.leaveDelay",
    Default = persistentState.autoLeaveDelay, Min = 0.5, Max = 20.0, Step = 0.5, Suffix = "s",
    Callback = function(v) persistentState.autoLeaveDelay = v end,
})

local worldReady = WorldState.ready
local worldTab = Lib:AddTab({ Title = "World", Icon = "globe" })

local worldRegistry = {
    lightingToggles = {},
    skyToggles = {},
    terrainToggles = {},
    terrainSliders = {},
}

local function buildToggle(section, label, registry, key, applyFn)
    local t = section:AddToggle({
        Title = label,
        ConfigKey = "world.toggle." .. tostring(key),
        Default = false,
        Callback = applyFn,
    })
    registry[key] = t
    return t
end

local skySec = worldTab:AddSection("Sky & Effects", "visual atmosphere")

local atmoPtrOriginal = 0
do
    if isPtr(WorldState.lightingPtr) then
        atmoPtrOriginal = rptr(WorldState.lightingPtr + 0x1c8) or 0
    end
end

buildToggle(skySec, "Disable Atmosphere", worldRegistry.skyToggles, "DisableAtmo", function(state)
    if not isPtr(WorldState.lightingPtr) then return end
    local lp = WorldState.lightingPtr
    if state then
        local target = isPtr(WorldState.cloudsPtr) and WorldState.cloudsPtr or 0
        safeWrite("uintptr_t", lp + 0x1c8, target)
    else
        if isPtr(WorldState.atmoPtr) then safeWrite("uintptr_t", lp + 0x1c8, WorldState.atmoPtr) end
    end
end)

buildToggle(skySec, "Disable Sun Rays", worldRegistry.skyToggles, "DisableSunRays", function(state)
    if not isPtr(WorldState.sunRaysPtr) then return end
    safeWrite("byte", WorldState.sunRaysPtr + 0xa0, state and 0 or (WorldState.originals.SunRays_Enabled or DEFAULTS.SunRays_Enabled))
end)

buildToggle(skySec, "Disable Blur (Stamina)", worldRegistry.skyToggles, "DisableBlur", function(state)
    if not isPtr(WorldState.blurPtr) then return end
    safeWrite("byte", WorldState.blurPtr + 0xa0, state and 0 or (WorldState.originals.Blur_Enabled or DEFAULTS.Blur_Enabled))
end)

buildToggle(skySec, "Disable Color Correction", worldRegistry.skyToggles, "DisableCC", function(state)
    if not isPtr(WorldState.colorCorrectionPtr) then return end
    safeWrite("byte", WorldState.colorCorrectionPtr + 0xa0, state and 0 or (WorldState.originals.CC_Enabled or DEFAULTS.CC_Enabled))
end)

local waterSec = worldTab:AddSection("Water & Terrain", "water and ground controls")
buildToggle(waterSec, "Disable Grass", worldRegistry.terrainToggles, "DisableGrass", function(state)
    if not isPtr(WorldState.terrainPtr) then return end
    safeWrite("float", WorldState.terrainPtr + 0x1e0, state and -0.5 or (WorldState.originals.Terrain_GrassLength or DEFAULTS.Terrain_GrassLength))
end)

worldRegistry.terrainSliders.WaterTransparency = waterSec:AddSlider({
    Title = "Water Transparency",
    ConfigKey = "world.waterTransparency",
    Default = DEFAULTS.Terrain_WaterTrans, Min = 0, Max = 1, Step = 0.05,
    Callback = function(v)
        if not isPtr(WorldState.terrainPtr) then return end
        safeWrite("float", WorldState.terrainPtr + 0x1ec, v)
    end,
})
worldRegistry.terrainSliders.WaterReflectance = waterSec:AddSlider({
    Title = "Water Reflectance",
    ConfigKey = "world.waterReflectance",
    Default = DEFAULTS.Terrain_WaterReflect, Min = 0, Max = 1, Step = 0.05,
    Callback = function(v)
        if not isPtr(WorldState.terrainPtr) then return end
        safeWrite("float", WorldState.terrainPtr + 0x1e8, v)
    end,
})
worldRegistry.terrainSliders.WaveSize = waterSec:AddSlider({
    Title = "Wave Size",
    ConfigKey = "world.waveSize",
    Default = DEFAULTS.Terrain_WaveSize, Min = 0, Max = 5, Step = 0.05,
    Callback = function(v)
        if not isPtr(WorldState.terrainPtr) then return end
        safeWrite("float", WorldState.terrainPtr + 0x1f0, v)
    end,
})
worldRegistry.terrainSliders.WaveSpeed = waterSec:AddSlider({
    Title = "Wave Speed",
    ConfigKey = "world.waveSpeed",
    Default = DEFAULTS.Terrain_WaveSpeed, Min = 0, Max = 100, Step = 0.05,
    Callback = function(v)
        if not isPtr(WorldState.terrainPtr) then return end
        safeWrite("float", WorldState.terrainPtr + 0x1f4, v)
    end,
})

local utilSec = worldTab:AddSection("Utilities", "quick actions")

local function toggleAllOff(registry)
    for _, t in pairs(registry) do
        pcall(function() t:SetValue(false) end)
    end
end

utilSec:AddButton({
    Title = "",
    ButtonText = "Restore All World Values",
    Expand = true,
    Variant = "danger",
    Callback = function()
        toggleAllOff(worldRegistry.lightingToggles)
        toggleAllOff(worldRegistry.skyToggles)
        toggleAllOff(worldRegistry.terrainToggles)

        pcall(function() worldRegistry.terrainSliders.WaterTransparency:SetValue(DEFAULTS.Terrain_WaterTrans) end)
        pcall(function() worldRegistry.terrainSliders.WaterReflectance:SetValue(DEFAULTS.Terrain_WaterReflect) end)
        pcall(function() worldRegistry.terrainSliders.WaveSize:SetValue(DEFAULTS.Terrain_WaveSize) end)
        pcall(function() worldRegistry.terrainSliders.WaveSpeed:SetValue(DEFAULTS.Terrain_WaveSpeed) end)

        resetToDefaults()

        Lib:Notify({
            Title = "World",
            Content = "All world values reset to defaults",
            Duration = 2,
            Type = "success",
        })
    end,
})

RunService.RenderStepped:Connect(function()
    _updateProjectionCache()
    RenderItemESP()
    RenderCorpseESP()
    RenderBannerESP()
    RenderVehicleESP()
    RenderPrivateStorageESP()
    RenderInspector()
end)

SafeNotify("Rick Said Its Loaded", "Walking Dead", 3)
