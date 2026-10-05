--!nocheck
--!nolint UnknownGlobal

local F       = shared.Facility
local Library = F.Library
local Entity  = F.Entity
local Esp     = F.Esp

local AIMBOT_URL = "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/CModules/FAimbot.luau"

local MOVEMENT_URL = "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/CModules/FMovement.luau"

local function fetchModule(url, label)
	local ok, result = pcall(function()
		return loadstring(game:HttpGet(url .. "?v=" .. tostring(tick()):gsub("%.", "")))()
	end)

	if not ok or type(result) ~= "table" then
		warn("Facility: could not load " .. label .. " from " .. url)
		return nil
	end

	return result
end

local Aimbot = fetchModule(AIMBOT_URL, "aimbot")
local Movement = fetchModule(MOVEMENT_URL, "movement")

if Movement then Movement:Load() end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Camera = workspace.CurrentCamera

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Camera = workspace.CurrentCamera
end)

local Window = Library:Window({
	Title             = "Facility",
	Suffix            = ".esp",
	Width             = 700,
	Height            = 580,
	MinWidth          = 580,
	SectionTitleStyle = "border",
})

local Combat   = Window:Tab("Combat", "crosshair")
local Movements = Window:Tab("Movement", "move")
local Visuals  = Window:Tab("Visuals", "eye")
local Settings = Window:Tab("Settings", "cog")

local LocalPlayer = Players.LocalPlayer

local function factionOf(player)
	local data = player:FindFirstChild("PersonalFactionData")
	local value = data and data:FindFirstChild("PersonalFaction")
	return value and value.Value or nil
end

function Entity:IsTargetable(player)
	if player == LocalPlayer then return false end
	if self.Settings.TeamCheck == "Off" then return true end

	local mine, theirs = factionOf(LocalPlayer), factionOf(player)

	if mine == nil or theirs == nil then return true end

	return mine ~= theirs
end

task.spawn(function()
	while task.wait(1) do
		pcall(function() Entity:RefreshTargets() end)
	end
end)

local PLAYER_TEAMS = { "enemy", "friendly", "whitelist" }

local function set(key, value)
	for _, name in ipairs(PLAYER_TEAMS) do
		local team = Esp.teamSettings[name]
		if team then team[key] = value end
	end
end

local function setPair(key, color, alpha)
	local pair = { color, alpha ~= nil and (1 - alpha) or 1 }
	Esp.teamSettings.enemy[key] = pair
end

Esp.teamSettings.enemy.enabled = true
Esp.teamSettings.friendly.enabled = false
Esp.teamSettings.friendly.boxColor = { Color3.fromRGB(80, 200, 120), 1 }
Esp.teamSettings.friendly.nameColor = { Color3.fromRGB(80, 200, 120), 1 }

local VEHICLE_FOLDERS = {
	["Tank Workspace"]       = "tank",
	["Submarine Workspace"]  = "submarine",
	["RC Workspace"]         = "rc",
	["Plane Workspace"]      = "plane",
	["Vehicle Workspace"]    = "vehicle",
	["Helicopter Workspace"] = "helicopter",
	["Drone Workspace"]      = "drone",
}

local VEHICLE_COLORS = {
	tank       = Color3.fromRGB(200, 120, 60),
	submarine  = Color3.fromRGB(60, 160, 200),
	rc         = Color3.fromRGB(200, 200, 90),
	plane      = Color3.fromRGB(120, 200, 255),
	vehicle    = Color3.fromRGB(180, 180, 180),
	helicopter = Color3.fromRGB(150, 110, 220),
	drone      = Color3.fromRGB(120, 230, 150),
}

for key, color in pairs(VEHICLE_COLORS) do
	Esp:AddTeam(key, {
		enabled      = false,
		box          = true,
		boxColor     = { color, 1 },
		name         = true,
		nameColor    = { color, 1 },
		distance     = true,
		healthBar    = true,
		healthText   = true,
		healthyColor = color,
		dyingColor   = Color3.fromRGB(255, 70, 70),
		maxDistance  = 5000,
	})
end

local vehicles = {}

local function untrackVehicle(model)
	if not vehicles[model] then return end
	vehicles[model] = nil
	pcall(function() Esp:RemoveInstance(model) end)
end

local function trackVehicle(model, kind)
	if vehicles[model] then return end
	if not model:IsA("Model") and not model:IsA("BasePart") then return end

	task.spawn(function()
		local anchor = model:IsA("Model")
			and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true))
			or model

		if not anchor then
			local deadline = tick() + 5
			repeat
				task.wait(0.1)
				anchor = model:IsA("Model")
					and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true))
					or model
			until anchor or tick() > deadline or model.Parent == nil
		end

		if not anchor or model.Parent == nil then return end

		vehicles[model] = kind

		Esp:AddInstance(model, {
			Team      = kind,
			Text      = model.Name,
			Health    = "Health",
			MaxHealth = "MaxHealth",
		})

		model.AncestryChanged:Connect(function()
			if model.Parent == nil then untrackVehicle(model) end
		end)
	end)
end

task.spawn(function()
	local systems = workspace:WaitForChild("Game Systems", 30)
	if not systems then
		warn("Facility: Game Systems not found, vehicle esp disabled")
		return
	end

	for folderName, kind in pairs(VEHICLE_FOLDERS) do
		local folder = systems:FindFirstChild(folderName)
		if folder then
			for _, model in ipairs(folder:GetChildren()) do
				trackVehicle(model, kind)
			end
			folder.ChildAdded:Connect(function(model) trackVehicle(model, kind) end)
			folder.ChildRemoved:Connect(untrackVehicle)
		end
	end
end)

if Movement then

Movement.Settings.WalkSpeedMode = "Velocity"
Movement.Settings.JumpMode = "Humanoid"

local flyBox = Movements:Section("Fly", 1)

flyBox:Toggle({
	Text = "Fly",
	Flag = "move_fly",
	Default = false,
	Callback = function(state) Movement:Fly(state) end,
})
	:Keybind({ Default = "F", Flag = "move_fly_key" })

flyBox:Slider({
	Text = "Speed",
	Flag = "move_fly_speed",
	Min = 1, Max = 20, Default = 2,
	Decimals = 1,
	Callback = function(value) Movement.Settings.FlySpeed = value end,
})

flyBox:Toggle({
	Text = "Vehicle Fly",
	Flag = "move_vehicle_fly",
	Default = false,
	Callback = function(state) Movement:VehicleFly(state) end,
})

flyBox:Slider({
	Text = "Vehicle Speed",
	Flag = "move_vehicle_fly_speed",
	Min = 1, Max = 20, Default = 2,
	Decimals = 1,
	Callback = function(value) Movement.Settings.VehicleFlySpeed = value end,
})

local speedBox = Movements:Section("Speed", 2)

speedBox:Toggle({
	Text = "Walk Speed",
	Flag = "move_walkspeed",
	Default = false,
	Callback = function(state)
		Movement:WalkSpeed(state and Movement.Settings.WalkSpeed or 16)
	end,
})

speedBox:Slider({
	Text = "Value",
	Flag = "move_walkspeed_value",
	Min = 16, Max = 300, Default = 16,
	Callback = function(value)
		Movement.Settings.WalkSpeed = value
		if Library.Flags["move_walkspeed"] then Movement:WalkSpeed(value) end
	end,
})

local jumpBox = Movements:Section("Jump", 2)

jumpBox:Toggle({
	Text = "Jump Power",
	Flag = "move_jumppower",
	Default = false,
	Callback = function(state)
		Movement:JumpPower(state and Movement.Settings.JumpPower or 50)
	end,
})

jumpBox:Slider({
	Text = "Value",
	Flag = "move_jumppower_value",
	Min = 50, Max = 500, Default = 50,
	Callback = function(value)
		Movement.Settings.JumpPower = value
		if Library.Flags["move_jumppower"] then Movement:JumpPower(value) end
	end,
})

jumpBox:Toggle({
	Text = "Infinite Jump",
	Flag = "move_infinite_jump",
	Default = false,
	Callback = function(state) Movement:InfiniteJump(state) end,
})

local otherBox = Movements:Section("Other", 1)

otherBox:Toggle({
	Text = "Noclip",
	Flag = "move_noclip",
	Default = false,
	Callback = function(state) Movement:Noclip(state) end,
})
	:Keybind({ Default = "N", Flag = "move_noclip_key" })

otherBox:Toggle({
	Text = "Noclip Vehicle",
	Flag = "move_noclip_vehicle",
	Default = false,
	Callback = function(state) Movement.Settings.NoclipVehicle = state end,
})

local noFallApplied = false

local function applyNoFallDamage()
	if noFallApplied then return true end

	if not (getrawmetatable and setreadonly and getnamecallmethod) then
		Library:Error("Movement", "Your executor does not support metatable hooks.", 8)
		return false
	end

	local ok, err = pcall(function()
		local engine = ReplicatedStorage:WaitForChild("ACS_Engine", 5)
		local events = engine and engine:WaitForChild("Events", 5)
		local fdmg = events and events:WaitForChild("FDMG", 5)
		if not fdmg then error("FDMG not found") end

		local mt = getrawmetatable(game)
		setreadonly(mt, false)

		local oldNamecall = mt.__namecall
		mt.__namecall = function(self, ...)
			if noFallApplied and self == fdmg
				and getnamecallmethod() == "FireServer" then
				return nil
			end
			return oldNamecall(self, ...)
		end

		setreadonly(mt, true)
	end)

	if not ok then
		Library:Error("Movement", "No fall damage failed: " .. tostring(err), 8)
		return false
	end

	noFallApplied = true
	return true
end

otherBox:Toggle({
	Text = "No Fall Damage",
	Flag = "move_no_fall",
	Default = false,
	Callback = function(state)
		if state then
			if not applyNoFallDamage() then return end
		end
		noFallApplied = state
	end,
})

otherBox:Toggle({
	Text = "Swim",
	Flag = "move_swim",
	Default = false,
	Callback = function(state) Movement:Swim(state) end,
})

otherBox:Toggle({
	Text = "Float",
	Flag = "move_float",
	Default = false,
	Callback = function(state) Movement:Float(state) end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Height",
			Flag = "move_float_height",
			Min = 1, Max = 10, Default = 3.1,
			Decimals = 1,
			Callback = function(value) Movement.Settings.FloatHeight = value end,
		})
	end)

otherBox:Toggle({
	Text = "Spider",
	Flag = "move_spider",
	Default = false,
	Callback = function(state) Movement:Spider(state) end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Climb Speed",
			Flag = "move_spider_speed",
			Min = 0.5, Max = 5, Default = 1,
			Decimals = 1,
			Callback = function(value) Movement.Settings.SpiderSpeed = value end,
		})
	end)

end

local espBox = Visuals:Section("Esp", 1)

espBox:Toggle({
	Text = "Enable",
	Flag = "esp_enable",
	Default = false,
	Callback = function(state)
		if state then
			pcall(function() Esp:Load(Entity) end)
		else
			pcall(function() Esp:Unload() end)
		end
	end,
})
	:Keybind({ Default = "RightAlt", Flag = "esp_enable_key" })

espBox:Toggle({
	Text = "Box",
	Flag = "esp_box",
	Default = true,
	Callback = function(state) set("box", state) end,
})
	:ColorPicker({
		Flag = "esp_box_outline_color",
		Default = Color3.new(0, 0, 0),
		Callback = function(color, alpha) setPair("boxOutlineColor", color, alpha) end,
	})
	:ColorPicker({
		Flag = "esp_box_color",
		Default = Color3.fromRGB(255, 60, 60),
		Callback = function(color, alpha)
			setPair("boxColor", color, alpha)
			setPair("box3dColor", color, alpha)
		end,
	})
	:Gear(function(panel)
		panel:Dropdown({
			Text = "Style",
			Flag = "esp_box_style",
			Options = { "2D", "3D" },
			Default = "2D",
			Callback = function(value)
				set("box", value == "2D")
				set("box3d", value == "3D")
			end,
		})
		panel:Toggle({
			Text = "Filled",
			Flag = "esp_box_fill",
			Default = false,
			Callback = function(state) set("boxFill", state) end,
		})
			:ColorPicker({
				Flag = "esp_box_fill_color",
				Default = Color3.fromRGB(255, 60, 60),
				DefaultAlpha = 0.5,
				Callback = function(color, alpha) setPair("boxFillColor", color, alpha) end,
			})
	end)

espBox:Toggle({
	Text = "Health Bar",
	Flag = "esp_health_bar",
	Default = true,
	Callback = function(state) set("healthBar", state) end,
})
	:ColorPicker({
		Flag = "esp_health_healthy",
		Default = Color3.new(0, 1, 0),
		Alpha = false,
		Callback = function(color) set("healthyColor", color) end,
	})
	:ColorPicker({
		Flag = "esp_health_dying",
		Default = Color3.new(1, 0, 0),
		Alpha = false,
		Callback = function(color) set("dyingColor", color) end,
	})

espBox:Toggle({
	Text = "Tracers",
	Flag = "esp_tracer",
	Default = false,
	Callback = function(state) set("tracer", state) end,
})
	:ColorPicker({
		Flag = "esp_tracer_color",
		Default = Color3.new(1, 1, 1),
		Callback = function(color, alpha) setPair("tracerColor", color, alpha) end,
	})
	:Gear(function(panel)
		panel:Dropdown({
			Text = "Origin",
			Flag = "esp_tracer_origin",
			Options = { "Bottom", "Middle", "Top", "Mouse" },
			Default = "Bottom",
			Callback = function(value) set("tracerOrigin", value) end,
		})
	end)

espBox:Toggle({
	Text = "Skeleton",
	Flag = "esp_skeleton",
	Default = false,
	Callback = function(state) set("skeleton", state) end,
})
	:ColorPicker({
		Flag = "esp_skeleton_color",
		Default = Color3.new(1, 1, 1),
		Callback = function(color, alpha) setPair("skeletonColor", color, alpha) end,
	})

espBox:Toggle({
	Text = "Chams",
	Flag = "esp_chams",
	Default = false,
	Callback = function(state) set("chams", state) end,
})
	:ColorPicker({
		Flag = "esp_chams_outline",
		Default = Color3.new(1, 1, 1),
		Callback = function(color, alpha) setPair("chamsOutlineColor", color, alpha) end,
	})
	:ColorPicker({
		Flag = "esp_chams_fill",
		Default = Color3.fromRGB(255, 60, 60),
		DefaultAlpha = 0.5,
		Callback = function(color, alpha) setPair("chamsFillColor", color, alpha) end,
	})

espBox:Toggle({
	Text = "Off Screen Arrow",
	Flag = "esp_arrow",
	Default = false,
	Callback = function(state) set("offScreenArrow", state) end,
})
	:ColorPicker({
		Flag = "esp_arrow_color",
		Default = Color3.new(1, 1, 1),
		Callback = function(color, alpha) setPair("offScreenArrowColor", color, alpha) end,
	})
	:Gear(function(panel)
		panel:Slider({
			Text = "Size",
			Flag = "esp_arrow_size",
			Min = 5, Max = 40, Default = 15,
			Callback = function(value) set("offScreenArrowSize", value) end,
		})
		panel:Slider({
			Text = "Radius",
			Flag = "esp_arrow_radius",
			Min = 50, Max = 400, Default = 150,
			Callback = function(value) set("offScreenArrowRadius", value) end,
		})
	end)

local aimBox = Combat:Section("Aimbot", 1)

aimBox:Toggle({
	Text = "Enable",
	Flag = "aim_enable",
	Default = false,
	Callback = function(state)
		if state then
			pcall(function() Aimbot:Load(Entity) end)
		end
		Aimbot.Enabled = state
	end,
})

aimBox:Keybind({
	Text = "Aim Key",
	Flag = "aim_key",
	Default = "MB2",
	Mode = "toggle",
	OnChanged = function(key)
		local map = {
			MB1 = Enum.UserInputType.MouseButton1,
			MB2 = Enum.UserInputType.MouseButton2,
			MB3 = Enum.UserInputType.MouseButton3,
		}
		Aimbot:SetKey(map[key] or Enum.KeyCode[key] or Enum.UserInputType.MouseButton2)
	end,
})

aimBox:Toggle({
	Text = "Toggle Mode",
	Flag = "aim_toggle_mode",
	Default = false,
	Callback = function(state) Aimbot.Settings.ToggleMode = state end,
})

aimBox:Dropdown({
	Text = "Priority",
	Flag = "aim_priority",
	Options = { "Cursor", "Closest", "LowestHealth" },
	Default = "Cursor",
	Callback = function(value) Aimbot.Settings.Priority = value end,
})

aimBox:Dropdown({
	Text = "Target Part",
	Flag = "aim_parts",
	Options = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart", "Torso" },
	Default = { "Head" },
	Multi = true,
	Empty = "Head",
	Callback = function(selected)
		if #selected == 0 then selected = { "Head" } end
		Aimbot.Settings.Parts = selected
	end,
})

aimBox:Slider({
	Text = "Smoothness",
	Flag = "aim_smoothness",
	Min = 0.05, Max = 1, Default = 0.25,
	Decimals = 2,
	Callback = function(value)
		Aimbot.Settings.Smoothness = value
		Aimbot.Settings.Sensitivity = value
	end,
})

aimBox:Dropdown({
	Text = "Easing Style",
	Flag = "aim_easing_style",
	Options = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Back" },
	Default = "Quad",
	Callback = function(value) Aimbot.Settings.EasingStyle = value end,
})

aimBox:Dropdown({
	Text = "Easing Direction",
	Flag = "aim_easing_direction",
	Options = { "In", "Out", "InOut" },
	Default = "Out",
	Callback = function(value) Aimbot.Settings.EasingDirection = value end,
})

aimBox:Slider({
	Text = "Switch Delay",
	Flag = "aim_switch_delay",
	Min = 0, Max = 2, Default = 0,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) Aimbot.Settings.SwitchDelay = value end,
})

aimBox:Slider({
	Text = "Max Distance",
	Flag = "aim_max_distance",
	Min = 100, Max = 5000, Default = 2000,
	Suffix = " studs",
	Callback = function(value) Aimbot.Settings.MaxDistance = value end,
})

local fovBox = Combat:Section("Fov", 2)

fovBox:Toggle({
	Text = "Fov",
	Flag = "aim_fov_enabled",
	Default = true,
	Callback = function(state)
		Aimbot.Settings.FovCheck = state
		Aimbot.Settings.FovVisible = state
	end,
})
	:ColorPicker({
		Flag = "aim_fov_color",
		Default = Color3.fromRGB(255, 255, 255),
		Callback = function(color) Aimbot.Settings.FovColor = color end,
	})
	:ColorPicker({
		Flag = "aim_fov_lock_color",
		Default = Color3.fromRGB(255, 70, 70),
		Callback = function(color) Aimbot.Settings.FovLockColor = color end,
	})

fovBox:Slider({
	Text = "Radius",
	Flag = "aim_fov",
	Min = 20, Max = 600, Default = 120,
	Callback = function(value) Aimbot:SetFov(value) end,
})

fovBox:Slider({
	Text = "Thickness",
	Flag = "aim_fov_thickness",
	Min = 1, Max = 5, Default = 1,
	Callback = function(value) Aimbot.Settings.FovThickness = value end,
})

fovBox:Slider({
	Text = "Transparency",
	Flag = "aim_fov_transparency",
	Min = 0, Max = 1, Default = 0.4,
	Decimals = 2,
	Callback = function(value) Aimbot.Settings.FovTransparency = value end,
})

fovBox:Toggle({
	Text = "Filled",
	Flag = "aim_fov_filled",
	Default = false,
	Callback = function(state) Aimbot.Settings.FovFilled = state end,
})

local behaviourBox = Combat:Section("Behaviour", 2)

behaviourBox:Toggle({
	Text = "Team Check",
	Flag = "aim_team_check",
	Default = true,
	Callback = function(state) Aimbot.Settings.TeamCheck = state end,
})

behaviourBox:Toggle({
	Text = "Wall Check",
	Flag = "aim_wall_check",
	Default = false,
	Callback = function(state) Aimbot.Settings.WallCheck = state end,
})

behaviourBox:Toggle({
	Text = "Ignore Downed",
	Flag = "aim_ignore_downed",
	Default = false,
	Callback = function(state) Aimbot.Settings.IgnoreDowned = state end,
})

behaviourBox:Toggle({
	Text = "Ignore Forcefield",
	Flag = "aim_ignore_forcefield",
	Default = false,
	Callback = function(state) Aimbot.Settings.IgnoreForcefield = state end,
})

behaviourBox:Slider({
	Text = "Deadzone",
	Flag = "aim_deadzone",
	Min = 0, Max = 200, Default = 0,
	Callback = function(value) Aimbot.Settings.Deadzone = value end,
})

behaviourBox:Toggle({
	Text = "Target Line",
	Flag = "aim_target_line",
	Default = false,
	Callback = function(state) Aimbot.Settings.TargetLine = state end,
})
	:ColorPicker({
		Flag = "aim_target_line_color",
		Default = Color3.fromRGB(255, 70, 70),
		Callback = function(color) Aimbot.Settings.TargetLineColor = color end,
	})
	:Gear(function(panel)
		panel:Slider({
			Text = "Thickness",
			Flag = "aim_target_line_thickness",
			Min = 1, Max = 5, Default = 1,
			Callback = function(value) Aimbot.Settings.TargetLineThickness = value end,
		})
	end)

behaviourBox:Toggle({
	Text = "Target Info",
	Flag = "aim_target_info",
	Default = false,
	Callback = function(state) Aimbot.Settings.TargetInfo = state end,
})
	:ColorPicker({
		Flag = "aim_target_info_color",
		Default = Color3.fromRGB(255, 255, 255),
		Callback = function(color) Aimbot.Settings.TargetInfoColor = color end,
	})
	:Gear(function(panel)
		panel:Slider({
			Text = "Text Size",
			Flag = "aim_target_info_size",
			Min = 8, Max = 24, Default = 13,
			Callback = function(value) Aimbot.Settings.TargetInfoSize = value end,
		})
	end)

behaviourBox:Toggle({
	Text = "Sticky Target",
	Flag = "aim_sticky",
	Default = true,
	Callback = function(state) Aimbot.Settings.Sticky = state end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Hold Fov",
			Flag = "aim_sticky_fov",
			Min = 1, Max = 3, Default = 1.6,
			Decimals = 1,
			Callback = function(value) Aimbot.Settings.StickyFov = value end,
		})
	end)

behaviourBox:Toggle({
	Text = "Prediction",
	Flag = "aim_prediction",
	Default = false,
	Callback = function(state) Aimbot.Settings.Prediction = state end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Time",
			Flag = "aim_prediction_time",
			Min = 0, Max = 0.5, Default = 0.12,
			Decimals = 2,
			Suffix = " s",
			Callback = function(value) Aimbot.Settings.PredictionTime = value end,
		})
	end)

local SilentAim = {
	Enabled = false,
	IgnoreSeated = false,
	Hooked = false,
	HitChance = 100,
	HitPart = "Head",
	RandomPart = false,
	Fov = 0,
}

local SILENT_PARTS = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart" }

local function silentRoll()
	local chance = SilentAim.HitChance
	if chance >= 100 then return true end
	if chance <= 0 then return false end
	return math.random(1, 100) <= chance
end

local function silentPart(record)
	local character = record.Character
	if not character then return nil end

	local name = SilentAim.HitPart
	if SilentAim.RandomPart then
		name = SILENT_PARTS[math.random(1, #SILENT_PARTS)]
	end

	local part = character:FindFirstChild(name)
	if part and part:IsA("BasePart") then return part end

	return record.Head or record.RootPart
end

local function silentTarget(origin)
	if not Entity then return nil end

	local settings = Aimbot.Settings
	local center = Camera.ViewportSize * 0.5
	local cursor = UserInputService:GetMouseLocation()
	local aim = settings.Mode == "Mouse"
		and Vector2.new(cursor.X, cursor.Y)
		or Vector2.new(center.X, center.Y)

	local best, bestPart, bestScore = nil, nil, math.huge

	for _, record in ipairs(Entity:GetAll(settings.TeamCheck)) do
		local humanoid = record.Humanoid
		local seated = humanoid ~= nil and humanoid.SeatPart ~= nil

		if not (SilentAim.IgnoreSeated and seated) then
			if not settings.AliveCheck or (record.Health or 1) > 0 then
				local part = silentPart(record)

				if part then
					local screen, onScreen = Camera:WorldToViewportPoint(part.Position)

					if onScreen then
						local flat = Vector2.new(screen.X, screen.Y)
						local fromAim = (flat - aim).Magnitude
						local distance = (origin - part.Position).Magnitude

						local radius = SilentAim.Fov > 0 and SilentAim.Fov or settings.Fov
						local inFov = not settings.FovCheck or fromAim <= radius
						local inRange = distance <= settings.MaxDistance

						if inFov and inRange and Aimbot:_visible(record, part) then
							if fromAim < bestScore then
								best, bestPart, bestScore = record, part, fromAim
							end
						end
					end
				end
			end
		end
	end

	if not bestPart then return nil end
	if not silentRoll() then return nil end

	if settings.Prediction then
		local velocity = bestPart.AssemblyLinearVelocity
		if velocity.Magnitude > 0.1 then
			return bestPart.Position + velocity * settings.PredictionTime
		end
	end

	return bestPart.Position
end

local function hookSilentAim()
	if SilentAim.Hooked then return true end

	if not (hookfunction and require) then
		Library:Error("Silent Aim", "Your executor does not support hookfunction.", 8)
		return false
	end

	local bulletSystem = ReplicatedStorage:FindFirstChild("BulletFireSystem")
	if not bulletSystem then
		Library:Error("Silent Aim", "BulletFireSystem not found.", 8)
		return false
	end

	local fastCast = bulletSystem:FindFirstChild("FastCastRedux")
	local activeCastModule = fastCast and fastCast:FindFirstChild("ActiveCast")
	if not activeCastModule then
		Library:Error("Silent Aim", "ActiveCast module not found.", 8)
		return false
	end

	local ok, activeCast = pcall(require, activeCastModule)
	if not ok then
		Library:Error("Silent Aim", "Could not read ActiveCast.", 8)
		return false
	end

	local original
	original = hookfunction(rawget(activeCast, "new"), function(caster, origin, direction, velocity, ...)
		if SilentAim.Enabled then
			local target = silentTarget(origin)
			if target then
				local newDirection = target - origin
				return original(caster, origin, newDirection, newDirection.Unit * 9e9, ...)
			end
		end
		return original(caster, origin, direction, velocity, ...)
	end)

	SilentAim.Hooked = true
	return true
end

local GunMod = {
	Settings = {
		InfiniteAmmo = false,
		AmmoValue = 9999,
		NoRecoil = false,
		InfiniteDistance = false,
		DistanceValue = 20000,
		BulletSpeed = 9999,
		NoDrop = true,
		NoSpread = false,
	},
	Hooked = false,
}

local function patchGunConfig(config)
	if type(config) ~= "table" then return config end

	local settings = GunMod.Settings

	if settings.InfiniteAmmo then
		local amount = settings.AmmoValue
		config.Ammo = amount
		config.StoredAmmo = amount
		config.MagCount = amount
		config.IncludeChamberedBullet = true
	end

	if settings.NoRecoil then
		config.RecoilPunch = 0
		config.VPunchBase = 0
		config.MaxRecoilPower = 0
		config.RecoilPowerStepAmount = 0
		config.CamRecoilPower = 0
		config.AimRecoilReduction = 1
		config.PunchRecover = 1
		config.AimRecover = 1

		if type(config.VRecoil) == "table" then config.VRecoil = { 0, 0 } end
		if type(config.HRecoil) == "table" then config.HRecoil = { 0, 0 } end
	end

	if settings.InfiniteDistance then
		config.Distance = settings.DistanceValue
		config.BSpeed = settings.BulletSpeed
		if settings.NoDrop then config.BDrop = 0 end
	end

	if settings.NoSpread then
		config.MinSpread = 0
		config.MaxSpread = 0
		config.AimInaccuracyStepAmount = 0
		config.WalkMultiplier = 0
	end

	return config
end

local function hookGunMod()
	if GunMod.Hooked then return true end

	if not (hookmetamethod and getnamecallmethod) then
		Library:Error("Weapon", "Your executor does not support metamethod hooks.", 8)
		return false
	end

	local engine = ReplicatedStorage:FindFirstChild("ACS_Engine")
	local events = engine and engine:FindFirstChild("Events")
	local equip = events and events:FindFirstChild("Equip")

	if not equip then
		Library:Error("Weapon", "ACS_Engine.Events.Equip not found.", 8)
		return false
	end

	GunMod.Event = equip

	local original
	original = hookmetamethod(game, "__namecall", function(self, ...)
		if rawequal(self, equip) and getnamecallmethod() == "FireServer" then
			local gun, config = ...
			if type(config) == "table" then
				patchGunConfig(config)
				return original(self, gun, config)
			end
		end
		return original(self, ...)
	end)

	GunMod.Hooked = true
	return true
end

local function reequipGun()
	local character = LocalPlayer.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

	if not tool or not backpack then return false end

	tool.Parent = backpack
	task.wait(0.15)
	tool.Parent = character
	return true
end

local function applyGunMod()
	if not hookGunMod() then return false end
	task.spawn(reequipGun)
	return true
end

local gunBox = Combat:Section("Weapon", 1)

gunBox:Toggle({
	Text = "Infinite Ammo",
	Flag = "gun_infinite_ammo",
	Default = false,
	Callback = function(state)
		GunMod.Settings.InfiniteAmmo = state
		applyGunMod()
	end,
})

gunBox:Toggle({
	Text = "No Recoil",
	Flag = "gun_no_recoil",
	Default = false,
	Callback = function(state)
		GunMod.Settings.NoRecoil = state
		applyGunMod()
	end,
})

gunBox:Toggle({
	Text = "Infinite Distance",
	Flag = "gun_infinite_distance",
	Default = false,
	Callback = function(state)
		GunMod.Settings.InfiniteDistance = state
		applyGunMod()
	end,
})

gunBox:Toggle({
	Text = "No Spread",
	Flag = "gun_no_spread",
	Default = false,
	Callback = function(state)
		GunMod.Settings.NoSpread = state
		applyGunMod()
	end,
})

gunBox:Button({
	Text = "Reapply",
	Callback = function()
		if applyGunMod() then
			Library:Success("Weapon", "Patch reapplied to the held gun.", 3)
		end
	end,
})

local silentBox = Combat:Section("Silent Aim", 2)

silentBox:Toggle({
	Text = "Enable",
	Flag = "silent_enable",
	Default = false,
	Callback = function(state)
		if state and not SilentAim.Hooked then
			if not hookSilentAim() then
				SilentAim.Enabled = false
				return
			end
		end
		SilentAim.Enabled = state
	end,
})

silentBox:Toggle({
	Text = "Ignore Seated",
	Flag = "silent_ignore_seated",
	Default = false,
	Callback = function(state) SilentAim.IgnoreSeated = state end,
})

silentBox:Slider({
	Text = "Own Fov",
	Flag = "silent_fov",
	Min = 0, Max = 600, Default = 0,
	Callback = function(value) SilentAim.Fov = value end,
})

silentBox:Slider({
	Text = "Hit Chance",
	Flag = "silent_hit_chance",
	Min = 0, Max = 100, Default = 100,
	Suffix = "%",
	Callback = function(value) SilentAim.HitChance = value end,
})

silentBox:Dropdown({
	Text = "Hit Part",
	Flag = "silent_hit_part",
	Options = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart" },
	Default = "Head",
	Callback = function(value) SilentAim.HitPart = value end,
})

silentBox:Toggle({
	Text = "Random Part",
	Flag = "silent_random_part",
	Default = false,
	Callback = function(state) SilentAim.RandomPart = state end,
})

silentBox:Label("Own Fov at 0 reuses the aimbot fov", { Style = "dim" })

local triggerBox = Combat:Section("Trigger Bot", 1)

triggerBox:Toggle({
	Text = "Enable",
	Flag = "trigger_enable",
	Default = false,
	Callback = function(state) Aimbot.Settings.TriggerBot = state end,
})

triggerBox:Slider({
	Text = "Hold",
	Flag = "trigger_delay",
	Min = 0.01, Max = 0.5, Default = 0.08,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) Aimbot.Settings.TriggerDelay = value end,
})

triggerBox:Slider({
	Text = "Cooldown",
	Flag = "trigger_cooldown",
	Min = 0.05, Max = 2, Default = 0.25,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) Aimbot.Settings.TriggerCooldown = value end,
})

local checkBox = Visuals:Section("Check", 2)

checkBox:Toggle({
	Text = "Team Check",
	Flag = "esp_team_check",
	Default = true,
	Callback = function(state)
		Entity.Settings.TeamCheck = state and "Team" or "Off"
		Entity:RefreshTargets()
	end,
})
	:Gear(function(panel)
		panel:Dropdown({
			Text = "Allies",
			Flag = "esp_allies_mode",
			Options = { "Visible", "Hidden" },
			Default = "Hidden",
			Callback = function(value)
				Esp.teamSettings.friendly.enabled = value == "Visible"
			end,
		})
		panel:ColorPicker({
			Text = "Ally Color",
			Flag = "esp_ally_color",
			Default = Color3.fromRGB(80, 200, 120),
			Callback = function(color, alpha)
				local a = 1 - (alpha or 1)
				Esp.teamSettings.friendly.boxColor = { color, a }
				Esp.teamSettings.friendly.nameColor = { color, a }
				Esp.teamSettings.friendly.chamsFillColor = { color, 0.5 }
			end,
		})
	end)

checkBox:Toggle({
	Text = "Wall Check",
	Flag = "esp_wall_check",
	Default = false,
	Callback = function(state) set("wallCheck", state) end,
})

checkBox:Toggle({
	Text = "Alive Check",
	Flag = "esp_alive_check",
	Default = true,
	Callback = function(state) Esp.sharedSettings.aliveCheck = state end,
})

checkBox:Slider({
	Text = "Max Distance",
	Flag = "esp_max_distance",
	Min = 100, Max = 10000, Default = 5000,
	Suffix = " studs",
	Callback = function(value) set("maxDistance", value) end,
})

checkBox:Divider()

local playerIds = {}

local function playerNames()
	local names = {}
	table.clear(playerIds)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= Players.LocalPlayer then
			local label = other.DisplayName
			if other.DisplayName ~= other.Name then
				label = other.DisplayName .. " (@" .. other.Name .. ")"
			end
			playerIds[label] = other.UserId
			table.insert(names, label)
		end
	end
	table.sort(names)
	return names
end

local whitelistDropdown

checkBox:Toggle({
	Text = "Whitelist",
	Flag = "esp_whitelist",
	Default = true,
	Callback = function(state)
		Esp.sharedSettings.whitelistMode = state and "highlight" or "filter"
	end,
})
	:Gear(function(panel)
		panel:Dropdown({
			Text = "Mode",
			Flag = "esp_whitelist_mode",
			Options = { "Highlight", "Filter" },
			Default = "Highlight",
			Callback = function(value)
				Esp.sharedSettings.whitelistMode = value == "Filter" and "filter" or "highlight"
			end,
		})
		panel:Button({
			Text = "Clear List",
			Callback = function()
				table.clear(Esp.whitelist)
				if whitelistDropdown then whitelistDropdown:Set({}, true) end
				Library:Notify("Facility", "Whitelist cleared.", 3)
			end,
		})
	end)

whitelistDropdown = checkBox:Dropdown({
	Text = "Players",
	Flag = "esp_whitelist_players",
	Options = playerNames(),
	Multi = true,
	Default = {},
	Empty = "Nobody",
	Callback = function(selected)
		table.clear(Esp.whitelist)
		for _, label in ipairs(selected) do
			local id = playerIds[label]
			if id then table.insert(Esp.whitelist, id) end
		end
	end,
})

checkBox:Button({
	Text = "Refresh Players",
	Callback = function() whitelistDropdown:SetOptions(playerNames()) end,
})

Players.PlayerAdded:Connect(function()
	task.wait(1)
	whitelistDropdown:SetOptions(playerNames())
end)

Players.PlayerRemoving:Connect(function()
	task.wait(1)
	whitelistDropdown:SetOptions(playerNames())
end)

local vehicleBox = Visuals:Section("Vehicles", 1)

local VEHICLE_LABELS = {
	{ "tank",       "Tanks" },
	{ "submarine",  "Submarines" },
	{ "plane",      "Planes" },
	{ "helicopter", "Helicopters" },
	{ "vehicle",    "Vehicles" },
	{ "drone",      "Drones" },
	{ "rc",         "RC" },
}

vehicleBox:Toggle({
	Text = "All Vehicles",
	Flag = "esp_vehicles_all",
	Default = false,
	Callback = function(state)
		for key in pairs(VEHICLE_COLORS) do
			Esp.teamSettings[key].enabled = state
		end
	end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Max Distance",
			Flag = "esp_vehicle_distance",
			Min = 500, Max = 10000, Default = 5000,
			Suffix = " studs",
			Callback = function(value)
				for key in pairs(VEHICLE_COLORS) do
					Esp.teamSettings[key].maxDistance = value
				end
			end,
		})
		panel:Toggle({
			Text = "Names",
			Flag = "esp_vehicle_names",
			Default = true,
			Callback = function(state)
				for key in pairs(VEHICLE_COLORS) do
					Esp.teamSettings[key].name = state
				end
			end,
		})
		panel:Toggle({
			Text = "Health Bar",
			Flag = "esp_vehicle_health_bar",
			Default = true,
			Callback = function(state)
				for key in pairs(VEHICLE_COLORS) do
					Esp.teamSettings[key].healthBar = state
				end
			end,
		})
		panel:Toggle({
			Text = "Health Text",
			Flag = "esp_vehicle_health_text",
			Default = true,
			Callback = function(state)
				for key in pairs(VEHICLE_COLORS) do
					Esp.teamSettings[key].healthText = state
				end
			end,
		})
	end)

for _, entry in ipairs(VEHICLE_LABELS) do
	local key, label = entry[1], entry[2]

	vehicleBox:Toggle({
		Text = label,
		Flag = "esp_vehicle_" .. key,
		Default = false,
		Callback = function(state) Esp.teamSettings[key].enabled = state end,
	})
		:ColorPicker({
			Flag = "esp_vehicle_" .. key .. "_color",
			Default = VEHICLE_COLORS[key],
			Callback = function(color, alpha)
				local a = 1 - (alpha or 1)
				Esp.teamSettings[key].boxColor = { color, a }
				Esp.teamSettings[key].nameColor = { color, a }
			end,
		})
end

local displayBox = Visuals:Section("Display", 2)

displayBox:Toggle({
	Text = "Name",
	Flag = "esp_name",
	Default = true,
	Callback = function(state) set("name", state) end,
})
	:ColorPicker({
		Flag = "esp_name_color",
		Default = Color3.new(1, 1, 1),
		Callback = function(color, alpha) setPair("nameColor", color, alpha) end,
	})

displayBox:Toggle({
	Text = "Weapons",
	Flag = "esp_weapon",
	Default = false,
	Callback = function(state) set("weapon", state) end,
})
	:ColorPicker({
		Flag = "esp_weapon_color",
		Default = Color3.new(1, 1, 1),
		Callback = function(color, alpha) setPair("weaponColor", color, alpha) end,
	})

displayBox:Toggle({
	Text = "Distance",
	Flag = "esp_distance",
	Default = true,
	Callback = function(state) set("distance", state) end,
})
	:ColorPicker({
		Flag = "esp_distance_color",
		Default = Color3.new(1, 1, 1),
		Callback = function(color, alpha) setPair("distanceColor", color, alpha) end,
	})

displayBox:Toggle({
	Text = "Health",
	Flag = "esp_health_text",
	Default = false,
	Callback = function(state) set("healthText", state) end,
})
	:ColorPicker({
		Flag = "esp_health_text_color",
		Default = Color3.new(1, 1, 1),
		Callback = function(color, alpha) setPair("healthTextColor", color, alpha) end,
	})

displayBox:Divider()

displayBox:Slider({
	Text = "Text Size",
	Flag = "esp_text_size",
	Min = 8, Max = 28, Default = 13,
	Callback = function(value) Esp.sharedSettings.textSize = value end,
})

displayBox:Dropdown({
	Text = "Font",
	Flag = "esp_font",
	Options = { "UI", "System", "Plex", "Monospace" },
	Default = "Plex",
	Callback = function(value)
		local map = { UI = 0, System = 1, Plex = 2, Monospace = 3 }
		Esp.sharedSettings.textFont = map[value] or 2
	end,
})

local miscBox = Visuals:Section("Misc", "full")

miscBox:Split({
	function(left)
		left:Toggle({
			Text = "Rainbow",
			Flag = "esp_rainbow",
			Default = false,
			Callback = function(state) Esp.sharedSettings.rainbow = state end,
		})
			:Gear(function(panel)
				panel:Slider({
					Text = "Speed",
					Flag = "esp_rainbow_speed",
					Min = 50, Max = 1000, Default = 400,
					Callback = function(value) Esp.sharedSettings.rainbowSpeed = value end,
				})
			end)

		left:Toggle({
			Text = "Use Team Color",
			Flag = "esp_use_team_color",
			Default = false,
			Callback = function(state) Esp.sharedSettings.useTeamColor = state end,
		})
	end,
	function(right)
		right:Slider({
			Text = "Refresh Rate",
			Flag = "esp_slow_tick",
			Min = 0.02, Max = 0.5, Default = 0.1,
			Decimals = 2,
			Suffix = " s",
			Callback = function(value) Esp.sharedSettings.slowInterval = value end,
		})
	end,
})

local SaveManager      = Library.SaveManager
local InterfaceManager = Library.InterfaceManager
local ThemeManager     = Library.ThemeManager

SaveManager:SetLibrary(Library)
InterfaceManager:SetLibrary(Library)
InterfaceManager:SetWindow(Window)
ThemeManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
InterfaceManager:SetFolder("Facility")
ThemeManager:SetFolder("Facility")
SaveManager:SetFolder("Facility/esp")

InterfaceManager:BuildInterfaceSection(Settings, 1)
SaveManager:BuildConfigSection(Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(Visuals)

Library:Notify("Facility", "Player esp loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
