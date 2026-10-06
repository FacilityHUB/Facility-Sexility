local F       = shared.Facility
local Library = F.Library
local Entity  = F.Entity
local Esp     = F.Esp

local AIMBOT_URL = "https://raw.githubusercontent.com/FacilityHUB/Facility-Sexility/refs/heads/main/CModules/FAimbot.luau"

local moduleErrors = {}

local function fetchModule(url, label)
	local fetched, source = pcall(function()
		return game:HttpGet(url .. "?v=" .. tostring(tick()):gsub("%.", ""))
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

	if not ok then
		table.insert(moduleErrors, label .. ": runtime error - " .. tostring(result))
		return nil
	end

	if type(result) ~= "table" then
		table.insert(moduleErrors, label .. ": returned " .. typeof(result) .. " instead of a table")
		return nil
	end

	return result
end

local Aimbot = fetchModule(AIMBOT_URL, "aimbot")

F.Aimbot = Aimbot

for _, message in ipairs(moduleErrors) do
	warn("[Facility] " .. message)
end

if Aimbot then
	print("[Facility] aimbot version " .. tostring(Aimbot.Version or "unknown"))
end

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local Camera = workspace.CurrentCamera

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Camera = workspace.CurrentCamera
end)

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
local Visuals   = Window:Tab("Visuals", "eye")
local Settings  = Window:Tab("Settings", "cog")

if #moduleErrors > 0 then
	local failBox = Combat:Section("Modules", 1)

	for _, message in ipairs(moduleErrors) do
		failBox:Label(message, { Style = "dim" })
	end

	task.spawn(function()
		task.wait(1)
		for _, message in ipairs(moduleErrors) do
			Library:Error("Facility", message, 20)
		end
	end)
end

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
local charByPlayer = {}

local function charFolder()
	if charFolderCache and charFolderCache.Parent then return charFolderCache end
	charFolderCache = workspace:FindFirstChild("Characters")
	return charFolderCache
end

local function inCharacterFolder(model)
	local folder = charFolder()
	if not folder then return false end

	local parent = model.Parent
	if parent == folder then return true end

	return parent ~= nil and parent.Parent == folder
end

local function anchorOf(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function isCharacter(model)
	if not model or model.Parent == nil then return false end
	if not model:IsA("Model") then return false end
	if not inCharacterFolder(model) then return false end

	return anchorOf(model) ~= nil
end

local function playerOfModel(model)
	local player = Players:GetPlayerFromCharacter(model)
	if player then return player end

	player = Players:FindFirstChild(model.Name)
	if player then return player end

	for _, other in ipairs(Players:GetPlayers()) do
		if other.DisplayName == model.Name then return other end
	end

	return nil
end

local function collectModels(folder, into)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			table.insert(into, child)
		elseif child:IsA("Folder") then
			for _, nested in ipairs(child:GetChildren()) do
				if nested:IsA("Model") then table.insert(into, nested) end
			end
		end
	end
end

local function scanFolder()
	local found = {}

	local folder = charFolder()
	if not folder then
		charByPlayer = found
		return found
	end

	local models = {}
	collectModels(folder, models)

	for _, model in ipairs(models) do
		if anchorOf(model) then
			local player = playerOfModel(model)
			if player and not found[player] then found[player] = model end
		end
	end

	charByPlayer = found
	return found
end

local function characterOf(player)
	local cached = charByPlayer[player]
	if isCharacter(cached) then return cached end

	local own = player.Character
	if isCharacter(own) then
		charByPlayer[player] = own
		return own
	end

	return scanFolder()[player]
end

local function cleanGroup(value)
	if value == nil then return nil end

	local text = tostring(value)
	if text == "" or text == "Default" then return nil end

	return text
end

local function groupOfModel(model)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	local ok, group = pcall(function() return root.CollisionGroup end)
	if ok then
		local clean = cleanGroup(group)
		if clean then return clean end
	end

	return cleanGroup(root:GetAttribute("CollisionGroup"))
end

local VALID_TEAMS = {
	["Counter-Terrorists"] = true,
	["Terrorists"] = true,
}

local function isDeathmatch()
	local ok, mode = pcall(function() return workspace:GetAttribute("Gamemode") end)
	return ok and mode == "Deathmatch"
end

local function teamOf(player)
	local attribute = cleanGroup(player:GetAttribute("Team"))
	if attribute then return attribute end

	return groupOfModel(characterOf(player))
end

local function allSameGroup(mine)
	local seen = 0

	for player in pairs(charByPlayer) do
		if player ~= LocalPlayer then
			seen = seen + 1
			if teamOf(player) ~= mine then return false end
		end
	end

	return seen > 0
end

local function healthOf(model)
	local health = model:GetAttribute("Health")
	local maxHealth = model:GetAttribute("MaxHealth")

	if type(maxHealth) ~= "number" or maxHealth <= 0 then maxHealth = 100 end
	if type(health) ~= "number" then health = maxHealth end

	if model:GetAttribute("Dead") == true then health = 0 end

	return health, maxHealth
end

function Entity:IsTargetable(player)
	if player == LocalPlayer then return false end
	if self.Settings.TeamCheck == "Off" then return true end
	if isDeathmatch() then return true end

	local mine, theirs = teamOf(LocalPlayer), teamOf(player)
	if mine == nil or theirs == nil then return true end
	if not (VALID_TEAMS[mine] and VALID_TEAMS[theirs]) then return true end
	if mine ~= theirs then return true end

	return allSameGroup(mine)
end

local buildCounter = 0

function Entity:_build(player, character, isLocal)
	buildCounter = buildCounter + 1
	local id = buildCounter
	self.Ids[player] = id

	if not character then return end

	task.spawn(function()
		local root = anchorOf(character)

		if not root then
			local deadline = tick() + (self.Settings.LoadTimeout or 5)
			repeat
				task.wait(0.05)
				root = anchorOf(character)
			until root or tick() > deadline or self.Ids[player] ~= id or character.Parent == nil
		end

		if self.Ids[player] ~= id then return end
		if not root or character.Parent == nil then return end

		local head = character:FindFirstChild("Head") or root

		if isLocal then
			self.Self.Alive     = true
			self.Self.Character = character
			self.Self.Humanoid  = nil
			self.Self.Head      = head
			self.Self.RootPart  = root
			return
		end

		local health, maxHealth = healthOf(character)

		local ent = {
			Player      = player,
			Character   = character,
			Humanoid    = nil,
			Head        = head,
			RootPart    = root,
			Team        = groupOfModel(character),
			Targetable  = self:IsTargetable(player),
			Health      = health,
			MaxHealth   = maxHealth,
			Alive       = true,
			Connections = {},
		}

		local function watch(signal, fn)
			table.insert(ent.Connections, signal:Connect(fn))
		end

		local function syncHealth()
			ent.Health, ent.MaxHealth = healthOf(character)
			ent.Alive = ent.Health > 0
			self.Updated:Fire(ent)
		end

		watch(character:GetAttributeChangedSignal("Health"), syncHealth)
		watch(character:GetAttributeChangedSignal("MaxHealth"), syncHealth)
		watch(character:GetAttributeChangedSignal("Dead"), syncHealth)

		watch(root:GetPropertyChangedSignal("CollisionGroup"), function()
			ent.Team = groupOfModel(character)
			local targetable = self:IsTargetable(player)
			if ent.Targetable ~= targetable then
				ent.Targetable = targetable
				self.Updated:Fire(ent)
			end
		end)

		watch(character.AncestryChanged, function()
			if inCharacterFolder(character) then return end
			task.defer(function()
				if self.Entities[player] == ent then self:Remove(player) end
			end)
		end)

		self.Entities[player] = ent
		self.Added:Fire(ent)
	end)
end

function Entity:Refresh(player, isLocal)
	self:Remove(player)
	self:_build(player, characterOf(player), isLocal)
end

Esp.getWeapon = function(entity)
	local model = typeof(entity) == "Instance" and entity:IsA("Player")
		and characterOf(entity)
		or nil

	if not model then return nil end

	local holder = model:FindFirstChild("WeaponModel")
	if holder then
		local weapon = holder:FindFirstChildWhichIsA("Model") or holder:FindFirstChildWhichIsA("BasePart")
		if weapon then return weapon.Name end
	end

	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Tool") then return child.Name end
	end

	return nil
end

local function bindModel(model)
	task.wait(0.15)
	if not isCharacter(model) then return end

	local player = playerOfModel(model)
	if not player then return end

	charByPlayer[player] = model
	Entity:Refresh(player, player == LocalPlayer)
end

local function bindFolder(folder)
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.spawn(bindModel, child)
		elseif child:IsA("Folder") then
			child.ChildAdded:Connect(function(nested)
				if nested:IsA("Model") then task.spawn(bindModel, nested) end
			end)
		end
	end)

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Folder") then
			child.ChildAdded:Connect(function(nested)
				if nested:IsA("Model") then task.spawn(bindModel, nested) end
			end)
		end
	end
end

task.spawn(function()
	local folder = workspace:WaitForChild("Characters", 30)
	if not folder then
		warn("Facility: workspace.Characters not found")
		return
	end

	charFolderCache = folder
	bindFolder(folder)

	for player in pairs(scanFolder()) do
		Entity:Refresh(player, player == LocalPlayer)
	end
end)

task.spawn(function()
	while task.wait(1) do
		pcall(function()
			local present = scanFolder()

			local mine = present[LocalPlayer]
			if mine then
				if Entity.Self.Character ~= mine or not Entity.Self.Alive then
					Entity:Refresh(LocalPlayer, true)
				end
			else
				Entity.Self.Alive = false
			end

			for player, character in pairs(present) do
				if player ~= LocalPlayer then
					local ent = Entity.Entities[player]
					if not ent or ent.Character ~= character then
						Entity:Refresh(player, false)
					end
				end
			end

			for player in pairs(Entity.Entities) do
				if not present[player] then Entity:Remove(player) end
			end

			Entity:RefreshTargets()
		end)
	end
end)

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
			Library:Error("Esp", tostring(err), 10)
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

checkBox:Button({
	Text = "Debug Targets",
	Callback = function()
		local present = scanFolder()
		local models, tracked, targets = 0, 0, 0

		print("[Facility] group of " .. LocalPlayer.Name .. ": " .. tostring(teamOf(LocalPlayer)))

		for player, character in pairs(present) do
			models = models + 1

			local ent = Entity.Entities[player]
			if ent then tracked = tracked + 1 end
			if ent and ent.Targetable then targets = targets + 1 end

			print(string.format(
				"[Facility] %s model=%s group=%s entity=%s targetable=%s hp=%s/%s",
				player.Name,
				character.Name,
				tostring(groupOfModel(character)),
				ent and "yes" or "no",
				ent and tostring(ent.Targetable) or "-",
				ent and tostring(ent.Health) or "-",
				ent and tostring(ent.MaxHealth) or "-"
			))
		end

		local folder = charFolder()
		print("[Facility] Characters folder: " .. (folder and "found" or "missing"))

		Library:Notify("Facility", string.format(
			"%d models, %d tracked, %d targetable. Details in the console.",
			models, tracked, targets
		), 8)
	end,
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

local aimInput = {
	hooked = false,
	module = nil,
	original = nil,
	delta = nil,
	pending = nil,
	sign = 1,
	calibrated = false,
}

local function cameraInputModule()
	local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
	local playerModule = scripts and scripts:FindFirstChild("PlayerModule")
	local cameraModule = playerModule and playerModule:FindFirstChild("CameraModule")
	local input = cameraModule and cameraModule:FindFirstChild("CameraInput")

	if not input or not input:IsA("ModuleScript") then return nil end

	local ok, result = pcall(require, input)
	if ok and type(result) == "table" and type(result.getRotation) == "function" then
		return result
	end

	return nil
end

local function hookCameraInput()
	if aimInput.hooked then return true end

	local module = cameraInputModule()
	if not module then return false end

	local original = module.getRotation

	aimInput.module = module
	aimInput.original = original

	module.getRotation = function(...)
		local base = original(...)
		local extra = aimInput.delta
		aimInput.delta = nil

		if extra and typeof(base) == "Vector2" then
			return base + extra
		end

		return base
	end

	aimInput.hooked = true
	return true
end

local function lookAngles(cframe)
	local look = cframe.LookVector
	return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
end

local function wrapAngle(angle)
	while angle > math.pi do angle = angle - math.pi * 2 end
	while angle < -math.pi do angle = angle + math.pi * 2 end
	return angle
end

function Aimbot:_aim(position)
	if not hookCameraInput() then return end

	local cframe = Camera.CFrame
	local yaw, pitch = lookAngles(cframe)

	local pending = aimInput.pending
	aimInput.pending = nil

	if pending and not aimInput.calibrated then
		local moved = wrapAngle(yaw - pending.yaw)
		if math.abs(pending.want) > 0.004 and math.abs(moved) > 0.0008 then
			if (moved > 0) ~= (pending.want > 0) then
				aimInput.sign = -aimInput.sign
			end
			aimInput.calibrated = true
		end
	end

	local direction = position - cframe.Position
	if direction.Magnitude < 0.001 then return end

	direction = direction.Unit

	local wantYaw = math.atan2(-direction.X, -direction.Z)
	local wantPitch = math.asin(math.clamp(direction.Y, -1, 1))

	local eased = self:_eased(math.clamp(self.Settings.Smoothness, 0.01, 1))

	local deltaYaw = wrapAngle(wantYaw - yaw) * eased
	local deltaPitch = (wantPitch - pitch) * eased

	aimInput.delta = Vector2.new(-deltaYaw * aimInput.sign, -deltaPitch * aimInput.sign)
	aimInput.pending = { yaw = yaw, want = deltaYaw }
end

local aimBox = Combat:Section("Aimbot", 1)

aimBox:Toggle({
	Text = "Enable",
	Flag = "aim_enable",
	Default = false,
	Callback = function(state)
		if state then
			local ok, err = pcall(function() Aimbot:Load(Entity) end)
			if not ok then
				Library:Error("Aimbot", tostring(err), 10)
				return
			end

			if not cameraInputModule() then
				Library:Error("Aimbot", "CameraInput module not found, aiming will not work in this game.", 10)
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
	Default = "Cursor",
	Callback = function(value) Aimbot.Settings.Priority = value end,
})

aimBox:Dropdown({
	Text = "Target Part",
	Flag = "aim_parts",
	Options = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart" },
	Default = { "Head" },
	Multi = true,
	Empty = "Head",
	Callback = function(selected)
		if #selected == 0 then selected = { "Head" } end
		Aimbot.Settings.Parts = selected
	end,
})

aimBox:Slider({
	Text = "Sensitivity",
	Flag = "aim_sensitivity",
	Min = 0.02, Max = 1, Default = 0.35,
	Decimals = 2,
	Callback = function(value) Aimbot.Settings.Sensitivity = value end,
})

aimBox:Slider({
	Text = "Smoothness",
	Flag = "aim_smoothness",
	Min = 0.05, Max = 1, Default = 0.25,
	Decimals = 2,
	Callback = function(value) Aimbot.Settings.Smoothness = value end,
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
		panel:Toggle({
			Text = "Add Ping",
			Flag = "aim_prediction_ping",
			Default = false,
			Callback = function(state) Aimbot.Settings.PingPrediction = state end,
		})
	end)

local triggerBox = Combat:Section("Trigger Bot", 1)

local function triggerKeyEnum(name)
	local mouse = {
		MB1 = Enum.UserInputType.MouseButton1,
		MB2 = Enum.UserInputType.MouseButton2,
		MB3 = Enum.UserInputType.MouseButton3,
	}

	if mouse[name] then return mouse[name] end

	local ok, code = pcall(function() return Enum.KeyCode[name] end)
	if ok and code then return code end

	return Enum.KeyCode.C
end

local function applyTriggerKey()
	if not Library.Flags["trigger_use_key"] then
		Aimbot.Settings.Trigger.Key = nil
		return
	end

	Aimbot.Settings.Trigger.Key = triggerKeyEnum(Library.Flags["trigger_key"] or "C")
end

triggerBox:Toggle({
	Text = "Enable",
	Flag = "trigger_enable",
	Default = false,
	Callback = function(state) Aimbot.Settings.TriggerBot = state end,
})
	:Gear(function(panel)
		panel:Toggle({
			Text = "Require Aim",
			Flag = "trigger_require_aim",
			Default = false,
			Callback = function(state) Aimbot.Settings.Trigger.RequireAim = state end,
		})
		panel:Toggle({
			Text = "Hold Fire",
			Flag = "trigger_hold_fire",
			Default = false,
			Callback = function(state) Aimbot.Settings.Trigger.HoldFire = state end,
		})
		panel:Slider({
			Text = "Hit Chance",
			Flag = "trigger_hit_chance",
			Min = 0, Max = 100, Default = 100,
			Suffix = "%",
			Callback = function(value) Aimbot.Settings.Trigger.HitChance = value end,
		})
	end)

triggerBox:Dropdown({
	Text = "Mode",
	Flag = "trigger_mode",
	Options = { "Target", "Crosshair", "Fov" },
	Default = "Target",
	Callback = function(value) Aimbot.Settings.Trigger.Mode = value end,
})

triggerBox:Slider({
	Text = "Fov",
	Flag = "trigger_fov",
	Min = 0, Max = 400, Default = 0,
	Callback = function(value) Aimbot.Settings.Trigger.Fov = value end,
})

triggerBox:Toggle({
	Text = "Use Key",
	Flag = "trigger_use_key",
	Default = false,
	Callback = function() applyTriggerKey() end,
})

triggerBox:Keybind({
	Text = "Trigger Key",
	Flag = "trigger_key",
	Default = "C",
	Mode = "toggle",
	OnChanged = function() applyTriggerKey() end,
})

triggerBox:Slider({
	Text = "Reaction",
	Flag = "trigger_reaction",
	Min = 0, Max = 0.5, Default = 0,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) Aimbot.Settings.Trigger.ReactionTime = value end,
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

triggerBox:Divider()

triggerBox:Toggle({
	Text = "Wall Check",
	Flag = "trigger_wall_check",
	Default = true,
	Callback = function(state) Aimbot.Settings.Trigger.WallCheck = state end,
})
	:Gear(function(panel)
		panel:Toggle({
			Text = "Multipoint",
			Flag = "trigger_multipoint",
			Default = false,
			Callback = function(state) Aimbot.Settings.Trigger.Multipoint = state end,
		})
	end)

triggerBox:Toggle({
	Text = "Team Check",
	Flag = "trigger_team_check",
	Default = true,
	Callback = function(state) Aimbot.Settings.Trigger.TeamCheck = state end,
})

triggerBox:Slider({
	Text = "Max Distance",
	Flag = "trigger_max_distance",
	Min = 100, Max = 5000, Default = 2000,
	Suffix = " studs",
	Callback = function(value) Aimbot.Settings.Trigger.MaxDistance = value end,
})

triggerBox:Dropdown({
	Text = "Target Part",
	Flag = "trigger_parts",
	Options = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart" },
	Default = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart" },
	Multi = true,
	Empty = "Head",
	Callback = function(selected)
		if #selected == 0 then selected = { "Head" } end
		Aimbot.Settings.Trigger.Parts = selected
	end,
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
