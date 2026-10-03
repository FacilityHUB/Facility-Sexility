--!nocheck
--!nolint UnknownGlobal

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local function randomName()
    local chars = "abcdefghijklmnopqrstuvwxyz"
    local out = {}
    for i = 1, 10 do
        local index = math.random(1, #chars)
        out[i] = string.sub(chars, index, index)
    end
    return table.concat(out)
end

local Movement = {
    Settings = {
        FlySpeed = 2,
        FlyMode = "Velocity",
        VehicleFlySpeed = 2,

        WalkSpeed = 16,
        WalkSpeedMode = "Humanoid",

        JumpPower = 50,
        JumpMode = "Humanoid",

        NoclipVehicle = false,
        FloatHeight = 3.1,
        SpiderSpeed = 1,
    },

    State = {
        Fly = false,
        VehicleFly = false,
        Noclip = false,
        Swim = false,
        Float = false,
        InfiniteJump = false,
        Spider = false,
        WalkSpeed = false,
        JumpPower = false,
    },

    _connections = {},
    _loaded = false,
}

local velocityName = randomName()
local gyroName = randomName()
local floatName = randomName()

local function character()
    return LocalPlayer.Character
end

local function humanoid()
    local char = character()
    return char and char:FindFirstChildWhichIsA("Humanoid")
end

local function root()
    local char = character()
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("UpperTorso")
        or char.PrimaryPart
end

local function moveVector()
    local ok, control = pcall(function()
        return require(LocalPlayer:WaitForChild("PlayerScripts")
            :WaitForChild("PlayerModule")):GetControls()
    end)
    if ok and control then
        local fine, vector = pcall(function() return control:GetMoveVector() end)
        if fine and vector then return vector end
    end

    local humanoidInstance = humanoid()
    return humanoidInstance and humanoidInstance.MoveDirection or Vector3.zero
end

function Movement:_track(connection)
    table.insert(self._connections, connection)
    return connection
end

function Movement:_clearFly()
    local part = root()
    if part then
        local bv = part:FindFirstChild(velocityName)
        local bg = part:FindFirstChild(gyroName)
        if bv then bv:Destroy() end
        if bg then bg:Destroy() end
    end

    if self._flyLoop then
        self._flyLoop:Disconnect()
        self._flyLoop = nil
    end

    local humanoidInstance = humanoid()
    if humanoidInstance then humanoidInstance.PlatformStand = false end

    pcall(function()
        Camera.CameraType = Enum.CameraType.Custom
    end)
end

function Movement:_startFly(vehicle)
    self:_clearFly()

    local part = root()
    local humanoidInstance = humanoid()
    if not part or not humanoidInstance then return end

    local velocity = Instance.new("BodyVelocity")
    velocity.Name = velocityName
    velocity.MaxForce = Vector3.zero
    velocity.Velocity = Vector3.zero
    velocity.Parent = part

    local gyro = Instance.new("BodyGyro")
    gyro.Name = gyroName
    gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    gyro.P = 1000
    gyro.D = 50
    gyro.Parent = part

    self._flyLoop = RunService.RenderStepped:Connect(function()
        local currentRoot = root()
        local currentHumanoid = humanoid()
        if not currentRoot or not currentHumanoid then return end

        local bv = currentRoot:FindFirstChild(velocityName)
        local bg = currentRoot:FindFirstChild(gyroName)
        if not bv or not bg then return end

        local speed = vehicle and self.Settings.VehicleFlySpeed or self.Settings.FlySpeed

        bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        bg.CFrame = Camera.CFrame

        if not vehicle then currentHumanoid.PlatformStand = true end

        local direction = moveVector()
        local result = Vector3.zero

        if direction.X ~= 0 then
            result = result + Camera.CFrame.RightVector * (direction.X * speed * 50)
        end
        if direction.Z ~= 0 then
            result = result - Camera.CFrame.LookVector * (direction.Z * speed * 50)
        end

        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            result = result + Vector3.new(0, speed * 50, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            result = result - Vector3.new(0, speed * 50, 0)
        end

        bv.Velocity = result
    end)
end

function Movement:Fly(state)
    self.State.Fly = state and true or false
    if state then
        self.State.VehicleFly = false
        self:_startFly(false)
    else
        self:_clearFly()
    end
    return self
end

function Movement:VehicleFly(state)
    self.State.VehicleFly = state and true or false
    if state then
        self.State.Fly = false
        self:_startFly(true)
    else
        self:_clearFly()
    end
    return self
end

function Movement:SetFlySpeed(speed)
    self.Settings.FlySpeed = speed
    return self
end

function Movement:Noclip(state)
    self.State.Noclip = state and true or false

    if self._noclipLoop then
        self._noclipLoop:Disconnect()
        self._noclipLoop = nil
    end

    if not state then
        local char = character()
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide == false then
                    part.CanCollide = true
                end
            end
        end
        return self
    end

    self._noclipLoop = RunService.Stepped:Connect(function()
        local char = character()
        if not char then return end

        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end

        if self.Settings.NoclipVehicle then
            local humanoidInstance = humanoid()
            local seat = humanoidInstance and humanoidInstance.SeatPart
            local vehicle = seat and seat.Parent
            if vehicle then
                for _, part in ipairs(vehicle:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end
    end)

    return self
end

function Movement:WalkSpeed(value, mode)
    if value ~= nil then self.Settings.WalkSpeed = value end
    if mode then self.Settings.WalkSpeedMode = mode end

    self.State.WalkSpeed = self.Settings.WalkSpeed ~= 16

    if self._speedLoop then
        self._speedLoop:Disconnect()
        self._speedLoop = nil
    end

    local humanoidInstance = humanoid()

    if self.Settings.WalkSpeedMode == "CFrame" then
        if humanoidInstance then humanoidInstance.WalkSpeed = 16 end

        self._speedLoop = RunService.RenderStepped:Connect(function(dt)
            local currentRoot = root()
            local currentHumanoid = humanoid()
            if not currentRoot or not currentHumanoid then return end
            if currentHumanoid.MoveDirection.Magnitude == 0 then return end

            local extra = (self.Settings.WalkSpeed - 16) * dt
            currentRoot.CFrame = currentRoot.CFrame
                + currentHumanoid.MoveDirection * extra
        end)

    elseif self.Settings.WalkSpeedMode == "Velocity" then
        if humanoidInstance then humanoidInstance.WalkSpeed = 16 end

        self._speedLoop = RunService.RenderStepped:Connect(function()
            local currentRoot = root()
            local currentHumanoid = humanoid()
            if not currentRoot or not currentHumanoid then return end
            if currentHumanoid.MoveDirection.Magnitude == 0 then return end

            local wanted = currentHumanoid.MoveDirection * self.Settings.WalkSpeed
            currentRoot.AssemblyLinearVelocity =
                Vector3.new(wanted.X, currentRoot.AssemblyLinearVelocity.Y, wanted.Z)
        end)

    else
        if humanoidInstance then
            humanoidInstance.WalkSpeed = self.Settings.WalkSpeed
        end
    end

    return self
end

function Movement:JumpPower(value, mode)
    if value ~= nil then self.Settings.JumpPower = value end
    if mode then self.Settings.JumpMode = mode end

    self.State.JumpPower = self.Settings.JumpPower ~= 50

    local humanoidInstance = humanoid()
    if not humanoidInstance then return self end

    if self.Settings.JumpMode == "Height" then
        humanoidInstance.UseJumpPower = false
        humanoidInstance.JumpHeight = self.Settings.JumpPower / 7
    else
        humanoidInstance.UseJumpPower = true
        humanoidInstance.JumpPower = self.Settings.JumpPower
    end

    return self
end

function Movement:InfiniteJump(state)
    self.State.InfiniteJump = state and true or false

    if self._jumpConnection then
        self._jumpConnection:Disconnect()
        self._jumpConnection = nil
    end

    if not state then return self end

    self._jumpConnection = UserInputService.JumpRequest:Connect(function()
        local humanoidInstance = humanoid()
        if humanoidInstance then
            humanoidInstance:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)

    return self
end

function Movement:Swim(state)
    self.State.Swim = state and true or false

    if self._swimLoop then
        self._swimLoop:Disconnect()
        self._swimLoop = nil
    end

    local humanoidInstance = humanoid()

    if not state then
        if self._oldGravity then
            workspace.Gravity = self._oldGravity
            self._oldGravity = nil
        end

        if humanoidInstance then
            for _, item in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
                if item ~= Enum.HumanoidStateType.None then
                    pcall(function() humanoidInstance:SetStateEnabled(item, true) end)
                end
            end
        end
        return self
    end

    if not humanoidInstance then return self end

    self._oldGravity = self._oldGravity or workspace.Gravity
    workspace.Gravity = 0

    for _, item in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
        if item ~= Enum.HumanoidStateType.None then
            pcall(function() humanoidInstance:SetStateEnabled(item, false) end)
        end
    end
    humanoidInstance:ChangeState(Enum.HumanoidStateType.Swimming)

    self._swimLoop = RunService.Heartbeat:Connect(function()
        local currentRoot = root()
        local currentHumanoid = humanoid()
        if not currentRoot or not currentHumanoid then return end

        local moving = currentHumanoid.MoveDirection ~= Vector3.zero
            or UserInputService:IsKeyDown(Enum.KeyCode.Space)

        if not moving then
            currentRoot.AssemblyLinearVelocity = Vector3.zero
        end
    end)

    return self
end

function Movement:Float(state)
    self.State.Float = state and true or false

    if self._floatLoop then
        self._floatLoop:Disconnect()
        self._floatLoop = nil
    end

    local char = character()
    if char then
        local existing = char:FindFirstChild(floatName)
        if existing then existing:Destroy() end
    end

    if not state then return self end
    if not char then return self end

    local platform = Instance.new("Part")
    platform.Name = floatName
    platform.Size = Vector3.new(4, 0.2, 4)
    platform.Transparency = 1
    platform.Anchored = true
    platform.CanCollide = true
    platform.Parent = char

    self._floatLoop = RunService.Heartbeat:Connect(function()
        local currentRoot = root()
        if not currentRoot or platform.Parent == nil then return end
        platform.CFrame = CFrame.new(currentRoot.Position
            - Vector3.new(0, self.Settings.FloatHeight, 0))
    end)

    return self
end

function Movement:Spider(state)
    self.State.Spider = state and true or false

    if self._spiderLoop then
        self._spiderLoop:Disconnect()
        self._spiderLoop = nil
    end

    if not state then return self end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true

    self._spiderLoop = RunService.Heartbeat:Connect(function()
        local currentRoot = root()
        local char = character()
        if not currentRoot or not char then return end

        params.FilterDescendantsInstances = { char }

        local directions = {
            currentRoot.CFrame.LookVector,
            -currentRoot.CFrame.LookVector,
            currentRoot.CFrame.RightVector,
            -currentRoot.CFrame.RightVector,
        }

        for _, direction in ipairs(directions) do
            local hit = workspace:Raycast(currentRoot.Position, direction * 3, params)
            if hit then
                currentRoot.AssemblyLinearVelocity = Vector3.new(
                    currentRoot.AssemblyLinearVelocity.X,
                    self.Settings.SpiderSpeed * 25,
                    currentRoot.AssemblyLinearVelocity.Z)
                return
            end
        end
    end)

    return self
end

function Movement:_reapply()
    task.wait(0.4)

    if self.State.Fly then self:_startFly(false) end
    if self.State.VehicleFly then self:_startFly(true) end
    if self.State.Noclip then self:Noclip(true) end
    if self.State.Swim then self:Swim(true) end
    if self.State.Float then self:Float(true) end
    if self.State.Spider then self:Spider(true) end
    if self.State.WalkSpeed then self:WalkSpeed() end
    if self.State.JumpPower then self:JumpPower() end
end

function Movement:Load()
    if self._loaded then return self end

    self:_track(LocalPlayer.CharacterAdded:Connect(function()
        task.spawn(function() self:_reapply() end)
    end))

    self:_track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        Camera = workspace.CurrentCamera
    end))

    self._loaded = true
    return self
end

function Movement:Unload()
    self:Fly(false)
    self:VehicleFly(false)
    self:Noclip(false)
    self:Swim(false)
    self:Float(false)
    self:Spider(false)
    self:InfiniteJump(false)

    self.Settings.WalkSpeed = 16
    self.Settings.JumpPower = 50
    self:WalkSpeed(16, "Humanoid")
    self:JumpPower(50, "Humanoid")

    for _, connection in ipairs(self._connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(self._connections)

    self._loaded = false
end

return Movement
