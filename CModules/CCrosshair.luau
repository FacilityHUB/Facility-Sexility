-- Load with shared.Facility.Load("CModules/CCrosshair.luau").
-- Change Settings before or during use. Call :Load() to show and :Unload() to clean up.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Crosshair = {
    Settings = {
        mode = "mouse", -- "mouse", "center", or "position"
        position = Vector2.zero,
        crosshair_mode = "static", -- or "follow muzzle"
        refreshrate = 0,
        width = 1.5,
        length = 10,
        radius = 11,
        crosshair_color = Color3.fromRGB(0, 200, 255),
        spin = true,
        spin_speed = 150,
        spin_max = 340,
        spin_style = Enum.EasingStyle.Sine,
        resize = true,
        resize_speed = 150,
        resize_min = 5,
        resize_max = 22,
        scale_min = 1,
        scale_max = 1,
        show_lines = true,
        show_ammo = false,
    },
}

local connection
local outlines, strokes = {}, {}
local ammoLabel, ammoFrame, reserveField, ammoField
local nextScan = 0

local function getPosition(camera, settings)
    if settings.crosshair_mode == "follow muzzle" then
        local models = workspace:FindFirstChild("ViewModels")
        local firstPerson = models and models:FindFirstChild("FirstPerson")
        local name = Players.LocalPlayer.Name
        if firstPerson then
            for _, model in ipairs(firstPerson:GetChildren()) do
                if model:IsA("Model") and model.Name:sub(1, #name) == name then
                    local visual = model:FindFirstChild("ItemVisual")
                    local body = visual and visual:FindFirstChild("Body")
                    local primary = body and body:FindFirstChild("BodyPrimary")
                    local muzzle = primary and primary:FindFirstChild("_muzzle")
                    if muzzle and muzzle:IsA("Attachment") then
                        local point, visible = camera:WorldToViewportPoint(muzzle.WorldPosition)
                        if visible then return Vector2.new(point.X, point.Y) end
                    end
                end
            end
        end
    end
    if settings.mode == "center" then return camera.ViewportSize / 2 end
    if settings.mode == "position" then return settings.position end
    return Input:GetMouseLocation()
end

local function isText(object)
    return object and (object:IsA("TextLabel") or object:IsA("TextBox") or object:IsA("TextButton"))
end

local function readAmmo(now)
    if not (ammoFrame and ammoFrame.Parent and ammoFrame.Visible
        and reserveField.Parent == ammoFrame and ammoField.Parent == reserveField) then
        if now < nextScan then return nil end
        nextScan = now + 0.5
        ammoFrame, reserveField, ammoField = nil, nil, nil
        local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not gui then return nil end
        for _, frame in ipairs(gui:GetDescendants()) do
            if frame:IsA("Frame") and frame.Visible and frame:FindFirstChild("ItemName") and frame:FindFirstChild("Icon") then
                local reserve = frame:FindFirstChild("Reserve")
                local ammo = reserve and reserve:FindFirstChild("Ammo")
                if isText(reserve) and isText(ammo) then
                    ammoFrame, reserveField, ammoField = frame, reserve, ammo
                    break
                end
            end
        end
    end
    if ammoFrame then
        local reserve = reserveField.Text:match("%d+")
        local ammo = ammoField.Text:match("%d+")
        if reserve and ammo then return reserve .. " / " .. ammo end
    end
    return nil
end

local function draw(now)
    local settings = Crosshair.Settings
    local camera = workspace.CurrentCamera
    local visible = camera ~= nil and settings.show_lines
    local position = camera and getPosition(camera, settings)
    local angle, length, scale = 0, settings.length, 1
    if visible then
        if settings.spin and settings.spin_max > 0 then
            local phase = ((-now * settings.spin_speed) % settings.spin_max) / 360
            angle = TweenService:GetValue(phase, settings.spin_style, Enum.EasingDirection.InOut) * 360
        end
        scale = settings.scale_min + math.sin(now * settings.resize_speed) * (settings.scale_max - settings.scale_min)
        if settings.resize then
            length = settings.resize_min + math.sin(math.rad((now * settings.resize_speed) % 180)) * settings.resize_max
        end
    end
    for i = 1, 4 do
        local stroke, outline = strokes[i], outlines[i]
        if visible then
            local radians = math.rad((i - 1) * 90 + angle)
            local direction = Vector2.new(math.sin(radians), math.cos(radians))
            stroke.From = position + direction * (settings.radius * scale)
            stroke.To = position + direction * ((settings.radius + length) * scale)
            stroke.Color = settings.crosshair_color
            stroke.Thickness = settings.width
            outline.From = stroke.From - direction
            outline.To = stroke.To + direction
            outline.Thickness = settings.width + 1.5
        end
        stroke.Visible = visible
        outline.Visible = visible
    end
    local ammo = camera and settings.show_ammo and readAmmo(now)
    if ammo then
        ammoLabel.Text = ammo
        ammoLabel.Position = position + Vector2.new(0, visible and (settings.radius + settings.length + 18) or 18)
    end
    ammoLabel.Visible = ammo ~= nil and ammo ~= false
end

function Crosshair:Unload()
    if connection then connection:Disconnect() end
    connection = nil
    for _, lines in ipairs({strokes, outlines}) do
        for _, line in ipairs(lines) do line:Remove() end
        table.clear(lines)
    end
    if ammoLabel then ammoLabel:Remove() end
    ammoLabel, ammoFrame, reserveField, ammoField = nil, nil, nil, nil
    nextScan = 0
end

function Crosshair:Load()
    if connection then return end
    local ok, err = pcall(function()
        for i = 1, 4 do
            outlines[i] = Drawing.new("Line")
            outlines[i].Color = Color3.new(0, 0, 0)
            strokes[i] = Drawing.new("Line")
        end
        ammoLabel = Drawing.new("Text")
        ammoLabel.Center = true
        ammoLabel.Outline = true
        ammoLabel.Size = 13
        ammoLabel.Font = 2
        ammoLabel.Color = Color3.new(1, 1, 1)
        local last = -math.huge
        connection = RunService.RenderStepped:Connect(function()
            local now = os.clock()
            if now - last >= self.Settings.refreshrate then
                last = now
                draw(now)
            end
        end)
    end)
    if not ok then
        self:Unload()
        error(err, 2)
    end
end

return Crosshair
