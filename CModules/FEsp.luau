local getgenv = getgenv or function() return shared end
if getgenv().EspFusion then
    return getgenv().EspFusion
end

local cloneref   = getgenv().cloneref or function(i) return i end
local Players    = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UIS        = cloneref(game:GetService("UserInputService"))
local CoreGui    = cloneref(game:GetService("CoreGui"))

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local GuiParent do
    local ok = pcall(function()
        local t = Instance.new("ScreenGui")
        t.Parent = CoreGui
        t:Destroy()
    end)
    GuiParent = ok and CoreGui or LocalPlayer:WaitForChild("PlayerGui")
end

local HighlightContainer = Instance.new("Folder",
    (function()
        local ok, hui = pcall(function() return gethui() end)
        return (ok and hui) or GuiParent
    end)()
)

local floor  = math.floor
local round  = math.round or function(n) return math.floor(n + 0.5) end
local sin    = math.sin
local cos    = math.cos
local clamp  = math.clamp
local huge   = math.huge
local clear  = table.clear
local unpack = table.unpack or unpack

local function worldToScreen(pos)
    if typeof(pos) ~= "Vector3" then return Vector2.zero, false, 0 end
    local s, inB = Camera:WorldToViewportPoint(pos)
    return Vector2.new(s.X, s.Y), inB, s.Z
end

local function rotateVec(v, r)
    local x, y = v.X, v.Y
    local c, s = cos(r), sin(r)
    return Vector2.new(x*c - y*s, x*s + y*c)
end

local function lerpColor(a, b, t)
    if typeof(a) ~= "Color3" then a = Color3.new(1, 0, 0) end
    if typeof(b) ~= "Color3" then b = Color3.new(0, 1, 0) end
    return Color3.new(
        a.R + (b.R - a.R) * t,
        a.G + (b.G - a.G) * t,
        a.B + (b.B - a.B) * t
    )
end

local VERTICES = {
    Vector3.new(-1,-1,-1), Vector3.new(-1, 1,-1),
    Vector3.new(-1, 1, 1), Vector3.new(-1,-1, 1),
    Vector3.new( 1,-1,-1), Vector3.new( 1, 1,-1),
    Vector3.new( 1, 1, 1), Vector3.new( 1,-1, 1),
}

local function isBodyPart(name)
    return name == "Head"
        or name:find("Torso")
        or name:find("Leg")
        or name:find("Arm")
end

local function getBBoxParts(model)
    local parts = {}
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") and isBodyPart(child.Name) then
            parts[#parts+1] = child
        elseif child:IsA("Accessory") then
            local h = child:FindFirstChild("Handle")
            if h and h:IsA("BasePart") then
                parts[#parts+1] = h
            end
        end
    end
    if #parts == 0 then
        for _, v in ipairs(model:GetDescendants()) do
            if v:IsA("BasePart") then parts[#parts+1] = v end
        end
    end
    return parts
end

local function computeBBox(parts)
    local wmin = Vector3.new( huge,  huge,  huge)
    local wmax = Vector3.new(-huge, -huge, -huge)
    local counted = 0
    for _, p in ipairs(parts) do
        if typeof(p) == "Instance" and p.Parent ~= nil then
            counted = counted + 1
            local h = p.Size * 0.5
            local pos = p.Position
            wmin = Vector3.new(math.min(wmin.X, pos.X-h.X), math.min(wmin.Y, pos.Y-h.Y), math.min(wmin.Z, pos.Z-h.Z))
            wmax = Vector3.new(math.max(wmax.X, pos.X+h.X), math.max(wmax.Y, pos.Y+h.Y), math.max(wmax.Z, pos.Z+h.Z))
        end
    end
    if counted == 0 then return nil, nil end

    local center = (wmin+wmax)*0.5
    local size   = wmax-wmin
    local front  = Vector3.new(center.X, center.Y, wmax.Z)

    if (front - center).Magnitude < 0.001 then
        return CFrame.new(center), size
    end
    return CFrame.new(center, front), size
end

local function calcCorners(cf, size)
    local s2x, s2y, s2z = size.X*0.5, size.Y*0.5, size.Z*0.5
    local screenPts = {}
    local mnX, mnY =  huge,  huge
    local mxX, mxY = -huge, -huge
    for i, v in ipairs(VERTICES) do
        local world = cf * Vector3.new(v.X*s2x, v.Y*s2y, v.Z*s2z)
        local s2, _, _ = Camera:WorldToViewportPoint(world)
        local p = Vector2.new(s2.X, s2.Y)
        screenPts[i] = p
        if p.X < mnX then mnX = p.X end
        if p.Y < mnY then mnY = p.Y end
        if p.X > mxX then mxX = p.X end
        if p.Y > mxY then mxY = p.Y end
    end
    return {
        corners     = screenPts,
        topLeft     = Vector2.new(floor(mnX), floor(mnY)),
        topRight    = Vector2.new(floor(mxX), floor(mnY)),
        bottomLeft  = Vector2.new(floor(mnX), floor(mxY)),
        bottomRight = Vector2.new(floor(mxX), floor(mxY)),
    }
end

local R15_SEQUENCE = {
    "LowerTorso","UpperTorso",
    "LeftUpperArm","LeftLowerArm","LeftHand","LeftLowerArm","LeftUpperArm","UpperTorso",
    "RightUpperArm","RightLowerArm","RightHand","RightLowerArm","RightUpperArm","UpperTorso",
    "LowerTorso",
    "LeftUpperLeg","LeftLowerLeg","LeftFoot","LeftLowerLeg","LeftUpperLeg","LowerTorso",
    "RightUpperLeg","RightLowerLeg","RightFoot","RightLowerLeg","RightUpperLeg","LowerTorso",
    "UpperTorso","Head",
}

local R6_SEQUENCE = {
    "Torso",
    "Left Arm","Torso","Right Arm","Torso",
    "Left Leg","Torso","Right Leg","Torso",
    "Head",
}

local function detectRig(model)
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then
        return hum.RigType == Enum.HumanoidRigType.R15 and "R15" or "R6"
    end
    if model:FindFirstChild("UpperTorso") then return "R15" end
    if model:FindFirstChild("Torso") then return "R6" end
    return "Custom"
end

local function buildCustomSequence(model)
    local joints = {}
    for _, m in ipairs(model:GetDescendants()) do
        if m:IsA("Motor6D") and m.Part0 and m.Part1 then
            joints[#joints+1] = { m.Part0.Name, m.Part1.Name }
        end
    end
    local seen = {}
    local seq  = {}
    for _, pair in ipairs(joints) do
        for _, name in ipairs(pair) do
            if not seen[name] then
                seen[name] = true
                seq[#seq+1] = name
            end
        end
    end
    return seq
end

local function getSkeletonSequence(model)
    local rig = detectRig(model)
    if rig == "R15" then return R15_SEQUENCE
    elseif rig == "R6" then return R6_SEQUENCE
    else return buildCustomSequence(model) end
end

local function newDrawing(class, props)
    local d = Drawing.new(class)
    for k,v in pairs(props) do pcall(function() d[k]=v end) end
    return d
end

local function defaultTeamConfig()
    return {
        enabled           = true,
        maxDistance       = 5000,
        wallCheck         = false,

        -- Box 2D
        box               = true,
        boxColor          = { Color3.new(1,1,1), 1 },
        boxOutline        = true,
        boxOutlineColor   = { Color3.new(0,0,0), 1 },
        boxFill           = false,
        boxFillColor      = { Color3.new(1,1,1), 0.5 },

        -- Box 3D
        box3d             = false,
        box3dColor        = { Color3.new(1,1,1), 1 },

        -- Health
        healthBar         = true,
        healthyColor      = Color3.new(0,1,0),
        dyingColor        = Color3.new(1,0,0),
        healthBarOutline  = true,
        healthBarOutlineColor = { Color3.new(0,0,0), 0.5 },
        healthText        = false,
        healthTextColor   = { Color3.new(1,1,1), 1 },
        healthTextOutline = true,
        healthTextOutlineColor = Color3.new(0,0,0),

        -- Labels
        name              = true,
        nameColor         = { Color3.new(1,1,1), 1 },
        nameOutline       = true,
        nameOutlineColor  = Color3.new(0,0,0),

        distance          = true,
        distanceColor     = { Color3.new(1,1,1), 1 },
        distanceOutline   = true,
        distanceOutlineColor = Color3.new(0,0,0),

        weapon            = false,
        weaponColor       = { Color3.new(1,1,1), 1 },
        weaponOutline     = true,
        weaponOutlineColor= Color3.new(0,0,0),

        -- Tracer
        tracer            = false,
        tracerOrigin      = "Bottom", 
        tracerColor       = { Color3.new(1,1,1), 1 },
        tracerOutline     = true,
        tracerOutlineColor= { Color3.new(0,0,0), 1 },

        -- Off-screen arrow
        offScreenArrow         = false,
        offScreenArrowColor    = { Color3.new(1,1,1), 1 },
        offScreenArrowSize     = 15,
        offScreenArrowRadius   = 150,
        offScreenArrowOutline  = true,
        offScreenArrowOutlineColor = { Color3.new(0,0,0), 1 },

        -- Chams
        chams             = false,
        chamsVisibleOnly  = false,
        chamsFillColor    = { Color3.new(1,1,1), 0.5 },
        chamsOutlineColor = { Color3.new(1,1,1), 0 },

        -- Skeleton
        skeleton          = false,
        skeletonColor     = { Color3.new(1,1,1), 1 },
        skeletonThickness = 1,
    }
end

local Entity

local ENTITY_URL = "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/Libraries/Entity.luau"

local Lib = {
    _loaded      = false,
    _cache       = {},  
    _objects     = {},   
    _connections = {},

    whitelist    = {},   

    sharedSettings = {
        slowInterval  = 0.1,
        aliveCheck    = true,
        debug         = false,
        teamCheck     = "Team",
        whitelistMode = "highlight",
        textSize      = 13,
        textFont      = 2,
        useTeamColor  = false,
        rainbow       = false,
        rainbowSpeed  = 400,
    },

    teamSettings = {
        default = defaultTeamConfig(),
        enemy   = (function()
            local t = defaultTeamConfig()
            t.boxColor = { Color3.fromRGB(255,60,60), 1 }
            return t
        end)(),
        whitelist = (function()
            local t = defaultTeamConfig()
            t.boxColor     = { Color3.fromRGB(255, 215, 0), 1 }
            t.nameColor    = { Color3.fromRGB(255, 215, 0), 1 }
            t.chams        = true
            t.chamsFillColor = { Color3.fromRGB(255, 215, 0), 0.6 }
            t.chamsOutlineColor = { Color3.fromRGB(255, 215, 0), 0 }
            t.tracer       = true
            t.tracerColor  = { Color3.fromRGB(255, 215, 0), 1 }
            return t
        end)(),
        friendly = (function()
            local t = defaultTeamConfig()
            t.enabled = false
            return t
        end)(),
    },

    _rainbow = {
        hue   = 0,
        color = Color3.new(1,0,0),
        step  = 0,
    },
}

function Lib.getCharacter(entity)
    if Entity then
        local record = Entity:Get(entity)
        if record then return record.Character end
    end
    if typeof(entity) == "Instance" and entity:IsA("Player") then
        return entity.Character
    end
    return entity
end

function Lib.getTeamKey(entity)
    if Lib.sharedSettings.whitelistMode == "highlight" and Lib.isWhitelisted(entity) then
        return "whitelist"
    end
    if Entity then
        local record = Entity:Get(entity)
        if record then return record.Targetable and "enemy" or "friendly" end
    end
    return "enemy"
end

function Lib.getHealth(entity)
    local char = Lib.getCharacter(entity)
    if not char then return nil, nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then return hum.Health, hum.MaxHealth end
    return nil, nil
end

function Lib.getWeapon(entity)
    local char = Lib.getCharacter(entity)
    if not char then return nil end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then return child.Name end
    end
    return nil
end

function Lib.isWhitelisted(entity)
    local list = Lib.whitelist
    if #list == 0 then return false end
    if typeof(entity) ~= "Instance" or not entity:IsA("Player") then
        return false
    end
    local uid = entity.UserId
    for i = 1, #list do
        if list[i] == uid then return true end
    end
    return false
end

function Lib.getTeamColor(entity)
    if typeof(entity) == "Instance" and entity:IsA("Player") then
        local t = entity.Team
        return t and t.TeamColor and t.TeamColor.Color or nil
    end
    return nil
end

function Lib.getNPCTeamKey(instance)
    return "default"
end

local function resolveColor(lib, entity, colorPair, isOutline)
    local s = lib.sharedSettings

    local alpha = 1
    if typeof(colorPair) == "table" then
        alpha = colorPair[2]
        if typeof(alpha) ~= "number" then alpha = 1 end
    end

    if s.rainbow then
        return lib._rainbow.color, alpha
    end

    if s.useTeamColor and not isOutline then
        local tc = lib.getTeamColor(entity)
        if tc then return tc, alpha end
    end

    if typeof(colorPair) == "table" then
        local color = colorPair[1]
        if typeof(color) ~= "Color3" then color = Color3.new(1, 1, 1) end
        return color, alpha
    end

    if typeof(colorPair) == "Color3" then
        return colorPair, alpha
    end

    return Color3.new(1, 1, 1), alpha
end

local function getConfig(lib, entity, record, forcedKey)
    local key

    if forcedKey then
        key = forcedKey
    elseif lib.sharedSettings.whitelistMode == "highlight" and lib.isWhitelisted(entity) then
        key = "whitelist"
    elseif record then
        key = record.Targetable and "enemy" or "friendly"
    else
        key = lib.getTeamKey(entity)
    end

    return lib.teamSettings[key]
        or lib.teamSettings["default"]
        or defaultTeamConfig()
end

local function getNPCConfig(lib, instance)
    local key = lib.getNPCTeamKey(instance)
    return lib.teamSettings[key]
        or lib.teamSettings["default"]
        or defaultTeamConfig()
end

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.IgnoreWater = true

local ONE            = Vector2.new(1,  1)
local TWO            = Vector2.new(2,  2)
local HBAR_OFFSET    = Vector2.new(8,  0)
local HBAR_OL_OFFSET = Vector2.new(0,  1)
local NAME_OFFSET    = Vector2.new(0,  2)
local DIST_OFFSET    = Vector2.new(0,  2)

local EspObject = {}
EspObject.__index = EspObject

function EspObject.new(source, lib, options)
    local self = setmetatable({}, EspObject)
    self.lib = lib
    self.bin = {}
    self.D   = {}
    self._skelCache = {}

    if typeof(source) == "Instance" then
        options = options or {}
        self.instance = source
        self.record = {
            Player     = nil,
            Character  = source,
            Head       = source:FindFirstChild("Head")
                or source:FindFirstChild("HumanoidRootPart")
                or source.PrimaryPart,
            RootPart   = source:FindFirstChild("HumanoidRootPart") or source.PrimaryPart,
            Alive      = true,
            Targetable = true,
            Health     = 0,
            MaxHealth  = 0,
        }
        self.entity = source
        self._teamKey = options.Team
        self._displayName = options.Text or source.Name

        self._healthSource = options.Health
        self._maxHealthSource = options.MaxHealth
    else
        self.record = source
        self.entity = source.Player
        self._displayName = source.Player.DisplayName
    end

    lib._objects[self] = true
    return self
end

function EspObject:_draw(class, props)
    local d = newDrawing(class, props)
    table.insert(self.bin, d)
    return d
end

function EspObject:_d(key, class, props)
    local d = self.D[key]
    if d then return d end
    d = self:_draw(class, props)
    self.D[key] = d
    return d
end

function EspObject:_box3d(face)
    local set = self.D["box3d" .. face]
    if set then return set end
    set = {
        self:_draw("Line", { Thickness = 1, Visible = false }),
        self:_draw("Line", { Thickness = 1, Visible = false }),
        self:_draw("Line", { Thickness = 1, Visible = false }),
    }
    self.D["box3d" .. face] = set
    return set
end

function EspObject:_skelLine(index)
    local key = "skel" .. index
    local line = self.D[key]
    if line then return line end
    line = self:_draw("Line", { Thickness = 1, Visible = false })
    self.D[key] = line
    self._skelCount = math.max(self._skelCount or 0, index)
    return line
end

function EspObject:IsAlive()
    local model = self.instance or self.record.Character
    if not model or model.Parent == nil then return false end

    if self.instance and self._healthSource then
        if not self.lib.sharedSettings.aliveCheck then return true end
        return (self.record.Health or 1) > 0
    end

    if self.lib.sharedSettings.aliveCheck then
        local humanoid = self._humanoid
        if not humanoid or humanoid.Parent == nil then
            humanoid = model:FindFirstChildOfClass("Humanoid")
            self._humanoid = humanoid
        end
        if humanoid and humanoid.Health <= 0 then return false end
    end

    return true
end

function EspObject:Destruct()
    if self.lib and self.lib._objects then self.lib._objects[self] = nil end
    for _, d in ipairs(self.bin) do d:Remove() end
    clear(self)
end

function EspObject:Rebind(record)
    self.record = record
    self._parts = nil
    self._corners = nil
    self._skelSeq = nil
    self._skelCache = {}
    self._childCount = nil
end

function EspObject:Update(slow)
    local lib    = self.lib
    local record = self.record
    local entity = self.entity

    if slow or self._cfg == nil then
        self._cfg = getConfig(lib, entity, record, self._teamKey)
        self._enabled = self._cfg.enabled
        self._weapon = self._cfg.weapon and lib.getWeapon(entity) or nil
    end

    local cfg = self._cfg
    if not cfg or not self._enabled then
        self._onScreen = false
        return
    end

    if self.instance then
        local model = self.instance
        record.Alive = model.Parent ~= nil
        record.Character = model
        record.Head = model:FindFirstChild("Head")
            or model:FindFirstChild("HumanoidRootPart")
            or model.PrimaryPart
        record.RootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart

        local source = self._healthSource

        if type(source) == "function" then
            local ok, health, maxHealth = pcall(source, model)
            if ok and type(health) == "number" then
                record.Health = health
                record.MaxHealth = type(maxHealth) == "number" and maxHealth or record.MaxHealth
            end

        elseif type(source) == "string" then
            local value = model:FindFirstChild(source)
            if value and value.Value ~= nil then
                record.Health = tonumber(value.Value) or 0

                local maxSource = self._maxHealthSource
                if type(maxSource) == "string" then
                    local maxValue = model:FindFirstChild(maxSource)
                    if maxValue then record.MaxHealth = tonumber(maxValue.Value) or 0 end
                elseif type(maxSource) == "number" then
                    record.MaxHealth = maxSource
                end

                if not record.MaxHealth or record.MaxHealth <= 0
                    or record.Health > record.MaxHealth then
                    record.MaxHealth = math.max(record.Health, record.MaxHealth or 0)
                end
            end

        else
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            if humanoid then
                record.Health = humanoid.Health
                record.MaxHealth = humanoid.MaxHealth
            end
        end
    end

    local character = record.Character
    local head = record.Head

    if not character or character.Parent == nil or not head then
        self._onScreen = false
        self._corners = nil
        return
    end

    local headPos = head.Position
    if typeof(headPos) ~= "Vector3" then
        self._onScreen = false
        self._corners = nil
        return
    end

    if cfg.skeleton and not self._skelSeq then
        self._skelSeq = getSkeletonSequence(character)
    end

    local screenPos, onScreen, depth = worldToScreen(headPos)

    if depth > cfg.maxDistance then
        self._onScreen = false
        return
    end

    self._onScreen = onScreen
    self._depth = depth
    self._screenPos = screenPos

    if cfg.wallCheck and onScreen then
        local origin = Camera.CFrame.Position
        local ignore = { character }
        local myChar = Entity and Entity.Self.Character or LocalPlayer.Character
        if myChar then table.insert(ignore, myChar) end
        wallParams.FilterDescendantsInstances = ignore

        self._visible = workspace:Raycast(origin, headPos - origin, wallParams) == nil
    else
        self._visible = true
    end

    if onScreen then
        local cf, size
        if character:IsA("Model") then
            local ok, boxCf, boxSize = pcall(character.GetBoundingBox, character)
            if ok then cf, size = boxCf, boxSize end
        end

        if not cf then
            if self._parts == nil or slow then
                local children = character:GetChildren()
                if self._parts == nil or #children ~= self._childCount then
                    self._childCount = #children
                    self._parts = getBBoxParts(character)
                end
            end
            if self._parts and #self._parts > 0 then
                cf, size = computeBBox(self._parts)
            end
        end

        self._corners = cf and calcCorners(cf, size) or nil

        self._health = record.Health
        self._maxHealth = record.MaxHealth

    elseif cfg.offScreenArrow then
        local cf = Camera.CFrame
        local flat = CFrame.fromMatrix(cf.Position, cf.RightVector, Vector3.yAxis)
        local obj = flat:PointToObjectSpace(headPos)
        local flatDir = Vector2.new(obj.X, obj.Z)
        self._direction = flatDir.Magnitude > 0 and flatDir.Unit or nil
    end
end

function EspObject:Render()
    local lib      = self.lib
    local D        = self.D
    local cfg      = self._cfg
    local enabled  = self._enabled and self.record.Character ~= nil
        and (self._visible ~= false)
    local onScreen = self._onScreen or false
    local corners  = self._corners
    local entity   = self.entity
    local vp       = Camera.ViewportSize

    if cfg and cfg.BeforeUpdate then cfg.BeforeUpdate(self) end

    if not cfg or not enabled then
        if self._anyVisible then
            for _, d in ipairs(self.bin) do d.Visible = false end
            self._anyVisible = false
        end
        return
    end
    self._anyVisible = true

    local hasBox = onScreen and corners ~= nil

    if cfg.box and hasBox then
        local tl = corners.topLeft
        local br = corners.bottomRight
        local sz = br - tl
        local c, t = resolveColor(lib, entity, cfg.boxColor)

        local box = self:_d("box", "Square", { Thickness = 1 })
        box.Visible = true
        box.Position = tl
        box.Size = sz
        box.Color = c
        box.Transparency = t

        if cfg.boxOutline then
            local oc, ot = resolveColor(lib, entity, cfg.boxOutlineColor, true)
            local outer = self:_d("boxOuter", "Square", { Thickness = 1 })
            outer.Visible = true
            outer.Position = tl - ONE
            outer.Size = sz + TWO
            outer.Color = oc
            outer.Transparency = ot

            local inner = self:_d("boxInner", "Square", { Thickness = 1 })
            inner.Visible = true
            inner.Position = tl + ONE
            inner.Size = sz - TWO
            inner.Color = oc
            inner.Transparency = ot
        else
            if D.boxOuter then D.boxOuter.Visible = false end
            if D.boxInner then D.boxInner.Visible = false end
        end
    else
        if D.box then D.box.Visible = false end
        if D.boxOuter then D.boxOuter.Visible = false end
        if D.boxInner then D.boxInner.Visible = false end
    end

    if cfg.boxFill and hasBox then
        local c, t = resolveColor(lib, entity, cfg.boxFillColor)
        local fill = self:_d("boxFill", "Square", { Filled = true })
        fill.Visible = true
        fill.Position = corners.topLeft
        fill.Size = corners.bottomRight - corners.topLeft
        fill.Color = c
        fill.Transparency = t
    elseif D.boxFill then
        D.boxFill.Visible = false
    end

    if cfg.box3d and hasBox then
        local c, t = resolveColor(lib, entity, cfg.box3dColor)
        local pts = corners.corners
        for i = 1, 4 do
            local ni = (i % 4) + 1
            local f = self:_box3d(i)
            f[1].From, f[1].To = pts[i], pts[ni]
            f[2].From, f[2].To = pts[ni], pts[ni + 4]
            f[3].From, f[3].To = pts[ni + 4], pts[i + 4]
            for j = 1, 3 do
                f[j].Visible = true
                f[j].Color = c
                f[j].Transparency = t
            end
        end
    else
        for i = 1, 4 do
            local f = D["box3d" .. i]
            if f then
                for j = 1, 3 do f[j].Visible = false end
            end
        end
    end

    local hvis = cfg.healthBar and hasBox and self._health and self._maxHealth and self._maxHealth > 0
    if hvis then
        local ratio = clamp(self._health / self._maxHealth, 0, 1)
        local tl = corners.topLeft
        local bl = corners.bottomLeft
        local barFrom = tl - HBAR_OFFSET
        local barTo = bl - HBAR_OFFSET
        local curPos = Vector2.new(barFrom.X, barFrom.Y + (barTo.Y - barFrom.Y) * (1 - ratio))

        local bar = self:_d("hbar", "Line", { Thickness = 1 })
        bar.Visible = true
        bar.From = curPos
        bar.To = barTo
        bar.Color = lerpColor(cfg.dyingColor, cfg.healthyColor, ratio)

        if cfg.healthBarOutline then
            local oc, ot = resolveColor(lib, entity, cfg.healthBarOutlineColor, true)
            local ol = self:_d("hbarOL", "Line", { Thickness = 3 })
            ol.Visible = true
            ol.From = barFrom - HBAR_OL_OFFSET
            ol.To = barTo + HBAR_OL_OFFSET
            ol.Color = oc
            ol.Transparency = ot
        elseif D.hbarOL then
            D.hbarOL.Visible = false
        end

        if cfg.healthText then
            local text = self:_d("htext", "Text", { Center = true })
            local hc, ht = resolveColor(lib, entity, cfg.healthTextColor)
            text.Visible = true
            text.Text = round(self._health) .. "hp"
            text.Size = lib.sharedSettings.textSize
            text.Font = lib.sharedSettings.textFont
            text.Color = hc
            text.Transparency = ht
            text.Outline = cfg.healthTextOutline
            text.OutlineColor = cfg.healthTextOutlineColor
            text.Position = curPos - Vector2.new(
                text.TextBounds.X * 0.5 + HBAR_OFFSET.X + 6,
                text.TextBounds.Y * 0.5)
        elseif D.htext then
            D.htext.Visible = false
        end
    else
        if D.hbar then D.hbar.Visible = false end
        if D.hbarOL then D.hbarOL.Visible = false end
        if D.htext then D.htext.Visible = false end
    end

    if cfg.name and hasBox then
        local name = self:_d("name", "Text", { Center = false })
        local nc, nt = resolveColor(lib, entity, cfg.nameColor)
        name.Visible = true
        name.Text = self._displayName or ""
        name.Size = lib.sharedSettings.textSize
        name.Font = lib.sharedSettings.textFont
        name.Color = nc
        name.Transparency = nt
        name.Outline = cfg.nameOutline
        name.OutlineColor = cfg.nameOutlineColor
        local topCenter = (corners.topLeft + corners.topRight) * 0.5
        name.Position = Vector2.new(
            topCenter.X - name.TextBounds.X * 0.5,
            corners.topLeft.Y - name.TextBounds.Y - NAME_OFFSET.Y)
    elseif D.name then
        D.name.Visible = false
    end

    local distanceShown = false
    if cfg.distance and hasBox and self._depth then
        local dist = self:_d("distance", "Text", { Center = true })
        local dc, dt = resolveColor(lib, entity, cfg.distanceColor)
        dist.Visible = true
        distanceShown = true
        dist.Text = round(self._depth) .. " studs"
        dist.Size = lib.sharedSettings.textSize
        dist.Font = lib.sharedSettings.textFont
        dist.Color = dc
        dist.Transparency = dt
        dist.Outline = cfg.distanceOutline
        dist.OutlineColor = cfg.distanceOutlineColor
        dist.Position = (corners.bottomLeft + corners.bottomRight) * 0.5 + DIST_OFFSET
    elseif D.distance then
        D.distance.Visible = false
    end

    if cfg.weapon and hasBox and self._weapon then
        local weapon = self:_d("weapon", "Text", { Center = true })
        local wc, wt = resolveColor(lib, entity, cfg.weaponColor)
        weapon.Visible = true
        weapon.Text = self._weapon
        weapon.Size = lib.sharedSettings.textSize
        weapon.Font = lib.sharedSettings.textFont
        weapon.Color = wc
        weapon.Transparency = wt
        weapon.Outline = cfg.weaponOutline
        weapon.OutlineColor = cfg.weaponOutlineColor
        local base = (corners.bottomLeft + corners.bottomRight) * 0.5
        weapon.Position = base + (distanceShown
            and DIST_OFFSET + Vector2.new(0, D.distance.TextBounds.Y)
            or Vector2.zero)
    elseif D.weapon then
        D.weapon.Visible = false
    end

    if cfg.tracer and hasBox then
        local tc, tt = resolveColor(lib, entity, cfg.tracerColor)
        local origin
        local o = cfg.tracerOrigin
        if o == "Middle" then
            origin = vp * 0.5
        elseif o == "Top" then
            origin = vp * Vector2.new(0.5, 0)
        elseif o == "Mouse" then
            local m = UIS:GetMouseLocation()
            origin = Vector2.new(m.X, m.Y)
        else
            origin = vp * Vector2.new(0.5, 1)
        end
        local target = (corners.bottomLeft + corners.bottomRight) * 0.5

        local tracer = self:_d("tracer", "Line", { Thickness = 1 })
        tracer.Visible = true
        tracer.From = origin
        tracer.To = target
        tracer.Color = tc
        tracer.Transparency = tt

        if cfg.tracerOutline then
            local oc, ot = resolveColor(lib, entity, cfg.tracerOutlineColor, true)
            local ol = self:_d("tracerOL", "Line", { Thickness = 3 })
            ol.Visible = true
            ol.From = origin
            ol.To = target
            ol.Color = oc
            ol.Transparency = ot
        elseif D.tracerOL then
            D.tracerOL.Visible = false
        end
    else
        if D.tracer then D.tracer.Visible = false end
        if D.tracerOL then D.tracerOL.Visible = false end
    end

    if cfg.offScreenArrow and not onScreen and self._direction then
        local dir = self._direction
        local ctr = vp * 0.5
        local raw = ctr + dir * cfg.offScreenArrowRadius
        local pos = Vector2.new(
            clamp(raw.X, 25, vp.X - 25),
            clamp(raw.Y, 25, vp.Y - 25))
        local size = cfg.offScreenArrowSize
        local a = pos
        local b = pos - rotateVec(dir, 0.45) * size
        local c = pos - rotateVec(dir, -0.45) * size

        local ac, at = resolveColor(lib, entity, cfg.offScreenArrowColor)
        local arrow = self:_d("arrow", "Triangle", { Filled = true })
        arrow.Visible = true
        arrow.PointA, arrow.PointB, arrow.PointC = a, b, c
        arrow.Color = ac
        arrow.Transparency = at

        if cfg.offScreenArrowOutline then
            local oc, ot = resolveColor(lib, entity, cfg.offScreenArrowOutlineColor, true)
            local ol = self:_d("arrowOL", "Triangle", { Thickness = 3 })
            ol.Visible = true
            ol.PointA, ol.PointB, ol.PointC = a, b, c
            ol.Color = oc
            ol.Transparency = ot
        elseif D.arrowOL then
            D.arrowOL.Visible = false
        end
    else
        if D.arrow then D.arrow.Visible = false end
        if D.arrowOL then D.arrowOL.Visible = false end
    end

    local lineIdx = 0
    if cfg.skeleton and onScreen and self._skelSeq and self.record.Character then
        local seq = self._skelSeq
        local cache = self._skelCache
        local sc, st = resolveColor(lib, entity, cfg.skeletonColor)
        local prevPos = nil

        for i = 1, #seq do
            local name = seq[i]
            local part = cache[name]
            if part == nil or part.Parent == nil then
                part = self.record.Character:FindFirstChild(name)
                cache[name] = part or false
            end
            if part and part ~= false then
                local spos, vis = worldToScreen(part.Position)
                if vis then
                    if prevPos then
                        lineIdx = lineIdx + 1
                        local l = self:_skelLine(lineIdx)
                        l.Visible = true
                        l.From = prevPos
                        l.To = spos
                        l.Color = sc
                        l.Transparency = st
                        l.Thickness = cfg.skeletonThickness
                    end
                    prevPos = spos
                else
                    prevPos = nil
                end
            else
                prevPos = nil
            end
        end
    end

    for i = lineIdx + 1, (self._skelCount or 0) do
        local l = D["skel" .. i]
        if l then l.Visible = false end
    end

    if cfg.AfterUpdate then cfg.AfterUpdate(self) end
end

local ChamObject = {}
ChamObject.__index = ChamObject

function ChamObject.new(source, lib, options)
    local self = setmetatable({}, ChamObject)
    self.lib = lib

    if typeof(source) == "Instance" then
        options = options or {}
        self.instance = source
        self.entity = source
        self._teamKey = options.Team
        self.record = { Character = source, Alive = true }
    else
        self.record = source
        self.entity = source.Player
    end

    self.highlight = Instance.new("Highlight", HighlightContainer)
    lib._objects[self] = true
    return self
end

function ChamObject:IsAlive()
    local model = self.instance or self.record.Character
    if not model or model.Parent == nil then return false end

    if self.lib.sharedSettings.aliveCheck then
        local humanoid = self._humanoid
        if not humanoid or humanoid.Parent == nil then
            humanoid = model:FindFirstChildOfClass("Humanoid")
            self._humanoid = humanoid
        end
        if humanoid and humanoid.Health <= 0 then return false end
    end

    return true
end

function ChamObject:Destruct()
    if self.lib and self.lib._objects then self.lib._objects[self] = nil end
    self.highlight:Destroy()
    clear(self)
end

function ChamObject:Rebind(record)
    self.record = record
end

function ChamObject:Update(slow)
    if not slow and self._primed then return end
    self._primed = true

    local lib  = self.lib
    local hl   = self.highlight
    local record = self.record

    if self.instance then
        record.Character = self.instance
        record.Alive = self.instance.Parent ~= nil
    end

    local cfg  = getConfig(lib, self.entity, record, self._teamKey)
    local char = record.Character

    local enabled = cfg.enabled and cfg.chams and char ~= nil
    if hl.Enabled ~= enabled then hl.Enabled = enabled end
    if not enabled then return end

    if hl.Adornee ~= char then hl.Adornee = char end

    local fc, ft = resolveColor(lib, self.entity, cfg.chamsFillColor)
    local oc, ot = resolveColor(lib, self.entity, cfg.chamsOutlineColor, true)

    if hl.FillColor ~= fc then hl.FillColor = fc end
    if hl.FillTransparency ~= (ft or 0.5) then hl.FillTransparency = ft or 0.5 end
    if hl.OutlineColor ~= oc then hl.OutlineColor = oc end
    if hl.OutlineTransparency ~= (ot or 0) then hl.OutlineTransparency = ot or 0 end

    local depth = cfg.chamsVisibleOnly
        and Enum.HighlightDepthMode.Occluded
        or Enum.HighlightDepthMode.AlwaysOnTop
    if hl.DepthMode ~= depth then hl.DepthMode = depth end
end

local InstanceObject = {}
InstanceObject.__index = InstanceObject

function InstanceObject.new(instance, lib, options)
    local self     = setmetatable({}, InstanceObject)
    self.instance  = instance
    self.lib       = lib
    self.options   = options or {}
    self.bin       = {}
    lib._objects[self] = true

    if instance:IsA("Model") then
        self._esp = EspObject.new(instance, lib, self.options)
        self._cham = ChamObject.new(instance, lib, self.options)
    else
        self._label = newDrawing("Text", { Center=true, Visible=false })
        self.bin[1] = self._label
    end

    return self
end

function InstanceObject:Destruct()
    if self.lib and self.lib._objects then self.lib._objects[self] = nil end
    if self._esp then self._esp:Destruct() end
    if self._cham then self._cham:Destruct() end
    for _, d in ipairs(self.bin) do d:Remove() end
    clear(self)
end

function InstanceObject:Render()
    local inst = self.instance
    if not inst or not inst.Parent then
        return self:Destruct()
    end

    if self._esp then return end

    local opts  = self.options
    local label = self._label
    if not opts.enabled then label.Visible=false return end

    local pivot = inst:IsA("BasePart") and inst.Position or inst:GetPivot().Position
    local pos, vis, depth = worldToScreen(pivot)

    local maxDist = opts.maxDistance or 5000
    label.Visible = vis and depth <= maxDist

    if label.Visible then
        local text = opts.getText and opts.getText(inst)
            or (opts.text or inst.Name)
                :gsub("{name}", inst.Name)
                :gsub("{distance}", tostring(round(depth)))
        label.Text         = text
        label.Position     = pos
        label.Size         = opts.textSize or self.lib.sharedSettings.textSize
        label.Font         = opts.textFont or self.lib.sharedSettings.textFont
        label.Color        = opts.textColor and opts.textColor[1] or Color3.new(1,1,1)
        label.Transparency = opts.textColor and opts.textColor[2] or 1
        label.Outline      = opts.textOutline ~= false
        label.OutlineColor = opts.textOutlineColor or Color3.new()
    end
end

function Lib:AddTeam(key, overrides)
    local base = defaultTeamConfig()
    if overrides then
        for k, v in pairs(overrides) do base[k] = v end
    end
    self.teamSettings[key] = base
    return base
end

function Lib:AddInstance(instance, options)
    assert(typeof(instance) == "Instance", "AddInstance: argument 1 must be an Instance")
    if self._cache[instance] then return self._cache[instance][1] end

    options = options or {}

    self._manual = self._manual or {}
    self._manual[instance] = options

    if not self._loaded then
        return
    end

    local object = InstanceObject.new(instance, self, options)
    self._cache[instance] = { object }
    return object
end

function Lib:RemoveInstance(instance)
    if self._manual then self._manual[instance] = nil end
    local objs = self._cache[instance]
    if not objs then return end
    for _, o in ipairs(objs) do o:Destruct() end
    self._cache[instance] = nil
end

function Lib:_release(object)
    local entity = object.entity or object.instance
    if object.bin then
        for _, d in ipairs(object.bin) do
            pcall(function() d.Visible = false end)
        end
    end
    if object.highlight then
        pcall(function() object.highlight.Enabled = false end)
    end

    local objs = entity and self._cache[entity]

    if objs then
        for _, o in ipairs(objs) do
            if o.Destruct then pcall(function() o:Destruct() end) end
        end
        self._cache[entity] = nil
    elseif object.Destruct then
        pcall(function() object:Destruct() end)
    end
end

function Lib:Load(handler)
    assert(not self._loaded, "Facility Esp: already loaded")

    Entity = handler or Entity
    if not Entity then
        Entity = loadstring(game:HttpGet(ENTITY_URL))()
    end
    if not Entity.Started then Entity:Start() end

    self.Entity = Entity
    Entity.Settings.TeamCheck = self.sharedSettings.teamCheck

    local function attach(record)
        if self._cache[record.Player] then
            for _, object in ipairs(self._cache[record.Player]) do
                object:Rebind(record)
            end
            return
        end

        self._cache[record.Player] = {
            EspObject.new(record, self),
            ChamObject.new(record, self),
        }
    end

    local function detach(record)
        local objects = self._cache[record.Player]
        if not objects then return end
        for _, object in ipairs(objects) do object:Destruct() end
        self._cache[record.Player] = nil
    end

    for _, record in ipairs(Entity:GetAll()) do
        attach(record)
    end

    for instance, options in pairs(self._manual or {}) do
        if instance.Parent ~= nil and not self._cache[instance] then
            self._cache[instance] = { InstanceObject.new(instance, self, options) }
        end
    end

    self._connections[1] = Entity.Added:Connect(attach)
    self._connections[2] = Entity.Removed:Connect(detach)

    local slowAccum = 0
    local rainbowAccum = 0

    self._connections[3] = RunService.RenderStepped:Connect(function(dt)
        local shared = self.sharedSettings

        if shared.rainbow then
            rainbowAccum = rainbowAccum + dt
            if rainbowAccum >= 1 / 60 then
                rainbowAccum = 0
                local rb = self._rainbow
                rb.hue = (rb.hue + 1 / shared.rainbowSpeed) % 1
                rb.color = Color3.fromHSV(rb.hue, 0.8, 1)
            end
        end

        slowAccum = slowAccum + dt
        local slow = slowAccum >= (shared.slowInterval or 0.1)
        if slow then
            slowAccum = 0
            if Entity.Settings.TeamCheck ~= shared.teamCheck then
                Entity.Settings.TeamCheck = shared.teamCheck
                Entity:RefreshTargets()
            end
        end

        if slow then
            for object in pairs(self._objects) do
                if object.IsAlive and not object:IsAlive() then
                    object._skip = true
                    if object.bin then
                        for _, d in ipairs(object.bin) do d.Visible = false end
                    end
                    if object.highlight then object.highlight.Enabled = false end
                else
                    object._skip = false
                end
            end
        end

        for object in pairs(self._objects) do
            if not object._skip then
                local ok, err = pcall(function()
                    if object.Update then object:Update(slow) end
                    if object.Render then object:Render() end
                end)
                if not ok and shared.debug then
                    warn("Facility Esp: " .. tostring(err))
                end
            end
        end
    end)

    self._connections[4] = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        Camera = workspace.CurrentCamera
    end)

    self._loaded = true
end

function Lib:Unload()
    if not self._loaded then return end

    for _, connection in pairs(self._connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(self._connections)

    for _, objects in pairs(self._cache) do
        for _, object in ipairs(objects) do
            pcall(function() object:Destruct() end)
        end
    end
    table.clear(self._cache)
    table.clear(self._objects)

    for _, child in ipairs(HighlightContainer:GetChildren()) do
        child:Destroy()
    end

    self._loaded = false
end

return Lib
