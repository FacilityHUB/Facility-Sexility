--!nocheck
--!nolint UnknownGlobal
--[[
	Facility — Zombies

	Everything living under workspace.Zombies_Local is a zombie. A boss
	carries a BossStateOverlay child, a plain zombie does not, which is
	the only reliable way to tell them apart.
--]]

local F = shared.Facility
local Library = F.Library
local Esp     = F.Esp

local Players = game:GetService("Players")

--=====================================================================
-- Window
--=====================================================================

local Window = Library:Window({
	Title             = "Facility",
	Suffix            = ".zombies",
	Width             = 640,
	Height            = 560,
	SectionTitleStyle = "border",
})

local Visuals = Window:Tab("Visuals", "eye")

--=====================================================================
-- Teams
--=====================================================================

Esp:AddTeam("zombie", {
	enabled     = true,
	box         = true,
	boxColor    = { Color3.fromRGB(150, 220, 150), 1 },
	name        = true,
	nameColor   = { Color3.fromRGB(200, 255, 200), 1 },
	distance    = true,
	healthBar   = true,
	maxDistance = 2500,
})

Esp:AddTeam("boss", {
	enabled     = true,
	box         = true,
	boxColor    = { Color3.fromRGB(255, 60, 255), 1 },
	name        = true,
	nameColor   = { Color3.fromRGB(255, 120, 255), 1 },
	distance    = true,
	healthBar   = true,
	healthText  = true,
	chams       = true,
	chamsFillColor    = { Color3.fromRGB(255, 60, 255), 0.6 },
	chamsOutlineColor = { Color3.fromRGB(255, 120, 255), 0 },
	tracer      = true,
	tracerColor = { Color3.fromRGB(255, 60, 255), 1 },
	maxDistance = 10000,
})

--=====================================================================
-- Sorting
--=====================================================================

local FOLDER_NAME  = "Zombies_Local"
local BOSS_MARKER  = "BossStateOverlay"

-- the overlay is sometimes reparented to nil, so a plain FindFirstChild
-- is not enough on its own
local function findNil(name, class)
	if not getnilinstances then return nil end
	local ok, list = pcall(getnilinstances)
	if not ok then return nil end

	for _, instance in ipairs(list) do
		if instance.ClassName == class and instance.Name == name then
			return instance
		end
	end
	return nil
end

local function isBoss(model)
	if model:FindFirstChild(BOSS_MARKER) then return true end

	-- the marker can live outside the model, match it by adornee
	local orphan = findNil(BOSS_MARKER, "Highlight")
	if orphan and orphan.Adornee == model then return true end

	return false
end

local function teamOf(model)
	return isBoss(model) and "boss" or "zombie"
end

--=====================================================================
-- Tracking
--=====================================================================

local tracked = {}

local function untrack(model)
	if not tracked[model] then return end
	tracked[model] = nil
	pcall(function() Esp:RemoveInstance(model) end)
end

local function track(model)
	if not model:IsA("Model") then return end
	if tracked[model] then return end

	-- a zombie spawns before its parts, wait for something to draw on
	task.spawn(function()
		local root = model:FindFirstChild("HumanoidRootPart")
			or model:WaitForChild("HumanoidRootPart", 5)
		if not root or model.Parent == nil then return end

		local team = teamOf(model)
		tracked[model] = team

		Esp:AddInstance(model, {
			Team = team,
			Text = model.Name,
		})

		-- a zombie can be promoted to boss during the fight
		local watcher
		watcher = model.ChildAdded:Connect(function(child)
			if child.Name ~= BOSS_MARKER then return end
			if tracked[model] == "boss" then return end

			untrack(model)
			tracked[model] = "boss"
			Esp:AddInstance(model, { Team = "boss", Text = model.Name })
		end)

		model.AncestryChanged:Connect(function()
			if model.Parent == nil then
				if watcher then watcher:Disconnect() end
				untrack(model)
			end
		end)
	end)
end

local folder = workspace:WaitForChild(FOLDER_NAME)

for _, model in ipairs(folder:GetChildren()) do
	track(model)
end

folder.ChildAdded:Connect(track)
folder.ChildRemoved:Connect(untrack)

--=====================================================================
-- Interface
--=====================================================================

local espBox = Visuals:Section("Esp", 1)

espBox:Toggle({
	Text = "Enable",
	Flag = "esp_enable",
	Default = false,
	Callback = function(state)
		if state then
			pcall(function() Esp:Load(F.Entity) end)
		else
			pcall(function() Esp:Unload() end)
		end
	end,
})
	:Keybind({ Default = "RightAlt", Flag = "esp_key" })

espBox:Toggle({
	Text = "Zombies",
	Flag = "esp_zombies",
	Default = true,
	Callback = function(state) Esp.teamSettings.zombie.enabled = state end,
})
	:ColorPicker({
		Flag = "esp_zombie_color",
		Default = Color3.fromRGB(150, 220, 150),
		Callback = function(color, alpha)
			Esp.teamSettings.zombie.boxColor = { color, 1 - (alpha or 1) }
		end,
	})
	:Gear(function(panel)
		panel:Toggle({
			Text = "Health Bar",
			Flag = "esp_zombie_health",
			Default = true,
			Callback = function(state) Esp.teamSettings.zombie.healthBar = state end,
		})
		panel:Slider({
			Text = "Max Distance",
			Flag = "esp_zombie_distance",
			Min = 100, Max = 5000, Default = 2500,
			Suffix = " studs",
			Callback = function(value) Esp.teamSettings.zombie.maxDistance = value end,
		})
	end)

espBox:Toggle({
	Text = "Bosses",
	Flag = "esp_bosses",
	Default = true,
	Callback = function(state) Esp.teamSettings.boss.enabled = state end,
})
	:ColorPicker({
		Flag = "esp_boss_color",
		Default = Color3.fromRGB(255, 60, 255),
		Callback = function(color, alpha)
			local a = 1 - (alpha or 1)
			Esp.teamSettings.boss.boxColor = { color, a }
			Esp.teamSettings.boss.tracerColor = { color, a }
			Esp.teamSettings.boss.chamsFillColor = { color, 0.6 }
		end,
	})
	:Gear(function(panel)
		panel:Toggle({
			Text = "Chams",
			Flag = "esp_boss_chams",
			Default = true,
			Callback = function(state) Esp.teamSettings.boss.chams = state end,
		})
		panel:Toggle({
			Text = "Tracer",
			Flag = "esp_boss_tracer",
			Default = true,
			Callback = function(state) Esp.teamSettings.boss.tracer = state end,
		})
		panel:Slider({
			Text = "Max Distance",
			Flag = "esp_boss_distance",
			Min = 500, Max = 10000, Default = 10000,
			Suffix = " studs",
			Callback = function(value) Esp.teamSettings.boss.maxDistance = value end,
		})
	end)

espBox:Toggle({
	Text = "Players",
	Flag = "esp_players",
	Default = false,
	Hint = "Other players, separate from the zombies",
	Callback = function(state) Esp.teamSettings.enemy.enabled = state end,
})

--=====================================================================
-- Live list
--=====================================================================

local listBox = Visuals:Section("Tracked", 2)

local counter = listBox:Label("-", { Style = "bright" })

local board = listBox:Table({
	Columns = { "Name", "Distance", "Type" },
	MaxRows = 10,
	EmptyText = "Nothing nearby",
})

task.spawn(function()
	while task.wait(0.5) do
		local zombies, bosses = 0, 0
		local rows = {}

		local character = Players.LocalPlayer.Character
		local myRoot = character and character:FindFirstChild("HumanoidRootPart")

		for model, team in pairs(tracked) do
			if model.Parent == nil then
				untrack(model)
			else
				if team == "boss" then bosses = bosses + 1 else zombies = zombies + 1 end

				if #rows < 10 then
					local root = model:FindFirstChild("HumanoidRootPart")
					local distance = "-"
					if myRoot and root then
						distance = string.format("%d", (myRoot.Position - root.Position).Magnitude)
					end
					table.insert(rows, {
						model.Name,
						distance,
						team,
						Style = team == "boss" and "warning" or "dim",
					})
				end
			end
		end

		counter:Set(zombies .. " zombies  |  " .. bosses .. " bosses")

		table.sort(rows, function(a, b)
			return (tonumber(a[2]) or 9e9) < (tonumber(b[2]) or 9e9)
		end)

		board:SetRows(rows)
	end
end)

--=====================================================================
-- Managers
--=====================================================================

local Settings = Window:Tab("Settings", "cog")

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
SaveManager:SetFolder("Facility/zombies")

InterfaceManager:BuildInterfaceSection(Settings, 1)
SaveManager:BuildConfigSection(Settings, 2)
ThemeManager:Mount(Window)

Window:SetTab(Visuals)

Library:Notify("Facility", "Zombies loaded.", 4)

SaveManager:LoadAutoloadConfig()
ThemeManager:Load()
