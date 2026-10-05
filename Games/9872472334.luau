--!nocheck
--!nolint UnknownGlobal

local F       = shared.Facility
local Library = F.Library
local Entity  = F.Entity
local Esp     = F.Esp

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Camera = workspace.CurrentCamera
end)

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

local Window = Library:Window({
	Title             = "Facility",
	Suffix            = ".hub",
	Width             = 700,
	Height            = 580,
	MinWidth          = 580,
	SectionTitleStyle = "border",
})

local Combat   = Window:Tab("Combat", "crosshair")
local Movements = Window:Tab("Movement", "move")
local Visuals  = Window:Tab("Visuals", "eye")
local Collect  = Window:Tab("Collect", "coins")
local Settings = Window:Tab("Settings", "cog")

local function localRoot()
	local character = LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function waitForRoot(timeout)
	local deadline = tick() + (timeout or 5)
	repeat
		local root = localRoot()
		if root then return root end
		task.wait(0.1)
	until tick() > deadline
	return nil
end

local function pressKey(keyCode, duration)
	VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
	task.wait(duration or 0.08)
	VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

local NPC_FOLDER = workspace:WaitForChild("Players", 20)

local function isNpc(model)
	if not model:IsA("Model") then return false end
	if Players:GetPlayerFromCharacter(model) then return false end
	return model:FindFirstChildWhichIsA("Humanoid") ~= nil
end

Esp:AddTeam("npc", {
	enabled     = true,
	box         = true,
	boxColor    = { Color3.fromRGB(255, 80, 80), 1 },
	boxOutline  = true,
	name        = true,
	nameColor   = { Color3.fromRGB(255, 140, 140), 1 },
	distance    = true,
	healthBar   = false,
	healthText  = false,
	weapon      = false,
	skeleton    = false,
	chams       = false,
	chamsFillColor    = { Color3.fromRGB(255, 80, 80), 0.6 },
	chamsOutlineColor = { Color3.fromRGB(255, 140, 140), 0 },
	maxDistance = 3000,
})

Esp:AddTeam("collectable", {
	enabled     = false,
	box         = true,
	boxColor    = { Color3.fromRGB(255, 215, 0), 1 },
	name        = true,
	nameColor   = { Color3.fromRGB(255, 235, 120), 1 },
	distance    = true,
	healthBar   = false,
	skeleton    = false,
	maxDistance = 2000,
})

Esp.teamSettings.enemy.enabled = false
Esp.teamSettings.friendly.enabled = false

local npcs = {}

local function untrackNpc(model)
	if not npcs[model] then return end
	npcs[model] = nil
	pcall(function() Esp:RemoveInstance(model) end)
end

local function trackNpc(model)
	if npcs[model] then return end
	if not isNpc(model) then return end

	task.spawn(function()
		local root = model:FindFirstChild("HumanoidRootPart")
			or model:WaitForChild("HumanoidRootPart", 5)
		if not root or model.Parent == nil then return end

		npcs[model] = true
		Esp:AddInstance(model, { Team = "npc", Text = model.Name })

		model.AncestryChanged:Connect(function()
			if model.Parent == nil then untrackNpc(model) end
		end)
	end)
end

if NPC_FOLDER then
	for _, model in ipairs(NPC_FOLDER:GetChildren()) do
		trackNpc(model)
	end
	NPC_FOLDER.ChildAdded:Connect(trackNpc)
	NPC_FOLDER.ChildRemoved:Connect(untrackNpc)
end

local collectables = {}
local collectFolder

local function collectableFolder()
	if collectFolder and collectFolder.Parent then return collectFolder end

	local effects = workspace:FindFirstChild("Effects")
	local parent = effects and effects:FindFirstChild("Collectables")
	collectFolder = parent and parent:FindFirstChild("Interactables")

	return collectFolder
end

local function untrackCollectable(model)
	if not collectables[model] then return end
	collectables[model] = nil
	pcall(function() Esp:RemoveInstance(model) end)
end

local function trackCollectable(model)
	if collectables[model] then return end
	if not model:IsA("Model") then return end

	task.spawn(function()
		local anchor = model.PrimaryPart
			or model:FindFirstChildWhichIsA("BasePart", true)

		if not anchor then
			local deadline = tick() + 3
			repeat
				task.wait(0.1)
				anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
			until anchor or tick() > deadline or model.Parent == nil
		end

		if not anchor or model.Parent == nil then return end

		collectables[model] = true
		Esp:AddInstance(model, { Team = "collectable", Text = model.Name })

		model.AncestryChanged:Connect(function()
			if model.Parent == nil then untrackCollectable(model) end
		end)
	end)
end

task.spawn(function()
	local folder = collectableFolder()

	local deadline = tick() + 30
	while not folder and tick() < deadline do
		task.wait(1)
		folder = collectableFolder()
	end

	if not folder then
		warn("Facility: collectables folder not found")
		return
	end

	for _, model in ipairs(folder:GetChildren()) do
		trackCollectable(model)
	end

	folder.ChildAdded:Connect(trackCollectable)
	folder.ChildRemoved:Connect(untrackCollectable)
end)

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
	Text = "Npc",
	Flag = "esp_npc",
	Default = true,
	Callback = function(state) Esp.teamSettings.npc.enabled = state end,
})
	:ColorPicker({
		Flag = "esp_npc_color",
		Default = Color3.fromRGB(255, 80, 80),
		Callback = function(color, alpha)
			local a = 1 - (alpha or 1)
			Esp.teamSettings.npc.boxColor = { color, a }
			Esp.teamSettings.npc.nameColor = { color, a }
		end,
	})

espBox:Toggle({
	Text = "Npc Chams",
	Flag = "esp_npc_chams",
	Default = false,
	Callback = function(state) Esp.teamSettings.npc.chams = state end,
})
	:ColorPicker({
		Flag = "esp_npc_chams_color",
		Default = Color3.fromRGB(255, 80, 80),
		DefaultAlpha = 0.5,
		Callback = function(color, alpha)
			Esp.teamSettings.npc.chamsFillColor = { color, 1 - (alpha or 1) }
		end,
	})

espBox:Toggle({
	Text = "Collectables",
	Flag = "esp_collectables",
	Default = false,
	Callback = function(state) Esp.teamSettings.collectable.enabled = state end,
})
	:ColorPicker({
		Flag = "esp_collectable_color",
		Default = Color3.fromRGB(255, 215, 0),
		Callback = function(color, alpha)
			local a = 1 - (alpha or 1)
			Esp.teamSettings.collectable.boxColor = { color, a }
			Esp.teamSettings.collectable.nameColor = { color, a }
		end,
	})

espBox:Toggle({
	Text = "Players",
	Flag = "esp_players",
	Default = false,
	Callback = function(state) Esp.teamSettings.enemy.enabled = state end,
})

local displayBox = Visuals:Section("Display", 2)

displayBox:Toggle({
	Text = "Name",
	Flag = "esp_name",
	Default = true,
	Callback = function(state)
		Esp.teamSettings.npc.name = state
		Esp.teamSettings.collectable.name = state
	end,
})

displayBox:Toggle({
	Text = "Distance",
	Flag = "esp_distance",
	Default = true,
	Callback = function(state)
		Esp.teamSettings.npc.distance = state
		Esp.teamSettings.collectable.distance = state
	end,
})

displayBox:Toggle({
	Text = "Box Outline",
	Flag = "esp_outline",
	Default = true,
	Callback = function(state)
		Esp.teamSettings.npc.boxOutline = state
		Esp.teamSettings.collectable.boxOutline = state
	end,
})

displayBox:Slider({
	Text = "Max Distance",
	Flag = "esp_max_distance",
	Min = 100, Max = 5000, Default = 3000,
	Suffix = " studs",
	Callback = function(value)
		Esp.teamSettings.npc.maxDistance = value
		Esp.teamSettings.collectable.maxDistance = value
	end,
})

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

local TICKET_RANGE = 14
local INTERACT_RANGE = 5

local AutoCollect = {
	Enabled = false,
	Radius = 300,
	Delay = 0.35,
	Return = true,
	Types = { "Point", "Token", "Experience", "Log", "Ticket" },
}

local function matchesType(name)
	for _, kind in ipairs(AutoCollect.Types) do
		if name:lower():find(kind:lower(), 1, true) then return true end
	end
	return false
end

local function isTicket(name)
	return name:lower():find("ticket", 1, true) ~= nil
end

local function anchorOf(model)
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function runAutoCollect()
	while AutoCollect.Enabled do
		local folder = collectableFolder()
		local root = waitForRoot(3)

		if not folder or not root then
			task.wait(1)
		else
			local home = root.CFrame
			local list = {}

			for _, model in ipairs(folder:GetChildren()) do
				if matchesType(model.Name) then
					local anchor = anchorOf(model)
					if anchor then
						local distance = (home.Position - anchor.Position).Magnitude
						if distance <= AutoCollect.Radius then
							table.insert(list, { model = model, anchor = anchor, distance = distance })
						end
					end
				end
			end

			table.sort(list, function(a, b) return a.distance < b.distance end)

			for _, entry in ipairs(list) do
				if not AutoCollect.Enabled then return end
				if entry.model.Parent == nil then break end

				local anchor = anchorOf(entry.model)
				if anchor then
					local current = localRoot()
					if current then
						pcall(function()
							current.CFrame = CFrame.new(anchor.Position + Vector3.new(0, 2, 0))
						end)
					end

					task.wait(AutoCollect.Delay)

					if not isTicket(entry.model.Name) then
						pressKey(Enum.KeyCode.E, 0.12)
						task.wait(0.15)
					end
				end
			end

			if AutoCollect.Return and #list > 0 then
				local current = localRoot()
				if current then
					pcall(function() current.CFrame = home end)
				end
			end

			if #list == 0 then task.wait(1) end
		end
	end
end

local collectBox = Collect:Section("Auto Collect", 1)

collectBox:Toggle({
	Text = "Auto Collect",
	Flag = "collect_enable",
	Default = false,
	Callback = function(state)
		AutoCollect.Enabled = state
		if state then task.spawn(runAutoCollect) end
	end,
})
	:Keybind({ Default = "RightControl", Flag = "collect_key" })

collectBox:Dropdown({
	Text = "Types",
	Flag = "collect_types",
	Options = { "Point", "Token", "Experience", "Log", "Ticket" },
	Default = { "Point", "Token", "Experience", "Log", "Ticket" },
	Multi = true,
	Empty = "None",
	Callback = function(selected)
		AutoCollect.Types = #selected > 0 and selected or { "Point" }
	end,
})

collectBox:Slider({
	Text = "Radius",
	Flag = "collect_radius",
	Min = 50, Max = 2000, Default = 300,
	Suffix = " studs",
	Callback = function(value) AutoCollect.Radius = value end,
})

collectBox:Slider({
	Text = "Delay",
	Flag = "collect_delay",
	Min = 0.1, Max = 2, Default = 0.35,
	Decimals = 2,
	Suffix = " s",
	Callback = function(value) AutoCollect.Delay = value end,
})

collectBox:Toggle({
	Text = "Return To Start",
	Flag = "collect_return",
	Default = true,
	Callback = function(state) AutoCollect.Return = state end,
})

local collectInfo = Collect:Section("Nearby", 2)

local collectCount = collectInfo:Label("-", { Style = "bright" })

local collectTable = collectInfo:Table({
	Columns = { "Item", "Distance" },
	MaxRows = 8,
	EmptyText = "Nothing nearby",
})

task.spawn(function()
	while task.wait(1) do
		local folder = collectableFolder()
		local root = localRoot()
		local rows = {}
		local total = 0

		if folder and root then
			local list = {}

			for _, model in ipairs(folder:GetChildren()) do
				local anchor = anchorOf(model)
				if anchor then
					total = total + 1
					table.insert(list, {
						name = model.Name,
						distance = (root.Position - anchor.Position).Magnitude,
					})
				end
			end

			table.sort(list, function(a, b) return a.distance < b.distance end)

			for index, entry in ipairs(list) do
				if index > 8 then break end
				table.insert(rows, { entry.name, string.format("%d", entry.distance) })
			end
		end

		collectCount:Set(total .. " collectables in the map")
		collectTable:SetRows(rows)
	end
end)

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
	Default = { "HumanoidRootPart" },
	Multi = true,
	Empty = "HumanoidRootPart",
	Callback = function(selected)
		if #selected == 0 then selected = { "HumanoidRootPart" } end
		Aimbot.Settings.Parts = selected
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
	end)

aimBox:Dropdown({
	Text = "Easing Style",
	Flag = "aim_easing_style",
	Options = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Back" },
	Default = "Quad",
	Callback = function(value) Aimbot.Settings.EasingStyle = value end,
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

local behaviourBox = Combat:Section("Behaviour", 2)

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
	Text = "Sticky Target",
	Flag = "aim_sticky",
	Default = true,
	Callback = function(state) Aimbot.Settings.Sticky = state end,
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

behaviourBox:Toggle({
	Text = "Target Info",
	Flag = "aim_target_info",
	Default = false,
	Callback = function(state) Aimbot.Settings.TargetInfo = state end,
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
	end)

end

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

otherBox:Toggle({
	Text = "Spider",
	Flag = "move_spider",
	Default = false,
	Callback = function(state) Movement:Spider(state) end,
})

end

local statsBox = Settings:Section("Stats", 1)

local statNpc = statsBox:Label("-", { Style = "bright" })

task.spawn(function()
	while task.wait(1) do
		local count = 0
		for model in pairs(npcs) do
			if model.Parent == nil then
				untrackNpc(model)
			else
				count = count + 1
			end
		end
		statNpc:Set(count .. " npcs tracked")
	end
end)

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
SaveManager:SetFolder("Facility/9872472334")

InterfaceManager:BuildInterfaceSection(Settings, 1)
SaveManager:BuildConfigSection(Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(Visuals)

Library:Notify("Facility", "Loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
