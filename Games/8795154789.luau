local FH = shared.Facility
local Library = FH and FH.Library
assert(Library, "Start Facility with the loader")
local Entity = FH.Entity
local Esp = FH.Esp

local SESSION = (shared.FacilitySession or 0) + 1
shared.FacilitySession = SESSION

local function alive()
	return shared.FacilitySession == SESSION
end

if shared.FacilityCleanup then
	pcall(shared.FacilityCleanup)
	shared.FacilityCleanup = nil
end

local HUB_BASE = FH.HubBase or "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/"
local moduleErrors = {}

local function fetchModule(path, label)
	local fetched, source = pcall(function()
		return game:HttpGet(HUB_BASE .. path .. "?v=" .. tostring(tick()):gsub("%.", ""))
	end)
	if not fetched or type(source) ~= "string" then
		table.insert(moduleErrors, label .. ": download failed - " .. tostring(source))
		return nil
	end
	local chunk, compileError = loadstring(source)
	if not chunk then
		table.insert(moduleErrors, label .. ": compile failed - " .. tostring(compileError))
		return nil
	end
	local ok, result = pcall(chunk)
	if not ok or type(result) ~= "table" then
		table.insert(moduleErrors, label .. ": load failed - " .. tostring(result))
		return nil
	end
	return result
end

local Aimbot = fetchModule("CModules/FAimbot.luau", "aimbot")
FH.Aimbot = Aimbot

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local H = {}
local U = {}
local S = { connections = {}, drawings = {}, triggerHeld = false, lastTap = 0 }
local F = {
	teamMode = "Team",
	silent = false,
	silentPart = "Head",
	silentFov = 150,
	silentShowFov = true,
	silentColor = Color3.fromRGB(232, 161, 168),
	silentTeam = true,
	silentWall = true,
	silentAround = false,
	rapid = false,
	rapidShots = 15,
	trigger = false,
	triggerMode = "Crosshair",
	triggerFov = 0,
	triggerTeam = true,
	triggerDelay = 0,
}

local FALLBACK_PARTS = { "HumanoidRootPart", "UpperTorso", "Torso", "LowerTorso", "Head" }
local TURN_LIMIT = 20
local MIN_DISTANCE = 5

function H.track(connection)
	table.insert(S.connections, connection)
	return connection
end

function H.gcall(fn, ...)
	local packed = table.pack(...)
	local box = nil
	task.spawn(function()
		box = table.pack(pcall(fn, table.unpack(packed, 1, packed.n)))
	end)
	if not box then
		local deadline = os.clock() + 10
		while not box and os.clock() < deadline do task.wait() end
	end
	if not box then return false, "timed out" end
	return table.unpack(box, 1, box.n)
end

function H.T(section, text, flag, default, callback, hint)
	return section:Toggle({
		Text = text, Flag = flag, Default = default, Hint = hint,
		Callback = function(state) pcall(callback, state) end,
	})
end

function H.S(section, text, flag, min, max, default, decimals, callback, suffix)
	return section:Slider({
		Text = text, Flag = flag, Min = min, Max = max, Default = default, Decimals = decimals, Suffix = suffix,
		Callback = function(value) pcall(callback, tonumber(value) or default) end,
	})
end

function H.D(section, text, flag, options, default, callback)
	return section:Dropdown({
		Text = text, Flag = flag, Options = options, Default = default,
		Callback = function(value)
			if type(value) == "table" then value = value[1] end
			pcall(callback, value)
		end,
	})
end

function H.notifyError(title, message)
	pcall(function() Library:Notify({ Title = title, Text = tostring(message), Duration = 10, Style = "Error" }) end)
end

function H.setTeamMode(mode)
	F.teamMode = mode
	pcall(function() Entity.Settings.TeamCheck = mode end)
	pcall(function() Esp.sharedSettings.teamCheck = mode end)
	pcall(function() Entity:RefreshTargets() end)
end

function H.camera()
	return workspace.CurrentCamera
end

function H.center()
	local camera = H.camera()
	return camera and camera.ViewportSize / 2 or Vector2.zero
end

function H.findPart(character, name)
	local part = character:FindFirstChild(name)
	if part and part:IsA("BasePart") then return part end
	for _, item in ipairs(character:GetDescendants()) do
		if item.Name == name and item:IsA("BasePart") then return item end
	end
end

function H.visible(origin, position, ignore)
	local camera = H.camera()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LocalPlayer.Character, camera, ignore }
	params.IgnoreWater = true
	local direction = position - origin
	local distance = direction.Magnitude
	if distance <= 0 then return false end
	local hit = workspace:Raycast(origin, direction, params)
	return hit == nil or hit.Distance >= distance - 0.5
end

function H.records(teamCheck)
	if Entity then return Entity:GetAll(teamCheck) end
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if player ~= LocalPlayer and humanoid then
			table.insert(list, { Player = player, Character = character, Humanoid = humanoid })
		end
	end
	return list
end

function H.aimPoint(character, origin)
	local wanted = H.findPart(character, F.silentPart)
	if wanted and (not F.silentWall or H.visible(origin, wanted.Position, character)) then return wanted end
	for _, name in ipairs(FALLBACK_PARTS) do
		if name ~= F.silentPart then
			local part = H.findPart(character, name)
			if part and (not F.silentWall or H.visible(origin, part.Position, character)) then return part end
		end
	end
	return nil
end

function H.silentTarget(origin)
	local camera = H.camera()
	if not camera then return nil end
	local center = H.center()
	local best
	for _, record in ipairs(H.records(F.silentTeam)) do
		local character = record.Character
		local humanoid = record.Humanoid
		if character and character.Parent and character ~= LocalPlayer.Character and humanoid and humanoid.Health > 0 then
			local part = H.aimPoint(character, origin)
			if part and (not F.silentAround or H.visible(origin, part.Position, character)) then
				local point, onScreen = camera:WorldToViewportPoint(part.Position)
				local screen = onScreen and (Vector2.new(point.X, point.Y) - center).Magnitude or math.huge
				local depth = (part.Position - origin).Magnitude
				local allowed = F.silentAround or (onScreen and screen <= F.silentFov)
				if allowed and depth >= MIN_DISTANCE then
					local entry = { position = part.Position, screen = screen, depth = depth, onScreen = onScreen }
					if not best then
						best = entry
					elseif entry.onScreen ~= best.onScreen then
						if entry.onScreen then best = entry end
					elseif entry.onScreen and math.abs(entry.screen - best.screen) >= 30 then
						if entry.screen < best.screen then best = entry end
					elseif entry.depth < best.depth then
						best = entry
					end
				end
			end
		end
	end
	return best
end

S.bullets = nil
S.signals = nil
pcall(function()
	local modules = ReplicatedStorage:FindFirstChild("ModuleScripts")
	local gunModules = modules and modules:FindFirstChild("GunModules")
	local bulletModule = gunModules and gunModules:FindFirstChild("BulletHandler")
	if bulletModule then
		local ok, result = H.gcall(require, bulletModule)
		if ok and type(result) == "table" and type(result.Fire) == "function" then S.bullets = result end
	end
	local signalModule = ReplicatedStorage:FindFirstChild("SignalManager")
	if signalModule then
		local ok, result = H.gcall(require, signalModule)
		if ok and type(result) == "table" then S.signals = result end
	end
end)

if S.bullets then
	if shared.FacilityShotOriginal and S.bullets.Fire ~= shared.FacilityShotOriginal then
		S.bullets.Fire = shared.FacilityShotOriginal
	end
	shared.FacilityShotOriginal = shared.FacilityShotOriginal or S.bullets.Fire
end
local originalFire = shared.FacilityShotOriginal

function H.copyShots(payload, count)
	for index = 2, count do
		local copy = table.clone(payload)
		if type(payload.Misc) == "table" then
			copy.Misc = table.clone(payload.Misc)
			copy.Misc.ShotID = tick() + index * 0.0001
			copy.Misc.NewSeed = (copy.Misc.NewSeed or 0) + 11
		end
		copy.BulletId = tick() + index * 0.0001
		pcall(originalFire, copy)
	end
end

function H.shotHook(payload)
	if not alive() or type(payload) ~= "table" or (not F.silent and not F.rapid) then
		return originalFire(payload)
	end
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local airborne = humanoid and humanoid.FloorMaterial == Enum.Material.Air
	local camera = H.camera()

	if F.silent and airborne and root and typeof(payload.Origin) == "Vector3" then
		payload.Origin = root.Position + Vector3.new(0, 1.5, 0)
		if typeof(payload.VisualOrigin) == "Vector3" then payload.VisualOrigin = payload.Origin end
	end

	local origin = typeof(payload.Origin) == "Vector3" and payload.Origin or nil
	local spoof
	if F.silent and origin then
		local target = H.silentTarget(origin)
		if target then
			local direction = (target.position - origin).Unit
			payload.Direction = direction
			if type(payload.Misc) == "table" then
				if typeof(payload.Misc.CamCFrame) == "CFrame" then
					payload.Misc.CamCFrame = CFrame.lookAt(origin, origin + direction)
				end
				payload.Misc.Spread = 0
			end
			if camera then
				local angle = math.deg(math.acos(math.clamp(camera.CFrame.LookVector:Dot(direction), -1, 1)))
				if F.silentAround or (angle > TURN_LIMIT and not airborne) then
					spoof = CFrame.lookAt(origin, origin + direction)
				end
			end
		end
	end

	local previous
	if spoof and camera then
		previous = camera.CFrame
		camera.CFrame = spoof
	end
	local result = originalFire(payload)
	if F.rapid then H.copyShots(payload, F.rapidShots) end
	if previous and camera then camera.CFrame = previous end
	return result
end

if S.bullets and originalFire then
	S.bullets.Fire = H.shotHook
else
	table.insert(moduleErrors, "silent aim: the game's bullet module was not found")
end

pcall(function()
	local circle = Drawing.new("Circle")
	circle.Thickness = 1.5
	circle.Transparency = 0.7
	circle.Filled = false
	circle.NumSides = 64
	circle.Visible = false
	U.silentCircle = circle
	table.insert(S.drawings, circle)
end)

H.track(RunService.RenderStepped:Connect(function()
	local circle = U.silentCircle
	if not circle then return end
	circle.Visible = alive() and F.silent and F.silentShowFov and not F.silentAround
	if circle.Visible then
		circle.Position = H.center()
		circle.Radius = F.silentFov
		circle.Color = F.silentColor
	end
end))

function H.fireWeapon(state)
	if S.signals and type(S.signals.Fire) == "function" then
		pcall(S.signals.Fire, "FireWeapon", state)
		return true
	end
	if state == Enum.UserInputState.Begin and mouse1press then
		pcall(mouse1press)
		return true
	elseif state == Enum.UserInputState.End and mouse1release then
		pcall(mouse1release)
		return true
	end
	return false
end

function H.triggerRelease()
	if S.triggerHeld then
		S.triggerHeld = false
		H.fireWeapon(Enum.UserInputState.End)
	end
end

function H.triggerValid(record)
	if not record or not record.Character or not record.Character.Parent then return false end
	if record.Player == LocalPlayer then return false end
	local humanoid = record.Humanoid
	if not humanoid or humanoid.Health <= 0 then return false end
	if F.triggerTeam and record.Targetable == false then return false end
	return true
end

function H.recordFor(part)
	for _, record in ipairs(H.records(false)) do
		if record.Character and part:IsDescendantOf(record.Character) then return record end
	end
end

function H.triggerTarget()
	local camera = H.camera()
	if not camera then return nil end
	if F.triggerMode == "Target" then
		local target = Aimbot and Aimbot.Target
		local record = target and Entity and Entity:Get(target)
		return H.triggerValid(record) and record or nil
	end
	local center = H.center()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LocalPlayer.Character, camera }
	if F.triggerMode == "Crosshair" then
		local ray = camera:ViewportPointToRay(center.X, center.Y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
		local record = hit and H.recordFor(hit.Instance)
		return H.triggerValid(record) and record or nil
	end
	local radius = F.triggerFov > 0 and F.triggerFov or 12
	for _, record in ipairs(H.records(false)) do
		if H.triggerValid(record) then
			local head = record.Head or record.Character:FindFirstChild("Head")
			if head then
				local point, onScreen = camera:WorldToViewportPoint(head.Position)
				if onScreen and (Vector2.new(point.X, point.Y) - center).Magnitude <= radius
					and H.visible(camera.CFrame.Position, head.Position, record.Character) then
					return record
				end
			end
		end
	end
end

H.track(RunService.Heartbeat:Connect(function()
	if not alive() then return end
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not F.trigger or not humanoid or humanoid.Health <= 0 or not tool or UserInputService:GetFocusedTextBox() then
		H.triggerRelease()
		return
	end
	if not H.triggerTarget() then
		H.triggerRelease()
		return
	end
	if F.triggerDelay <= 0 then
		if not S.triggerHeld then
			S.triggerHeld = true
			H.fireWeapon(Enum.UserInputState.Begin)
		end
		return
	end
	local now = os.clock()
	if now - S.lastTap >= F.triggerDelay then
		S.lastTap = now
		H.fireWeapon(Enum.UserInputState.Begin)
		H.fireWeapon(Enum.UserInputState.End)
	end
end))

shared.FacilityCleanup = function()
	F.silent, F.rapid, F.trigger = false, false, false
	H.triggerRelease()
	if S.bullets and originalFire and S.bullets.Fire == H.shotHook then S.bullets.Fire = originalFire end
	for _, connection in ipairs(S.connections) do pcall(function() connection:Disconnect() end) end
	table.clear(S.connections)
	for _, drawing in ipairs(S.drawings) do pcall(function() drawing:Remove() end) end
	table.clear(S.drawings)
	if Aimbot then pcall(function() Aimbot:Unload() end) end
	pcall(function() Esp:Unload() end)
	pcall(function() Library:Destroy() end)
end

local Window = Library:Window({
	Title = "Facility",
	Suffix = ".app",
	Width = 720,
	Height = 600,
	MinWidth = 580,
	SectionTitleStyle = "border",
	MobileButton = true,
	TabStyle = "side",
})

function H.sub(tab, name, icon)
	if tab.SubTab then return tab:SubTab(name, icon) end
	return tab
end

U.Combat = Window:Tab("Combat", "crosshair")
U.Visuals = Window:Tab("Visuals", "eye")
Window:TabDivider()
U.Settings = Window:Tab("Settings", "settings")

U.AimSub = H.sub(U.Combat, "Aimbot", "crosshair")
U.RageSub = H.sub(U.Combat, "Rage", "zap")

if #moduleErrors > 0 then
	U.failBox = U.AimSub:Section("Modules", "full")
	for _, message in ipairs(moduleErrors) do U.failBox:Label(message, { Style = "dim" }) end
end

if Aimbot then
	Aimbot.Settings.TeamCheck = true
	Aimbot.Settings.WallCheck = true

	U.aimBox = U.AimSub:Section("Aimbot", 1)
	U.aimBox:Toggle({
		Text = "Enable",
		Flag = "flk_aim_enable",
		Default = false,
		Callback = function(state)
			if state then
				local ok, err = pcall(function() Aimbot:Load(Entity) end)
				if not ok then
					H.notifyError("Aimbot", err)
					return
				end
			end
			Aimbot.Enabled = state
		end,
	})
	U.aimBox:Keybind({
		Text = "Aim Key",
		Flag = "flk_aim_key",
		Default = "MB2",
		Mode = "toggle",
		OnChanged = function(key)
			local map = {
				MB1 = Enum.UserInputType.MouseButton1,
				MB2 = Enum.UserInputType.MouseButton2,
				MB3 = Enum.UserInputType.MouseButton3,
			}
			local ok, chosen = pcall(function() return map[key] or Enum.KeyCode[key] end)
			chosen = ok and chosen or Enum.UserInputType.MouseButton2
			Aimbot.Settings.Key = chosen
			pcall(function() Aimbot:SetKey(chosen) end)
		end,
	})
	H.T(U.aimBox, "Toggle Mode", "flk_aim_toggle_mode", false, function(state) Aimbot.Settings.ToggleMode = state end)
	H.D(U.aimBox, "Priority", "flk_aim_priority", { "Cursor", "Closest", "LowestHealth" }, "Cursor", function(value) Aimbot.Settings.Priority = value end)
	U.aimBox:Dropdown({
		Text = "Target Part",
		Flag = "flk_aim_parts",
		Options = { "Head", "UpperTorso", "HumanoidRootPart" },
		Default = { "Head" },
		Multi = true,
		Empty = "Head",
		Callback = function(selected)
			if #selected == 0 then selected = { "Head" } end
			Aimbot.Settings.Parts = selected
		end,
	})
	U.aimBox:Toggle({
		Text = "Random Part",
		Flag = "flk_aim_random_part",
		Default = false,
		Callback = function(state) Aimbot.Settings.RandomPart = state end,
	}):Gear(function(panel)
		H.S(panel, "Interval", "flk_aim_random_interval", 0.1, 3, 1, 1, function(value) Aimbot.Settings.RandomInterval = value end, " s")
	end)
	H.S(U.aimBox, "Smoothness", "flk_aim_smoothness", 0.05, 1, 0.3, 2, function(value) Aimbot.Settings.Smoothness = value end)
	H.S(U.aimBox, "Sensitivity", "flk_aim_sensitivity", 0.02, 1, 0.5, 2, function(value) Aimbot.Settings.Sensitivity = value end)
	H.D(U.aimBox, "Easing Style", "flk_aim_easing_style", { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Back" }, "Quad", function(value) Aimbot.Settings.EasingStyle = value end)
	H.D(U.aimBox, "Easing Direction", "flk_aim_easing_direction", { "In", "Out", "InOut" }, "Out", function(value) Aimbot.Settings.EasingDirection = value end)
	H.S(U.aimBox, "Switch Delay", "flk_aim_switch_delay", 0, 2, 0, 2, function(value) Aimbot.Settings.SwitchDelay = value end, " s")
	H.S(U.aimBox, "Max Distance", "flk_aim_max_distance", 100, 5000, 3000, 0, function(value) Aimbot.Settings.MaxDistance = value end, " studs")

	U.fovBox = U.AimSub:Section("Fov", 2)
	U.fovBox:Toggle({
		Text = "Fov",
		Flag = "flk_aim_fov_enabled",
		Default = true,
		Callback = function(state)
			Aimbot.Settings.FovCheck = state
			Aimbot.Settings.FovVisible = state
		end,
	})
		:ColorPicker({ Flag = "flk_aim_fov_color", Default = Color3.fromRGB(255, 255, 255), Callback = function(color) Aimbot.Settings.FovColor = color end })
		:ColorPicker({ Flag = "flk_aim_fov_lock_color", Default = Color3.fromRGB(255, 70, 70), Callback = function(color) Aimbot.Settings.FovLockColor = color end })
	U.fovBox:Slider({
		Text = "Radius",
		Flag = "flk_aim_fov",
		Min = 20, Max = 600, Default = 180,
		Callback = function(value)
			Aimbot.Settings.Fov = value
			pcall(function() Aimbot:SetFov(value) end)
		end,
	})
	H.S(U.fovBox, "Thickness", "flk_aim_fov_thickness", 1, 5, 1, 0, function(value) Aimbot.Settings.FovThickness = value end)
	H.S(U.fovBox, "Transparency", "flk_aim_fov_transparency", 0, 1, 0.4, 2, function(value) Aimbot.Settings.FovTransparency = value end)
	H.T(U.fovBox, "Filled", "flk_aim_fov_filled", false, function(state) Aimbot.Settings.FovFilled = state end)

	U.behaviourBox = U.AimSub:Section("Behaviour", 2)
	H.T(U.behaviourBox, "Team Check", "flk_aim_team_check", true, function(state) Aimbot.Settings.TeamCheck = state end)
	H.T(U.behaviourBox, "Wall Check", "flk_aim_wall_check", true, function(state) Aimbot.Settings.WallCheck = state end)
	H.T(U.behaviourBox, "Multipoint", "flk_aim_multipoint", false, function(state) Aimbot.Settings.Multipoint = state end)
	H.S(U.behaviourBox, "Deadzone", "flk_aim_deadzone", 0, 200, 0, 0, function(value) Aimbot.Settings.Deadzone = value end)
	U.behaviourBox:Toggle({
		Text = "Sticky Target",
		Flag = "flk_aim_sticky",
		Default = true,
		Callback = function(state) Aimbot.Settings.Sticky = state end,
	}):Gear(function(panel)
		H.S(panel, "Hold Fov", "flk_aim_sticky_fov", 1, 3, 1.6, 1, function(value) Aimbot.Settings.StickyFov = value end)
	end)
	U.behaviourBox:Toggle({
		Text = "Prediction",
		Flag = "flk_aim_prediction",
		Default = false,
		Callback = function(state) Aimbot.Settings.Prediction = state end,
	}):Gear(function(panel)
		H.S(panel, "Time", "flk_aim_prediction_time", 0, 0.5, 0.1, 2, function(value) Aimbot.Settings.PredictionTime = value end, " s")
		H.T(panel, "Add Ping", "flk_aim_prediction_ping", false, function(state) Aimbot.Settings.PingPrediction = state end)
	end)
	U.behaviourBox:Toggle({
		Text = "Target Line",
		Flag = "flk_aim_target_line",
		Default = false,
		Callback = function(state) Aimbot.Settings.TargetLine = state end,
	}):ColorPicker({ Flag = "flk_aim_target_line_color", Default = Color3.fromRGB(255, 70, 70), Callback = function(color) Aimbot.Settings.TargetLineColor = color end })
	H.T(U.behaviourBox, "Target Info", "flk_aim_target_info", false, function(state) Aimbot.Settings.TargetInfo = state end)
end

U.teamBox = U.AimSub:Section("Targets", 1)
H.D(U.teamBox, "Team Check", "flk_team_mode", { "Team", "TeamColor", "Off" }, "Team", function(value) H.setTeamMode(value) end)
U.teamBox:Label("Use Off in free for all if nobody gets targeted.", { Style = "dim" })

U.silentBox = U.RageSub:Section("Silent Aim", 1)
U.silentBox:Toggle({
	Text = "Silent Aim",
	Flag = "flk_silent",
	Default = false,
	Hint = "bends your bullets toward the closest enemy in the fov",
	Callback = function(state) F.silent = state end,
})
	:Keybind({ Default = "X", Flag = "flk_silent_key" })
	:ColorPicker({ Flag = "flk_silent_color", Default = F.silentColor, Callback = function(color) F.silentColor = color end })
H.D(U.silentBox, "Aim Part", "flk_silent_part", { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso" }, "Head", function(value) F.silentPart = value end)
H.S(U.silentBox, "Fov", "flk_silent_fov", 25, 500, 150, 0, function(value) F.silentFov = value end)
H.T(U.silentBox, "Show Fov", "flk_silent_show_fov", true, function(state) F.silentShowFov = state end)
U.silentBox:Toggle({
	Text = "Any Direction",
	Flag = "flk_silent_around",
	Default = false,
	Hint = "ignores the fov and also hits enemies behind you",
	Callback = function(state) F.silentAround = state end,
}):Keybind({ Default = "G", Flag = "flk_silent_around_key" })
H.T(U.silentBox, "Team Check", "flk_silent_team", true, function(state) F.silentTeam = state end)
H.T(U.silentBox, "Wall Check", "flk_silent_wall", true, function(state) F.silentWall = state end)

U.rapidBox = U.RageSub:Section("Rapid Fire", 2)
U.rapidBox:Toggle({
	Text = "Rapid Fire",
	Flag = "flk_rapid",
	Default = false,
	Hint = "sends several bullets for every shot",
	Callback = function(state) F.rapid = state end,
}):Keybind({ Default = "R", Flag = "flk_rapid_key" })
H.S(U.rapidBox, "Bullets Per Shot", "flk_rapid_shots", 2, 15, 15, 0, function(value) F.rapidShots = value end)

U.triggerBox = U.RageSub:Section("Trigger Bot", 2)
U.triggerBox:Toggle({
	Text = "Enable",
	Flag = "flk_trigger",
	Default = false,
	Hint = "fires while an enemy is under your crosshair",
	Callback = function(state)
		F.trigger = state
		if not state then H.triggerRelease() end
	end,
}):Keybind({ Default = "T", Flag = "flk_trigger_key" })
H.D(U.triggerBox, "Mode", "flk_trigger_mode", { "Crosshair", "Target", "Fov" }, "Crosshair", function(value) F.triggerMode = value end)
H.S(U.triggerBox, "Fov", "flk_trigger_fov", 0, 400, 0, 0, function(value) F.triggerFov = value end)
H.T(U.triggerBox, "Team Check", "flk_trigger_team", true, function(state) F.triggerTeam = state end)
H.S(U.triggerBox, "Shot Delay", "flk_trigger_delay", 0, 2, 0, 2, function(value)
	F.triggerDelay = value
	H.triggerRelease()
end, " s")
U.triggerBox:Label("0 holds and sprays, higher values tap. Fov 0 is 12 px.", { Style = "dim" })

U.PLAYER_TEAMS = { "enemy", "friendly", "whitelist" }

function H.espSet(key, value)
	for _, name in ipairs(U.PLAYER_TEAMS) do
		local team = Esp.teamSettings[name]
		if team then team[key] = value end
	end
end

function H.espPair(key, color, alpha)
	Esp.teamSettings.enemy[key] = { color, alpha ~= nil and (1 - alpha) or 1 }
end

U.espBox = U.Visuals:Section("Esp", 1)
U.espBox:Toggle({
	Text = "Enable",
	Flag = "flk_esp_enable",
	Default = false,
	Callback = function(state)
		local ok, err
		if state then
			ok, err = pcall(function() Esp:Load(Entity) end)
		else
			ok, err = pcall(function() Esp:Unload() end)
		end
		if not ok then H.notifyError("Esp", err) end
	end,
}):Keybind({ Default = "None", Flag = "flk_esp_enable_key" })
U.espBox:Toggle({
	Text = "Box",
	Flag = "flk_esp_box",
	Default = true,
	Callback = function(state) H.espSet("box", state) end,
})
	:ColorPicker({
		Flag = "flk_esp_box_color",
		Default = Color3.fromRGB(255, 60, 60),
		Callback = function(color, alpha)
			H.espPair("boxColor", color, alpha)
			H.espPair("box3dColor", color, alpha)
		end,
	})
	:Gear(function(panel)
		H.D(panel, "Style", "flk_esp_box_style", { "2D", "3D" }, "2D", function(value)
			H.espSet("box", value == "2D")
			H.espSet("box3d", value == "3D")
		end)
	end)
U.espBox:Toggle({
	Text = "Health Bar",
	Flag = "flk_esp_health_bar",
	Default = true,
	Callback = function(state) H.espSet("healthBar", state) end,
})
	:ColorPicker({ Flag = "flk_esp_health_healthy", Default = Color3.fromRGB(82, 197, 148), Callback = function(color) H.espSet("healthyColor", color) end })
	:ColorPicker({ Flag = "flk_esp_health_dying", Default = Color3.fromRGB(240, 90, 102), Callback = function(color) H.espSet("dyingColor", color) end })
U.espBox:Toggle({
	Text = "Skeleton",
	Flag = "flk_esp_skeleton",
	Default = false,
	Callback = function(state) H.espSet("skeleton", state) end,
}):ColorPicker({ Flag = "flk_esp_skeleton_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("skeletonColor", color, alpha) end })
U.espBox:Toggle({
	Text = "Tracers",
	Flag = "flk_esp_tracer",
	Default = false,
	Callback = function(state) H.espSet("tracer", state) end,
})
	:ColorPicker({ Flag = "flk_esp_tracer_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("tracerColor", color, alpha) end })
	:Gear(function(panel)
		H.D(panel, "Origin", "flk_esp_tracer_origin", { "Bottom", "Middle", "Top", "Mouse" }, "Bottom", function(value) H.espSet("tracerOrigin", value) end)
	end)
U.espBox:Toggle({
	Text = "Highlight",
	Flag = "flk_esp_chams",
	Default = false,
	Callback = function(state) H.espSet("chams", state) end,
}):ColorPicker({ Flag = "flk_esp_chams_color", Default = Color3.fromRGB(255, 60, 60), Callback = function(color, alpha) H.espPair("chamsFillColor", color, alpha) end })
U.espBox:Toggle({
	Text = "Off Screen Arrow",
	Flag = "flk_esp_arrow",
	Default = false,
	Callback = function(state) H.espSet("offScreenArrow", state) end,
}):ColorPicker({ Flag = "flk_esp_arrow_color", Default = Color3.new(1, 1, 1), Callback = function(color, alpha) H.espPair("offScreenArrowColor", color, alpha) end })

U.displayBox = U.Visuals:Section("Display", 2)
U.displayBox:Toggle({
	Text = "Name",
	Flag = "flk_esp_name",
	Default = true,
	Callback = function(state) H.espSet("name", state) end,
}):ColorPicker({ Flag = "flk_esp_name_color", Default = Color3.fromRGB(236, 241, 250), Callback = function(color, alpha) H.espPair("nameColor", color, alpha) end })
U.displayBox:Toggle({
	Text = "Distance",
	Flag = "flk_esp_distance",
	Default = true,
	Callback = function(state) H.espSet("distance", state) end,
}):ColorPicker({ Flag = "flk_esp_distance_color", Default = Color3.fromRGB(170, 184, 205), Callback = function(color, alpha) H.espPair("distanceColor", color, alpha) end })
U.displayBox:Toggle({
	Text = "Weapon",
	Flag = "flk_esp_weapon",
	Default = true,
	Callback = function(state) H.espSet("weapon", state) end,
}):ColorPicker({ Flag = "flk_esp_weapon_color", Default = Color3.fromRGB(255, 220, 100), Callback = function(color, alpha) H.espPair("weaponColor", color, alpha) end })
H.T(U.displayBox, "Health", "flk_esp_health_text", false, function(state) H.espSet("healthText", state) end)
H.T(U.displayBox, "Team Color", "flk_esp_team_color", false, function(state) Esp.sharedSettings.useTeamColor = state end)
H.T(U.displayBox, "Rainbow", "flk_esp_rainbow", false, function(state) Esp.sharedSettings.rainbow = state end)
H.S(U.displayBox, "Text Size", "flk_esp_text_size", 8, 24, 13, 0, function(value) Esp.sharedSettings.textSize = value end)
H.S(U.displayBox, "Max Distance", "flk_esp_max_distance", 100, 5000, 1500, 0, function(value) H.espSet("maxDistance", value) end, " studs")
U.displayBox:Toggle({
	Text = "Show Teammates",
	Flag = "flk_esp_allies",
	Default = false,
	Callback = function(state) Esp.teamSettings.friendly.enabled = state end,
}):ColorPicker({
	Flag = "flk_esp_ally_color",
	Default = Color3.fromRGB(0, 200, 255),
	Callback = function(color)
		Esp.teamSettings.friendly.boxColor = { color, 1 }
		Esp.teamSettings.friendly.nameColor = { color, 1 }
	end,
})

local SaveManager = Library.SaveManager
local InterfaceManager = Library.InterfaceManager
local ThemeManager = Library.ThemeManager

SaveManager:SetLibrary(Library)
InterfaceManager:SetLibrary(Library)
InterfaceManager:SetWindow(Window)
ThemeManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
InterfaceManager:SetFolder("Facility")
ThemeManager:SetFolder("Facility")
SaveManager:SetFolder("Facility/8795154789")

InterfaceManager:BuildInterfaceSection(U.Settings, 1)
SaveManager:BuildConfigSection(U.Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(U.Combat)

Library:Notify("Facility", "Flick loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
