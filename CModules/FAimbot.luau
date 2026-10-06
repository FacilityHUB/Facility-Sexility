local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Stats = game:GetService("Stats")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local ENTITY_URL = "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/Libraries/Entity.luau"

local Entity

local Aimbot = {
    Enabled = false,
    Active = false,
    Target = nil,

    Settings = {
        Key = Enum.UserInputType.MouseButton2,
        ToggleMode = false,

        Mode = "Camera",
        Smoothness = 0.25,
        Sensitivity = 0.35,
        EasingStyle = "Quad",
        EasingDirection = "Out",

        Elastic = false,
        Stiffness = 18,
        Damping = 0.72,
        MaxOvershoot = 60,

        HitChance = 100,
        SwitchDelay = 0,
        Deadzone = 0,

        TargetLine = false,
        TargetLineColor = Color3.fromRGB(255, 70, 70),
        TargetLineThickness = 1,
        TargetLineOrigin = "Mouse",

        TargetInfo = false,
        TargetInfoSize = 13,
        TargetInfoColor = Color3.fromRGB(255, 255, 255),

        IgnoreDowned = false,
        IgnoreForcefield = false,

        Priority = "Cursor",
        Parts = { "Head" },
        RandomPart = false,
        RandomInterval = 1,

        Multipoint = false,

        MaxDistance = 2000,
        TeamCheck = true,
        WallCheck = false,
        AliveCheck = true,

        Fov = 120,
        FovCheck = true,
        FovVisible = true,
        FovFilled = false,
        FovThickness = 1,
        FovColor = Color3.fromRGB(255, 255, 255),
        FovLockColor = Color3.fromRGB(255, 70, 70),
        FovTransparency = 0.4,

        Prediction = false,
        PredictionTime = 0.12,
        PingPrediction = false,

        Sticky = true,
        StickyFov = 1.6,

        TriggerBot = false,
        TriggerDelay = 0.08,
        TriggerCooldown = 0.25,

        Trigger = {
            Mode = "Target",
            Fov = 0,
            Key = nil,
            RequireAim = false,
            ReactionTime = 0,
            HoldFire = false,

            WallCheck = true,
            Multipoint = false,
            TeamCheck = true,
            AliveCheck = true,
            MaxDistance = 2000,
            HitChance = 100,

            Parts = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart" },
        },
    },

    _connections = {},
    _loaded = false,
}

local function viewportCenter()
    local size = Camera.ViewportSize
    return Vector2.new(size.X * 0.5, size.Y * 0.5)
end

local function cursorPoint()
    local location = UserInputService:GetMouseLocation()
    return Vector2.new(location.X, location.Y)
end

local function aimOrigin()
    return Aimbot.Settings.Mode == "Mouse" and cursorPoint() or viewportCenter()
end

local function pingSeconds()
    local value = 0
    pcall(function()
        value = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
    end)
    return value
end

function Aimbot:_line()
    if self._lineDrawing then return self._lineDrawing end

    local line = Drawing.new("Line")
    line.Thickness = self.Settings.TargetLineThickness
    line.Color = self.Settings.TargetLineColor
    line.Transparency = 1
    line.Visible = false

    self._lineDrawing = line
    return line
end

function Aimbot:_info()
    if self._infoDrawing then return self._infoDrawing end

    local text = Drawing.new("Text")
    text.Size = self.Settings.TargetInfoSize
    text.Color = self.Settings.TargetInfoColor
    text.Center = true
    text.Outline = true
    text.Transparency = 1
    text.Visible = false

    self._infoDrawing = text
    return text
end

function Aimbot:_fov()
    if self._fovCircle then return self._fovCircle end

    local circle = Drawing.new("Circle")
    circle.Thickness = self.Settings.FovThickness
    circle.Color = self.Settings.FovColor
    circle.Filled = self.Settings.FovFilled
    circle.Transparency = self.Settings.FovTransparency
    circle.Radius = self.Settings.Fov
    circle.Position = viewportCenter()
    circle.Visible = false

    self._fovCircle = circle
    return circle
end

function Aimbot:_partOf(record)
    local character = record.Character
    if not character then return nil end

    local name = self._currentPart or self.Settings.Parts[1] or "Head"

    local part = character:FindFirstChild(name)
    if part and part:IsA("BasePart") then return part end

    part = character:FindFirstChild(name, true)
    if part and part:IsA("BasePart") then return part end

    return record.Head or record.RootPart
end

local MULTIPOINT_SCALE = 0.75

local MULTIPOINT_OFFSETS = {
    Vector3.new(0, 0, 0),
    Vector3.new(1, 0, 0),
    Vector3.new(-1, 0, 0),
    Vector3.new(0, 1, 0),
    Vector3.new(0, -1, 0),
}

function Aimbot:_points(part, multipoint)
    if multipoint == nil then multipoint = self.Settings.Multipoint end

    if not multipoint then
        return { part.Position }
    end

    local half = part.Size * 0.5 * MULTIPOINT_SCALE
    local cframe = part.CFrame
    local points = {}

    for _, offset in ipairs(MULTIPOINT_OFFSETS) do
        table.insert(points, cframe:PointToWorldSpace(offset * half))
    end

    return points
end

function Aimbot:_visiblePoint(record, part, wallCheck, multipoint)
    if wallCheck == nil then wallCheck = self.Settings.WallCheck end
    if multipoint == nil then multipoint = self.Settings.Multipoint end

    local points = self:_points(part, multipoint)

    if not wallCheck then
        if not multipoint then return points[1] end
        return points[math.random(1, #points)]
    end

    local origin = Camera.CFrame.Position

    local params = self._rayParams
    if not params then
        params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        self._rayParams = params
    end

    local ignore = { record.Character }
    if LocalPlayer.Character then table.insert(ignore, LocalPlayer.Character) end
    params.FilterDescendantsInstances = ignore

    local function clear(point)
        return workspace:Raycast(origin, point - origin, params) == nil
    end

    if not multipoint then
        return clear(points[1]) and points[1] or nil
    end

    local visible = {}
    for _, point in ipairs(points) do
        if clear(point) then table.insert(visible, point) end
    end

    if #visible == 0 then return nil end
    return visible[math.random(1, #visible)]
end

function Aimbot:_visible(record, part)
    if not self.Settings.WallCheck then return true end

    local origin = Camera.CFrame.Position
    local target = part.Position

    local params = self._rayParams
    if not params then
        params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        self._rayParams = params
    end

    local ignore = { record.Character }
    if LocalPlayer.Character then table.insert(ignore, LocalPlayer.Character) end
    params.FilterDescendantsInstances = ignore

    local hit = workspace:Raycast(origin, target - origin, params)
    return hit == nil
end

function Aimbot:_predict(part, point)
    point = point or part.Position

    if not self.Settings.Prediction then return point end

    local velocity = part.AssemblyLinearVelocity
    if velocity.Magnitude < 0.1 then return point end

    local amount = self.Settings.PredictionTime
    if self.Settings.PingPrediction then
        amount = amount + pingSeconds()
    end

    return point + velocity * amount
end

function Aimbot:_score(record, part, origin, radius)
    local screen, onScreen = Camera:WorldToViewportPoint(part.Position)
    if not onScreen then return nil end

    local flat = Vector2.new(screen.X, screen.Y)
    local fromAim = (flat - origin).Magnitude

    if self.Settings.FovCheck and fromAim > radius then return nil end

    local distance = (Camera.CFrame.Position - part.Position).Magnitude
    if distance > self.Settings.MaxDistance then return nil end

    local point = self:_visiblePoint(record, part)
    if not point then return nil end

    local deadzone = self.Settings.Deadzone or 0
    if deadzone > 0 and fromAim < deadzone then return nil end

    if self.Settings.IgnoreDowned then
        local humanoid = record.Humanoid
        if humanoid and humanoid.PlatformStand then return nil end
    end

    if self.Settings.IgnoreForcefield then
        local character = record.Character
        if character and character:FindFirstChildOfClass("ForceField") then return nil end
    end

    local priority = self.Settings.Priority
    local score

    if priority == "Closest" then
        score = distance
    elseif priority == "LowestHealth" then
        score = record.Health or math.huge
    else
        score = fromAim
    end

    return score, point
end

function Aimbot:_select()
    if not Entity then return nil, nil end

    local origin = aimOrigin()
    local radius = self.Settings.Fov

    local best, bestPart, bestPoint, bestScore = nil, nil, nil, math.huge

    if self.Settings.Sticky and self.Target then
        local record = Entity:Get(self.Target)
        if record and record.Alive then
            local part = self:_partOf(record)
            if part then
                local score, point = self:_score(record, part, origin,
                    radius * self.Settings.StickyFov)
                if score then return record, part, point end
            end
        end
        self.Target = nil
    end

    for _, record in ipairs(Entity:GetAll(self.Settings.TeamCheck)) do
        if not self.Settings.AliveCheck or (record.Health or 1) > 0 then
            local part = self:_partOf(record)
            if part then
                local score, point = self:_score(record, part, origin, radius)
                if score and score < bestScore then
                    best, bestPart, bestPoint, bestScore = record, part, point, score
                end
            end
        end
    end

    return best, bestPart, bestPoint
end

function Aimbot:_eased(alpha)
    local styleName = self.Settings.EasingStyle
    if not styleName or styleName == "Linear" then return alpha end

    local style = Enum.EasingStyle[styleName]
    local direction = Enum.EasingDirection[self.Settings.EasingDirection or "Out"]
    if not style then return alpha end

    local ok, value = pcall(function()
        return TweenService:GetValue(alpha, style, direction)
    end)

    return ok and value or alpha
end

function Aimbot:RollHitChance()
    local chance = self.Settings.HitChance or 100
    if chance >= 100 then return true end
    if chance <= 0 then return false end
    return math.random(1, 100) <= chance
end

function Aimbot:_spring(position, dt)
    local settings = self.Settings
    local origin = Camera.CFrame.Position

    if not self._springPoint then
        self._springPoint = origin + Camera.CFrame.LookVector * 100
        self._springVelocity = Vector3.zero
    end

    local wanted = position
    local offset = wanted - self._springPoint

    local acceleration = offset * settings.Stiffness
    local velocity = (self._springVelocity + acceleration * dt)
        * math.clamp(settings.Damping, 0.1, 0.999)

    local limit = settings.MaxOvershoot
    if limit > 0 and velocity.Magnitude > limit * 100 then
        velocity = velocity.Unit * limit * 100
    end

    self._springVelocity = velocity
    self._springPoint = self._springPoint + velocity * dt

    return self._springPoint
end

function Aimbot:_resetSpring()
    self._springPoint = nil
    self._springVelocity = nil
end

local function typingInBox()
    local ok, box = pcall(function()
        return UserInputService:GetFocusedTextBox()
    end)
    return ok and box ~= nil
end

function Aimbot:_keyDown()
    if typingInBox() then return false end

    local key = self.Settings.Key
    if typeof(key) ~= "EnumItem" then return false end

    if key.EnumType == Enum.UserInputType then
        local ok, down = pcall(function()
            return UserInputService:IsMouseButtonPressed(key)
        end)
        return ok and down == true
    end

    if key.EnumType == Enum.KeyCode then
        local ok, down = pcall(function()
            return UserInputService:IsKeyDown(key)
        end)
        return ok and down == true
    end

    return false
end

function Aimbot:_aim(position, dt)
    local mode = self.Settings.Mode

    if mode == "Camera" then
        local point = position

        if self.Settings.Elastic then
            point = self:_spring(position, dt or 1 / 60)
        end

        local goal = CFrame.new(Camera.CFrame.Position, point)

        if self.Settings.Elastic then
            Camera.CFrame = goal
        else
            local smooth = math.clamp(self.Settings.Smoothness, 0.01, 1)
            Camera.CFrame = Camera.CFrame:Lerp(goal, self:_eased(smooth))
        end

    elseif mode == "Mouse" then
        if not mousemoverel then return end

        local screen, onScreen = Camera:WorldToViewportPoint(position)
        if not onScreen then return end

        local delta = Vector2.new(screen.X, screen.Y) - cursorPoint()
        local sensitivity = math.clamp(self.Settings.Sensitivity, 0.01, 1)
        mousemoverel(delta.X * sensitivity, delta.Y * sensitivity)
    end
end

function Aimbot:_trigger()
    if self._triggering then return end

    local now = tick()
    if now - (self._lastTrigger or 0) < self.Settings.TriggerCooldown then return end

    self._triggering = true
    self._lastTrigger = now

    task.spawn(function()
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(self.Settings.TriggerDelay)
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end)
        self._triggering = false
    end)
end

function Aimbot:_triggerKeyDown()
    local key = self.Settings.Trigger.Key
    if key == nil then return true end
    if typeof(key) ~= "EnumItem" then return true end

    if key.EnumType == Enum.UserInputType then
        local ok, down = pcall(function()
            return UserInputService:IsMouseButtonPressed(key)
        end)
        return ok and down == true
    end

    local ok, down = pcall(function()
        return UserInputService:IsKeyDown(key)
    end)
    return ok and down == true
end

function Aimbot:_triggerPartOf(record)
    local character = record.Character
    if not character then return nil end

    local names = self.Settings.Trigger.Parts

    if type(names) == "table" then
        for _, name in ipairs(names) do
            local part = character:FindFirstChild(name)
            if part and part:IsA("BasePart") then return part end
        end
    end

    return record.Head or record.RootPart
end

function Aimbot:_triggerValid(record, part, config)
    if not record or not part then return false end
    if config.TeamCheck and not record.Targetable then return false end
    if config.AliveCheck and (record.Health or 1) <= 0 then return false end

    local distance = (Camera.CFrame.Position - part.Position).Magnitude
    if distance > config.MaxDistance then return false end

    if config.WallCheck then
        local point = self:_visiblePoint(record, part, true, config.Multipoint)
        if not point then return false end
    end

    return true
end

function Aimbot:_triggerPick(config)
    if not Entity then return nil, nil end

    if config.Mode == "Target" then
        if not self.Target then return nil, nil end
        local record = Entity:Get(self.Target)
        if not record then return nil, nil end
        return record, self:_triggerPartOf(record)
    end

    if config.Mode == "Crosshair" then
        local params = self._triggerParams
        if not params then
            params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.IgnoreWater = true
            self._triggerParams = params
        end

        local ignore = {}
        if LocalPlayer.Character then table.insert(ignore, LocalPlayer.Character) end
        if Entity.Self and Entity.Self.Character then
            table.insert(ignore, Entity.Self.Character)
        end
        params.FilterDescendantsInstances = ignore

        local cframe = Camera.CFrame
        local hit = workspace:Raycast(cframe.Position, cframe.LookVector * config.MaxDistance, params)
        if not hit then return nil, nil end

        local model = hit.Instance:FindFirstAncestorOfClass("Model")
        while model do
            for _, record in pairs(Entity.Entities) do
                if record.Character == model then
                    return record, hit.Instance:IsA("BasePart") and hit.Instance or self:_triggerPartOf(record)
                end
            end
            model = model:FindFirstAncestorOfClass("Model")
        end

        return nil, nil
    end

    local origin = aimOrigin()
    local radius = config.Fov > 0 and config.Fov or 12
    local best, bestPart, bestScore = nil, nil, math.huge

    for _, record in pairs(Entity.Entities) do
        if record.Alive then
            local part = self:_triggerPartOf(record)

            if part then
                local screen, onScreen = Camera:WorldToViewportPoint(part.Position)

                if onScreen then
                    local distance = (Vector2.new(screen.X, screen.Y) - origin).Magnitude
                    if distance <= radius and distance < bestScore then
                        best, bestPart, bestScore = record, part, distance
                    end
                end
            end
        end
    end

    return best, bestPart
end

function Aimbot:_triggerUpdate()
    local config = self.Settings.Trigger

    if not self.Settings.TriggerBot or not self.Enabled then
        self._triggerSince = nil
        return
    end

    if config.RequireAim and not self.Active then
        self._triggerSince = nil
        return
    end

    if not self:_triggerKeyDown() then
        self._triggerSince = nil
        return
    end

    local record, part = self:_triggerPick(config)

    if not self:_triggerValid(record, part, config) then
        self._triggerSince = nil
        return
    end

    local now = tick()

    if not self._triggerSince then
        self._triggerSince = now
        self._triggerRolled = nil
    end

    if now - self._triggerSince < (config.ReactionTime or 0) then return end

    if self._triggerRolled == nil then
        local chance = config.HitChance or 100
        self._triggerRolled = chance >= 100 or (chance > 0 and math.random(1, 100) <= chance)
    end

    if not self._triggerRolled then return end

    self:_trigger()

    if not config.HoldFire then
        self._triggerSince = nil
        self._triggerRolled = nil
    end
end

function Aimbot:SetKey(key)
    self.Settings.Key = key
end

function Aimbot:SetFov(radius)
    self.Settings.Fov = radius
    if self._fovCircle then self._fovCircle.Radius = radius end
end

function Aimbot:Load(handler)
    if self._loaded then return self end

    Entity = handler or Entity
    if not Entity then
        Entity = loadstring(game:HttpGet(ENTITY_URL))()
    end
    if not Entity.Started then Entity:Start() end

    self.Entity = Entity
    self._currentPart = self.Settings.Parts[1]

    local circle = self:_fov()

    self._connections[1] = UserInputService.InputBegan:Connect(function(input)
        if not self.Enabled then return end
