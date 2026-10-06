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

local LocalPlayer = Players.LocalPlayer

local Window = Library:Window({
	Title             = "Facility",
	Suffix            = ".Sexility",
	Width             = 700,
	Height            = 580,
	MinWidth          = 580,
	SectionTitleStyle = "border",
	MobileButton      = true,
})

local Combat    = Window:Tab("Combat", "crosshair")
local Movements = Window:Tab("Movement", "move")
local Visuals   = Window:Tab("Visuals", "eye")
local Settings  = Window:Tab("Settings", "cog")

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

Entity.Settings.TeamCheck = "Team"
Esp.sharedSettings.teamCheck = "Team"

local charFolderCache

local function charFolder()
	if charFolderCache and charFolderCache.Parent then return charFolderCache end
	charFolderCache = workspace:FindFirstChild("Characters")
	return charFolderCache
end

local function isCharacter(model)
	return model
		and model.Parent ~= nil
		and model:IsA("Model")
		and model:FindFirstChildWhichIsA("Humanoid") ~= nil
end

local function characterOf(player)
	local own = player.Character
	if isCharacter(own) then return own end

	local folder = charFolder()
	if not folder then return nil end

	local model = folder:FindFirstChild(player.Name)
	if isCharacter(model) then return model end

	return nil
end

local function playerOfModel(model)
	local player = Players:GetPlayerFromCharacter(model)
	if player then return player end
	return Players:FindFirstChild(model.Name)
end

local function teamOf(player)
	local character = characterOf(player)
	if not character then return nil end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	local attribute = root:GetAttribute("CollisionGroup")
	if attribute ~= nil and attribute ~= "" then return tostring(attribute) end

	local ok, group = pcall(function() return root.CollisionGroup end)
	if ok and type(group) == "string" and group ~= "" then return group end

	return nil
end

function Entity:IsTargetable(player)
	if player == LocalPlayer then return false end
	if self.Settings.TeamCheck == "Off" then return true end

	local mine, theirs = teamOf(LocalPlayer), teamOf(player)
	if mine == nil or theirs == nil then return true end

	return mine ~= theirs
end

function Entity:Refresh(player, isLocal)
	self:Remove(player)
	self:_build(player, characterOf(player), isLocal)
end

local function bindFolder(folder)
	folder.ChildAdded:Connect(function(model)
		task.wait(0.15)
		if not isCharacter(model) then return end

		local player = playerOfModel(model)
		if not player then return end

		Entity:Refresh(player, player == LocalPlayer)
	end)

	folder.ChildRemoved:Connect(function(model)
		local player = playerOfModel(model)
		if not player then return end

		if player == LocalPlayer then
			Entity.Self.Alive = false
			return
		end

		local ent = Entity.Entities[player]
		if ent and ent.Character == model then Entity:Remove(player) end
	end)
end

task.spawn(function()
	local folder = workspace:WaitForChild("Characters", 30)
	if not folder then
		warn("Facility: workspace.Characters not found")
		return
	end

	charFolderCache = folder
	bindFolder(folder)

	for _, model in ipairs(folder:GetChildren()) do
		local player = isCharacter(model) and playerOfModel(model)
		if player then Entity:Refresh(player, player == LocalPlayer) end
	end
end)

task.spawn(function()
	while task.wait(1) do
		pcall(function()
			local mine = characterOf(LocalPlayer)
			if mine then
				if Entity.Self.Character ~= mine or not Entity.Self.Alive then
					Entity:Refresh(LocalPlayer, true)
				end
			else
				Entity.Self.Alive = false
			end

			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= LocalPlayer then
					local character = characterOf(other)
					local ent = Entity.Entities[other]

					if character then
						if not ent or ent.Character ~= character then
							Entity:Refresh(other, false)
						end
					elseif ent then
						Entity:Remove(other)
					end
				end
			end

			Entity:RefreshTargets()
		end)
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

local checkBox = Visuals:Section("Check", 2)

checkBox:Toggle({
	Text = "Team Check",
	Flag = "esp_team_check",
	Default = true,
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
		if other ~= LocalPlayer then
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

if Aimbot then

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

aimBox:Toggle({
	Text = "Elastic Aim",
	Flag = "aim_elastic",
	Default = false,
	Callback = function(state) Aimbot.Settings.Elastic = state end,
})
	:Gear(function(panel)
		panel:Slider({
			Text = "Stiffness",
			Flag = "aim_stiffness",
			Min = 4, Max = 60, Default = 18,
			Callback = function(value) Aimbot.Settings.Stiffness = value end,
		})
		panel:Slider({
			Text = "Damping",
			Flag = "aim_damping",
			Min = 0.3, Max = 0.98, Default = 0.72,
			Decimals = 2,
			Callback = function(value) Aimbot.Settings.Damping = value end,
		})
		panel:Slider({
			Text = "Max Overshoot",
			Flag = "aim_overshoot",
			Min = 0, Max = 200, Default = 60,
			Callback = function(value) Aimbot.Settings.MaxOvershoot = value end,
		})
	end)

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
	Text = "Multipoint",
	Flag = "aim_multipoint",
	Default = false,
	Callback = function(state) Aimbot.Settings.Multipoint = state end,
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
		panel:Dropdown({
			Text = "Origin",
			Flag = "aim_target_line_origin",
			Options = { "Mouse", "Center" },
			Default = "Mouse",
			Callback = function(value) Aimbot.Settings.TargetLineOrigin = value end,
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
SaveManager:SetFolder("Facility/114234929420007")

InterfaceManager:BuildInterfaceSection(Settings, 1)
SaveManager:BuildConfigSection(Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(Visuals)

Library:Notify("Facility", "Loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
