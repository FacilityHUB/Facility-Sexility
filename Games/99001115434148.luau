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

F.Aimbot = Aimbot
F.Movement = Movement

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local Camera = workspace.CurrentCamera

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Camera = workspace.CurrentCamera
end)

task.spawn(function()
	task.wait(3)

	local custom = workspace:FindFirstChild("CustomCamera")

	if custom and custom:IsA("Camera") and custom ~= workspace.CurrentCamera then
		Library:Notify({
			Title = "Camera",
			Text = "workspace.CustomCamera is not the rendering camera, esp and aim may be offset.",
			Style = "warning",
			Duration = 10,
		})
	end
end)

local cleanupTasks = {}

local function onCleanup(fn)
	table.insert(cleanupTasks, fn)
end

local Window = Library:Window({
	Title             = "Facility",
	Suffix            = ".Sexility",
	Width             = 700,
	Height            = 580,
	MinWidth          = 580,
	SectionTitleStyle = "border",
	MobileButton      = true,
})

local Combat   = Window:Tab("Combat", "crosshair")
local Visuals  = Window:Tab("Visuals", "eye")
local Hitbox   = Window:Tab("Hitbox", "box")
local Guns     = Window:Tab("Guns", "crosshair")
local Movements = Window:Tab("Movement", "move")
local Settings = Window:Tab("Settings", "cog")

local PLAYER_TEAMS = { "enemy", "friendly", "whitelist" }

local function set(key, value)
	for _, name in ipairs(PLAYER_TEAMS) do
		local team = Esp.teamSettings[name]
		if team then team[key] = value end
	end
end

local function setPair(key, color, alpha)
	Esp.teamSettings.enemy[key] = { color, alpha ~= nil and (1 - alpha) or 1 }
end

Esp.teamSettings.enemy.enabled = true
Esp.teamSettings.friendly.enabled = false
Esp.teamSettings.friendly.boxColor = { Color3.fromRGB(80, 200, 120), 1 }
Esp.teamSettings.friendly.nameColor = { Color3.fromRGB(80, 200, 120), 1 }

Entity.Settings.TeamCheck = "Off"
Esp.sharedSettings.teamCheck = "Off"

local HITBOX_NAME = "FacilityHitbox"

local HitboxState = {
	Enabled = false,
	Size = 10,
	Visibility = 0.6,
	Shape = "Ball",
}

local function removeHitbox(character)
	local part = character and character:FindFirstChild(HITBOX_NAME)
	if part then pcall(function() part:Destroy() end) end
end

local function applyHitbox(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local part = character:FindFirstChild(HITBOX_NAME)

	if not part then
		part = Instance.new("Part")
		part.Name = HITBOX_NAME
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.ForceField
		part.Color = Color3.fromRGB(255, 60, 60)
		part.CanCollide = false
		part.CanQuery = false
		part.Massless = true
		part.Anchored = false
		part.Parent = character

		local weld = Instance.new("Weld")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end

	part.Shape = HitboxState.Shape == "Block" and Enum.PartType.Block or Enum.PartType.Ball
	part.Size = Vector3.new(HitboxState.Size, HitboxState.Size, HitboxState.Size)
	part.Transparency = 1 - HitboxState.Visibility
end

local hitboxRunning = true

task.spawn(function()
	while hitboxRunning do
		task.wait(0.3)

		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer then
				local character = player.Character

				if character then
					if HitboxState.Enabled then
						pcall(applyHitbox, character)
					else
						pcall(removeHitbox, character)
					end
				end
			end
		end
	end
end)

onCleanup(function()
	hitboxRunning = false

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			pcall(removeHitbox, player.Character)
		end
	end
end)

local GunGiver = {
	Paths = {},
	Tools = {},
	Selected = nil,
}

local function scanTools(folder, prefix, results)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Tool") then
			local path = prefix .. child.Name
			table.insert(results.Paths, path)
			results.Tools[path] = child
		elseif child:IsA("Folder") or child:IsA("Model") then
			scanTools(child, prefix .. child.Name .. ".", results)
		end
	end

	return results
end

local function refreshGuns()
	GunGiver.Paths = {}
	GunGiver.Tools = {}

	local folder = ReplicatedStorage:FindFirstChild("GunModels")
	if not folder then return 0 end

	scanTools(folder, "", GunGiver)
	table.sort(GunGiver.Paths)

	return #GunGiver.Paths
end

local function giveTool(tool, path)
	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

	if not backpack then
		Library:Notify({ Title = "Guns", Text = "No backpack found.", Style = "error", Duration = 5 })
		return false
	end

	local ok = pcall(function()
		local clone = tool:Clone()
		clone.Parent = backpack

		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if humanoid and character and not character:FindFirstChildOfClass("Tool") then
			humanoid:EquipTool(clone)
		end
	end)

	if not ok then
		Library:Notify({ Title = "Guns", Text = "Could not give " .. tostring(path), Style = "error", Duration = 5 })
	end

	return ok
end

refreshGuns()

local espBox = Visuals:Section("Esp", 1)

espBox:Toggle({
	Text = "Enable",
	Flag = "esp_enable",
	Default = false,
	Callback = function(state)
		local ok, err

		if state then
			ok, err = pcall(function() Esp:Load(Entity) end)
		else
			ok, err = pcall(function() Esp:Unload() end)
		end

		if not ok then
			Library:Notify({ Title = "Esp", Text = tostring(err), Style = "error", Duration = 10 })
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
		Default = Color3.fromRGB(0, 255, 100),
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
				Default = Color3.fromRGB(0, 255, 100),
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
		Default = Color3.fromRGB(0, 255, 100),
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

local checkBox = Visuals:Section("Check", 2)

checkBox:Toggle({
	Text = "Team Check",
	Flag = "esp_team_check",
	Default = false,
	Callback = function(state)
		local mode = state and "Team" or "Off"
		Esp.sharedSettings.teamCheck = mode
		Entity.Settings.TeamCheck = mode
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
	Min = 50, Max = 10000, Default = 5000,
	Suffix = " studs",
	Callback = function(value) set("maxDistance", value) end,
})

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
	Default = true,
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

if Aimbot then

Aimbot.Settings.Mode = "Camera"
Aimbot.Settings.TeamCheck = false

local aimBox = Combat:Section("Aimbot", 1)

aimBox:Toggle({
	Text = "Enable Aim Lock",
	Flag = "aim_enable",
	Default = false,
	Callback = function(state)
		if state then
			local ok, err = pcall(function() Aimbot:Load(Entity) end)

			if not ok then
				Library:Notify({ Title = "Aimbot", Text = tostring(err), Style = "error", Duration = 10 })
				return
			end
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
	Default = "Closest",
	Callback = function(value) Aimbot.Settings.Priority = value end,
})

aimBox:Dropdown({
	Text = "Target Part",
	Flag = "aim_parts",
	Options = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart", "Torso" },
	Default = { "HumanoidRootPart" },
	Multi = true,
	Empty = "HumanoidRootPart",
	Callback = function(selected)
		if #selected == 0 then selected = { "HumanoidRootPart" } end
		Aimbot.Settings.Parts = selected
	end,
})

aimBox:Slider({
	Text = "Smoothness",
	Flag = "aim_smoothness",
	Min = 0.01, Max = 1, Default = 1,
	Decimals = 2,
	Callback = function(value) Aimbot.Settings.Smoothness = value end,
})

aimBox:Dropdown({
	Text = "Easing Style",
	Flag = "aim_easing_style",
	Options = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Back" },
	Default = "Linear",
	Callback = function(value) Aimbot.Settings.EasingStyle = value end,
})

aimBox:Toggle({
	Text = "Random Part",
	Flag = "aim_random_part",
	Default = false,
	Callback = function(state) Aimbot.Settings.RandomPart = state end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Interval",
			Flag = "aim_random_interval",
			Min = 0.1, Max = 3, Default = 1,
			Decimals = 1,
			Suffix = " s",
			Callback = function(value) Aimbot.Settings.RandomInterval = value end,
		})
	end)

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
	Min = 100, Max = 10000, Default = 5000,
	Suffix = " studs",
	Callback = function(value) Aimbot.Settings.MaxDistance = value end,
})

aimBox:Toggle({
	Text = "Override Camera",
	Flag = "aim_override_camera",
	Default = false,
	Callback = function(state)
		if state then
			pcall(function() Camera.CameraType = Enum.CameraType.Scriptable end)
		else
			pcall(function() Camera.CameraType = Enum.CameraType.Custom end)
		end
	end,
})

onCleanup(function()
	pcall(function() Camera.CameraType = Enum.CameraType.Custom end)
end)

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
		Default = Color3.fromRGB(255, 50, 50),
		Callback = function(color) Aimbot.Settings.FovLockColor = color end,
	})

fovBox:Slider({
	Text = "Radius",
	Flag = "aim_fov",
	Min = 10, Max = 800, Default = 150,
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
	Min = 0, Max = 1, Default = 0,
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
	Default = false,
	Callback = function(state) Aimbot.Settings.TeamCheck = state end,
})

behaviourBox:Toggle({
	Text = "Visibility Check",
	Flag = "aim_wall_check",
	Default = false,
	Callback = function(state) Aimbot.Settings.WallCheck = state end,
})

behaviourBox:Toggle({
	Text = "Multipoint",
	Flag = "aim_multipoint",
	Default = false,
	Callback = function(state) Aimbot.Settings.Multipoint = state end,
})

behaviourBox:Toggle({
	Text = "Alive Check",
	Flag = "aim_alive_check",
	Default = true,
	Callback = function(state) Aimbot.Settings.AliveCheck = state end,
})

behaviourBox:Slider({
	Text = "Deadzone",
	Flag = "aim_deadzone",
	Min = 0, Max = 200, Default = 0,
	Callback = function(value) Aimbot.Settings.Deadzone = value end,
})

behaviourBox:Toggle({
	Text = "Auto Switch Target",
	Flag = "aim_sticky",
	Default = true,
	Callback = function(state) Aimbot.Settings.Sticky = not state end,
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
	Text = "Target Line",
	Flag = "aim_target_line",
	Default = false,
	Callback = function(state) Aimbot.Settings.TargetLine = state end,
})
	:ColorPicker({
		Flag = "aim_target_line_color",
		Default = Color3.fromRGB(255, 50, 50),
		Callback = function(color) Aimbot.Settings.TargetLineColor = color end,
	})

behaviourBox:Toggle({
	Text = "Target Info",
	Flag = "aim_target_info",
	Default = false,
	Callback = function(state) Aimbot.Settings.TargetInfo = state end,
})
	:ColorPicker({
		Flag = "aim_target_info_color",
		Default = Color3.fromRGB(255, 200, 50),
		Callback = function(color) Aimbot.Settings.TargetInfoColor = color end,
	})

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
		panel:Toggle({
			Text = "Add Ping",
			Flag = "aim_prediction_ping",
			Default = false,
			Callback = function(state) Aimbot.Settings.PingPrediction = state end,
		})
	end)

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

end

local hitboxBox = Hitbox:Section("Hitbox Expander", 1)

hitboxBox:Toggle({
	Text = "Enable",
	Flag = "hitbox_enable",
	Default = false,
	Callback = function(state) HitboxState.Enabled = state end,
})

hitboxBox:Slider({
	Text = "Size",
	Flag = "hitbox_size",
	Min = 1, Max = 30, Default = 10,
	Decimals = 1,
	Suffix = " studs",
	Callback = function(value) HitboxState.Size = value end,
})

hitboxBox:Slider({
	Text = "Visibility",
	Flag = "hitbox_visibility",
	Min = 0, Max = 1, Default = 0.6,
	Decimals = 2,
	Callback = function(value) HitboxState.Visibility = value end,
})

hitboxBox:Dropdown({
	Text = "Shape",
	Flag = "hitbox_shape",
	Options = { "Ball", "Block" },
	Default = "Ball",
	Callback = function(value) HitboxState.Shape = tostring(value) end,
})

local gunBox = Guns:Section("Gun Giver", 1)

gunBox:Label("Scans ReplicatedStorage.GunModels for tools.", { Style = "dim" })

local gunCountLabel = gunBox:Label(string.format("%d guns found", #GunGiver.Paths))

local gunDropdown

gunDropdown = gunBox:Dropdown({
	Text = "Select Gun",
	Flag = "gun_select",
	Options = #GunGiver.Paths > 0 and GunGiver.Paths or { "No gun found" },
	Default = GunGiver.Paths[1] or "No gun found",
	Callback = function(value) GunGiver.Selected = tostring(value) end,
})

gunBox:Button({
	Text = "Give Selected",
	Callback = function()
		local tool = GunGiver.Selected and GunGiver.Tools[GunGiver.Selected]

		if not tool then
			Library:Notify({ Title = "Guns", Text = "No gun selected.", Style = "error", Duration = 5 })
			return
		end

		if giveTool(tool, GunGiver.Selected) then
			Library:Notify({
				Title = "Guns",
				Text = "Gave " .. GunGiver.Selected,
				Style = "success",
				Duration = 4,
			})
		end
	end,
})

gunBox:Button({
	Text = "Give All",
	Callback = function()
		if #GunGiver.Paths == 0 then
			Library:Notify({ Title = "Guns", Text = "Nothing to give.", Style = "error", Duration = 5 })
			return
		end

		local given = 0

		for _, path in ipairs(GunGiver.Paths) do
			if giveTool(GunGiver.Tools[path], path) then given = given + 1 end
			task.wait(0.05)
		end

		Library:Notify({
			Title = "Guns",
			Text = string.format("Gave %d gun(s).", given),
			Style = "success",
			Duration = 4,
		})
	end,
})

gunBox:Button({
	Text = "Refresh List",
	Callback = function()
		local count = refreshGuns()

		pcall(function()
			gunDropdown:SetOptions(#GunGiver.Paths > 0 and GunGiver.Paths or { "No gun found" })
		end)

		pcall(function() gunCountLabel:Set(string.format("%d guns found", count)) end)

		Library:Notify({
			Title = "Guns",
			Text = string.format("%d gun(s) found.", count),
			Style = count > 0 and "success" or "warning",
			Duration = 4,
		})
	end,
})

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
SaveManager:SetFolder("Facility/99001115434148")

InterfaceManager:BuildInterfaceSection(Settings, 1)
SaveManager:BuildConfigSection(Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(Combat)

Library:Notify("Facility", "Loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()

local libraryDestroy = Library.Destroy

function Library:Destroy(...)
	for index = #cleanupTasks, 1, -1 do
		pcall(cleanupTasks[index])
	end

	table.clear(cleanupTasks)

	return libraryDestroy(self, ...)
end

F.Unload = function()
	pcall(function() Library:Destroy() end)
end
